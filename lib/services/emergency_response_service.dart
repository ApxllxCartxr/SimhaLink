import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'package:latlong2/latlong.dart';
import 'package:simha_link/models/emergency_response.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/services/routing_service.dart';

/// Service for managing emergency response tracking
class EmergencyResponseService {
  static final EmergencyResponseService _instance = EmergencyResponseService._internal();
  factory EmergencyResponseService() => _instance;
  EmergencyResponseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Location _location = Location();
  
  // Active response tracking
  EmergencyResponse? _currentResponse;
  StreamSubscription<LocationData>? _locationTrackingSubscription;
  StreamSubscription<QuerySnapshot>? _responseStreamSubscription;
  Timer? _routeUpdateTimer;
  
  // Callbacks for UI updates
  Function(EmergencyResponse?)? _onResponseUpdated;
  Function(List<LatLng>)? _onRouteUpdated;

  /// Get current user's active emergency response
  EmergencyResponse? get currentResponse => _currentResponse;

  /// Check if current user has an active response
  bool get hasActiveResponse => _currentResponse?.isActive ?? false;

  /// Initialize response tracking for current user
  Future<void> initialize({
    Function(EmergencyResponse?)? onResponseUpdated,
    Function(List<LatLng>)? onRouteUpdated,
  }) async {
    _onResponseUpdated = onResponseUpdated;
    _onRouteUpdated = onRouteUpdated;
    
    await _loadCurrentResponse();
    _startListeningToResponses();
  }

  /// Create a new emergency response
  Future<EmergencyResponse> createResponse({
    required String emergencyId,
    required LatLng emergencyLocation,
    required LatLng volunteerLocation,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      final response = EmergencyResponse(
        responseId: '', // Will be set by Firestore
        emergencyId: emergencyId,
        volunteerId: user.uid,
        volunteerName: user.displayName ?? 'Volunteer',
        status: EmergencyResponseStatus.responding,
        timestamp: DateTime.now(),
        lastUpdated: DateTime.now(),
        volunteerLocation: volunteerLocation,
        distanceToEmergency: _calculateDistance(volunteerLocation, emergencyLocation),
        estimatedArrivalTime: await _calculateETA(volunteerLocation, emergencyLocation),
      );

      final docRef = await _firestore
          .collection('emergency_responses')
          .add(response.toFirestore());

      final createdResponse = response.copyWith();
      _currentResponse = EmergencyResponse(
        responseId: docRef.id,
        emergencyId: createdResponse.emergencyId,
        volunteerId: createdResponse.volunteerId,
        volunteerName: createdResponse.volunteerName,
        status: createdResponse.status,
        timestamp: createdResponse.timestamp,
        lastUpdated: createdResponse.lastUpdated,
        volunteerLocation: createdResponse.volunteerLocation,
        estimatedArrivalTime: createdResponse.estimatedArrivalTime,
        notes: createdResponse.notes,
        routePoints: createdResponse.routePoints,
        distanceToEmergency: createdResponse.distanceToEmergency,
      );

      _notifyResponseUpdated();
      AppLogger.logInfo('Emergency response created: ${docRef.id}');
      
      return _currentResponse!;
    } catch (e) {
      AppLogger.logError('Failed to create emergency response', e);
      rethrow;
    }
  }

  /// Update response status
  Future<void> updateStatus(EmergencyResponseStatus newStatus) async {
    if (_currentResponse == null) return;

    try {
      final updatedResponse = _currentResponse!.copyWith(
        status: newStatus,
        lastUpdated: DateTime.now(),
      );

      await _firestore
          .collection('emergency_responses')
          .doc(_currentResponse!.responseId)
          .update({
        'status': newStatus.name,
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });

      _currentResponse = updatedResponse;
      
      // Handle status-specific actions
      await _handleStatusChange(newStatus);
      
      _notifyResponseUpdated();
      AppLogger.logInfo('Response status updated to: ${newStatus.name}');
    } catch (e) {
      AppLogger.logError('Failed to update response status', e);
      rethrow;
    }
  }

  /// Handle status change side effects
  Future<void> _handleStatusChange(EmergencyResponseStatus status) async {
    switch (status) {
      case EmergencyResponseStatus.enRoute:
        await _startLocationTracking();
        await _startRouteTracking();
        break;
      case EmergencyResponseStatus.arrived:
        await _stopRouteTracking();
        break;
      case EmergencyResponseStatus.completed:
        await _stopLocationTracking();
        await _completeResponse();
        break;
      case EmergencyResponseStatus.unavailable:
        await _stopLocationTracking();
        await _cancelResponse();
        break;
      default:
        break;
    }
  }

  /// Start tracking volunteer location
  Future<void> _startLocationTracking() async {
    final permissionStatus = await _location.requestPermission();
    if (permissionStatus != PermissionStatus.granted) {
      throw Exception('Location permission required for tracking');
    }

    _locationTrackingSubscription?.cancel();
    _locationTrackingSubscription = _location.onLocationChanged.listen(
      (locationData) => _updateVolunteerLocation(locationData),
      onError: (error) => AppLogger.logError('Location tracking error', error),
    );
  }

  /// Update volunteer location in response
  Future<void> _updateVolunteerLocation(LocationData locationData) async {
    if (_currentResponse == null || 
        !_currentResponse!.shouldTrackLocation ||
        locationData.latitude == null ||
        locationData.longitude == null) return;

    try {
      final volunteerLocation = LatLng(locationData.latitude!, locationData.longitude!);
      
      final updatedResponse = _currentResponse!.copyWith(
        volunteerLocation: volunteerLocation,
        lastUpdated: DateTime.now(),
      );

      await _firestore
          .collection('emergency_responses')
          .doc(_currentResponse!.responseId)
          .update({
        'volunteerLocation': GeoPoint(volunteerLocation.latitude, volunteerLocation.longitude),
        'lastUpdated': Timestamp.fromDate(DateTime.now()),
      });

      _currentResponse = updatedResponse;
      _notifyResponseUpdated();
    } catch (e) {
      AppLogger.logError('Failed to update volunteer location', e);
    }
  }

  /// Start route tracking and updates
  Future<void> _startRouteTracking() async {
    if (_currentResponse?.volunteerLocation == null) return;

    // Get emergency location
    final emergencyLocation = await _getEmergencyLocation(_currentResponse!.emergencyId);
    if (emergencyLocation == null) return;

    // Calculate initial route
    await _updateRoute(_currentResponse!.volunteerLocation!, emergencyLocation);

    // Start periodic route updates
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateRouteIfNeeded(emergencyLocation),
    );
  }

  /// Update route between volunteer and emergency
  Future<void> _updateRoute(LatLng volunteerLocation, LatLng emergencyLocation) async {
    try {
      final route = await RoutingService.getWalkingRoute(volunteerLocation, emergencyLocation);
      
      if (route.isNotEmpty && _currentResponse != null) {
        final updatedResponse = _currentResponse!.copyWith(
          routePoints: route,
          lastUpdated: DateTime.now(),
          estimatedArrivalTime: await _calculateETA(volunteerLocation, emergencyLocation),
          distanceToEmergency: _calculateDistance(volunteerLocation, emergencyLocation),
        );

        await _firestore
            .collection('emergency_responses')
            .doc(_currentResponse!.responseId)
            .update({
          'routePoints': route.map((point) => GeoPoint(point.latitude, point.longitude)).toList(),
          'lastUpdated': Timestamp.fromDate(DateTime.now()),
          'estimatedArrivalTime': updatedResponse.estimatedArrivalTime,
          'distanceToEmergency': updatedResponse.distanceToEmergency,
        });

        _currentResponse = updatedResponse;
        _onRouteUpdated?.call(route);
        _notifyResponseUpdated();
      }
    } catch (e) {
      AppLogger.logError('Failed to update route', e);
    }
  }

  /// Update route if volunteer location changed significantly
  Future<void> _updateRouteIfNeeded(LatLng emergencyLocation) async {
    if (_currentResponse?.volunteerLocation == null) return;

    final lastRoute = _currentResponse!.routePoints;
    if (lastRoute == null || lastRoute.isEmpty) {
      await _updateRoute(_currentResponse!.volunteerLocation!, emergencyLocation);
      return;
    }

    // Check if volunteer moved significantly from last route point
    final currentLocation = _currentResponse!.volunteerLocation!;
    final lastRoutePoint = lastRoute.first;
    final distanceMoved = _calculateDistance(currentLocation, lastRoutePoint);

    // Update route if moved more than 50 meters
    if (distanceMoved > 50) {
      await _updateRoute(currentLocation, emergencyLocation);
    }
  }

  /// Stop route tracking
  Future<void> _stopRouteTracking() async {
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = null;
  }

  /// Stop location tracking
  Future<void> _stopLocationTracking() async {
    _locationTrackingSubscription?.cancel();
    _locationTrackingSubscription = null;
  }

  /// Complete the emergency response
  Future<void> _completeResponse() async {
    _currentResponse = null;
    await _stopLocationTracking();
    await _stopRouteTracking();
    _notifyResponseUpdated();
  }

  /// Cancel the emergency response
  Future<void> _cancelResponse() async {
    if (_currentResponse != null) {
      await _firestore
          .collection('emergency_responses')
          .doc(_currentResponse!.responseId)
          .delete();
    }
    
    _currentResponse = null;
    await _stopLocationTracking();
    await _stopRouteTracking();
    _notifyResponseUpdated();
  }

  /// Load current user's active response
  Future<void> _loadCurrentResponse() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final querySnapshot = await _firestore
          .collection('emergency_responses')
          .where('volunteerId', isEqualTo: user.uid)
          .where('status', whereIn: [
            EmergencyResponseStatus.responding.name,
            EmergencyResponseStatus.enRoute.name,
            EmergencyResponseStatus.arrived.name,
            EmergencyResponseStatus.assisting.name,
          ])
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        _currentResponse = EmergencyResponse.fromFirestore(querySnapshot.docs.first);
        
        // Resume tracking if en route
        if (_currentResponse!.status == EmergencyResponseStatus.enRoute) {
          await _startLocationTracking();
          final emergencyLocation = await _getEmergencyLocation(_currentResponse!.emergencyId);
          if (emergencyLocation != null) {
            await _startRouteTracking();
          }
        }
      }
    } catch (e) {
      AppLogger.logError('Failed to load current response', e);
    }
  }

  /// Start listening to response updates
  void _startListeningToResponses() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _responseStreamSubscription?.cancel();
    _responseStreamSubscription = _firestore
        .collection('emergency_responses')
        .where('volunteerId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final response = EmergencyResponse.fromFirestore(snapshot.docs.first);
          if (response.isActive) {
            _currentResponse = response;
          } else if (!response.isActive) {
            _currentResponse = null;
          }
          _notifyResponseUpdated();
        }
      },
      onError: (error) => AppLogger.logError('Response stream error', error),
    );
  }

  /// Get emergency location from emergency ID
  Future<LatLng?> _getEmergencyLocation(String emergencyId) async {
    try {
      // This should get the emergency location from your existing emergency system
      // For now, returning null - you'll need to integrate with your UserLocation system
      return null;
    } catch (e) {
      AppLogger.logError('Failed to get emergency location', e);
      return null;
    }
  }

  /// Calculate distance between two points in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // meters
    final double dLat = (point2.latitude - point1.latitude) * (pi / 180);
    final double dLon = (point2.longitude - point1.longitude) * (pi / 180);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(point1.latitude * (pi / 180)) * cos(point2.latitude * (pi / 180)) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Calculate estimated time of arrival
  Future<String> _calculateETA(LatLng from, LatLng to) async {
    final distance = _calculateDistance(from, to);
    // Assume average walking speed of 1.4 m/s (5 km/h)
    final timeInSeconds = distance / 1.4;
    final minutes = (timeInSeconds / 60).round();
    
    if (minutes < 1) {
      return "< 1 min";
    } else if (minutes == 1) {
      return "1 min";
    } else {
      return "$minutes mins";
    }
  }

  /// Notify UI of response updates
  void _notifyResponseUpdated() {
    _onResponseUpdated?.call(_currentResponse);
  }

  /// Get all responses for a specific emergency (for organizers/other volunteers to see)
  Stream<List<EmergencyResponse>> getResponsesForEmergency(String emergencyId) {
    return _firestore
        .collection('emergency_responses')
        .where('emergencyId', isEqualTo: emergencyId)
        .orderBy('timestamp')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EmergencyResponse.fromFirestore(doc))
            .toList());
  }

  /// Clean up resources
  void dispose() {
    _locationTrackingSubscription?.cancel();
    _responseStreamSubscription?.cancel();
    _routeUpdateTimer?.cancel();
  }
}
