import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Manages geographic-consistent marker sizing based on real-world coverage
class GeographicMarkerManager {
  static const Distance _distanceCalculator = Distance();
  
  // Default coverage areas in meters for different marker types
  static const Map<MarkerType, double> _defaultCoverageRadiusMeters = {
    MarkerType.emergency: 50.0,        // Emergency covers ~50m radius
    MarkerType.medical: 30.0,          // Medical station covers ~30m radius  
    MarkerType.drinkingWater: 20.0,    // Water source covers ~20m radius
    MarkerType.accessibility: 25.0,    // Accessibility feature covers ~25m radius
    MarkerType.historical: 15.0,       // Historical marker covers ~15m radius
    MarkerType.userLocation: 10.0,     // User location precision ~10m radius
    MarkerType.volunteer: 40.0,        // Volunteer coverage area ~40m radius
    MarkerType.organizer: 60.0,        // Organizer oversight area ~60m radius
  };

  /// Calculate marker size based on geographic coverage and current zoom level
  static double calculateGeographicMarkerSize({
    required double currentZoom,
    required LatLng markerPosition,
    required MarkerType markerType,
    double? customCoverageRadiusMeters,
    double minPixelSize = 20.0,
    double maxPixelSize = 120.0,
  }) {
    // Get coverage radius for this marker type
    final coverageRadius = customCoverageRadiusMeters ?? 
                          _defaultCoverageRadiusMeters[markerType] ?? 
                          25.0;
    
    // Calculate pixels per meter at current zoom and latitude
    final pixelsPerMeter = _calculatePixelsPerMeter(currentZoom, markerPosition.latitude);
    
    // Calculate geographic marker size in pixels
    final geographicSize = coverageRadius * pixelsPerMeter * 2; // Diameter
    
    // Clamp to reasonable pixel bounds
    return geographicSize.clamp(minPixelSize, maxPixelSize);
  }

  /// Calculate accuracy circle size for location markers
  static double calculateAccuracyCircleRadius({
    required double currentZoom,
    required LatLng centerPosition,
    required double accuracyMeters,
  }) {
    final pixelsPerMeter = _calculatePixelsPerMeter(currentZoom, centerPosition.latitude);
    return accuracyMeters * pixelsPerMeter;
  }

  /// Get optimal icon size within a geographic marker
  static double calculateIconSize(double markerSize) {
    // Icon should be about 60% of marker size for good visual balance
    return (markerSize * 0.6).clamp(12.0, 40.0);
  }

  /// Calculate geographic distance between two points
  static double calculateDistance(LatLng point1, LatLng point2) {
    return _distanceCalculator.as(LengthUnit.Meter, point1, point2);
  }

  /// Check if a marker should be visible at current zoom (based on its coverage area)
  static bool shouldMarkerBeVisible({
    required double currentZoom,
    required MarkerType markerType,
    double minVisibleZoom = 10.0,
  }) {
    // Different marker types become visible at different zoom levels based on their importance
    final Map<MarkerType, double> minZoomLevels = {
      MarkerType.emergency: 8.0,        // Always visible - highest priority
      MarkerType.medical: 10.0,         // Visible from medium zoom
      MarkerType.organizer: 11.0,       // Organizers visible from medium-high zoom
      MarkerType.volunteer: 12.0,       // Volunteers visible at higher zoom
      MarkerType.accessibility: 13.0,   // Accessibility features at high zoom
      MarkerType.drinkingWater: 13.0,   // Water sources at high zoom
      MarkerType.historical: 14.0,      // Historical markers at highest zoom
      MarkerType.userLocation: 8.0,     // User location always visible
    };

    final requiredZoom = minZoomLevels[markerType] ?? minVisibleZoom;
    return currentZoom >= requiredZoom;
  }

  /// Create a geographic-aware marker widget
  static Widget buildGeographicMarker({
    required MarkerType markerType,
    required double markerSize,
    required Color primaryColor,
    required IconData iconData,
    Color backgroundColor = Colors.white,
    double borderWidth = 2.0,
    bool showAccuracyCircle = false,
    double accuracyMeters = 10.0,
    VoidCallback? onTap,
  }) {
    final iconSize = calculateIconSize(markerSize);
    
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Accuracy circle (for location markers)
          if (showAccuracyCircle)
            Container(
              width: markerSize * 2, // Accuracy circle is larger
              height: markerSize * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.1),
                border: Border.all(
                  color: primaryColor.withOpacity(0.3),
                  width: 1.0,
                ),
              ),
            ),
          
          // Main marker
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: markerSize,
            height: markerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(
                color: primaryColor,
                width: borderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.3),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                iconData,
                size: iconSize,
                color: primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Calculate pixels per meter at given zoom level and latitude
  static double _calculatePixelsPerMeter(double zoom, double latitude) {
    // Web Mercator projection calculations
    // At zoom level z, there are 2^z tiles across the width of the world
    // Each tile is 256 pixels
    // The world width in pixels at zoom z is: 256 * 2^z
    
    final worldWidthPixels = 256.0 * pow(2, zoom);
    
    // The world width in meters at the equator is the circumference of Earth
    const earthCircumferenceMeters = 40075016.686; // meters
    
    // At the given latitude, the actual distance represented by a degree of longitude
    // is reduced by cos(latitude)
    final latitudeRadians = latitude * pi / 180;
    final metersPerPixelAtLatitude = (earthCircumferenceMeters * cos(latitudeRadians)) / worldWidthPixels;
    
    return 1.0 / metersPerPixelAtLatitude;
  }
}

/// Enum for different marker types with their coverage characteristics
enum MarkerType {
  emergency,
  medical,
  drinkingWater,
  accessibility,
  historical,
  userLocation,
  volunteer,
  organizer,
}

/// Extension to get display properties for marker types
extension MarkerTypeExtension on MarkerType {
  String get displayName {
    switch (this) {
      case MarkerType.emergency:
        return 'Emergency';
      case MarkerType.medical:
        return 'Medical';
      case MarkerType.drinkingWater:
        return 'Drinking Water';
      case MarkerType.accessibility:
        return 'Accessibility';
      case MarkerType.historical:
        return 'Historical';
      case MarkerType.userLocation:
        return 'User Location';
      case MarkerType.volunteer:
        return 'Volunteer';
      case MarkerType.organizer:
        return 'Organizer';
    }
  }

  IconData get defaultIcon {
    switch (this) {
      case MarkerType.emergency:
        return Icons.emergency;
      case MarkerType.medical:
        return Icons.local_hospital;
      case MarkerType.drinkingWater:
        return Icons.water_drop;
      case MarkerType.accessibility:
        return Icons.accessibility;
      case MarkerType.historical:
        return Icons.museum;
      case MarkerType.userLocation:
        return Icons.person_pin_circle;
      case MarkerType.volunteer:
        return Icons.volunteer_activism;
      case MarkerType.organizer:
        return Icons.admin_panel_settings;
    }
  }

  Color get defaultColor {
    switch (this) {
      case MarkerType.emergency:
        return const Color(0xFFE53E3E);
      case MarkerType.medical:
        return const Color(0xFF38A169);
      case MarkerType.drinkingWater:
        return const Color(0xFF3182CE);
      case MarkerType.accessibility:
        return const Color(0xFF805AD5);
      case MarkerType.historical:
        return const Color(0xFFD69E2E);
      case MarkerType.userLocation:
        return const Color(0xFF2B6CB0);
      case MarkerType.volunteer:
        return const Color(0xFF38A169);
      case MarkerType.organizer:
        return const Color(0xFFE53E3E);
    }
  }
}
