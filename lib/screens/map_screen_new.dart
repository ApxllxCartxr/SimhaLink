import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/models/poi.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:simha_link/screens/group_chat_screen.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/utils/error_handler.dart';
import 'package:simha_link/widgets/loading_widgets.dart';
import 'package:simha_link/services/notification_service.dart';
import 'package:simha_link/services/routing_service.dart';
import 'package:simha_link/services/auth_service.dart';
import 'package:simha_link/config/app_colors.dart';

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
  final Location _location = Location();
  
  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription<QuerySnapshot>? _groupLocationsSubscription;
  StreamSubscription<QuerySnapshot>? _poisSubscription;
  StreamSubscription<QuerySnapshot>? _emergenciesSubscription;
  StreamSubscription<QuerySnapshot>? _volunteersSubscription;
  StreamSubscription<QuerySnapshot>? _organizersSubscription;
  
  List<UserLocation> _groupMembers = [];
  List<POI> _pois = [];
  List<UserLocation> _emergencies = [];
  List<UserLocation> _nearbyVolunteers = [];
  List<UserLocation> _allVolunteers = [];
  UserLocation? _selectedMember;
  POI? _selectedPOI;
  bool _isEmergency = false;
  LocationData? _currentLocation;
  String? _userRole;
  
  bool _isMapReady = false;
  bool _isPlacingPOI = false;
  
  // Routing state
  List<LatLng> _currentRoute = [];

  @override
  void initState() {
    super.initState();
    _setupLocationTracking();
    _listenToGroupLocations();
    _listenToPOIs();
    _getUserRole();
    // We'll get the location after the map is ready
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _groupLocationsSubscription?.cancel();
    _poisSubscription?.cancel();
    _emergenciesSubscription?.cancel();
    _volunteersSubscription?.cancel();
    _organizersSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _setupLocationTracking() async {
    try {
      // Request location permissions
      final permissionStatus = await _location.requestPermission();
      if (permissionStatus != PermissionStatus.granted) {
        if (mounted) {
          ErrorHandler.showError(context, 'Location permission denied');
        }
        return;
      }

      // Enable background location and configure settings
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 5000, // Update every 5 seconds
        distanceFilter: 10, // Update when moved 10 meters
      );

      // Start location tracking
      _locationSubscription = _location.onLocationChanged.listen(
        _updateUserLocation,
        onError: (e) => print('Location tracking error: $e'),
      );
    } catch (e) {
      print('Error setting up location tracking: $e');
      if (mounted) {
        ErrorHandler.showError(context, 'Failed to start location tracking: $e');
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_isMapReady) return;
    
    try {
      final locationData = await _location.getLocation();
      if (!mounted) return;

      setState(() {
        _currentLocation = locationData;
      });
      
      try {
        _mapController.move(
          LatLng(locationData.latitude!, locationData.longitude!),
          15,
        );
      } catch (e) {
        debugPrint('Error moving map: $e');
      }
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  Future<void> _updateUserLocation(LocationData locationData) async {
    if (!mounted) return;
    
    setState(() {
      _currentLocation = locationData;
    });
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final location = UserLocation(
        userId: user.uid,
        userName: AuthService.getUserDisplayName(user),
        latitude: locationData.latitude ?? 0,
        longitude: locationData.longitude ?? 0,
        isEmergency: _isEmergency,
        lastUpdated: DateTime.now(),
        userRole: _userRole,
      );

      // Log emergency status for debugging
      print('📍 Updating user location - Emergency: $_isEmergency');

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('locations')
          .doc(user.uid)
          .set(location.toMap());
          
      print('✅ Location updated successfully in group ${widget.groupId}');
    } catch (e) {
      debugPrint('Error updating user location: $e');
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
    // Listen to all locations in the current group
    // This allows attendees to see other group members and volunteers to see their group
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
        
        // For attendees, only show active members (updated within last 5 minutes)
        // For volunteers and organizers, show all members
        List<UserLocation> filteredMembers;
        if (_userRole == 'Attendee') {
          final now = DateTime.now();
          final activeThreshold = now.subtract(const Duration(minutes: 5));
          
          filteredMembers = allMembers.where((member) {
            return member.lastUpdated.isAfter(activeThreshold);
          }).toList();
          
          // Debug logging for attendees
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          final otherActiveMembers = filteredMembers.where((member) => member.userId != currentUserId).length;
          final totalOtherMembers = allMembers.where((member) => member.userId != currentUserId).length;
          print('📱 Attendee view: $otherActiveMembers active members (out of $totalOtherMembers total)');
        } else {
          // Volunteers and organizers see all members
          filteredMembers = allMembers;
          
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          final otherMembers = filteredMembers.where((member) => member.userId != currentUserId).length;
          print('👥 ${_userRole ?? 'User'} view: $otherMembers total members visible');
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

  void _listenToEmergencies() {
    if (_userRole != 'Volunteer') return;
    
    print('🚨 Volunteer: Starting to listen for emergencies across all groups');
    
    // Listen to all groups to detect emergencies across the platform
    _emergenciesSubscription = FirebaseFirestore.instance
        .collection('groups')
        .snapshots()
        .listen((groupSnapshot) async {
      if (!mounted) return;
      
      List<UserLocation> allEmergencies = [];
      
      // Check each group for emergency locations
      for (final groupDoc in groupSnapshot.docs) {
        try {
          final locationsSnapshot = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupDoc.id)
              .collection('locations')
              .where('isEmergency', isEqualTo: true)
              .get();
          
          final groupEmergencies = locationsSnapshot.docs
              .map((doc) => UserLocation.fromMap(doc.data()))
              .where((location) => location.isEmergency) // Double-check the emergency status
              .toList();
          
          allEmergencies.addAll(groupEmergencies);
        } catch (e) {
          print('Error fetching emergencies from group ${groupDoc.id}: $e');
        }
      }
      
      if (mounted) {
        final previousEmergencyCount = _emergencies.length;
        setState(() {
          _emergencies = allEmergencies;
        });
        
        // Log emergency status changes
        if (allEmergencies.length != previousEmergencyCount) {
          print('🚨 Emergency count changed: $previousEmergencyCount → ${allEmergencies.length}');
        }
        
        if (allEmergencies.isNotEmpty) {
          print('🚨 Volunteer sees ${allEmergencies.length} active emergencies');
        } else {
          print('✅ No active emergencies detected');
        }
      }
    });
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
        
        // Start listening to emergencies if user is a volunteer
        if (_userRole == 'Volunteer') {
          _listenToEmergencies();
          _listenToNearbyVolunteers();
          _listenToOrganizers();
        }
        
        // Start listening to volunteers if user is an organizer
        if (_userRole == 'Organizer') {
          _listenToAllVolunteers();
        }
      }
    } catch (e) {
      print('Error getting user role: $e');
    }
  }

  void _listenToNearbyVolunteers() {
    if (_userRole != 'Volunteer') return;
    
    print('👮 Volunteer: Listening for nearby volunteers and organizers');
    
    // Listen to all groups to find volunteers and organizers
    _volunteersSubscription = FirebaseFirestore.instance
        .collection('groups')
        .snapshots()
        .listen((groupSnapshot) async {
      if (!mounted) return;
      
      List<UserLocation> nearbyVolunteers = [];
      final currentLocation = _currentLocation;
      
      if (currentLocation == null) return;
      
      // Check each group for volunteer and organizer locations
      for (final groupDoc in groupSnapshot.docs) {
        try {
          final locationsSnapshot = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupDoc.id)
              .collection('locations')
              .get();
          
          final allUsers = locationsSnapshot.docs
              .map((doc) => UserLocation.fromMap(doc.data()))
              .toList();
          
          // Filter for volunteers and organizers only
          final staffUsers = allUsers.where((user) => 
            user.userRole == 'Volunteer' || user.userRole == 'Organizer'
          ).toList();
          
          // Filter by proximity (within reasonable distance)
          for (final user in staffUsers) {
            final distance = _calculateDistance(
              currentLocation.latitude!,
              currentLocation.longitude!,
              user.latitude,
              user.longitude,
            );
            
            // Show volunteers/organizers within 2km range
            if (distance <= 2000 && user.userId != FirebaseAuth.instance.currentUser?.uid) {
              nearbyVolunteers.add(user);
            }
          }
        } catch (e) {
          print('Error fetching staff from group ${groupDoc.id}: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _nearbyVolunteers = nearbyVolunteers;
        });
        
        print('👮 Found ${nearbyVolunteers.length} nearby volunteers/organizers');
      }
    });
  }

  void _listenToOrganizers() {
    if (_userRole != 'Volunteer') return;
    
    // Organizers are included in the nearby volunteers listener above
    // This method exists for consistency and future expansion
  }

  void _listenToAllVolunteers() {
    if (_userRole != 'Organizer') return;
    
    print('👑 Organizer: Listening for all volunteers');
    
    // Listen to all groups to find volunteers
    _organizersSubscription = FirebaseFirestore.instance
        .collection('groups')
        .snapshots()
        .listen((groupSnapshot) async {
      if (!mounted) return;
      
      List<UserLocation> allVolunteers = [];
      
      // Check each group for volunteer locations
      for (final groupDoc in groupSnapshot.docs) {
        try {
          final locationsSnapshot = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupDoc.id)
              .collection('locations')
              .get();
          
          final volunteers = locationsSnapshot.docs
              .map((doc) => UserLocation.fromMap(doc.data()))
              .where((user) => user.userRole == 'Volunteer')
              .toList();
          
          allVolunteers.addAll(volunteers);
        } catch (e) {
          print('Error fetching volunteers from group ${groupDoc.id}: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _allVolunteers = allVolunteers;
        });
        
        print('👑 Organizer sees ${allVolunteers.length} volunteers across all groups');
      }
    });
  }

  Future<void> _toggleEmergency() async {
    final wasEmergency = _isEmergency;
    
    // Show confirmation dialog before activating emergency
    if (!wasEmergency) {
      final shouldActivate = await _showEmergencyConfirmationDialog();
      if (!shouldActivate) return;
    }
    
    setState(() {
      _isEmergency = !_isEmergency;
    });

    try {
      final locationData = await _location.getLocation();
      
      // Update user location with new emergency status
      await _updateUserLocation(locationData);

      if (_isEmergency && !wasEmergency) {
        // Emergency was just activated - send notification
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && _currentLocation != null) {
          final emergencyUser = UserLocation(
            userId: user.uid,
            userName: AuthService.getUserDisplayName(user),
            latitude: _currentLocation!.latitude!,
            longitude: _currentLocation!.longitude!,
            isEmergency: true,
            lastUpdated: DateTime.now(),
            userRole: _userRole,
          );

          // Show loading indicator
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('🚨 Sending emergency alert...'),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }

          await NotificationService.sendEmergencyNotification(
            groupId: widget.groupId,
            emergencyUser: emergencyUser,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🚨 Emergency alert sent! Volunteers and group members have been notified.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } else if (!_isEmergency && wasEmergency) {
        // Emergency was just deactivated - show confirmation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Emergency status turned off'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // Revert the state if operation failed
      setState(() {
        _isEmergency = wasEmergency;
      });
      
      if (mounted) {
        ErrorHandler.showError(
          context,
          'Failed to update emergency status: ${ErrorHandler.getFirebaseErrorMessage(e)}',
          onRetry: _toggleEmergency,
        );
      }
    }
  }

  /// Show confirmation dialog before activating emergency
  Future<bool> _showEmergencyConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.mapEmergency, width: 2),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.mapEmergency, size: 28),
              const SizedBox(width: 12),
              Text(
                'Emergency Alert',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will immediately alert:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildBulletPoint('All your group members'),
              _buildBulletPoint('Nearest volunteers within 5km'),
              _buildBulletPoint('Send push notifications to phones'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Only use this for real emergencies that require immediate assistance.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.mapEmergency,
                foregroundColor: AppColors.textOnPrimary,
              ),
              child: const Text('Send Emergency Alert'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 6,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _findNearestGroupMember() {
    if (_currentLocation == null || _groupMembers.isEmpty) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    UserLocation? nearestMember;
    double? shortestDistance;

    for (final member in _groupMembers) {
      if (member.userId == currentUserId) continue; // Skip self

      final distance = _calculateDistance(
        _currentLocation!.latitude!,
        _currentLocation!.longitude!,
        member.latitude,
        member.longitude,
      );

      if (nearestMember == null || distance < shortestDistance!) {
        nearestMember = member;
        shortestDistance = distance;
      }
    }

    if (nearestMember != null) {
      // Focus on nearest member
      _mapController.moveAndRotate(
        LatLng(nearestMember.latitude, nearestMember.longitude),
        15,
        0,
      );

      // Show information about the nearest member
      setState(() {
        _selectedMember = nearestMember;
      });

      // Show a snackbar with distance info
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nearest member: ${nearestMember.userName} (${shortestDistance!.toStringAsFixed(0)}m away)',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLon = (lon2 - lon1) * (pi / 180);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Role-based marker visibility
    if (_userRole == 'Attendee') {
      // Attendees see: Other attendees in the same group
      markers.addAll(_groupMembers
          .where((member) => 
              member.userId != currentUserId && 
              (member.userRole == 'Attendee' || member.userRole == null)) // Include users without role for backward compatibility
          .map((member) => _buildUserMarker(member, AppColors.mapAttendee, Icons.person_pin)));
    } else if (_userRole == 'Volunteer') {
      // Volunteers see: Other volunteers and organizers nearby, emergencies from all groups
      markers.addAll(_nearbyVolunteers
          .map((volunteer) => _buildUserMarker(volunteer, 
              volunteer.userRole == 'Volunteer' ? AppColors.mapVolunteer : AppColors.mapOrganizer, 
              volunteer.userRole == 'Volunteer' ? Icons.local_hospital : Icons.admin_panel_settings)));
      
      // Add emergency markers from all groups
      markers.addAll(_emergencies.map((emergency) {
        // Check if this emergency is already shown as a nearby volunteer to avoid duplicates
        final isAlreadyShown = _nearbyVolunteers.any((volunteer) => 
            volunteer.userId == emergency.userId && emergency.isEmergency);
        
        if (isAlreadyShown) return null; // Skip if already shown
        
        return _buildEmergencyMarker(emergency);
      }).where((marker) => marker != null).cast<Marker>());
    } else if (_userRole == 'Organizer') {
      // Organizers see: All volunteers across all groups
      markers.addAll(_allVolunteers
          .map((volunteer) => _buildUserMarker(volunteer, AppColors.mapVolunteer, Icons.local_hospital)));
      
      // Also see other organizers in the same group
      markers.addAll(_groupMembers
          .where((member) => 
              member.userId != currentUserId && 
              member.userRole == 'Organizer')
          .map((organizer) => _buildUserMarker(organizer, AppColors.mapOrganizer, Icons.admin_panel_settings)));
    }

    // Everyone sees their current location marker (blue like Google Maps)
    if (_currentLocation != null && currentUserId != null) {
      markers.add(_buildCurrentLocationMarker());
    }

    return markers;
  }

  Marker _buildUserMarker(UserLocation user, Color color, IconData icon) {
    return Marker(
      point: LatLng(user.latitude, user.longitude),
      width: 60,
      height: 60,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedMember = user);
          _calculateRoute();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Main role-specific icon
              Icon(
                icon,
                color: color,
                size: 32,
              ),
              // Emergency indicator overlay
              if (user.isEmergency)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.mapEmergency,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.warning,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _buildEmergencyMarker(UserLocation emergency) {
    return Marker(
      point: LatLng(emergency.latitude, emergency.longitude),
      width: 60,
      height: 60,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedMember = emergency);
          _calculateRoute();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🚨 Emergency: ${emergency.userName} needs help!'),
              backgroundColor: AppColors.mapEmergency,
              duration: const Duration(seconds: 4),
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.mapEmergency,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.mapEmergency.withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(
              Icons.emergency,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildCurrentLocationMarker() {
    return Marker(
      point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
      width: 40,
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.mapCurrentUser, // Blue like Google Maps
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: AppColors.mapCurrentUser.withOpacity(0.3),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  List<Marker> _buildPOIMarkers() {
    // Filter POIs based on user role
    List<POI> visiblePOIs = [];
    
    if (_userRole == 'Attendee') {
      // Attendees see: Organizer-set location markers (Drinking Water, Restroom, Medical Aid, Historical, etc.)
      visiblePOIs = _pois.where((poi) => 
          poi.type == MarkerType.drinkingWater ||
          poi.type == MarkerType.restroom ||
          poi.type == MarkerType.medical ||
          poi.type == MarkerType.historical ||
          poi.type == MarkerType.accessibility ||
          poi.type == MarkerType.information ||
          poi.type == MarkerType.food ||
          poi.type == MarkerType.parking
      ).toList();
    } else if (_userRole == 'Volunteer') {
      // Volunteers see: All POIs and can set high priority markers
      visiblePOIs = _pois;
    } else if (_userRole == 'Organizer') {
      // Organizers see: All POIs
      visiblePOIs = _pois;
    } else {
      // Default: show basic POIs
      visiblePOIs = _pois.where((poi) => 
          poi.type == MarkerType.information ||
          poi.type == MarkerType.drinkingWater ||
          poi.type == MarkerType.restroom
      ).toList();
    }
    
    return visiblePOIs.map((poi) {
      return Marker(
        point: LatLng(poi.latitude, poi.longitude),
        width: 45,
        height: 45,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedPOI = poi);
            _calculatePOIRoute();
          },
          child: Container(
            decoration: BoxDecoration(
              color: _getPOIBackgroundColor(poi.type),
              borderRadius: BorderRadius.circular(22.5),
              border: Border.all(
                color: _getPOIBorderColor(poi.type), 
                width: 2
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                POI.getPoiIcon(poi.type),
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Color _getPOIBackgroundColor(MarkerType type) {
    switch (type) {
      case MarkerType.emergency:
        return AppColors.mapEmergency;
      case MarkerType.medical:
        return Colors.white;
      case MarkerType.security:
        return Colors.white;
      case MarkerType.drinkingWater:
        return Colors.white;
      default:
        return Colors.white;
    }
  }

  Color _getPOIBorderColor(MarkerType type) {
    switch (type) {
      case MarkerType.emergency:
        return AppColors.mapEmergency;
      case MarkerType.medical:
        return Colors.red.shade700;
      case MarkerType.security:
        return Colors.blue.shade700;
      case MarkerType.drinkingWater:
        return Colors.blue.shade600;
      case MarkerType.restroom:
        return Colors.brown.shade600;
      case MarkerType.food:
        return Colors.orange.shade700;
      case MarkerType.historical:
        return Colors.purple.shade600;
      case MarkerType.accessibility:
        return Colors.green.shade600;
      case MarkerType.parking:
        return Colors.grey.shade700;
      default:
        return AppColors.primary;
    }
  }

  List<String> _getAvailablePOITypes() {
    if (_userRole == 'Volunteer') {
      // Volunteers can set high priority location markers
      return [
        'Medical Aid',
        'Emergency', 
        'Drinking Water',
        'Security',
        'Information',
      ];
    } else if (_userRole == 'Organizer') {
      // Organizers can set all POI types
      return POI.poiTypes;
    }
    
    // Default: no POI creation allowed
    return [];
  }

  Future<void> _calculateRoute() async {
    if (_selectedMember == null || _currentLocation == null) {
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
      final start = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
      final end = LatLng(_selectedMember!.latitude, _selectedMember!.longitude);
      
      // Get walking route (most appropriate for emergency/group scenarios)
      final route = await RoutingService.getWalkingRoute(start, end);
      
      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
          
          if (route.length > 2) {
            // Real route found (more than just start and end points)
            final distance = RoutingService.calculateRouteDistance(route);
            final time = RoutingService.estimateWalkingTime(route);
            
            String routeSource = '';
            if (route.length > 10) {
              routeSource = ' (OSRM)'; // Likely from OSRM API with many waypoints
            }
            
            _routeInfo = '${RoutingService.formatDistance(distance)} • ${RoutingService.formatTime(time)} walking$routeSource';
          } else {
            // Simple route (straight line or fallback)
            final distance = _calculateDistance(
              start.latitude, start.longitude,
              end.latitude, end.longitude,
            );
            _routeInfo = '${distance.round()}m direct path';
          }
        });
      }
    } catch (e) {
      print('Error calculating route: $e');
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
          
          // Create a simple straight line route as ultimate fallback
          final start = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
          final end = LatLng(_selectedMember!.latitude, _selectedMember!.longitude);
          _currentRoute = [start, end];
          
          final distance = _calculateDistance(
            start.latitude, start.longitude,
            end.latitude, end.longitude,
          );
          _routeInfo = '${distance.round()}m direct line (routing unavailable)';
        });
      }
    }
  }

  Future<void> _calculatePOIRoute() async {
    if (_selectedPOI == null || _currentLocation == null) {
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
      final start = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
      final end = LatLng(_selectedPOI!.latitude, _selectedPOI!.longitude);
      
      // Get walking route
      final route = await RoutingService.getWalkingRoute(start, end);
      
      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
          
          if (route.length > 2) {
            // Real route found
            final distance = RoutingService.calculateRouteDistance(route);
            final time = RoutingService.estimateWalkingTime(route);
            
            String routeSource = '';
            if (route.length > 10) {
              routeSource = ' (OSRM)';
            }
            
            _routeInfo = '${RoutingService.formatDistance(distance)} • ${RoutingService.formatTime(time)} walking$routeSource';
          } else {
            // Simple route (straight line or fallback)
            final distance = _calculateDistance(
              start.latitude, start.longitude,
              end.latitude, end.longitude,
            );
            _routeInfo = '${distance.round()}m direct path';
          }
        });
      }
    } catch (e) {
      print('Error calculating POI route: $e');
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
          
          // Create a simple straight line route as ultimate fallback
          final start = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);
          final end = LatLng(_selectedPOI!.latitude, _selectedPOI!.longitude);
          _currentRoute = [start, end];
          
          final distance = _calculateDistance(
            start.latitude, start.longitude,
            end.latitude, end.longitude,
          );
          _routeInfo = '${distance.round()}m direct line (routing unavailable)';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.black),
          onPressed: () async {
            await FirebaseAuth.instance.signOut();
            // AuthWrapper will automatically handle navigation to AuthScreen
          },
        ),
        title: FutureBuilder<Map<String, String>>(
          future: _getGroupAndUserInfo(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final groupName = snapshot.data!['groupName'] ?? 'Simha Link Map';
              final userRole = snapshot.data!['userRole'];
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    groupName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (userRole != null)
                    Text(
                      userRole,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                ],
              );
            }
            return const Text(
              'Simha Link Map',
              style: TextStyle(color: Colors.black),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupChatScreen(groupId: widget.groupId),
                ),
              );
            },
          ),
          // Show POI placement button for organizers and volunteers
          if (_userRole == 'Organizer' || _userRole == 'Volunteer')
            IconButton(
              icon: Icon(
                _isPlacingPOI ? Icons.close : Icons.add_location,
                color: _isPlacingPOI ? Colors.red : Colors.black,
              ),
              tooltip: _isPlacingPOI ? 'Cancel POI Placement' : 'Add POI',
              onPressed: () {
                setState(() {
                  _isPlacingPOI = !_isPlacingPOI;
                });
              },
            ),
          FutureBuilder<bool>(
            future: _shouldShowShareButton(),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return IconButton(
                  icon: const Icon(Icons.share, color: Colors.black),
                  onPressed: () async {
                    await _shareGroupCode();
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(12.9716, 77.5946), // Bangalore coordinates
              initialZoom: 13.0,
              onMapReady: () {
                setState(() => _isMapReady = true);
                _getCurrentLocation();
              },
              onTap: (tapPosition, latLng) {
                if (_selectedMember != null || _selectedPOI != null) {
                  setState(() {
                    _selectedMember = null;
                    _selectedPOI = null;
                    _currentRoute = [];
                    _routeInfo = '';
                  });
                }
                
                if (_isPlacingPOI && (_userRole == 'Organizer' || _userRole == 'Volunteer')) {
                  _showPOIPlacementDialog(latLng);
                  setState(() {
                    _isPlacingPOI = false;
                  });
                }
                
                // Handle general tap
                if (_userRole == 'Organizer') {
                  // For organizers, show location options
                  print('📍 Organizer tapped at: ${latLng.latitude}, ${latLng.longitude}');
                }
                
                setState(() {}); // Trigger efficient rebuild
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.simha_link.app',
              ),
              // Current location circle
              if (_currentLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                      radius: _isEmergency ? 12 : 6,
                      useRadiusInMeter: false,
                      color: _isEmergency ? Colors.red.withOpacity(0.2) : Colors.black.withOpacity(0.1),  
                      borderColor: _isEmergency ? Colors.red : Colors.black,
                      borderStrokeWidth: _isEmergency ? 2 : 1.5,
                    ),
                  ],
                ),
              // Current location marker (blue dot like Google Maps)
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.mapCurrentUser,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: Icon(
                          Icons.circle,
                          size: _isEmergency ? 12 : 8,
                          color: _isEmergency ? Colors.red : Colors.black,
                        ),
                      ),
                      // Emergency pulse effect
                      builder: (context) => AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isEmergency)
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.withOpacity(0.2),
                                ),
                              ),
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.mapCurrentUser,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              // User markers with clustering
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 80,
                  size: const Size(35, 35),
                  markers: _buildMarkers(), // Role-based markers
                  onClusterTap: (cluster) {
                    print('Cluster tapped with ${cluster.count} markers');
                  },
                  centerMarkerOnClick: true,
                  zoomToBoundsOnClick: true,
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17.5),
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.black45,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Separate POI layer (no clustering)
              MarkerLayer(
                markers: _buildPOIMarkers(),
              ),
              if (_currentRoute.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _currentRoute,
                      strokeWidth: 4,
                      color: _selectedMember?.isEmergency == true ? Colors.red : Colors.blue,
                      borderStrokeWidth: 1,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
            ],
          ),
          // Info panel for user capabilities
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _userRole == 'Attendee' ? 
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.group,
                            color: Colors.green,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_groupMembers.length} active members visible',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'View: Group members, Location markers',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ) : 
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _userRole == 'Volunteer' ? Icons.local_hospital :
                            _userRole == 'Organizer' ? Icons.admin_panel_settings :
                            Icons.person,
                            color: _userRole == 'Volunteer' ? Colors.red : Colors.purple,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _userRole == 'Volunteer' ? 'Seeing all emergencies' : 'Can add POIs',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userRole == 'Volunteer' ? 'View: Volunteers, Organizers, All POIs' : 'View: All volunteers, All POIs',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
              ),
            ),
          ),
          // Emergency button
          Positioned(
            bottom: 120,
            right: 16,
            child: FloatingActionButton(
              onPressed: _toggleEmergency,
              backgroundColor: _isEmergency ? AppColors.mapEmergency : AppColors.surface,
              elevation: 8,
              child: Icon(
                Icons.emergency,
                color: _isEmergency ? AppColors.textOnPrimary : AppColors.mapEmergency,
                size: 28,
              ),
            ),
          ),
          // Find nearest member button (attendees only)
          if (_userRole == 'Attendee' && _groupMembers.length > 1)
            Positioned(
              bottom: 60,
              left: 16,
              child: FloatingActionButton(
                mini: true,
                onPressed: _findNearestGroupMember,
                backgroundColor: Colors.white,
                child: const Icon(Icons.near_me, color: Colors.black),
              ),
            ),
          // Go to current location button
          if (_userRole == 'Attendee' && _groupMembers.length > 1)
            Positioned(
              bottom: 120,
              left: 16,
              child: FloatingActionButton(
                mini: true,
                onPressed: () async {
                  final locationData = await _location.getLocation();
                  _mapController.moveAndRotate(
                    LatLng(locationData.latitude!, locationData.longitude!),
                    15,
                    0,
                  );
                },
                backgroundColor: Colors.white,
                child: const Icon(Icons.my_location, color: Colors.black),
              ),
            ),
        ],
      ),
    );
  }

  Future<Map<String, String>> _getGroupAndUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {'groupName': 'Simha Link Map'};

      // Get group info
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      String groupName = 'Simha Link Map';
      if (groupDoc.exists) {
        groupName = groupDoc.data()?['name'] ?? 'Simha Link Map';
      }

      // Get user role
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String? userRole;
      if (userDoc.exists) {
        userRole = userDoc.data()?['role'] as String?;
      }

      return {
        'groupName': groupName,
        if (userRole != null) 'userRole': userRole,
      };
    } catch (e) {
      print('Error getting group and user info: $e');
      return {'groupName': 'Simha Link Map'};
    }
  }

  Future<bool> _shouldShowShareButton() async {
    try {
      // Don't show for default groups
      if (await UserPreferences.isDefaultGroup(widget.groupId)) {
        return false;
      }

      // Don't show for special groups (volunteers, organizers)
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        final groupType = groupDoc.data()?['type'] as String?;
        return groupType != 'special';
      }

      return true; // Show for custom groups
    } catch (e) {
      return false; // Hide on error
    }
  }

  Future<void> _shareGroupCode() async {
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      if (groupDoc.exists) {
        final groupCode = groupDoc.data()?['groupCode'] as String?;
        final groupName = groupDoc.data()?['name'] as String? ?? 'Group';
        
        if (groupCode != null) {
          await Clipboard.setData(ClipboardData(
            text: 'Join my group "$groupName" on Simha Link!\n\nGroup Code: $groupCode\n\nDownload the app and enter this code to join.',
          ));
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Group invite copied to clipboard!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching group code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showPOIPlacementDialog(LatLng location) async {
    if (_userRole != 'Organizer' && _userRole != 'Volunteer') return;

    String? selectedType;
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    bool canSubmit = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Check if form can be submitted
            void checkFormValidity() {
              final newCanSubmit = nameController.text.trim().isNotEmpty && selectedType != null;
              if (newCanSubmit != canSubmit) {
                setState(() {
                  canSubmit = newCanSubmit;
                });
              }
            }

            return AlertDialog(
              title: const Text('Add Point of Interest'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'POI Name *',
                          border: OutlineInputBorder(),
                          helperText: 'Give it a clear name',
                        ),
                        enabled: !isLoading,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a POI name';
                          }
                          return null;
                        },
                        onChanged: (value) => checkFormValidity(),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'POI Type *',
                          border: OutlineInputBorder(),
                          helperText: 'Select category',
                        ),
                        items: _getAvailablePOITypes().map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Row(
                              children: [
                                Text(POI.getPoiIcon(MarkerType.fromString(type))),
                                const SizedBox(width: 8),
                                Text(type),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: isLoading ? null : (value) {
                          setState(() {
                            selectedType = value;
                          });
                          checkFormValidity();
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a POI type';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                          border: OutlineInputBorder(),
                          helperText: 'Additional details',
                        ),
                        maxLines: 3,
                        enabled: !isLoading,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                LoadingButton(
                  onPressed: canSubmit
                      ? () async {
                          if (!formKey.currentState!.validate()) return;
                          
                          setState(() => isLoading = true);
                          try {
                            await _createPOI(
                              location,
                              nameController.text.trim(),
                              selectedType!,
                              descriptionController.text.trim(),
                            );
                            if (mounted) {
                              Navigator.of(context).pop();
                              ErrorHandler.showSuccess(context, 'POI created successfully!');
                            }
                          } catch (e) {
                            setState(() => isLoading = false);
                            if (mounted) {
                              ErrorHandler.showError(
                                context,
                                'Failed to create POI: ${ErrorHandler.getFirebaseErrorMessage(e)}',
                              );
                            }
                          }
                        }
                      : null,
                  text: 'Add POI',
                  isLoading: isLoading,
                  icon: Icons.add_location,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createPOI(LatLng location, String name, String type, String description) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final poiRef = FirebaseFirestore.instance.collection('pois').doc();
      final poi = POI(
        id: poiRef.id,
        name: name,
        type: MarkerType.fromString(type),
        latitude: location.latitude,
        longitude: location.longitude,
        description: description,
        createdBy: user.uid,
        createdAt: DateTime.now(),
      );

      // Create POI in Firestore
      await poiRef.set(poi.toMap());

      // Send notification to group members
      await NotificationService.sendPOINotification(
        groupId: widget.groupId,
        poiName: name,
        poiType: type,
        creatorName: AuthService.getUserDisplayName(user),
      );

    } catch (e) {
      rethrow; // Let the calling method handle the error
    }
  }
}
