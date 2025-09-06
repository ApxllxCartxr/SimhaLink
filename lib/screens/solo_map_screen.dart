import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/poi.dart';
import 'package:simha_link/screens/broadcast_list_screen.dart';
import 'package:simha_link/services/broadcast_service.dart';
import 'package:simha_link/services/routing_service.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/screens/group_creation_screen.dart';

// Import the map managers
import 'map/managers/location_manager.dart';
import '../services/emergency_management_service.dart';
import '../services/emergency_database_service.dart';
import '../models/emergency.dart';

/// Solo Map Screen for users not in any group
/// Provides full map functionality for solo attendees including emergency features
class SoloMapScreen extends StatefulWidget {
  const SoloMapScreen({super.key});

  @override
  State<SoloMapScreen> createState() => _SoloMapScreenState();
}

class _SoloMapScreenState extends State<SoloMapScreen> with TickerProviderStateMixin {
  final _mapController = MapController();
  
  // Managers
  late LocationManager _locationManager;
  
  // Emergency Database System for solo users  
  StreamSubscription<List<Emergency>>? _emergenciesSubscription;
  List<Emergency> _activeEmergencies = [];
  final Set<String> _notifiedEmergencies = <String>{};
  
  // Data streams
  StreamSubscription<QuerySnapshot>? _poisSubscription;
  
  // State variables
  List<POI> _pois = [];
  POI? _selectedPOI;
  bool _isEmergency = false;
  final String _userRole = 'Attendee'; // Solo users are always attendees
  bool _isMapReady = false;
  
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
      groupId: 'solo_${FirebaseAuth.instance.currentUser?.uid ?? 'unknown'}',
      userRole: _userRole,
      isEmergency: _isEmergency,
    );
  }

  /// Initialize emergency management for solo users
  Future<void> _initializeEmergencyManagement() async {
    try {
      // Initialize emergency management service
      await EmergencyManagementService.initialize();
      
      // Clean up any stale emergencies for the current user
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        AppLogger.logInfo('Solo user cleaning up stale emergencies: $userId');
        await EmergencyDatabaseService.cleanupUserEmergencies(userId);
      }
      
      // Cancel any existing subscription
      _emergenciesSubscription?.cancel();
      
      // Solo users listen to emergencies they can see (typically their group)
      AppLogger.logInfo('Solo user listening to group emergencies');
      _emergenciesSubscription = EmergencyManagementService.listenToGroupEmergencies(
        'solo_$userId',
        (emergencies) {
          if (mounted) {
            setState(() {
              _activeEmergencies = emergencies;
            });
            _handleNewEmergencyNotifications(emergencies);
          }
        },
      );
      
      AppLogger.logInfo('Solo emergency management initialized');
    } catch (e) {
      AppLogger.logError('Error initializing solo emergency management', e);
      
      // Retry after delay
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _initializeEmergencyManagement();
        }
      });
    }
  }

  /// Handle new emergency notifications for solo users
  void _handleNewEmergencyNotifications(List<Emergency> emergencies) {
    for (final emergency in emergencies) {
      if (!_notifiedEmergencies.contains(emergency.emergencyId)) {
        _notifiedEmergencies.add(emergency.emergencyId);
        
        // Show emergency notification
        _showTopSnackBar(
          message: 'Emergency status: ${emergency.status.name}',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          icon: const Icon(Icons.emergency, color: Colors.white),
        );
      }
    }
    
    // Clean up resolved notifications
    _notifiedEmergencies.removeWhere((id) => 
        !emergencies.any((emergency) => emergency.emergencyId == id));
  }

  Future<void> _setupInitialData() async {
    await _setupLocationTracking();
    _listenToGroupLocations();
    _listenToPOIs();
    await _initializeEmergencyManagement();
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
      
      // For solo users, store location in a special solo collection
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('solo_locations')
            .doc(user.uid)
            .set({
          'userId': user.uid,
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'isEmergency': _isEmergency,
          'role': _userRole,
        });
      }
    } catch (e) {
      if (mounted) {
        AppLogger.logError('Error updating solo user location', e);
      }
    }
  }

  void _listenToPOIs() {
    _poisSubscription = FirebaseFirestore.instance
        .collection('pois')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _pois = snapshot.docs.map((doc) {
            try {
              final data = doc.data();
              data['id'] = doc.id; // Add document ID to data
              return POI.fromMap(data);
            } catch (e) {
              AppLogger.logError('Error parsing POI: ${doc.id}', e);
              return null;
            }
          }).where((poi) => poi != null).cast<POI>().toList();
        });
      }
    });
  }

  void _listenToGroupLocations() {
    // Solo users don't need group location tracking
  }

  Future<void> _toggleEmergency() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      if (!_isEmergency) {
        // Create emergency for solo user
        final currentLocation = _locationManager.currentLocation;
        if (currentLocation?.latitude != null && currentLocation?.longitude != null) {
          await EmergencyDatabaseService.createEmergencyWithState(
            attendeeId: userId,
            attendeeName: FirebaseAuth.instance.currentUser?.displayName ?? 'Solo User',
            groupId: 'solo_$userId', // Special solo group ID
            location: LatLng(currentLocation!.latitude!, currentLocation.longitude!),
            message: 'Solo user emergency',
          );
          
          _showTopSnackBar(
            message: 'Emergency activated! Your location has been recorded.',
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            icon: const Icon(Icons.emergency, color: Colors.white),
          );
        }
      } else {
        // Resolve emergency
        final activeEmergency = _activeEmergencies.firstWhere(
          (e) => e.attendeeId == userId && e.status != EmergencyStatus.resolved,
          orElse: () => _activeEmergencies.first,
        );
        
        await EmergencyDatabaseService.markResolvedByAttendee(
          activeEmergency.emergencyId,
        );
        
        _showTopSnackBar(
          message: 'Emergency resolved',
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          icon: const Icon(Icons.check, color: Colors.white),
        );
      }
      
      setState(() {
        _isEmergency = !_isEmergency;
      });
      
    } catch (e) {
      if (mounted) {
        _showTopSnackBar(
          message: 'Error toggling emergency: ${e.toString()}',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!_isMapReady) return;
    
    try {
      final locationData = await _locationManager.getCurrentLocation();
      if (locationData != null && mounted) {
        _mapController.move(
          LatLng(locationData.latitude!, locationData.longitude!),
          16.0,
        );
      }
    } catch (e) {
      AppLogger.logError('Error getting current location', e);
    }
  }

  /// Build POI markers for the map
  List<Marker> _buildPOIMarkers() {
    return _pois.map((poi) {
      final isSelected = _selectedPOI?.id == poi.id;
      return Marker(
        point: LatLng(poi.latitude, poi.longitude),
        width: isSelected ? 50 : 40,
        height: isSelected ? 50 : 40,
        child: GestureDetector(
          onTap: () => _onPOITap(poi),
          onLongPress: () => _onPOILongPress(poi),
          child: Container(
            decoration: BoxDecoration(
              color: _getMarkerColor(poi.type),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.yellow : Colors.white,
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              poi.type.iconData,
              color: Colors.white,
              size: isSelected ? 25 : 20,
            ),
          ),
        ),
      );
    }).toList();
  }

  void _onPOITap(POI poi) {
    // Solo users cannot manage markers, just select for routing
    setState(() => _selectedPOI = poi);
    _calculatePOIRoute();
  }

  void _onPOILongPress(POI poi) {
    // For non-organizers, show basic marker information
    _showMarkerInfoDialog(poi);
  }

  void _showMarkerInfoDialog(POI poi) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${poi.type.name}'),
            const SizedBox(height: 8),
            Text('Description: ${poi.description}'),
            const SizedBox(height: 8),
            Text('Created: ${poi.createdAt.toString().split(' ')[0]}'),
          ],
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

  Future<void> _calculatePOIRoute() async {
    if (_selectedPOI == null || _locationManager.currentLocation == null) {
      setState(() {
        _routeInfo = '';
        _currentRoute = [];
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
        _locationManager.currentLocation!.longitude!,
      );
      final end = LatLng(_selectedPOI!.latitude, _selectedPOI!.longitude);
      
      final route = await RoutingService.getWalkingRoute(start, end);
      
      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
          
          final distance = _calculateDistance(
            start.latitude, start.longitude,
            end.latitude, end.longitude,
          );
          
          _routeInfo = 'Route to ${_selectedPOI!.name}: ${(distance / 1000).toStringAsFixed(2)} km';
        });
      }
    } catch (e) {
      debugPrint('Error calculating POI route: $e');
      if (mounted) {
        setState(() {
          _routeInfo = 'Unable to calculate route';
          _isLoadingRoute = false;
          _currentRoute = [];
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
              backgroundColor: Colors.blue,
              child: const Icon(Icons.campaign, color: Colors.white),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
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
      AppLogger.logInfo('SoloMapScreen disposing resources');
      _poisSubscription?.cancel();
      _emergenciesSubscription?.cancel();
      _locationManager.dispose();
      EmergencyManagementService.dispose();
      _mapController.dispose();
      AppLogger.logInfo('SoloMapScreen resources disposed successfully');
    } catch (e) {
      AppLogger.logError('Error disposing SoloMapScreen resources', e);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                // Clear selections for solo users
                setState(() {
                  _selectedPOI = null;
                  _currentRoute = [];
                  _routeInfo = '';
                });
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
                          ? Colors.red.withOpacity(0.15)
                          : Colors.blue.withOpacity(0.2),
                      borderColor: _isEmergency ? Colors.red : Colors.blue,
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
                      color: Colors.blue,
                      strokeWidth: 4,
                      pattern: const StrokePattern.dotted(),
                    ),
                  ],
                ),
                
              // POI markers (medium priority)
              MarkerLayer(
                markers: _buildPOIMarkers(),
              ),
              
              // Current location marker (higher priority than POI)
              if (_locationManager.currentLocation?.latitude != null &&
                  _locationManager.currentLocation?.longitude != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _locationManager.currentLocation!.latitude!,
                        _locationManager.currentLocation!.longitude!,
                      ),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isEmergency ? Colors.red : Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isEmergency ? Icons.emergency : Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                
              // Emergency markers (HIGHEST PRIORITY - Always on top)
              MarkerLayer(
                markers: _buildEmergencyMarkers(),
              ),
            ],
          ),
          
          // Info panel (matches group map style)
          if (_routeInfo.isNotEmpty)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.white.withOpacity(0.95),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.directions,
                        color: Colors.blue,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Route Information',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _routeInfo,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      if (_isLoadingRoute)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedPOI = null;
                            _currentRoute = [];
                            _routeInfo = '';
                          });
                        },
                        icon: const Icon(Icons.close),
                        iconSize: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Floating action buttons (matches group map layout)
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Broadcast button (always visible)
                _buildBroadcastButton(),
                const SizedBox(height: 12),
                
                // Join group button (replaces POI creation for solo users)
                FloatingActionButton.extended(
                  heroTag: "join_group",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GroupCreationScreen(),
                      ),
                    );
                  },
                  backgroundColor: Colors.green,
                  icon: const Icon(Icons.group_add, color: Colors.white),
                  label: const Text('Join Group', style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                
                // Emergency button (solo users can activate emergency)
                FloatingActionButton(
                  heroTag: "emergency",
                  onPressed: () async {
                    if (_isEmergency) {
                      // Show resolve dialog for active emergencies
                      final shouldResolve = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('🟢 Resolve Emergency'),
                          content: const Text('Mark this emergency as resolved?\n\nThis will notify that you are safe.'),
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
                        await _toggleEmergency();
                      }
                    } else {
                      // Normal emergency activation
                      await _toggleEmergency();
                    }
                  },
                  backgroundColor: _isEmergency ? Colors.red : Colors.orange,
                  foregroundColor: Colors.white,
                  child: Icon(
                    _isEmergency ? Icons.emergency : Icons.emergency_outlined,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Location button (always visible)
                FloatingActionButton(
                  heroTag: "location",
                  onPressed: _getCurrentLocation,
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.my_location, color: Colors.white, size: 24),
                ),
              ],
            ),
          ),
          
          // Solo mode indicator (replaces role info from group map)
          Positioned(
            top: 16,
            left: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person,
                      color: Colors.purple,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Solo Mode - Tap markers for directions',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Emergency status card (shown when emergency is active)
          if (_isEmergency)
            Positioned(
              bottom: 120, // Above floating action buttons
              left: 16,
              right: 90, // Leave space for FABs
              child: Card(
                elevation: 8,
                color: Colors.red,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emergency,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Emergency Active',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your emergency has been recorded. Tap the emergency button again to resolve.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 150,
          left: 16,
          right: 16,
        ),
        action: action,
      ),
    );
  }

  /// Build emergency markers for the map
  List<Marker> _buildEmergencyMarkers() {
    List<Marker> emergencyMarkers = [];
    
    for (final emergency in _activeEmergencies) {
      if (emergency.status == EmergencyStatus.resolved) continue;

      final markerSize = 50.0;
      final iconSize = 30.0;

      emergencyMarkers.add(
        Marker(
          point: emergency.location,
          width: markerSize,
          height: markerSize,
          child: GestureDetector(
            onTap: () => _onEmergencyMarkerTap(emergency),
            child: Container(
              decoration: BoxDecoration(
                color: _getEmergencyMarkerColor(emergency),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.emergency,
                color: Colors.white,
                size: iconSize,
              ),
            ),
          ),
        ),
      );
    }

    return emergencyMarkers;
  }

  /// Get appropriate color for emergency marker based on status
  Color _getEmergencyMarkerColor(Emergency emergency) {
    switch (emergency.status) {
      case EmergencyStatus.unverified:
        return Colors.orange;
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
    _mapController.move(emergency.location, 16.0);

    // Show emergency info
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('Status: ${emergency.status.name}'),
            const SizedBox(height: 8),
            Text('Time: ${emergency.createdAt.toString().split('.')[0]}'),
            const SizedBox(height: 8),
            Text('Message: ${emergency.message ?? 'No message'}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  /// Get marker color for POI type
  Color _getMarkerColor(MarkerType type) {
    switch (type) {
      case MarkerType.medical:
        return Colors.red;
      case MarkerType.drinkingWater:
        return Colors.blue;
      case MarkerType.emergency:
        return Colors.red.shade800;
      case MarkerType.accessibility:
        return Colors.purple;
      case MarkerType.historical:
        return Colors.brown;
      case MarkerType.restroom:
        return Colors.green;
      case MarkerType.food:
        return Colors.orange;
      case MarkerType.parking:
        return Colors.grey;
      case MarkerType.security:
        return Colors.indigo;
      case MarkerType.information:
        return Colors.teal;
    }
  }
}
