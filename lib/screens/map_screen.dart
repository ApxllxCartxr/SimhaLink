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
import 'package:simha_link/screens/group_chat_screen.dart';
import 'package:simha_link/screens/broadcast_list_screen.dart';
import 'package:simha_link/services/broadcast_service.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/widgets/state_sync_status_widget.dart';
import 'package:simha_link/utils/error_handler.dart';
import 'package:simha_link/services/routing_service.dart';
import 'package:simha_link/config/app_colors.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/screens/auth_wrapper.dart';

// Import the new managers and widgets
import 'map/managers/location_manager.dart';
import 'map/managers/emergency_manager.dart';
import 'map/managers/marker_manager.dart';
import 'map/widgets/map_info_panel.dart';
import 'map/widgets/map_legend.dart';
import 'map/widgets/emergency_dialog.dart';
import 'map/widgets/marker_action_bottom_sheet.dart';

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
  late EmergencyManager _emergencyManager;
  late MarkerManager _markerManager;
  
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
    _emergencyManager = EmergencyManager(
      userRole: _userRole,
      groupId: widget.groupId,
    );
    _markerManager = MarkerManager(
      userRole: _userRole,
      isMapReady: _isMapReady,
    );
  }

  Future<void> _setupInitialData() async {
    await _getUserRole();
    await _setupLocationTracking();
    _listenToGroupLocations();
    _listenToPOIs();
    _startEmergencyListeners();
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
    _emergencyManager.listenToEmergencies(() {
      if (mounted) setState(() {});
    });
    
    _emergencyManager.listenToNearbyVolunteers(
      _locationManager.currentLocation,
      () {
        if (mounted) setState(() {});
      },
    );
    
    _emergencyManager.listenToAllVolunteers(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggleEmergency() async {
    final shouldActivate = _isEmergency ? true : await showEmergencyConfirmationDialog(context);
    if (!shouldActivate) return;
    
    try {
      await _emergencyManager.toggleEmergency(
        currentEmergencyStatus: _isEmergency,
        currentLocation: _locationManager.currentLocation,
        onEmergencyChanged: (newStatus) {
          setState(() {
            _isEmergency = newStatus;
          });
        },
        context: context,
      );
      
      // Update location with new emergency status
      if (_locationManager.currentLocation != null) {
        await _updateUserLocation(_locationManager.currentLocation!);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isMarkerManagementMode 
              ? 'Tap markers to manage them' 
              : 'Marker management disabled',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onUserMarkerTap(UserLocation user) {
    setState(() => _selectedMember = user);
    _calculateRoute();
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
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap on the map to place a POI'),
        duration: Duration(seconds: 3),
      ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a POI name')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${type.displayName} created successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error creating POI: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating POI: $e')),
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
      _locationManager.dispose();
      _emergencyManager.dispose();
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
      appBar: _buildAppBar(),
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
              // Current location circle
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
              // User markers with clustering
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  markers: _markerManager.buildMarkers(
                    groupMembers: _groupMembers,
                    emergencies: _emergencyManager.emergencies,
                    nearbyVolunteers: _emergencyManager.nearbyVolunteers,
                    allVolunteers: _emergencyManager.allVolunteers,
                    currentLocation: _locationManager.currentLocation,
                    onUserMarkerTap: _onUserMarkerTap,
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
              // POI markers (no clustering)
              MarkerLayer(
                markers: _markerManager.buildPOIMarkers(
                  pois: _pois,
                  onPOITap: _onPOITap,
                  onPOILongPress: _onPOILongPress,
                ),
              ),
              // Route polyline
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
                const SizedBox(height: 8),
                
                // POI Creation button (Organizers only)
                if (_userRole == 'Organizer' && !_isPlacingPOI) ...[
                  FloatingActionButton(
                    heroTag: "addPOI",
                    onPressed: _startPOIPlacement,
                    backgroundColor: AppColors.secondary,
                    child: const Icon(Icons.add_location, size: 24),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
                ],
                
                // Emergency button
                FloatingActionButton(
                  heroTag: "emergency",
                  onPressed: _toggleEmergency,
                  backgroundColor: _isEmergency ? AppColors.mapEmergency : AppColors.surface,
                  foregroundColor: _isEmergency ? Colors.white : AppColors.mapEmergency,
                  child: Icon(
                    _isEmergency ? Icons.emergency : Icons.emergency_outlined,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 8),
                // Location button
                FloatingActionButton(
                  heroTag: "location",
                  onPressed: _getCurrentLocation,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.my_location, color: AppColors.textOnPrimary, size: 24),
                ),
              ],
            ),
          ),
          
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

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.logout, color: Colors.black),
        onPressed: () async {
          await FirebaseAuth.instance.signOut();
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
                if (userRole != null)
                  Text(
                    userRole,
                    style: TextStyle(
                      color: Colors.grey[600],
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
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.black),
          onSelected: (value) async {
            if (value == 'logout') {
              await FirebaseAuth.instance.signOut();
            } else if (value == 'leave_group') {
              if (_userRole != 'Attendee') return;
              
              await UserPreferences.clearGroupData();
              // Note: State sync will be disposed in AuthWrapper when user signs out
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const AuthWrapper()),
                );
              }
            } else if (value == 'debug_state') {
              _showStateSyncDebugDialog();
            }
          },
          itemBuilder: (context) => [
            if (_userRole == 'Attendee')
              const PopupMenuItem(
                value: 'leave_group',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app),
                    SizedBox(width: 8),
                    Text('Leave Group'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 8),
                  Text('Logout'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'debug_state',
              child: Row(
                children: [
                  Icon(Icons.bug_report),
                  SizedBox(width: 8),
                  Text('Debug State'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showStateSyncDebugDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('State Sync Debug'),
        content: const SizedBox(
          width: 400,
          height: 300,
          child: StateSyncStatusWidget(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>> _getGroupAndUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {'groupName': 'Simha Link Map'};

      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .get();

      String groupName = 'Simha Link Map';
      if (groupDoc.exists) {
        groupName = groupDoc.data()?['name'] ?? 'Simha Link Map';
      }

      return {
        'groupName': groupName,
        if (_userRole != null) 'userRole': _userRole!,
      };
    } catch (e) {
      debugPrint('Error getting group and user info: $e');
      return {'groupName': 'Simha Link Map'};
    }
  }
}
