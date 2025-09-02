import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:simha_link/models/poi.dart' as poi_model;
import 'package:simha_link/services/geographic_marker_service.dart' as geo;

/// Service for standardizing marker sizes across the entire app
class MarkerSizingService {
  // Consistent base sizes for all markers
  static const double BASE_MARKER_SIZE = 40.0;
  static const double MIN_MARKER_SIZE = 24.0;
  static const double MAX_MARKER_SIZE = 60.0;
  
  // Icon sizes relative to marker size
  static const double ICON_SIZE_RATIO = 0.6;
  
  /// Get standardized marker size for any marker type
  static double getStandardMarkerSize({
    required double currentZoom,
    geo.MarkerType? geoMarkerType,
    poi_model.MarkerType? poiMarkerType,
    bool useGeographicScaling = true,
  }) {
    if (useGeographicScaling && geoMarkerType != null) {
      // Use geographic scaling for location-based markers
      return _calculateGeographicSize(currentZoom, geoMarkerType);
    } else {
      // Use zoom-based scaling for POI and user markers
      return _calculateZoomBasedSize(currentZoom);
    }
  }
  
  /// Get standardized icon size based on marker size
  static double getIconSize(double markerSize) {
    return (markerSize * ICON_SIZE_RATIO).clamp(12.0, 36.0);
  }
  
  /// Calculate geographic-based marker size
  static double _calculateGeographicSize(double zoom, geo.MarkerType markerType) {
    try {
      // Use a fixed position for calculation (won't affect size significantly)
      final testPosition = const LatLng(12.9716, 77.5946);
      
      return geo.GeographicMarkerManager.calculateGeographicMarkerSize(
        currentZoom: zoom,
        markerPosition: testPosition,
        markerType: markerType,
        minPixelSize: MIN_MARKER_SIZE,
        maxPixelSize: MAX_MARKER_SIZE,
      );
    } catch (e) {
      // Fallback to zoom-based sizing
      return _calculateZoomBasedSize(zoom);
    }
  }
  
  /// Calculate zoom-based marker size (for POIs and user markers)
  static double _calculateZoomBasedSize(double zoom) {
    // Consistent zoom-based scaling formula
    final double scaleFactor = ((zoom - 15.0) * 0.08) + 1.0;
    final double scaledSize = BASE_MARKER_SIZE * scaleFactor;
    
    return scaledSize.clamp(MIN_MARKER_SIZE, MAX_MARKER_SIZE);
  }
  
  /// Get visual priority for marker type (higher = more prominent)
  static int getMarkerPriority(dynamic markerType) {
    if (markerType is geo.MarkerType) {
      switch (markerType) {
        case geo.MarkerType.emergency:
          return 10; // Highest priority
        case geo.MarkerType.medical:
          return 8;
        case geo.MarkerType.volunteer:
        case geo.MarkerType.organizer:
          return 7;
        case geo.MarkerType.userLocation:
          return 6;
        default:
          return 5;
      }
    } else if (markerType is poi_model.MarkerType) {
      switch (markerType) {
        case poi_model.MarkerType.emergency:
          return 10;
        case poi_model.MarkerType.medical:
          return 8;
        case poi_model.MarkerType.security:
          return 7;
        default:
          return 5;
      }
    }
    return 5; // Default priority
  }
  
  /// Get marker elevation (shadow/prominence) based on priority
  static double getMarkerElevation(int priority) {
    switch (priority) {
      case 10: return 8.0; // Emergency - highest elevation
      case 8:  return 6.0; // Medical - high elevation
      case 7:  return 4.0; // Staff - medium elevation
      default: return 2.0; // Others - low elevation
    }
  }
  
  /// Get marker border width based on priority
  static double getBorderWidth(int priority) {
    switch (priority) {
      case 10: return 3.0; // Emergency - thick border
      case 8:  return 2.5; // Medical - medium-thick border
      case 7:  return 2.0; // Staff - medium border
      default: return 1.5; // Others - thin border
    }
  }
  
  /// Create standardized marker decoration
  static BoxDecoration createStandardMarkerDecoration({
    required Color primaryColor,
    required Color backgroundColor,
    required int priority,
    bool isSelected = false,
    bool isPulsing = false,
  }) {
    final borderWidth = getBorderWidth(priority);
    final elevation = getMarkerElevation(priority);
    
    return BoxDecoration(
      color: backgroundColor,
      shape: BoxShape.circle,
      border: Border.all(
        color: isSelected ? Colors.yellow : primaryColor,
        width: isSelected ? borderWidth + 1.0 : borderWidth,
      ),
      boxShadow: [
        BoxShadow(
          color: primaryColor.withOpacity(isPulsing ? 0.6 : 0.3),
          blurRadius: elevation,
          spreadRadius: isPulsing ? 2.0 : 1.0,
          offset: Offset(0, elevation / 2),
        ),
        if (isSelected)
          BoxShadow(
            color: Colors.yellow.withOpacity(0.4),
            blurRadius: 8.0,
            spreadRadius: 3.0,
          ),
      ],
    );
  }
}
