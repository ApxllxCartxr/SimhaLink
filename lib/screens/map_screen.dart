import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/models/poi.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:simha_link/screens/broadcast_list_screen.dart';
import 'package:simha_link/services/broadcast_service.dart';
import 'package:simha_link/utils/error_handler.dart';
import 'package:simha_link/services/routing_service.dart';
import 'package:simha_link/config/app_colors.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/services/geographic_marker_service.dart' as geo;

// Import the new managers and widgets
import 'map/managers/location_manager.dart';
// REMOVED: emergency_manager.dart - using EmergencyManagementService instead
import 'map/managers/marker_manager.dart';
import 'map/widgets/map_info_panel.dart';
import 'map/widgets/map_legend.dart';
import 'map/widgets/marker_action_bottom_sheet.dart';
import 'map/widgets/emergency_response_card.dart';
import '../models/emergency_response.dart';
import '../services/emergency_management_service.dart';
import '../services/emergency_database_service.dart';
import '../models/emergency.dart';

class MapScreen extends StatefulWidget {
  final String groupId;
  
  const MapScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _mapController = MapController();
  
  // Managers
  late LocationManager _locationManager;
  // REMOVED: EmergencyManager - using EmergencyManagementService instead
  late MarkerManager _markerManager;
  
  // New Emergency Database System - Unified approach
  StreamSubscription<List<Emergency>>? _emergenciesSubscription;
  List<StreamSubscription<List<Emergency>>> _additionalEmergencySubscriptions = [];
  List<Emergency> _activeEmergencies = [];
  Emergency? _currentEmergencyResponse; // Current emergency volunteer is responding to
  final Set<String> _notifiedEmergencies = <String>{};
  
  // Data streams
  StreamSubscription<QuerySnapshot>? _groupLocationsSubscription;
  StreamSubscription<QuerySnapshot>? _poisSubscription;
  
  // State variables
  List<UserLocation> _groupMembers = [];
  List<POI> _pois = [];
  UserLocation? _selectedMember;
  POI? _selectedPOI;
  bool _isEmergency = false;
  String? _userRole;
  bool _isMapReady = false;
  bool _isPlacingPOI = false;
  bool _isMarkerManagementMode = false;
  
  // Routing state
  List<LatLng> _currentRoute = [];
  bool _isLoadingRoute = false;
  String _routeInfo = '';

  @override
  void initState() {
    super.initState();
    _initializeManagers();
    _setupInitialData();
  }

  void _initializeManagers() {
    _locationManager = LocationManager(
      groupId: widget.groupId,
      userRole: _userRole,
      isEmergency: _isEmergency,
    );
    // REMOVED: Old emergency manager that used UserLocation objects
    // Only use Emergency objects via EmergencyManagementService
    _markerManager = MarkerManager(
      userRole: _userRole,
      isMapReady: _isMapReady,
    );
  }

  /// Initialize emergency management and database listeners
  Future<void> _initializeEmergencyManagement() async {
    try {
      // Initialize emergency management service
      await EmergencyManagementService.initialize();
      
      // CRITICAL: Clean up any stale/duplicate emergencies for the current user
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        AppLogger.logInfo('Cleaning up stale emergencies for user: $userId');
        await EmergencyDatabaseService.cleanupUserEmergencies(userId);
      }
      
      // Cancel any existing subscription to prevent memory leaks
      _emergenciesSubscription?.cancel();
      
      // Listen to emergencies based on user role
      AppLogger.logInfo('Setting up emergency listeners for role: $_userRole');
      
      if (_userRole?.toLowerCase() == 'volunteer') {
        // VOLUNTEERS see ALL emergencies from ALL groups - Use same approach as attendees but for all groups
        AppLogger.logInfo('Volunteer detected - listening to ALL group emergencies without indexes');
        await _listenToAllGroupEmergenciesForVolunteers();
      } else {
        // ATTENDEES and ORGANIZERS see only their group emergencies
        AppLogger.logInfo('Non-volunteer (${_userRole ?? 'Unknown'}) detected - listening to group ${widget.groupId} emergencies only');
        _emergenciesSubscription = EmergencyManagementService.listenToGroupEmergencies(
          widget.groupId,
          (emergencies) {
            if (!mounted) return;
            
            AppLogger.logInfo('Group received ${emergencies.length} emergencies: ${emergencies.map((e) => '${e.attendeeName} (${e.emergencyId})').join(', ')}');
            
            setState(() {
              _activeEmergencies = emergencies;
              
              // CRITICAL: Restore emergency state for attendees across login/logout
              if (_userRole == 'Attendee') {
                final userId = FirebaseAuth.instance.currentUser?.uid;
                final hasActiveEmergency = emergencies.any((emergency) => 
                  emergency.attendeeId == userId && emergency.isActive); // Use isActive property
                
                if (_isEmergency != hasActiveEmergency) {
                  _isEmergency = hasActiveEmergency;
                  _locationManager.isEmergency = hasActiveEmergency;
                  _locationManager.updateEmergencyStatus(hasActiveEmergency);
                  
                  AppLogger.logInfo('Emergency state restored from database: $_isEmergency');
                }
              }
            });
            
            AppLogger.logInfo('Group emergency data updated: ${emergencies.length} active emergencies in group ${widget.groupId}');
          },
        );
      }
      
      // Add error handling for the subscription
      _emergenciesSubscription?.onError((error) {
        AppLogger.logError('Emergency subscription error', error);
        
        // Handle the specific Firebase index error
        if (error.toString().contains('requires an index')) {
          AppLogger.logError('Firebase index required for emergency queries. Please create the index in Firebase Console.');
          
          if (mounted) {
            _showTopSnackBar(
              message: '⚠️ Database setup required. Please contact administrator.',
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              icon: const Icon(Icons.warning, color: Colors.white),
            );
          }
        }
        
        // Attempt to reconnect after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            AppLogger.logInfo('Attempting to reconnect to emergency stream...');
            _initializeEmergencyManagement();
          }
        });
      });
      
      // Disable old emergency manager listeners to prevent conflicts
      // _emergencyManager.dispose(); // REMOVED - No longer using old UserLocation-based system
      
      AppLogger.logInfo('Emergency management initialized - Role: $_userRole, listening to ${_userRole == 'Volunteer' ? 'ALL' : 'GROUP'} emergencies');
    } catch (e) {
      AppLogger.logError('Error initializing emergency management', e);
      
      // Retry initialization after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          AppLogger.logInfo('Retrying emergency management initialization...');
          _initializeEmergencyManagement();
        }
      });
    }
  }

  /// Listen to all group emergencies for volunteers (avoiding Firebase indexes)
  Future<void> _listenToAllGroupEmergenciesForVolunteers() async {
    try {
      // Get all groups first
      final groupsSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .get();

      List<StreamSubscription<List<Emergency>>> groupSubscriptions = [];

      // Listen to each group's emergencies separately (same method attendees use)
      for (final groupDoc in groupsSnapshot.docs) {
        final groupId = groupDoc.id;
        AppLogger.logInfo('Volunteer listening to group: $groupId');
        
        // Use the same method that works for attendees - EmergencyManagementService.listenToGroupEmergencies
        final subscription = EmergencyManagementService.listenToGroupEmergencies(
          groupId,
          (groupEmergencies) {
            if (!mounted) return;
            
            try {
              AppLogger.logInfo('Volunteer received ${groupEmergencies.length} emergencies from group $groupId');
              
              // Update the combined list of emergencies
              setState(() {
                // Remove old emergencies from this group and add new ones
                _activeEmergencies = _activeEmergencies
                    .where((emergency) => emergency.groupId != groupId)
                    .toList();
                
                // FILTER: Only add emergencies visible to volunteers (exclude fake/resolved)
                final visibleEmergencies = groupEmergencies
                    .where((emergency) => emergency.status.visibleToVolunteers)
                    .toList();
                    
                _activeEmergencies.addAll(visibleEmergencies);
                
                // Sort by creation time (newest first)
                _activeEmergencies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              });
              
              // Show notifications for new emergencies
              _handleNewEmergencyNotifications(groupEmergencies);
              
              AppLogger.logInfo('Volunteer total active emergencies: ${_activeEmergencies.length}');
            } catch (e) {
              AppLogger.logError('Error processing emergencies for group $groupId', e);
            }
          },
        );
        
        groupSubscriptions.add(subscription);
      }

      // Store the subscription for cleanup (we'll use the first one as the main subscription)
      if (groupSubscriptions.isNotEmpty) {
        _emergenciesSubscription = groupSubscriptions.first;
        
        // Store additional subscriptions for cleanup
        _additionalEmergencySubscriptions = groupSubscriptions.skip(1).toList();
      }
      
      AppLogger.logInfo('Volunteer listening to ${groupsSnapshot.docs.length} groups for emergencies');
    } catch (e) {
      AppLogger.logError('Error setting up volunteer emergency listening', e);
      
      // Fallback to single group listening if there's an error
      if (mounted) {
        _emergenciesSubscription = EmergencyManagementService.listenToGroupEmergencies(
          widget.groupId,
          (emergencies) {
            if (!mounted) return;
            
            setState(() {
              _activeEmergencies = emergencies;
            });
            
            _handleNewEmergencyNotifications(emergencies);
            
            AppLogger.logInfo('Volunteer fallback - listening to current group only: ${emergencies.length} emergencies');
          },
        );
      }
    }
  }

  /// Handle new emergency notifications for volunteers
  void _handleNewEmergencyNotifications(List<Emergency> emergencies) {
    // Track which emergencies we've already notified about
    for (final emergency in emergencies) {
      if (!_notifiedEmergencies.contains(emergency.emergencyId)) {
        _notifiedEmergencies.add(emergency.emergencyId);
        
        // Show notification for this emergency
        _showTopSnackBar(
          message: '🚨 Emergency: ${emergency.attendeeName} needs assistance!',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
          icon: const Icon(Icons.warning, color: Colors.white),
          action: SnackBarAction(
            label: 'RESPOND',
            textColor: Colors.white,
            onPressed: () async {
              await _handleEmergencyResponseFromDatabase(emergency);
            },
          ),
        );
      }
    }
    
    // Clean up notifications for resolved emergencies
    _notifiedEmergencies.removeWhere((id) => 
        !emergencies.any((emergency) => emergency.emergencyId == id));
  }

  /// Handle volunteer responding to database emergency
  Future<void> _handleEmergencyResponseFromDatabase(Emergency emergency) async {
    // Show EmergencyResponseCard for volunteers to respond
    if (_userRole == 'Volunteer' && 
        !emergency.responses.containsKey(FirebaseAuth.instance.currentUser?.uid)) {
      
      setState(() {
        _currentEmergencyResponse = emergency;
      });
      
      // Focus map on emergency location
      _mapController.move(emergency.location, 16.0);
      
      // Show notification to volunteer
      if (mounted) {
        _showTopSnackBar(
          message: '🚨 New emergency alert! Respond to help.',
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
          icon: const Icon(Icons.emergency, color: Colors.white),
        );
      }
    }
  }

  Future<void> _setupInitialData() async {
    await _getUserRole();
    await _setupLocationTracking();
    _listenToGroupLocations();
    _listenToPOIs();
    _startEmergencyListeners();
    // Initialize emergency management AFTER user role is fetched
    await _initializeEmergencyManagement();
  }

  Future<void> _getUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && mounted) {
        setState(() {
          _userRole = userDoc.data()?['role'] as String?;
        });
        
        // Reinitialize managers with the user role
        _initializeManagers();
      }
    } catch (e) {
      AppLogger.logError('Error getting user role', e);
    }
  }

  Future<void> _setupLocationTracking() async {
    final success = await _locationManager.setupLocationTracking();
    if (!success) return;
    
    _locationManager.startLocationUpdates((locationData) {
      setState(() {
        _locationManager.currentLocation = locationData;
      });
      _updateUserLocation(locationData);
    });
  }

  Future<void> _updateUserLocation(LocationData locationData) async {
    try {
      _locationManager.isEmergency = _isEmergency;
      _locationManager.userRole = _userRole;
      await _locationManager.updateUserLocationInFirebase(locationData);
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          'Failed to update location: ${ErrorHandler.getFirebaseErrorMessage(e)}',
          onRetry: () => _updateUserLocation(locationData),
        );
      }
    }
  }

  void _listenToGroupLocations() {
    _groupLocationsSubscription = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('locations')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        final allMembers = snapshot.docs
            .map((doc) => UserLocation.fromMap(doc.data()))
            .toList();
        
        List<UserLocation> filteredMembers;
        if (_userRole == 'Attendee') {
          final now = DateTime.now();
          final activeThreshold = now.subtract(const Duration(minutes: 5));
          
          filteredMembers = allMembers.where((member) {
            return member.lastUpdated.isAfter(activeThreshold);
          }).toList();
        } else {
          filteredMembers = allMembers;
        }
        
        setState(() {
          _groupMembers = filteredMembers;
        });
      }
    });
  }

  void _listenToPOIs() {
    _poisSubscription = FirebaseFirestore.instance
        .collection('pois')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _pois = snapshot.docs
              .map((doc) => POI.fromMap(doc.data()))
              .toList();
        });
      }
    });
  }

  void _startEmergencyListeners() {
    // UNIFIED EMERGENCY SYSTEM: Only use Emergency objects via EmergencyManagementService
    // Emergency notifications are handled by _initializeEmergencyManagement via _handleNewEmergencyNotifications
    
    // Note: Old UserLocation-based emergency system has been completely removed
    // All emergency functionality now uses the Emergency object model for consistency
  }

  Future<void> _toggleEmergency() async {
    // Only allow attendees to toggle emergency
    if (_userRole != 'Attendee') return;
    
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      if (!_isEmergency) {
        // STRICT ENFORCEMENT: Check for existing emergency before creating
        AppLogger.logInfo('Checking for existing emergency before creation...');
        final existingEmergency = await EmergencyDatabaseService.getUserActiveEmergency(userId);
        if (existingEmergency != null) {
          AppLogger.logWarning('BLOCKED: User $userId already has active emergency: ${existingEmergency.emergencyId}');
          
          // Update UI state to reflect existing emergency
          setState(() {
            _isEmergency = true;
            _locationManager.isEmergency = true;
          });
          _locationManager.updateEmergencyStatus(true);
          
          if (mounted) {
            _showTopSnackBar(
              message: '🚨 You already have an active emergency! Only one emergency per user allowed.',
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
              icon: const Icon(Icons.block, color: Colors.white),
            );
          }
          return; // HARD STOP - Don't create a new emergency
        }

        // CREATING NEW EMERGENCY - Unified system
        if (_locationManager.currentLocation == null) {
          throw Exception('Location not available');
        }
        
        final currentLocation = LatLng(
          _locationManager.currentLocation!.latitude!,
          _locationManager.currentLocation!.longitude!,
        );
        
        // Create emergency using unified system
        final emergency = await EmergencyDatabaseService.createEmergencyWithState(
          attendeeId: userId,
          attendeeName: FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown User',
          groupId: widget.groupId,
          location: currentLocation,
          message: null,
        );
        
        // Update local state and location manager
        setState(() {
          _isEmergency = true;
          _locationManager.isEmergency = true;
        });
        
        // Update location manager for enhanced tracking
        _locationManager.updateEmergencyStatus(true);
        
        if (mounted) {
          _showTopSnackBar(
            message: '🚨 Emergency activated! Volunteers have been notified.',
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            icon: const Icon(Icons.emergency, color: Colors.white),
          );
        }
        
        AppLogger.logInfo('Emergency created with unified system: ${emergency.emergencyId}');
        
      } else {
        // RESOLVING EXISTING EMERGENCY - Enhanced cleanup
        // Find current user's emergency in active emergencies
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId != null) {
          final userEmergency = _activeEmergencies.firstWhere(
            (emergency) => emergency.attendeeId == userId,
            orElse: () => Emergency(
              emergencyId: '',
              attendeeId: '',
              attendeeName: '',
              groupId: '',
              location: const LatLng(0, 0),
              status: EmergencyStatus.resolved,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              responses: {},
              resolvedBy: const EmergencyResolution(attendee: false, hasVolunteerCompleted: false),
            ),
          );
          
          if (userEmergency.emergencyId.isNotEmpty) {
            // Resolve emergency with complete cleanup
            await EmergencyManagementService.resolveEmergency(userEmergency.emergencyId);
          }
        }
        
        // Update local state and location manager
        setState(() {
          _isEmergency = false;
          _locationManager.isEmergency = false;
        });
        
        // Update location manager to normal tracking
        _locationManager.updateEmergencyStatus(false);
        
        if (mounted) {
          _showTopSnackBar(
            message: '✅ Emergency resolved! Thank you for your safety.',
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            icon: const Icon(Icons.check_circle, color: Colors.white),
          );
        }
      }
      
      // Force refresh to update UI
      if (mounted) {
        setState(() {
          // This will trigger a complete rebuild with new emergency status
        });
      }
      
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          'Failed to update emergency status: ${ErrorHandler.getFirebaseErrorMessage(e)}',
          onRetry: _toggleEmergency,
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_isMapReady) return;
    
    try {
      final locationData = await _locationManager.getCurrentLocation();
      if (locationData != null && mounted) {
        setState(() {
          _locationManager.currentLocation = locationData;
        });
        
        _mapController.move(
          LatLng(locationData.latitude!, locationData.longitude!),
          15,
        );
      }
    } catch (e) {
      AppLogger.logError('Error getting current location', e);
    }
  }

  void _toggleMarkerManagement() {
    if (_userRole != 'Organizer') return;
    
    setState(() {
      _isMarkerManagementMode = !_isMarkerManagementMode;
    });

    // Show instructions to user
    _showTopSnackBar(
      message: _isMarkerManagementMode 
          ? 'Tap markers to manage them' 
          : 'Marker management disabled',
      backgroundColor: Colors.blue,
      duration: const Duration(seconds: 2),
      icon: Icon(
        _isMarkerManagementMode ? Icons.edit : Icons.visibility_off,
        color: Colors.white,
      ),
    );
  }

  void _onUserMarkerTap(UserLocation user) {
    // Normal behavior: select for routing
    // Emergency responses are now handled via the database emergency markers only
    setState(() => _selectedMember = user);
    _calculateRoute();
  }

  void _onUserMarkerLongPress(UserLocation user) {
    // For user markers, fall back to regular tap behavior
    // Emergency responses are now handled via the database emergency markers only
    _onUserMarkerTap(user);
  }

  void _onPOITap(POI poi) {
    if (_isMarkerManagementMode && _userRole == 'Organizer') {
      // Show management options
      _showMarkerActionBottomSheet(poi);
    } else {
      // Normal behavior: select for routing
      setState(() => _selectedPOI = poi);
      _calculatePOIRoute();
    }
  }

  void _onPOILongPress(POI poi) {
    // Organizers can long-press any marker to see details and management options
    if (_userRole == 'Organizer') {
      _showMarkerActionBottomSheet(poi);
    } else {
      // For non-organizers, show basic marker information
      _showMarkerInfoDialog(poi);
    }
  }

  void _showMarkerActionBottomSheet(POI poi) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MarkerActionBottomSheet(
        poi: poi,
        userRole: _userRole ?? 'Attendee',
        onClose: () => Navigator.of(context).pop(),
        onMarkerUpdated: () {
          // Refresh happens automatically via stream
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _showMarkerInfoDialog(POI poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(poi.type.iconData, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  poi.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (poi.description.isNotEmpty) ...[
              const Text(
                'Description:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(poi.description),
              const SizedBox(height: 12),
            ],
            Text(
              'Type: ${poi.type.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Location: ${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _selectedPOI = poi);
              _calculatePOIRoute();
            },
            child: const Text('Get Directions'),
          ),
        ],
      ),
    );
  }

  Future<void> _calculateRoute() async {
    if (_selectedMember == null || _locationManager.currentLocation == null) {
      setState(() {
        _currentRoute = [];
        _routeInfo = '';
      });
      return;
    }
    
    setState(() {
      _isLoadingRoute = true;
      _routeInfo = 'Calculating route...';
    });
    
    try {
      final start = LatLng(
        _locationManager.currentLocation!.latitude!, 
        _locationManager.currentLocation!.longitude!
      );
      final end = LatLng(_selectedMember!.latitude, _selectedMember!.longitude);
      
      final route = await RoutingService.getWalkingRoute(start, end);
      
      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
          
          if (route.length > 2) {
            final distance = RoutingService.calculateRouteDistance(route);
            final time = RoutingService.estimateWalkingTime(route);
            _routeInfo = '${RoutingService.formatDistance(distance)} • ${RoutingService.formatTime(time)} walking';
          } else {
            final distance = _calculateDistance(
              start.latitude, start.longitude,
              end.latitude, end.longitude,
            );
            _routeInfo = '${distance.round()}m direct path';
          }
        });
      }
    } catch (e) {
      debugPrint('Error calculating route: $e');
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
          _routeInfo = 'Route calculation failed';
        });
      }
    }
  }

  Future<void> _calculatePOIRoute() async {
    if (_selectedPOI == null || _locationManager.currentLocation == null) {
      setState(() {
        _currentRoute = [];
        _routeInfo = '';
      });
      return;
    }
    
    setState(() {
      _isLoadingRoute = true;
      _routeInfo = 'Calculating route...';
    });
    
    try {
      final start = LatLng(
        _locationManager.currentLocation!.latitude!, 
        _locationManager.currentLocation!.longitude!
      );
      final end = LatLng(_selectedPOI!.latitude, _selectedPOI!.longitude);
      
      final route = await RoutingService.getWalkingRoute(start, end);
      
      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
          
          if (route.length > 2) {
            final distance = RoutingService.calculateRouteDistance(route);
            final time = RoutingService.estimateWalkingTime(route);
            _routeInfo = '${RoutingService.formatDistance(distance)} • ${RoutingService.formatTime(time)} walking';
          } else {
            final distance = _calculateDistance(
              start.latitude, start.longitude,
              end.latitude, end.longitude,
            );
            _routeInfo = '${distance.round()}m direct path';
          }
        });
      }
    } catch (e) {
      debugPrint('Error calculating POI route: $e');
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
          _routeInfo = 'Route calculation failed';
        });
      }
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLon = (lon2 - lon1) * (pi / 180);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Start POI placement mode (Organizers only)
  void _startPOIPlacement() {
    if (_userRole != 'Organizer') return;
    
    setState(() {
      _isPlacingPOI = true;
    });
    
    _showTopSnackBar(
      message: 'Tap on the map to place a POI',
      backgroundColor: Colors.blue,
      duration: const Duration(seconds: 3),
      icon: const Icon(Icons.add_location, color: Colors.white),
    );
  }

  /// Show POI creation dialog
  void _showPOICreationDialog(LatLng position) {
    String poiName = '';
    String poiDescription = '';
    MarkerType selectedType = MarkerType.information;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Point of Interest'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'POI Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => poiName = value,
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (value) => poiDescription = value,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MarkerType>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'POI Type',
                    border: OutlineInputBorder(),
                  ),
                  items: MarkerType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          Icon(type.iconData, size: 20),
                          const SizedBox(width: 8),
                          Text(type.displayName),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (MarkerType? newType) {
                    if (newType != null) {
                      setDialogState(() => selectedType = newType);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => _isPlacingPOI = false);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (poiName.trim().isEmpty) {
                  _showTopSnackBar(
                    message: 'Please enter a POI name',
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 2),
                    icon: const Icon(Icons.warning, color: Colors.white),
                  );
                  return;
                }
                
                Navigator.of(dialogContext).pop();
                await _createPOI(position, poiName.trim(), poiDescription.trim(), selectedType);
                setState(() => _isPlacingPOI = false);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  /// Create POI in Firestore
  Future<void> _createPOI(LatLng position, String name, String description, MarkerType type) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final poi = POI(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        type: type,
        latitude: position.latitude,
        longitude: position.longitude,
        description: description,
        createdBy: user.uid,
        createdAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('pois')
          .doc(poi.id)
          .set(poi.toMap());

      if (mounted) {
        _showTopSnackBar(
          message: '${type.displayName} created successfully',
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          icon: const Icon(Icons.check_circle, color: Colors.white),
        );
      }
    } catch (e) {
      debugPrint('Error creating POI: $e');
      if (mounted) {
        _showTopSnackBar(
          message: 'Error creating POI: $e',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          icon: const Icon(Icons.error, color: Colors.white),
        );
      }
    }
  }

  /// Build broadcast button with unread count badge
  Widget _buildBroadcastButton() {
    return StreamBuilder<int>(
      stream: BroadcastService.getUnreadCountStream(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        
        return Stack(
          children: [
            FloatingActionButton(
              heroTag: "broadcast",
              onPressed: _navigateToBroadcasts,
              backgroundColor: AppColors.primary,
              child: const Icon(
                Icons.campaign,
                color: Colors.white,
                size: 24,
              ),
            ),
            
            // Unread count badge
            if (unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Navigate to broadcast list screen
  Future<void> _navigateToBroadcasts() async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const BroadcastListScreen(),
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.logError('Error navigating to broadcasts', e, stackTrace);
    }
  }

  @override
  void dispose() {
    try {
      AppLogger.logInfo('MapScreen disposing resources');
      _groupLocationsSubscription?.cancel();
      _poisSubscription?.cancel();
      _emergenciesSubscription?.cancel();
      
      // Cancel additional emergency subscriptions for volunteers
      for (final subscription in _additionalEmergencySubscriptions) {
        subscription.cancel();
      }
      _additionalEmergencySubscriptions.clear();
      
      _locationManager.dispose();
      // REMOVED: _emergencyManager.dispose() - using EmergencyManagementService instead
      EmergencyManagementService.dispose();
      _mapController.dispose();
      AppLogger.logInfo('MapScreen resources disposed successfully');
    } catch (e) {
      AppLogger.logError('Error disposing MapScreen resources', e);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Update marker manager state
    _markerManager = MarkerManager(
      userRole: _userRole,
      isMapReady: _isMapReady,
      mapController: _mapController,
    );

    return Scaffold(
      floatingActionButton: null,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(12.9716, 77.5946),
              initialZoom: 15,
              maxZoom: 18,
              minZoom: 3,
              keepAlive: true,
              onMapReady: () {
                setState(() => _isMapReady = true);
                _getCurrentLocation();
              },
              onTap: (tapPosition, point) {
                if (_isPlacingPOI && _userRole == 'Organizer') {
                  // Handle POI placement
                  _showPOICreationDialog(point);
                } else if (_selectedMember != null || _selectedPOI != null) {
                  // Clear selections
                  setState(() {
                    _selectedMember = null;
                    _selectedPOI = null;
                    _currentRoute = [];
                    _routeInfo = '';
                  });
                }
              },
              onMapEvent: (event) {
                if (_isMapReady && mounted) {
                  setState(() {});
                }
              },
            ),
            children: [
              // Tile layer
              TileLayer(
                urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.simha_link',
                maxZoom: 19,
                keepBuffer: 8,
                tileProvider: NetworkTileProvider(),
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              // Current location circle (lowest priority - should be underneath everything)
              if (_locationManager.currentLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(
                        _locationManager.currentLocation!.latitude!,
                        _locationManager.currentLocation!.longitude!
                      ),
                      radius: _locationManager.currentLocation!.accuracy ?? 50.0, // Use GPS accuracy or 50m default
                      useRadiusInMeter: true, // Geographic scaling - radius in real-world meters
                      color: _isEmergency 
                          ? AppColors.mapEmergency.withOpacity(0.15)
                          : AppColors.mapCurrentUser.withOpacity(0.2),
                      borderColor: _isEmergency ? AppColors.mapEmergency : AppColors.mapCurrentUser,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              // Route polylines (before markers for better visibility)
              if (_currentRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _currentRoute,
                      color: AppColors.primary,
                      strokeWidth: 4,
                      pattern: const StrokePattern.dotted(),
                    ),
                  ],
                ),
              // POI markers (medium priority)
              MarkerLayer(
                markers: _markerManager.buildPOIMarkers(
                  pois: _pois,
                  onPOITap: _onPOITap,
                  onPOILongPress: _onPOILongPress,
                ),
              ),
              // User markers with clustering (higher priority than POI)
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  markers: _markerManager.buildMarkers(
                    groupMembers: _groupMembers,
                    activeEmergencies: _activeEmergencies, // Pass active emergencies to avoid duplicates
                    nearbyVolunteers: [], // Disable old system
                    allVolunteers: [], // Disable old system
                    currentLocation: _locationManager.currentLocation,
                    onUserMarkerTap: _onUserMarkerTap,
                    onUserMarkerLongPress: _onUserMarkerLongPress,
                  ),
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.primary,
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Emergency markers (HIGHEST PRIORITY - Always on top)
              MarkerLayer(
                markers: _buildEmergencyMarkers(),
              ),
            ],
          ),
          
          // Info panel
          MapInfoPanel(
            selectedMember: _selectedMember,
            selectedPOI: _selectedPOI,
            routeInfo: _routeInfo,
            isLoadingRoute: _isLoadingRoute,
            onClose: () {
              setState(() {
                _selectedMember = null;
                _selectedPOI = null;
                _currentRoute = [];
                _routeInfo = '';
              });
            },
          ),
          
          // Legend
          if (!_isPlacingPOI)
            MapLegend(userRole: _userRole),
          
          // Floating action buttons
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Broadcast button (always visible)
                _buildBroadcastButton(),
                const SizedBox(height: 12), // Increased spacing
                
                // POI Creation button (Organizers only)
                if (_userRole == 'Organizer' && !_isPlacingPOI) ...[
                  FloatingActionButton(
                    heroTag: "addPOI",
                    onPressed: _startPOIPlacement,
                    backgroundColor: AppColors.secondary,
                    child: const Icon(Icons.add_location, size: 24),
                  ),
                  const SizedBox(height: 12),
                  // Marker management button
                  FloatingActionButton(
                    heroTag: "marker_management",
                    onPressed: _toggleMarkerManagement,
                    backgroundColor: _isMarkerManagementMode ? AppColors.primary : AppColors.surface,
                    foregroundColor: _isMarkerManagementMode ? Colors.white : AppColors.primary,
                    child: Icon(
                      _isMarkerManagementMode ? Icons.edit_off : Icons.edit_location,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                
                // Emergency button (Attendees only)
                if (_userRole == 'Attendee') ...[
                  FloatingActionButton(
                    heroTag: "emergency",
                    onPressed: () async {
                      if (_isEmergency) {
                        // Show resolve dialog for active emergencies
                        final shouldResolve = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('🟢 Resolve Emergency'),
                            content: const Text('Mark this emergency as resolved?\n\nThis will notify all volunteers that you are safe.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                child: const Text('✅ Resolve Emergency'),
                              ),
                            ],
                          ),
                        );
                        
                        if (shouldResolve == true) {
                          await _resolveEmergency(FirebaseAuth.instance.currentUser!.uid);
                        }
                      } else {
                        // Normal emergency activation
                        await _toggleEmergency();
                      }
                    },
                    backgroundColor: _isEmergency ? AppColors.mapEmergency : AppColors.surface,
                    foregroundColor: _isEmergency ? Colors.white : AppColors.mapEmergency,
                    child: Icon(
                      _isEmergency ? Icons.emergency : Icons.emergency_outlined,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Location button (always visible)
                FloatingActionButton(
                  heroTag: "location",
                  onPressed: _getCurrentLocation,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.my_location, color: AppColors.textOnPrimary, size: 24),
                ),
              ],
            ),
          ),
          
          // Emergency Response Card for Volunteers - Connected to Database
          // Positioned with better spacing and responsiveness
          // Emergency Response Card for volunteers - positioned at bottom
          if (_userRole == 'Volunteer' && _currentEmergencyResponse != null) ...[
            // DEBUG: Log when card should show
            Builder(
              builder: (context) {
                print('🔍 DEBUG BUILD: Emergency response card should show - Role: $_userRole, Emergency: ${_currentEmergencyResponse?.emergencyId}');
                return Container();
              },
            ),
            Positioned(
              bottom: 16, // At bottom of screen
              left: 16,
              right: 16,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4, // Limit height for swipe area
                ),
                child: EmergencyResponseCard(
                  emergency: _currentEmergencyResponse,
                  response: EmergencyResponse(
                    responseId: '${_currentEmergencyResponse!.emergencyId}_${FirebaseAuth.instance.currentUser?.uid ?? ''}',
                    emergencyId: _currentEmergencyResponse!.emergencyId,
                    volunteerId: FirebaseAuth.instance.currentUser?.uid ?? '',
                    volunteerName: FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown Volunteer',
                    status: _getCurrentVolunteerStatus(_currentEmergencyResponse!),
                    timestamp: _currentEmergencyResponse!.createdAt,
                    lastUpdated: _currentEmergencyResponse!.updatedAt,
                    volunteerLocation: _locationManager.currentLocation?.latitude != null && 
                                       _locationManager.currentLocation?.longitude != null
                        ? LatLng(_locationManager.currentLocation!.latitude!, _locationManager.currentLocation!.longitude!)
                        : null,
                    notes: _currentEmergencyResponse!.message,
                  ),
                  onStatusUpdate: (status) async {
                    print('🎯 DEBUG: Status update triggered with: ${status.name}');
                    if (_currentEmergencyResponse != null) {
                      print('🎯 DEBUG: Calling _updateVolunteerResponseStatus');
                      await _updateVolunteerResponseStatus(_currentEmergencyResponse!, status);
                      
                      // If volunteer marked as completed, clear the current response
                      if (status == EmergencyResponseStatus.completed && mounted) {
                        setState(() {
                          _currentEmergencyResponse = null;
                        });
                      }
                    }
                  },
                  onCancel: () async {
                    if (_currentEmergencyResponse != null && FirebaseAuth.instance.currentUser != null) {
                      await EmergencyDatabaseService.removeVolunteerResponse(
                        emergencyId: _currentEmergencyResponse!.emergencyId,
                        volunteerId: FirebaseAuth.instance.currentUser!.uid,
                      );
                      setState(() {
                        _currentEmergencyResponse = null;
                      });
                    }
                  },
                  onViewEmergency: () {
                    if (_currentEmergencyResponse != null) {
                      _focusOnLocation(_currentEmergencyResponse!.location);
                    }
                  },
                ),
              ),
            ),
          ],
          
          // Role info
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  _userRole == 'Attendee' ? 'Tap markers for directions' : 
                  _userRole == 'Volunteer' ? 'Monitor emergencies & assist' :
                  _userRole == 'Organizer' ? 
                    (_isMarkerManagementMode ? 'Tap markers to manage them' : 'Long-press markers to manage them') : 
                  'Map view',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper method to show SnackBar at the top of the screen
  void _showTopSnackBar({
    required String message,
    required Color backgroundColor,
    Duration duration = const Duration(seconds: 3),
    Widget? icon,
    SnackBarAction? action,
  }) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              icon,
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(
          top: 120, // Increased from 80 to avoid role info card
          left: 16,
          right: 16,
          bottom: 16,
        ),
        action: action,
      ),
    );
  }

  /// Update volunteer response status using new enhanced emergency system
  Future<void> _updateVolunteerResponseStatus(Emergency emergency, EmergencyResponseStatus newStatus) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      print('🔄 Updating volunteer status to: ${newStatus.name}');

      // Use the new enhanced pipeline methods
      switch (newStatus) {
        case EmergencyResponseStatus.responding:
          // Update to responding status
          await EmergencyManagementService.updateVolunteerStatus(
            emergencyId: emergency.emergencyId,
            status: EmergencyVolunteerStatus.responding,
          );
          break;
          
        case EmergencyResponseStatus.enRoute:
          // Update to en route status
          await EmergencyManagementService.updateVolunteerStatus(
            emergencyId: emergency.emergencyId,
            status: EmergencyVolunteerStatus.enRoute,
          );
          break;
          
        case EmergencyResponseStatus.arrived:
          // Mark as arrived
          await EmergencyManagementService.volunteerMarkArrived(
            emergencyId: emergency.emergencyId,
          );
          break;
          
        case EmergencyResponseStatus.verified:
          // Mark emergency as verified and update volunteer status
          await EmergencyManagementService.updateVolunteerStatus(
            emergencyId: emergency.emergencyId,
            status: EmergencyVolunteerStatus.verified,
          );
          
          // Verify the emergency as real using the existing service
          await EmergencyManagementService.volunteerVerifyEmergency(
            emergencyId: emergency.emergencyId,
            isReal: true,
            markAsSerious: false,
          );
          
          _showTopSnackBar(
            message: '✅ Emergency verified - proceeding to assist',
            backgroundColor: Colors.teal,
            duration: const Duration(seconds: 3),
            icon: const Icon(Icons.verified, color: Colors.white),
          );
          print('✅ Emergency verified by volunteer');
          break;
          
        case EmergencyResponseStatus.assisting:
          // Start assisting
          await EmergencyManagementService.updateVolunteerStatus(
            emergencyId: emergency.emergencyId,
            status: EmergencyVolunteerStatus.assisting,
          );
          print('🚑 Volunteer started assisting');
          break;
          
        case EmergencyResponseStatus.completed:
          // Resolve emergency
          await EmergencyManagementService.volunteerResolveEmergency(
            emergencyId: emergency.emergencyId,
          );
          
          // Clear current emergency response
          setState(() {
            _currentEmergencyResponse = null;
          });
          
          _showTopSnackBar(
            message: '✅ Emergency marked as resolved',
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            icon: const Icon(Icons.check_circle, color: Colors.white),
          );
          print('✅ Emergency resolved by volunteer');
          break;
          
        case EmergencyResponseStatus.unavailable:
          // Remove volunteer response
          await EmergencyDatabaseService.removeVolunteerResponse(
            emergencyId: emergency.emergencyId,
            volunteerId: userId,
          );
          
          // Clear current emergency response
          setState(() {
            _currentEmergencyResponse = null;
          });
          break;
          
        default:
          break;
      }
      
      // Refresh the emergency data to reflect the updated status
      await _refreshCurrentEmergencyData(emergency.emergencyId);
      
      // Show confirmation message
      if (mounted) {
        _showTopSnackBar(
          message: '✅ Status updated to: ${newStatus.displayName}',
          backgroundColor: newStatus.statusColor,
          duration: const Duration(seconds: 2),
          icon: const Icon(Icons.update, color: Colors.white),
        );
      }
    } catch (e) {
      AppLogger.logError('Error updating volunteer response status', e);
      
      if (mounted) {
        _showTopSnackBar(
          message: '❌ Failed to update status: $e',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          icon: const Icon(Icons.error, color: Colors.white),
        );
      }
    }
  }

  /// Refresh the current emergency data to reflect updated status
  Future<void> _refreshCurrentEmergencyData(String emergencyId) async {
    try {
      print('🔄 Refreshing emergency data for: $emergencyId');
      
      // Get updated emergency data from database
      final updatedEmergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      
      if (updatedEmergency != null && mounted) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null && updatedEmergency.responses.containsKey(currentUserId)) {
          final volunteerStatus = updatedEmergency.responses[currentUserId]!.status;
          print('🔄 Updated volunteer status: ${volunteerStatus.name}');
        }
        
        setState(() {
          // Update the current emergency response with fresh data
          _currentEmergencyResponse = updatedEmergency;
          
          // Update the emergency in the active emergencies list
          final index = _activeEmergencies.indexWhere((e) => e.emergencyId == emergencyId);
          if (index != -1) {
            _activeEmergencies[index] = updatedEmergency;
          }
        });
        
        print('🔄 Emergency data refreshed successfully for: $emergencyId');
      } else {
        print('❌ No updated emergency data found for: $emergencyId');
      }
    } catch (e) {
      print('❌ Error refreshing emergency data: $e');
    }
  }

  /// Handle emergency resolution - called by both attendees and volunteers
  Future<void> _resolveEmergency(String emergencyId) async {
    try {
      if (_userRole == 'Attendee') {
        // Attendee resolving their own emergency using new system
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId != null) {
          // Find current user's emergency in active emergencies
          final userEmergency = _activeEmergencies.firstWhere(
            (emergency) => emergency.attendeeId == userId,
            orElse: () => Emergency(
              emergencyId: '',
              attendeeId: '',
              attendeeName: '',
              groupId: '',
              location: const LatLng(0, 0),
              status: EmergencyStatus.resolved,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              responses: {},
              resolvedBy: const EmergencyResolution(attendee: false, hasVolunteerCompleted: false),
            ),
          );
          
          if (userEmergency.emergencyId.isNotEmpty) {
            // Resolve emergency using new system
            await EmergencyManagementService.resolveEmergency(userEmergency.emergencyId);
            
            // Update local state
            setState(() {
              _isEmergency = false;
              _locationManager.isEmergency = false;
            });
            
            // Update location manager to normal tracking
            _locationManager.updateEmergencyStatus(false);
          }
        }
        
        if (mounted) {
          _showTopSnackBar(
            message: '✅ Emergency resolved! Thank you for your safety.',
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            icon: const Icon(Icons.check_circle, color: Colors.white),
          );
        }
      } else if (_userRole == 'Volunteer' && _currentEmergencyResponse != null) {
        // Volunteer marking emergency as completed - use new system
        await _updateVolunteerResponseStatus(_currentEmergencyResponse!, EmergencyResponseStatus.completed);
        
        // Check if attendee has also resolved the emergency
        await _checkAndCleanupResolvedEmergency(emergencyId);
      }
      
      // Force refresh of emergency data
      if (mounted) {
        setState(() {
          // This will trigger a rebuild and update emergency status
        });
      }
    } catch (e) {
      if (mounted) {
        _showTopSnackBar(
          message: '❌ Failed to resolve emergency: $e',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          icon: const Icon(Icons.error, color: Colors.white),
        );
      }
    }
  }

  /// Check if emergency is resolved by both sides and clean up database  
  Future<void> _checkAndCleanupResolvedEmergency(String emergencyId) async {
    try {
      // Use the new emergency system to check resolution status
      final emergency = await EmergencyDatabaseService.getEmergency(emergencyId);
      if (emergency == null) return;
      
      // Check if emergency is resolved
      final isResolved = emergency.status == EmergencyStatus.resolved;
      
      // Check if volunteer has completed their response
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final volunteerCompleted = currentUserId != null && 
          emergency.responses.containsKey(currentUserId) &&
          emergency.responses[currentUserId]?.status == EmergencyVolunteerStatus.completed;
      
      if (isResolved && volunteerCompleted) {
        // Both sides have resolved - clean up is handled by EmergencyManagementService
        if (mounted) {
          _showTopSnackBar(
            message: '🎉 Emergency fully resolved and cleaned up!',
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            icon: const Icon(Icons.celebration, color: Colors.white),
          );
        }
      }
    } catch (e) {
      // Log error but don't show to user as this is background cleanup
      AppLogger.logError('Error checking emergency resolution status', e);
    }
  }

  /// Initiate volunteer response to an emergency
  Future<void> _initiateVolunteerResponse(Emergency emergency) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showTopSnackBar(
        message: '❌ You must be logged in to respond to emergencies',
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
        icon: const Icon(Icons.error, color: Colors.white),
      );
      return;
    }

    // Check if volunteer has already responded
    if (emergency.responses.containsKey(currentUser.uid)) {
      _showTopSnackBar(
        message: '⚠️ You are already responding to this emergency',
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        icon: const Icon(Icons.info, color: Colors.white),
      );
      return;
    }

    try {
      // Get current location for volunteer response
      LatLng? currentLocation;
      final locationData = _locationManager.currentLocation;
      if (locationData?.latitude != null && locationData?.longitude != null) {
        currentLocation = LatLng(locationData!.latitude!, locationData.longitude!);
      }

      if (currentLocation == null) {
        _showTopSnackBar(
          message: '❌ Cannot determine your location. Please ensure GPS is enabled.',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          icon: const Icon(Icons.location_off, color: Colors.white),
        );
        return;
      }

      // Show loading indicator
      _showTopSnackBar(
        message: '⏳ Initiating emergency response...',
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
        icon: const Icon(Icons.hourglass_empty, color: Colors.white),
      );

      // STEP 1: Record volunteer response in database using new enhanced method
      await EmergencyManagementService.volunteerAcceptEmergency(
        emergencyId: emergency.emergencyId,
        volunteerName: currentUser.displayName ?? 'Unknown Volunteer',
        volunteerLocation: currentLocation,
      );

      // STEP 2: Set this as the current emergency response for the UI
      setState(() {
        _currentEmergencyResponse = emergency;
      });

      // STEP 3: Focus map on emergency location
      _focusOnLocation(emergency.location);

      // STEP 4: Show success notification
      _showTopSnackBar(
        message: '✅ Emergency response initiated! Use the response card to update your status.',
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        icon: const Icon(Icons.check_circle, color: Colors.white),
      );

      // STEP 5: Notify attendee that help is coming
      await _notifyAttendeeHelpComing(emergency);

    } catch (e) {
      AppLogger.logError('Error initiating volunteer response', e);
      
      _showTopSnackBar(
        message: '❌ Failed to initiate response: ${e.toString()}',
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        icon: const Icon(Icons.error, color: Colors.white),
      );
    }
  }

  /// Notify attendee that a volunteer is coming to help
  Future<void> _notifyAttendeeHelpComing(Emergency emergency) async {
    try {
      // Calculate distance to emergency
      final currentLocation = _locationManager.currentLocation;
      if (currentLocation?.latitude != null && currentLocation?.longitude != null) {
        final distance = _calculateDistance(
          currentLocation!.latitude!,
          currentLocation.longitude!,
          emergency.location.latitude,
          emergency.location.longitude,
        );

        final distanceKm = distance / 1000;
        final estimatedTime = (distanceKm / 5.0 * 60).round(); // Assuming 5 km/h walking speed

        // Log the volunteer response for development purposes
        AppLogger.logInfo(
          'Volunteer ${FirebaseAuth.instance.currentUser?.displayName} responding to emergency ${emergency.emergencyId}. '
          'Distance: ${distance.round()}m, Estimated time: ${estimatedTime}min'
        );

        // Show notification to the volunteer about distance
        _showTopSnackBar(
          message: '📍 You are ${EmergencyManagementService.formatDistance(distance)} from the emergency',
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
          icon: const Icon(Icons.navigation, color: Colors.white),
        );

        // TODO: Implement push notification to attendee
        // NotificationService.sendToUser(
        //   userId: emergency.attendeeId,
        //   title: 'Help is on the way!',
        //   body: 'A volunteer is approximately ${estimatedTime} minutes away.',
        // );
      }
    } catch (e) {
      AppLogger.logError('Error notifying attendee', e);
    }
  }

  // Top navigation AppBar removed per new UI. Helper methods were deleted.

  /// Get current volunteer's response status for an emergency
  EmergencyResponseStatus _getCurrentVolunteerStatus(Emergency emergency) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    print('🎯 DEBUG STATUS: Current user ID: $currentUserId');
    
    if (currentUserId == null) {
      print('🎯 DEBUG STATUS: No user ID, returning notified');
      return EmergencyResponseStatus.notified;
    }

    final response = emergency.responses[currentUserId];
    print('🎯 DEBUG STATUS: Emergency responses: ${emergency.responses.keys.toList()}');
    print('🎯 DEBUG STATUS: User response: ${response?.status.name ?? "null"}');
    
    if (response == null) {
      print('🎯 DEBUG STATUS: No response found, returning notified');
      return EmergencyResponseStatus.notified;
    }

    final mappedStatus = switch (response.status) {
      EmergencyVolunteerStatus.notified => EmergencyResponseStatus.notified,
      EmergencyVolunteerStatus.responding => EmergencyResponseStatus.responding,
      EmergencyVolunteerStatus.enRoute => EmergencyResponseStatus.enRoute,
      EmergencyVolunteerStatus.arrived => EmergencyResponseStatus.arrived,
      EmergencyVolunteerStatus.verified => EmergencyResponseStatus.verified,
      EmergencyVolunteerStatus.assisting => EmergencyResponseStatus.assisting,
      EmergencyVolunteerStatus.completed => EmergencyResponseStatus.completed,
      EmergencyVolunteerStatus.unavailable => EmergencyResponseStatus.unavailable,
    };
    
    print('🎯 DEBUG STATUS: Mapped ${response.status.name} to ${mappedStatus.name}');
    return mappedStatus;
  }

  /// Focus map on a specific location
  void _focusOnLocation(LatLng location) {
    _mapController.move(location, 16.0);
  }

  /// Build emergency markers for the map with maximum visual priority
  List<Marker> _buildEmergencyMarkers() {
    List<Marker> emergencyMarkers = [];
    
    AppLogger.logInfo('Building emergency markers: ${_activeEmergencies.length} active emergencies, user role: $_userRole');

    for (final emergency in _activeEmergencies) {
      AppLogger.logInfo('Processing emergency: ${emergency.attendeeName} (${emergency.emergencyId}), status: ${emergency.status.name}');
      
      // Skip resolved emergencies
      if (emergency.status == EmergencyStatus.resolved) {
        AppLogger.logInfo('Skipping resolved emergency: ${emergency.emergencyId}');
        continue;
      }

      // Use larger size for emergency markers to ensure visibility
      final baseMarkerSize = _markerManager.getGeographicMarkerSize(
        markerPosition: emergency.location,
        geoMarkerType: geo.MarkerType.emergency,
        minPixelSize: 40.0, // Increased minimum size
        maxPixelSize: 80.0, // Increased maximum size
      );
      
      // Add additional size boost for emergency markers
      final markerSize = (baseMarkerSize * 1.2).clamp(40.0, 90.0);
      final iconSize = (markerSize * 0.6).clamp(20.0, 36.0);
      final pulseSize = markerSize * 1.5; // For pulsing animation

      // Create emergency marker with maximum visual prominence
      emergencyMarkers.add(
        Marker(
          point: emergency.location,
          width: pulseSize, // Use larger size for pulsing effect
          height: pulseSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing background ring for animation
              AnimatedContainer(
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeInOut,
                width: pulseSize,
                height: pulseSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getEmergencyMarkerColor(emergency).withOpacity(0.3),
                  border: Border.all(
                    color: _getEmergencyMarkerColor(emergency).withOpacity(0.6),
                    width: 2.0,
                  ),
                ),
              ),
              // Main emergency marker
              GestureDetector(
                onTap: () => _onEmergencyMarkerTap(emergency),
                onLongPress: () => _onEmergencyMarkerLongPress(emergency),
                child: Container(
                  width: markerSize,
                  height: markerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getEmergencyMarkerColor(emergency),
                    border: Border.all(
                      color: Colors.white, 
                      width: 4.0, // Thick white border for contrast
                    ),
                    boxShadow: [
                      // Multiple shadows for maximum visibility
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: _getEmergencyMarkerColor(emergency).withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.emergency,
                    color: Colors.white,
                    size: iconSize,
                    shadows: const [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(1, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      
      AppLogger.logInfo('Created emergency marker for: ${emergency.attendeeName} at ${emergency.location}');
    }

    AppLogger.logInfo('Emergency markers built: ${emergencyMarkers.length} markers created');
    return emergencyMarkers;
  }

  /// Get appropriate color for emergency marker based on status
  Color _getEmergencyMarkerColor(Emergency emergency) {
    final hasVolunteers = emergency.responses.isNotEmpty;
    
    switch (emergency.status) {
      case EmergencyStatus.unverified:
        return hasVolunteers ? Colors.orange : Colors.red;
      case EmergencyStatus.accepted:
        return Colors.blue;
      case EmergencyStatus.inProgress:
        return Colors.purple;
      case EmergencyStatus.verified:
        return Colors.red;
      case EmergencyStatus.escalated:
        return Colors.deepOrange;
      case EmergencyStatus.resolved:
        return Colors.green;
      case EmergencyStatus.fake:
        return Colors.grey;
    }
  }

  /// Handle emergency marker tap
  void _onEmergencyMarkerTap(Emergency emergency) {
    // Focus on emergency location
    _focusOnLocation(emergency.location);

    // Show emergency info
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emergency,
                  color: _getEmergencyMarkerColor(emergency),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency Alert',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        emergency.attendeeName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (emergency.message != null) ...[
              Text(
                'Message:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(emergency.message!),
              const SizedBox(height: 16),
            ],
            Text(
              'Status: ${emergency.status.name.toUpperCase()}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _getEmergencyMarkerColor(emergency),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Volunteers responding: ${emergency.responses.length}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                if (_userRole == 'Volunteer') ...[
                  // DEBUG: Log button condition
                  Builder(
                    builder: (context) {
                      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                      final hasResponse = emergency.responses.containsKey(currentUserId);
                      print('🔍 DEBUG BUTTON: Current user ID: $currentUserId');
                      print('🔍 DEBUG BUTTON: Emergency responses: ${emergency.responses.keys.toList()}');
                      print('🔍 DEBUG BUTTON: Has response: $hasResponse');
                      print('🔍 DEBUG BUTTON: Will show: ${hasResponse ? "View Response" : "Respond"} button');
                      return Container();
                    },
                  ),
                  if (!emergency.responses.containsKey(FirebaseAuth.instance.currentUser?.uid))
                    // Show Respond button for new volunteers
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _initiateVolunteerResponse(emergency);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('🚨 Respond'),
                    )
                  else
                    // Show "View Response" button for volunteers already responding
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Set this emergency as current response to show the card
                        setState(() {
                          _currentEmergencyResponse = emergency;
                        });
                        _focusOnLocation(emergency.location);
                        
                        // Debug: Log volunteer status
                        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                        if (currentUserId != null && emergency.responses.containsKey(currentUserId)) {
                          final volunteerResponse = emergency.responses[currentUserId]!;
                          print('🔍 DEBUG: Volunteer status: ${volunteerResponse.status.name}');
                          print('🔍 DEBUG: Mapped to EmergencyResponseStatus: ${_getCurrentVolunteerStatus(emergency)}');
                        }
                        print('🔍 DEBUG: _currentEmergencyResponse set to: ${emergency.emergencyId}');
                        
                        _showTopSnackBar(
                          message: '📱 Emergency response card activated. Swipe up for options.',
                          backgroundColor: Colors.blue,
                          duration: const Duration(seconds: 3),
                          icon: const Icon(Icons.phone_android, color: Colors.white),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('� View Response'),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Handle emergency marker long press - Direct response for volunteers
  void _onEmergencyMarkerLongPress(Emergency emergency) {
    // Only volunteers can respond via long press
    if (_userRole != 'Volunteer') {
      _onEmergencyMarkerTap(emergency); // Fall back to regular tap behavior
      return;
    }

    // Check if volunteer has already responded
    if (emergency.responses.containsKey(FirebaseAuth.instance.currentUser?.uid)) {
      _showTopSnackBar(
        message: 'You are already responding to this emergency',
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
        icon: const Icon(Icons.info, color: Colors.white),
      );
      return;
    }

    // Show quick response dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.emergency,
              color: _getEmergencyMarkerColor(emergency),
              size: 28,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Respond to Emergency?'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency from: ${emergency.attendeeName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (emergency.message != null) ...[
              Text('Message: ${emergency.message!}'),
              const SizedBox(height: 8),
            ],
            Text(
              'Volunteers already responding: ${emergency.responses.length}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Text(
                'Long press detected! This will immediately activate your emergency response card.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              // FIXED: Use the same initiate response method
              await _initiateVolunteerResponse(emergency);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('🚨 Respond Now'),
          ),
        ],
      ),
    );
  }
}
