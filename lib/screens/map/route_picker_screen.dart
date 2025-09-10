import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import '../../core/utils/app_logger.dart';

class RoutePickerScreen extends StatefulWidget {
  final String? initialFromAddress;
  final String? initialToAddress;
  final LatLng? initialFromLocation;
  final LatLng? initialToLocation;

  const RoutePickerScreen({
    super.key,
    this.initialFromAddress,
    this.initialToAddress,
    this.initialFromLocation,
    this.initialToLocation,
  });

  @override
  State<RoutePickerScreen> createState() => _RoutePickerScreenState();
}

class _RoutePickerScreenState extends State<RoutePickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  
  LatLng? _fromLocation;
  LatLng? _toLocation;
  List<LatLng> _routePoints = [];
  String _fromAddress = '';
  String _toAddress = '';
  bool _isLoadingRoute = false;
  bool _isLoadingLocation = false;
  String _routeDistance = '';
  String _routeDuration = '';
  bool _currentLocationForFrom = false;
  
  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    // Initialize with passed data
    if (widget.initialFromLocation != null) {
      _fromLocation = widget.initialFromLocation;
      _fromAddress = widget.initialFromAddress ?? '';
      _fromController.text = _fromAddress;
    }
    
    if (widget.initialToLocation != null) {
      _toLocation = widget.initialToLocation;
      _toAddress = widget.initialToAddress ?? '';
      _toController.text = _toAddress;
    }
    
    // Calculate route if both locations are set
    if (_fromLocation != null && _toLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _calculateRoadRoute();
      });
    } else {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.logWarning('Location services are disabled');
        setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          AppLogger.logWarning('Location permissions denied');
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.logError('Location permissions permanently denied');
        setState(() => _isLoadingLocation = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final currentLocation = LatLng(position.latitude, position.longitude);
      
      // Center map on current location
      _mapController.move(currentLocation, 15.0);
      
      AppLogger.logInfo('Current location obtained: ${position.latitude}, ${position.longitude}');
      
    } catch (e) {
      AppLogger.logError('Error getting current location', e);
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _onMapTap(LatLng point) async {
    if (_fromLocation == null) {
      // Set pickup location
      setState(() {
        _fromLocation = point;
        _isLoadingRoute = true;
      });
      
      // Get address for from location
      await _getAddressFromCoordinates(point, true);
      
    } else if (_toLocation == null) {
      // Set destination
      setState(() {
        _toLocation = point;
        _isLoadingRoute = true;
      });
      
      // Get address for destination
      await _getAddressFromCoordinates(point, false);
      
      // Calculate route
      await _calculateRoadRoute();
      
    } else {
      // Both points selected - ask which one to update
      _showLocationUpdateDialog(point);
    }
  }

  void _showLocationUpdateDialog(LatLng point) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Location'),
        content: const Text('Which location would you like to update?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() {
                _fromLocation = point;
                _routePoints.clear();
                _isLoadingRoute = true;
              });
              await _getAddressFromCoordinates(point, true);
              await _calculateRoadRoute();
            },
            child: const Text('Update Pickup'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() {
                _toLocation = point;
                _routePoints.clear();
                _isLoadingRoute = true;
              });
              await _getAddressFromCoordinates(point, false);
              await _calculateRoadRoute();
            },
            child: const Text('Update Destination'),
          ),
        ],
      ),
    );
  }

  Future<void> _getAddressFromCoordinates(LatLng point, bool isFromLocation) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address = _formatAddress(placemark);
        
        setState(() {
          if (isFromLocation) {
            _fromAddress = address;
            _fromController.text = address;
          } else {
            _toAddress = address;
            _toController.text = address;
          }
        });
      }
    } catch (e) {
      AppLogger.logError('Error getting address from coordinates', e);
      // Fallback to coordinates
      final address = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
      setState(() {
        if (isFromLocation) {
          _fromAddress = address;
          _fromController.text = address;
        } else {
          _toAddress = address;
          _toController.text = address;
        }
      });
    }
  }

  String _formatAddress(Placemark placemark) {
    List<String> addressComponents = [];
    
    if (placemark.name != null && placemark.name!.isNotEmpty) {
      addressComponents.add(placemark.name!);
    }
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      addressComponents.add(placemark.street!);
    }
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      addressComponents.add(placemark.locality!);
    }
    if (placemark.administrativeArea != null && placemark.administrativeArea!.isNotEmpty) {
      addressComponents.add(placemark.administrativeArea!);
    }
    
    return addressComponents.isNotEmpty 
        ? addressComponents.join(', ') 
        : 'Selected Location';
  }

  Future<void> _calculateRoadRoute() async {
    if (_fromLocation == null || _toLocation == null) return;
    
    setState(() {
      _isLoadingRoute = true;
    });
    
    try {
      AppLogger.logInfo('Calculating road route from $_fromLocation to $_toLocation');
      
      // Try OSRM (completely free) first
      List<LatLng> routePoints = await _getOSRMRoute(_fromLocation!, _toLocation!, 'driving');
      
      if (routePoints.isEmpty) {
        AppLogger.logWarning('Driving route failed, trying walking route');
        routePoints = await _getOSRMRoute(_fromLocation!, _toLocation!, 'walking');
      }
      
      if (routePoints.isEmpty) {
        AppLogger.logWarning('OSRM failed, trying GraphHopper free tier');
        routePoints = await _getGraphHopperRoute(_fromLocation!, _toLocation!);
      }
      
      if (routePoints.isEmpty) {
        AppLogger.logWarning('All free routing services failed, generating smart fallback route');
        routePoints = _generateSmartRoute(_fromLocation!, _toLocation!);
        _routeDistance = _calculateDirectDistance(_fromLocation!, _toLocation!);
        _routeDuration = 'Estimated';
      }
      
      setState(() {
        _routePoints = routePoints;
        _isLoadingRoute = false;
      });
      
      _fitMapToRoute();
      
    } catch (e) {
      AppLogger.logError('Error calculating route', e);
      setState(() {
        _routePoints = [_fromLocation!, _toLocation!];
        _routeDistance = _calculateDirectDistance(_fromLocation!, _toLocation!);
        _routeDuration = 'Unknown';
        _isLoadingRoute = false;
      });
    }
  }

  Future<List<LatLng>> _getOSRMRoute(LatLng from, LatLng to, String profile) async {
    try {
      // OSRM (Open Source Routing Machine) - completely free
      final String url = 'https://router.project-osrm.org/route/v1/$profile/${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
      
      final response = await http.get(
        Uri.parse('$url?overview=full&geometries=geojson'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final coordinates = data['routes'][0]['geometry']['coordinates'] as List;
          
          final routePoints = coordinates.map<LatLng>((coord) {
            return LatLng(coord[1].toDouble(), coord[0].toDouble());
          }).toList();
          
          // Extract distance and duration from OSRM response
          final distance = data['routes'][0]['distance'] / 1000; // Convert to km
          final duration = data['routes'][0]['duration'] / 60; // Convert to minutes
          
          _routeDistance = '${distance.toStringAsFixed(1)} km';
          _routeDuration = '${duration.toInt()} min';
          
          AppLogger.logInfo('OSRM route calculated: ${routePoints.length} points, $_routeDistance, $_routeDuration');
          return routePoints;
        }
      }
      
      AppLogger.logWarning('OSRM failed: ${response.statusCode}');
      return [];
    } catch (e) {
      AppLogger.logError('OSRM error', e);
      return [];
    }
  }

  // Second FREE routing service - GraphHopper (free tier)
  Future<List<LatLng>> _getGraphHopperRoute(LatLng from, LatLng to) async {
    try {
      // GraphHopper has a free tier without API key for basic routing
      final String url = 'https://graphhopper.com/api/1/route';
      
      final response = await http.get(
        Uri.parse('$url?point=${from.latitude},${from.longitude}&point=${to.latitude},${to.longitude}&vehicle=car&type=json'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['paths'] != null && data['paths'].isNotEmpty) {
          final path = data['paths'][0];
          final points = path['points'];
          
          // Decode polyline if it's encoded, otherwise use direct points
          if (points is String) {
            // This would need polyline decoding - skip for now
            return [];
          }
          
          final distance = path['distance'] / 1000; // Convert to km
          final time = path['time'] / 60000; // Convert to minutes
          
          _routeDistance = '${distance.toStringAsFixed(1)} km';
          _routeDuration = '${time.toInt()} min';
          
          AppLogger.logInfo('GraphHopper route calculated');
          return [from, to]; // Simplified for now
        }
      }
      
      AppLogger.logWarning('GraphHopper failed: ${response.statusCode}');
      return [];
    } catch (e) {
      AppLogger.logError('GraphHopper error', e);
      return [];
    }
  }

  // Smart fallback routing - creates a more realistic route than straight line
  List<LatLng> _generateSmartRoute(LatLng from, LatLng to) {
    AppLogger.logInfo('Generating smart fallback route');
    
    // Calculate distance to determine how many waypoints to add
    final directDistance = _calculateDirectDistanceKm(from, to);
    
    if (directDistance < 1.0) {
      // Short distance - direct line is fine
      return [from, to];
    }
    
    // For longer distances, add some waypoints to simulate roads
    List<LatLng> waypoints = [from];
    
    // Add intermediate points with slight offsets to simulate road curves
    final latDiff = to.latitude - from.latitude;
    final lngDiff = to.longitude - from.longitude;
    
    // Add 2-4 waypoints depending on distance
    final numWaypoints = (directDistance / 5).clamp(2, 4).round();
    
    for (int i = 1; i < numWaypoints; i++) {
      final progress = i / numWaypoints;
      
      // Add some randomness to simulate road paths
      final latOffset = (math.Random().nextDouble() - 0.5) * 0.01;
      final lngOffset = (math.Random().nextDouble() - 0.5) * 0.01;
      
      final waypoint = LatLng(
        from.latitude + (latDiff * progress) + latOffset,
        from.longitude + (lngDiff * progress) + lngOffset,
      );
      
      waypoints.add(waypoint);
    }
    
    waypoints.add(to);
    
    // Estimate duration based on average speed (assume 30 km/h average)
    final estimatedDuration = (directDistance / 30 * 60).round();
    _routeDuration = '${estimatedDuration} min (est)';
    
    return waypoints;
  }

  double _calculateDirectDistanceKm(LatLng from, LatLng to) {
    const double earthRadius = 6371; // Earth radius in km
    final double lat1Rad = from.latitude * (math.pi / 180);
    final double lat2Rad = to.latitude * (math.pi / 180);
    final double deltaLat = (to.latitude - from.latitude) * (math.pi / 180);
    final double deltaLng = (to.longitude - from.longitude) * (math.pi / 180);

    final double a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) * math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  String _calculateDirectDistance(LatLng from, LatLng to) {
    const double earthRadius = 6371; // Earth radius in km
    final double lat1Rad = from.latitude * (math.pi / 180);
    final double lat2Rad = to.latitude * (math.pi / 180);
    final double deltaLat = (to.latitude - from.latitude) * (math.pi / 180);
    final double deltaLng = (to.longitude - from.longitude) * (math.pi / 180);

    final double a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) * math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    final double distance = earthRadius * c;
    return '${distance.toStringAsFixed(1)} km';
  }

  void _fitMapToRoute() {
    if (_routePoints.isEmpty) return;
    
    if (_routePoints.length == 1) {
      _mapController.move(_routePoints.first, 15.0);
      return;
    }
    
    // Calculate bounds from route points
    double minLat = _routePoints.first.latitude;
    double maxLat = _routePoints.first.latitude;
    double minLng = _routePoints.first.longitude;
    double maxLng = _routePoints.first.longitude;
    
    for (final point in _routePoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    
    // Add padding
    const padding = 0.01;
    final bounds = LatLngBounds(
      LatLng(minLat - padding, minLng - padding),
      LatLng(maxLat + padding, maxLng + padding),
    );
    
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds));
  }

  Future<void> _searchAddress(String query, bool isFromLocation) async {
    if (query.trim().isEmpty) return;
    
    try {
      List<Location> locations = await locationFromAddress(query);
      
      if (locations.isNotEmpty && mounted) {
        final location = locations.first;
        final latLng = LatLng(location.latitude, location.longitude);
        
        setState(() {
          if (isFromLocation) {
            _fromLocation = latLng;
            _fromAddress = query;
          } else {
            _toLocation = latLng;
            _toAddress = query;
          }
        });
        
        // Move map to the searched location
        _mapController.move(latLng, 15.0);
        
        // Calculate route if both locations are set
        if (_fromLocation != null && _toLocation != null) {
          await _calculateRoadRoute();
        }
      }
    } catch (e) {
      AppLogger.logError('Error searching address: $query', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not find address: $query'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _setCurrentLocation(bool isForFrom) async {
    setState(() {
      _isLoadingLocation = true;
      _currentLocationForFrom = isForFrom;
    });
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.logWarning('Location services are disabled');
        setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          AppLogger.logWarning('Location permissions denied');
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.logError('Location permissions permanently denied');
        setState(() => _isLoadingLocation = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final currentLocation = LatLng(position.latitude, position.longitude);
      
      // Get address for current location
      await _getAddressFromCoordinates(currentLocation, isForFrom);
      
      setState(() {
        if (isForFrom) {
          _fromLocation = currentLocation;
        } else {
          _toLocation = currentLocation;
        }
      });
      
      // Move map to current location
      _mapController.move(currentLocation, 15.0);
      
      // Calculate route if both locations are set
      if (_fromLocation != null && _toLocation != null) {
        await _calculateRoadRoute();
      }
      
    } catch (e) {
      AppLogger.logError('Error getting current location', e);
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _confirmRoute() {
    if (_fromLocation == null || _toLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both pickup and destination locations'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Return the route data
    Navigator.of(context).pop({
      'fromLocation': _fromLocation,
      'toLocation': _toLocation,
      'fromAddress': _fromAddress,
      'toAddress': _toAddress,
      'routePoints': _routePoints,
      'distance': _routeDistance,
      'duration': _routeDuration,
    });
  }

  void _clearRoute() {
    setState(() {
      _fromLocation = null;
      _toLocation = null;
      _routePoints.clear();
      _fromAddress = '';
      _toAddress = '';
      _fromController.clear();
      _toController.clear();
      _routeDistance = '';
      _routeDuration = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Route'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_fromLocation != null || _toLocation != null)
            IconButton(
              onPressed: _clearRoute,
              icon: const Icon(Icons.clear),
              tooltip: 'Clear Route',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(12.9716, 77.5946), // Bangalore
              initialZoom: 15,
              maxZoom: 18,
              minZoom: 3,
              onTap: (tapPosition, point) => _onMapTap(point),
            ),
            children: [
              // Tile layer - same as main map
              TileLayer(
                urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.simha_link',
                maxZoom: 19,
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              
              // Route polyline
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: Colors.black,
                      strokeWidth: 4,
                      pattern: _routePoints.length == 2 ? 
                        StrokePattern.dashed(segments: [10, 5]) : 
                        StrokePattern.solid(),
                    ),
                  ],
                ),
              
              // Location markers
              MarkerLayer(
                markers: [
                  // From marker
                  if (_fromLocation != null)
                    Marker(
                      point: _fromLocation!,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  
                  // To marker
                  if (_toLocation != null)
                    Marker(
                      point: _toLocation!,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.flag,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          
          // Search fields at the top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // From location search field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _fromController,
                          decoration: InputDecoration(
                            hintText: 'Pickup location',
                            prefixIcon: const Icon(Icons.location_on, color: Colors.green),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          onSubmitted: (value) => _searchAddress(value, true),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: IconButton(
                          onPressed: () => _setCurrentLocation(true),
                          icon: _isLoadingLocation && _currentLocationForFrom 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location, color: Colors.black),
                          tooltip: 'Use current location',
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // To location search field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _toController,
                          decoration: InputDecoration(
                            hintText: 'Destination',
                            prefixIcon: const Icon(Icons.flag, color: Colors.red),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          onSubmitted: (value) => _searchAddress(value, false),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: IconButton(
                          onPressed: () => _setCurrentLocation(false),
                          icon: _isLoadingLocation && !_currentLocationForFrom 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location, color: Colors.black),
                          tooltip: 'Use current location',
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Route info display
                if (_routePoints.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.route, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isLoadingRoute 
                                ? 'Calculating route...'
                                : 'Route: $_routeDistance • $_routeDuration',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Current location button
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton(
              onPressed: _getCurrentLocation,
              backgroundColor: Colors.white,
              child: _isLoadingLocation
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: Colors.blue),
            ),
          ),
        ],
      ),
      
      // Bottom confirmation buttons
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.grey),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _fromLocation != null && _toLocation != null && !_isLoadingRoute
                      ? _confirmRoute
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _isLoadingRoute
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Confirm Route',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }
}
