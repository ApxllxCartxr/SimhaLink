import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:simha_link/models/emergency.dart';
import 'package:simha_link/services/emergency_database_service.dart';
import 'package:simha_link/core/utils/app_logger.dart';

/// High-level service for managing emergency workflow and real-time updates
class EmergencyManagementService {
  static final Location _location = Location();
  static Timer? _locationUpdateTimer;
  static String? _currentEmergencyId;
  static String? _currentVolunteerId;
  static StreamSubscription<LocationData>? _locationSubscription;
  
  // Callbacks for UI updates
  static Function(List<Emergency>)? _onEmergenciesUpdated;
  static Function(Emergency?)? _onVolunteerResponseUpdated;
  
  /// Initialize the emergency management service
  static Future<void> initialize({
    Function(List<Emergency>)? onEmergenciesUpdated,
    Function(Emergency?)? onVolunteerResponseUpdated,
  }) async {
    _onEmergenciesUpdated = onEmergenciesUpdated;
    _onVolunteerResponseUpdated = onVolunteerResponseUpdated;
    
    AppLogger.logInfo('EmergencyManagementService initialized');
  }

  /// Create a new emergency for an attendee with duplicate prevention
  static Future<Emergency> createEmergency({
    required String attendeeName,
    required String groupId,
    required LatLng location,
    String? message,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      // Check if user already has an active emergency - ENFORCE ONE PER USER
      final existingEmergency = await EmergencyDatabaseService.getUserActiveEmergency(userId);
      if (existingEmergency != null) {
        AppLogger.logInfo('User already has active emergency, returning existing: ${existingEmergency.emergencyId}');
        
        // Start location tracking for existing emergency
        await _startAttendeeLocationTracking(existingEmergency.emergencyId, groupId, userId);
        
        return existingEmergency;
      }

      final emergency = await EmergencyDatabaseService.createEmergencyWithState(
        attendeeId: userId,
        attendeeName: attendeeName,
        groupId: groupId,
        location: location,
        message: message,
      );

      // Start real-time location tracking for the attendee
      await _startAttendeeLocationTracking(emergency.emergencyId, groupId, userId);

      AppLogger.logInfo('NEW emergency created by attendee: ${emergency.emergencyId}');
      return emergency;
    } catch (e) {
      AppLogger.logError('Error creating emergency', e);
      rethrow;
    }
  }

  /// Resolve emergency with complete cleanup
  static Future<void> resolveEmergency(String emergencyId) async {
    try {
      await EmergencyDatabaseService.resolveEmergencyWithCleanup(emergencyId);
      
      // Stop location tracking
      await _stopAttendeeLocationTracking();
      
      AppLogger.logInfo('Emergency resolved by attendee: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error resolving emergency', e);
      rethrow;
    }
  }

  /// Start real-time location tracking for attendee during emergency
  static Future<void> _startAttendeeLocationTracking(String emergencyId, String groupId, String attendeeId) async {
    try {
      // Stop any existing tracking
      await _stopAttendeeLocationTracking();
      
      _currentEmergencyId = emergencyId;
      _currentVolunteerId = attendeeId; // Reuse for attendee tracking

      // Configure location settings for high accuracy during emergency
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 3000, // 3 seconds for emergency
        distanceFilter: 2, // 2 meters
      );

      // Start location updates for attendee
      _locationSubscription = _location.onLocationChanged.listen(
        (LocationData locationData) {
          if (locationData.latitude != null && 
              locationData.longitude != null &&
              _currentEmergencyId != null) {
            
            final currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
            
            // Update emergency location in real-time
            EmergencyDatabaseService.updateEmergencyLocation(
              emergencyId: _currentEmergencyId!,
              groupId: groupId,
              attendeeId: attendeeId,
              location: currentLocation,
            ).catchError((error) {
              AppLogger.logError('Error updating attendee emergency location', error);
            });
          }
        },
        onError: (error) {
          AppLogger.logError('Attendee location tracking error', error);
        },
      );

      AppLogger.logInfo('Started real-time location tracking for attendee emergency: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error starting attendee location tracking', e);
    }
  }

  /// Stop attendee location tracking
  static Future<void> _stopAttendeeLocationTracking() async {
    try {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = null;
      _currentEmergencyId = null;
      _currentVolunteerId = null;

      AppLogger.logInfo('Stopped attendee location tracking');
    } catch (e) {
      AppLogger.logError('Error stopping attendee location tracking', e);
    }
  }

  /// Volunteer responds to an emergency
  static Future<void> volunteerRespond({
    required String emergencyId,
    required String volunteerName,
    required LatLng volunteerLocation,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      await EmergencyDatabaseService.addVolunteerResponse(
        emergencyId: emergencyId,
        volunteerId: userId,
        volunteerName: volunteerName,
        volunteerLocation: volunteerLocation,
      );

      // Start real-time location tracking for this volunteer
      await _startVolunteerLocationTracking(emergencyId, userId);

      AppLogger.logInfo('Volunteer responded to emergency: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error volunteer responding to emergency', e);
      rethrow;
    }
  }

  /// Update volunteer status
  static Future<void> updateVolunteerStatus({
    required String emergencyId,
    required EmergencyVolunteerStatus status,
    String? estimatedArrivalTime,
  }) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      // Get current location
      LatLng? currentLocation;
      try {
        final locationData = await _location.getLocation();
        if (locationData.latitude != null && locationData.longitude != null) {
          currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
        }
      } catch (e) {
        AppLogger.logWarning('Could not get current location for status update', e);
      }

      await EmergencyDatabaseService.updateVolunteerStatus(
        emergencyId: emergencyId,
        volunteerId: userId,
        status: status,
        currentLocation: currentLocation,
        estimatedArrivalTime: estimatedArrivalTime,
      );

      // Stop location tracking if volunteer completed or cancelled
      if (status == EmergencyVolunteerStatus.completed || 
          status == EmergencyVolunteerStatus.unavailable) {
        await _stopVolunteerLocationTracking();
      }

      AppLogger.logInfo('Volunteer status updated: ${status.name}');
    } catch (e) {
      AppLogger.logError('Error updating volunteer status', e);
      rethrow;
    }
  }

  /// Cancel volunteer response
  static Future<void> cancelVolunteerResponse(String emergencyId) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) throw Exception('User not authenticated');

      await EmergencyDatabaseService.removeVolunteerResponse(
        emergencyId: emergencyId,
        volunteerId: userId,
      );

      await _stopVolunteerLocationTracking();

      AppLogger.logInfo('Volunteer response cancelled: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error cancelling volunteer response', e);
      rethrow;
    }
  }

  /// Listen to group emergencies
  static StreamSubscription<List<Emergency>> listenToGroupEmergencies(
    String groupId,
    Function(List<Emergency>) onEmergenciesChanged,
  ) {
    return EmergencyDatabaseService.getGroupEmergencies(groupId).listen(
      onEmergenciesChanged,
      onError: (error) {
        AppLogger.logError('Error listening to group emergencies', error);
      },
    );
  }

  /// Listen to ALL emergencies across ALL groups (for volunteers)
  static StreamSubscription<List<Emergency>> listenToAllEmergencies(
    Function(List<Emergency>) onEmergenciesChanged,
  ) {
    return EmergencyDatabaseService.getAllEmergencies().listen(
      onEmergenciesChanged,
      onError: (error) {
        AppLogger.logError('Error listening to all emergencies', error);
      },
    );
  }

  /// Listen to volunteer's active responses
  static StreamSubscription<List<Emergency>> listenToVolunteerResponses(
    String volunteerId,
    Function(List<Emergency>) onResponsesChanged,
  ) {
    return EmergencyDatabaseService.getVolunteerActiveResponses(volunteerId).listen(
      onResponsesChanged,
      onError: (error) {
        AppLogger.logError('Error listening to volunteer responses', error);
      },
    );
  }

  /// Start real-time location tracking for volunteer
  static Future<void> _startVolunteerLocationTracking(String emergencyId, String volunteerId) async {
    try {
      // Stop any existing tracking
      await _stopVolunteerLocationTracking();
      
      _currentEmergencyId = emergencyId;
      _currentVolunteerId = volunteerId;

      // Check location permissions
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('Location service not enabled');
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          throw Exception('Location permission not granted');
        }
      }

      // Configure location settings for high accuracy during emergency
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000, // 5 seconds
        distanceFilter: 5, // 5 meters
      );

      // Start location updates
      _locationSubscription = _location.onLocationChanged.listen(
        (LocationData locationData) {
          if (locationData.latitude != null && 
              locationData.longitude != null &&
              _currentEmergencyId != null &&
              _currentVolunteerId != null) {
            
            final currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
            
            // Update location in database (fire and forget)
            EmergencyDatabaseService.updateVolunteerLocation(
              emergencyId: _currentEmergencyId!,
              volunteerId: _currentVolunteerId!,
              location: currentLocation,
            ).catchError((error) {
              AppLogger.logError('Error updating volunteer location', error);
            });
          }
        },
        onError: (error) {
          AppLogger.logError('Location tracking error', error);
        },
      );

      AppLogger.logInfo('Started location tracking for volunteer: $volunteerId');
    } catch (e) {
      AppLogger.logError('Error starting volunteer location tracking', e);
    }
  }

  /// Stop volunteer location tracking
  static Future<void> _stopVolunteerLocationTracking() async {
    try {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = null;
      _currentEmergencyId = null;
      _currentVolunteerId = null;

      AppLogger.logInfo('Stopped volunteer location tracking');
    } catch (e) {
      AppLogger.logError('Error stopping volunteer location tracking', e);
    }
  }

  /// Get emergency statistics
  static Future<Map<String, int>> getEmergencyStats(String groupId) {
    return EmergencyDatabaseService.getEmergencyStats(groupId);
  }

  /// Clean up service
  static Future<void> dispose() async {
    try {
      await _stopVolunteerLocationTracking();
      _onEmergenciesUpdated = null;
      _onVolunteerResponseUpdated = null;
      
      AppLogger.logInfo('EmergencyManagementService disposed');
    } catch (e) {
      AppLogger.logError('Error disposing EmergencyManagementService', e);
    }
  }
}
