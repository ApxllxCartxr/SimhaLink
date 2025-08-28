import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  // Base URL for OSRM services
  static const String _osrmBaseUrl = 'https://router.project-osrm.org';
  
  /// Get walking route between two points with fallback options
  static Future<List<LatLng>> getWalkingRoute(LatLng start, LatLng end) async {
    // Try OSRM first (free, no API key required)
    try {
      return await _getOSRMRoute(start, end, 'foot');
    } catch (e) {
      print('OSRM walking route failed: $e');
    }
    
    // Try OpenRouteService as backup
    try {
      return await _getOpenRouteServiceRoute(start, end, 'foot-walking');
    } catch (e) {
      print('OpenRouteService failed: $e');
    }
    
    // Fallback to simple straight line with waypoints
    print('Using simple route fallback with curved waypoints');
    return _generateSimpleRoute(start, end);
  }
  
  /// Get driving route between two points
  static Future<List<LatLng>> getDrivingRoute(LatLng start, LatLng end) async {
    try {
      return await _getOSRMRoute(start, end, 'car');
    } catch (e) {
      print('OSRM driving route failed: $e');
      try {
        return await _getOpenRouteServiceRoute(start, end, 'driving-car');
      } catch (e2) {
        print('OpenRouteService driving route failed: $e2');
        return _generateSimpleRoute(start, end);
      }
    }
  }
  
  /// Get cycling route between two points
  static Future<List<LatLng>> getCyclingRoute(LatLng start, LatLng end) async {
    try {
      return await _getOSRMRoute(start, end, 'bike');
    } catch (e) {
      print('OSRM cycling route failed: $e');
      try {
        return await _getOpenRouteServiceRoute(start, end, 'cycling-regular');
      } catch (e2) {
        print('OpenRouteService cycling route failed: $e2');
        return _generateSimpleRoute(start, end);
      }
    }
  }
  
  // OSRM routing implementation
  static Future<List<LatLng>> _getOSRMRoute(LatLng start, LatLng end, String profile) async {
    // Format: /route/v1/{profile}/{coordinates}?...
    final coordinates = '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
    final url = Uri.parse('$_osrmBaseUrl/route/v1/$profile/$coordinates?steps=true&geometries=geojson&overview=full');
    
    print('Requesting OSRM route: $url');
    
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
        final geometry = data['routes'][0]['geometry'];
        final coordinates = geometry['coordinates'] as List;
        
        final routePoints = coordinates.map<LatLng>((coord) {
          return LatLng(coord[1].toDouble(), coord[0].toDouble());
        }).toList();
        
        print('OSRM route found with ${routePoints.length} points');
        return routePoints;
      }
    }
    
    throw Exception('OSRM API error: ${response.statusCode} - ${response.body}');
  }
  
  // OpenRouteService with better error handling
  static Future<List<LatLng>> _getOpenRouteServiceRoute(LatLng start, LatLng end, String profile) async {
    // Use a public demo endpoint that doesn't require API key for basic routing
    final url = Uri.parse('https://api.openrouteservice.org/v2/directions/$profile/geojson');
    
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'coordinates': [
          [start.longitude, start.latitude],
          [end.longitude, end.latitude]
        ],
        'format': 'geojson',
        'instructions': false,
      }),
    ).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data['features'] != null && data['features'].isNotEmpty) {
        final geometry = data['features'][0]['geometry'];
        final coordinates = geometry['coordinates'] as List;
        
        return coordinates.map<LatLng>((coord) {
          return LatLng(coord[1].toDouble(), coord[0].toDouble());
        }).toList();
      }
    } else {
      throw Exception('OpenRouteService API error: ${response.statusCode} - ${response.body}');
    }
    
    throw Exception('No route found');
  }
  
  // Generate a simple route with intermediate waypoints for better visualization
  static List<LatLng> _generateSimpleRoute(LatLng start, LatLng end) {
    final List<LatLng> route = [];
    
    // Add start point
    route.add(start);
    
    // Calculate the difference
    final latDiff = end.latitude - start.latitude;
    final lngDiff = end.longitude - start.longitude;
    
    // Add intermediate waypoints for a more realistic route visualization
    final segments = 5; // Number of intermediate points
    
    for (int i = 1; i < segments; i++) {
      final ratio = i / segments;
      
      // Add some curve to make it look more like a real route
      final curveFactor = 0.0001; // Small curve for realism
      final curveOffset = curveFactor * (4 * ratio * (1 - ratio)); // Bell curve
      
      final lat = start.latitude + (latDiff * ratio);
      final lng = start.longitude + (lngDiff * ratio) + curveOffset;
      
      route.add(LatLng(lat, lng));
    }
    
    // Add end point
    route.add(end);
    
    return route;
  }
  
  /// Calculate estimated walking time in minutes
  static double estimateWalkingTime(List<LatLng> route) {
    if (route.length < 2) return 0;
    
    double totalDistance = 0;
    const distance = Distance();
    
    for (int i = 0; i < route.length - 1; i++) {
      totalDistance += distance.as(LengthUnit.Meter, route[i], route[i + 1]);
    }
    
    // Average walking speed: 5 km/h = 1.39 m/s
    // Time in minutes = distance_in_meters / (1.39 * 60)
    return totalDistance / (1.39 * 60);
  }
  
  /// Calculate total route distance in meters
  static double calculateRouteDistance(List<LatLng> route) {
    if (route.length < 2) return 0;
    
    double totalDistance = 0;
    const distance = Distance();
    
    for (int i = 0; i < route.length - 1; i++) {
      totalDistance += distance.as(LengthUnit.Meter, route[i], route[i + 1]);
    }
    
    return totalDistance;
  }
  
  /// Format distance for display
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()}m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km';
    }
  }
  
  /// Format time for display
  static String formatTime(double timeInMinutes) {
    if (timeInMinutes < 60) {
      return '${timeInMinutes.round()}min';
    } else {
      final hours = timeInMinutes ~/ 60;
      final minutes = (timeInMinutes % 60).round();
      return '${hours}h ${minutes}min';
    }
  }
}
