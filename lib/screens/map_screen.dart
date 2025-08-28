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
import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/utils/error_handler.dart';
import 'package:simha_link/widgets/loading_widgets.dart';
import 'package:simha_link/services/notification_service.dart';
import 'package:simha_link/services/routing_service.dart';

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
  
  List<UserLocation> _groupMembers = [];
  List<POI> _pois = [];
  List<UserLocation> _emergencies = [];
  UserLocation? _selectedMember;
  POI? _selectedPOI;
  bool _isEmergency = false;
  LocationData? _currentLocation;
  String? _userRole;
  
  bool _isMapReady = false;
  bool _isPlacingPOI = false;
  
  // Routing state
  List<LatLng> _currentRoute = [];
  bool _isLoadingRoute = false;
  String _routeInfo = '';

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
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _setupLocationTracking() async {
    try {
      // Request location permissions
      final permissionStatus = await _location.requestPermission();
      if (permissionStatus != PermissionStatus.granted) {
        return;
      }

      // Enable background mode
      await _location.enableBackgroundMode(enable: true);

      // Start location updates
      _locationSubscription = _location.onLocationChanged.listen((locationData) {
        _updateUserLocation(locationData);
      });
    } catch (e) {
      debugPrint('Error setting up location: $e');
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
        userName: user.displayName ?? 'Unknown User',
        latitude: locationData.latitude ?? 0,
        longitude: locationData.longitude ?? 0,
        isEmergency: _isEmergency,
        lastUpdated: DateTime.now(),
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
          print('� Attendee view: $otherActiveMembers active members (out of $totalOtherMembers total)');
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
        }
      }
    } catch (e) {
      print('Error getting user role: $e');
    }
  }

  Future<void> _toggleEmergency() async {
    final wasEmergency = _isEmergency;
    
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
            userName: user.displayName ?? 'Unknown User',
            latitude: _currentLocation!.latitude!,
            longitude: _currentLocation!.longitude!,
            isEmergency: true,
            lastUpdated: DateTime.now(),
          );

          await NotificationService.sendEmergencyNotification(
            groupId: widget.groupId,
            emergencyUser: emergencyUser,
          );

          if (mounted) {
            ErrorHandler.showInfo(context, 'Emergency alert sent to all group members');
          }
        }
      } else if (!_isEmergency && wasEmergency) {
        // Emergency was just deactivated - show confirmation
        if (mounted) {
          ErrorHandler.showInfo(context, 'Emergency status turned off');
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

  bool _isUserActive(UserLocation user) {
    final now = DateTime.now();
    final activeThreshold = now.subtract(const Duration(minutes: 5));
    return user.lastUpdated.isAfter(activeThreshold);
  }

  String _getLastSeenText(UserLocation user) {
    final now = DateTime.now();
    final difference = now.difference(user.lastUpdated);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Add group member markers (visible to all users in the group)
    // Filter out current user since they are shown with the black circle/ring
    markers.addAll(_groupMembers.where((member) => member.userId != currentUserId).map((member) {
      return Marker(
        point: LatLng(member.latitude, member.longitude),
        width: 60,
        height: 60,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedMember = member);
            _calculateRoute(); // Calculate route when member is selected
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Main person icon for other users
                Icon(
                  Icons.person_pin,
                  color: Colors.green,
                  size: 28,
                ),
                // Emergency indicator overlay
                if (member.isEmergency)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: const Icon(
                        Icons.warning,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }));

    // Add emergency markers for volunteers (shows emergencies from ALL groups)
    if (_userRole == 'Volunteer') {
      markers.addAll(_emergencies.map((emergency) {
        // Check if this emergency is already shown as a group member to avoid duplicates
        final isAlreadyShown = _groupMembers.any((member) => 
            member.userId == emergency.userId && member.isEmergency);
        
        if (isAlreadyShown) return null; // Skip if already shown in group members
        
        return Marker(
          point: LatLng(emergency.latitude, emergency.longitude),
          width: 55,
          height: 55,
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedMember = emergency);
              _calculateRoute(); // Calculate route when emergency is selected
              // Show info about this emergency
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Emergency: ${emergency.userName} needs help!'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(27.5),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
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
        );
      }).where((marker) => marker != null).cast<Marker>());
    }

    return markers;
  }

  List<Marker> _buildPOIMarkers() {
    // POI markers are not clustered and always visible
    return _pois.map((poi) {
      return Marker(
        point: LatLng(poi.latitude, poi.longitude),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedPOI = poi);
            _calculatePOIRoute(); // Calculate route when POI is selected
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(
                POI.getPoiIcon(poi.type),
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        ),
      );
    }).toList();
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
      
      // Get walking route to POI
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

  Future<void> _showGroupCodeDialog() async {
    try {
      // Fetch group data to get the join code
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      if (!groupDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Group not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final groupData = groupDoc.data()!;
      final groupName = groupData['name'] ?? 'Unknown Group';
      final joinCode = groupData['joinCode'] ?? '';

      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Share Group Code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Group: $groupName'),
                  const SizedBox(height: 16),
                  Text(
                    'Share this code with others to join:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            joinCode,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: joinCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Join code copied to clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
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
    if (_userRole != 'Organizer') return;

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
                          helperText: 'Enter a descriptive name',
                        ),
                        enabled: !isLoading,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'POI name is required';
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
                        items: POI.poiTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Row(
                              children: [
                                Text(POI.getPoiIcon(type)),
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
        type: type,
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
        creatorName: user.displayName ?? 'Unknown User',
      );

    } catch (e) {
      rethrow; // Let the calling method handle the error
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
              final data = snapshot.data!;
              final groupName = data['groupName'] ?? 'Simha Link Map';
              final userRole = data['userRole'];
              
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    groupName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (userRole != null && userRole != 'Attendee')
                    Text(
                      userRole,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                ],
              );
            }
            return const Text(
              'Simha Link Map',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        ),
        centerTitle: true,
        actions: [
          // Always show chat button for navigation to group chat
          IconButton(
            icon: const Icon(Icons.chat, color: Colors.black),
            tooltip: 'Group Chat',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupChatScreen(groupId: widget.groupId),
                ),
              );
            },
          ),
          // Share group join code button (only for custom groups, not default or special)
          FutureBuilder<bool>(
            future: _shouldShowShareButton(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!) {
                return IconButton(
                  icon: const Icon(Icons.share, color: Colors.black),
                  tooltip: 'Share Group Code',
                  onPressed: () => _showGroupCodeDialog(),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // POI placement button for organizers
          if (_userRole == 'Organizer')
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
          // Logout menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onSelected: (value) async {
              if (value == 'logout') {
                await FirebaseAuth.instance.signOut();
                // Don't clear group data on logout - let users keep their group when they log back in
              } else if (value == 'leave_group') {
                await UserPreferences.clearGroupData();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GroupCreationScreen(),
                    ),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'leave_group',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.black),
                    SizedBox(width: 8),
                    Text('Leave Group'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.black),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            color: const Color(0xFFF7F7F7), // Light background while map loads
          ),
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(12.9716, 77.5946), // Default to Bangalore coordinates
              initialZoom: 15,
              maxZoom: 18,
              minZoom: 3,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              keepAlive: true,
              onMapReady: () {
                setState(() => _isMapReady = true);
                _getCurrentLocation();
              },
              onTap: (tapPosition, point) {
                // Close any open selections when tapping on empty map
                if (_selectedMember != null || _selectedPOI != null) {
                  setState(() {
                    _selectedMember = null;
                    _selectedPOI = null;
                    _currentRoute = [];
                    _routeInfo = '';
                  });
                  return;
                }
                
                if (_isPlacingPOI && _userRole == 'Organizer') {
                  _showPOIPlacementDialog(point);
                  setState(() {
                    _isPlacingPOI = false;
                  });
                }
              },
              onLongPress: (tapPosition, point) {
                // Allow organizers to place POIs with long press without activating placement mode
                if (_userRole == 'Organizer') {
                  _showPOIPlacementDialog(point);
                }
              },
              onMapEvent: (event) {
                // Optimize marker updates based on map movement
                if (event is MapEventMoveEnd) {
                  setState(() {}); // Trigger efficient rebuild
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.simha_link',
                maxZoom: 19,
                keepBuffer: 8,
                tileProvider: NetworkTileProvider(),
                subdomains: const ['a', 'b', 'c', 'd'],
                evictErrorTileStrategy: EvictErrorTileStrategy.none,
              ),
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
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                      width: 30,
                      height: 30,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Main location indicator
                          Icon(
                            Icons.circle,
                            size: _isEmergency ? 12 : 8,
                            color: _isEmergency ? Colors.red : Colors.black,
                          ),
                          // Emergency warning overlay
                          if (_isEmergency)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white, width: 1),
                                ),
                                child: const Icon(
                                  Icons.warning,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 40,
                  size: const Size(35, 35),
                  markers: _buildMarkers(), // Only group members and emergencies
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _userRole == 'Attendee' ? 
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.group,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_groupMembers.length} active members visible',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: Text(
                          'Active in last 5 minutes',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ) :
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _userRole == 'Volunteer' ? Icons.local_hospital :
                        Icons.admin_panel_settings,
                        size: 16,
                        color: _userRole == 'Volunteer' ? Colors.red : Colors.purple,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _userRole == 'Volunteer' ? 'Seeing all emergencies' : 'Can add POIs',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Emergency button
                FloatingActionButton(
                  heroTag: 'emergency',
                  onPressed: _toggleEmergency,
                  backgroundColor: _isEmergency ? Colors.red : Colors.white,
                  child: Icon(
                    Icons.warning_rounded,
                    color: _isEmergency ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                // Find nearest group member button (for attendees)
                if (_userRole == 'Attendee' && _groupMembers.length > 1)
                  FloatingActionButton(
                    heroTag: 'nearest_member',
                    onPressed: _findNearestGroupMember,
                    backgroundColor: Colors.blue,
                    child: const Icon(Icons.people, color: Colors.white),
                  ),
                if (_userRole == 'Attendee' && _groupMembers.length > 1)
                  const SizedBox(height: 8),
                // Location button
                FloatingActionButton(
                  heroTag: 'location',
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
              ],
            ),
          ),
          if (_selectedMember != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _selectedMember!.isEmergency 
                                ? Icons.emergency 
                                : Icons.person,
                            color: _selectedMember!.isEmergency 
                                ? Colors.red 
                                : Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedMember!.isEmergency
                                      ? 'EMERGENCY: ${_selectedMember!.userName}'
                                      : 'Route to ${_selectedMember!.userName}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedMember!.isEmergency 
                                        ? Colors.red 
                                        : Colors.black,
                                  ),
                                ),
                                if (_routeInfo.isNotEmpty)
                                  Text(
                                    _routeInfo,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_isLoadingRoute)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _selectedMember = null;
                              _currentRoute = [];
                              _routeInfo = '';
                            }),
                          ),
                        ],
                      ),
                      if (_selectedMember!.isEmergency && _userRole == 'Volunteer')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Navigate to emergency location
                              _mapController.move(
                                LatLng(_selectedMember!.latitude, _selectedMember!.longitude),
                                17,
                              );
                            },
                            icon: const Icon(Icons.navigation, color: Colors.white),
                            label: const Text('Navigate to Emergency'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      if (!_selectedMember!.isEmergency && _currentRoute.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Center route on map
                              if (_currentRoute.isNotEmpty) {
                                _mapController.fitCamera(
                                  CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(_currentRoute),
                                    padding: const EdgeInsets.all(50),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.route),
                            label: const Text('View Full Route'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (_selectedPOI != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            POI.getPoiIcon(_selectedPOI!.type),
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedPOI!.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _selectedPOI!.type,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (_routeInfo.isNotEmpty)
                                  Text(
                                    _routeInfo,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_isLoadingRoute)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _selectedPOI = null;
                              _currentRoute = [];
                              _routeInfo = '';
                            }),
                          ),
                        ],
                      ),
                      if (_selectedPOI!.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_selectedPOI!.description),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              if (_currentRoute.isNotEmpty) {
                                // Show full route
                                _mapController.fitCamera(
                                  CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints(_currentRoute),
                                    padding: const EdgeInsets.all(50),
                                  ),
                                );
                              } else {
                                // Just center on POI
                                _mapController.move(
                                  LatLng(_selectedPOI!.latitude, _selectedPOI!.longitude),
                                  17,
                                );
                              }
                            },
                            icon: Icon(_currentRoute.isNotEmpty ? Icons.route : Icons.navigation),
                            label: Text(_currentRoute.isNotEmpty ? 'View Route' : 'Go to POI'),
                          ),
                          if (_userRole == 'Organizer')
                            ElevatedButton.icon(
                              onPressed: () async {
                                // Delete POI
                                await FirebaseFirestore.instance
                                    .collection('pois')
                                    .doc(_selectedPOI!.id)
                                    .delete();
                                setState(() => _selectedPOI = null);
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // POI placement instruction banner
          if (_isPlacingPOI && _userRole == 'Organizer')
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.blue,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.add_location, color: Colors.white),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Tap on the map to place a POI, or use long press anywhere',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isPlacingPOI = false;
                          });
                        },
                        child: const Text(
                          'CANCEL',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Map legend
          if (!_isPlacingPOI)
            Positioned(
              bottom: 16,
              left: 16,
              child: Card(
                color: Colors.white.withOpacity(0.9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Map Legend',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Your location
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_pin_circle, color: Colors.blue, size: 16),
                          const SizedBox(width: 4),
                          const Text('You', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Group members
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_pin, color: Colors.green, size: 16),
                          const SizedBox(width: 4),
                          const Text('Group Members', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                      if (_userRole == 'Volunteer') ...[
                        const SizedBox(height: 4),
                        // Emergencies
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.emergency, color: Colors.white, size: 10),
                            ),
                            const SizedBox(width: 4),
                            const Text('Emergencies', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      // POIs
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue, width: 1),
                            ),
                            child: const Center(
                              child: Text('🏥', style: TextStyle(fontSize: 8)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('Points of Interest', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Show a simple info card for the user
          FutureBuilder<bool>(
            future: UserPreferences.isDefaultGroup(widget.groupId),
            builder: (context, snapshot) {
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
