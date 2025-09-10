import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/models/poi.dart';
import 'package:simha_link/models/emergency.dart';
import 'package:simha_link/config/app_colors.dart';
import 'package:simha_link/services/geographic_marker_service.dart' as geo;
import 'package:simha_link/services/marker_sizing_service.dart';

/// Manages marker creation and display based on user roles
class MarkerManager {
  final String? userRole;
  final bool isMapReady;
  MapController? mapController;
  double currentZoom = 15.0;
  
  MarkerManager({
    required this.userRole,
    required this.isMapReady,
    this.mapController,
  });
  
  /// Updates the map controller reference
  void updateMapController(MapController controller) {
    mapController = controller;
  }
  
  /// Calculate zoom-responsive marker size based on current map zoom level
  double getZoomResponsiveSize({
    double baseSize = 60, 
    double minSize = 30, 
    double maxSize = 80
  }) {
    if (!isMapReady) return baseSize;
    
    try {
      final zoom = mapController?.camera.zoom ?? currentZoom;
      currentZoom = zoom;
      
      final double scaleFactor = ((zoom - 15) * 0.1) + 1.0;
      final double scaledSize = baseSize * scaleFactor;
      
      return scaledSize.clamp(minSize, maxSize);
    } catch (e) {
      if (currentZoom != 15.0) {
        final double scaleFactor = ((currentZoom - 15) * 0.1) + 1.0;
        final double scaledSize = baseSize * scaleFactor;
        return scaledSize.clamp(minSize, maxSize);
      }
      return baseSize;
    }
  }
  
  /// Calculate geographic-consistent marker size based on real-world coverage
  double getGeographicMarkerSize({
    required LatLng markerPosition,
    required geo.MarkerType geoMarkerType,
    double? customCoverageRadiusMeters,
    double minPixelSize = 20.0,
    double maxPixelSize = 120.0,
  }) {
    if (!isMapReady) return 40.0; // Default fallback
    
    try {
      final zoom = mapController?.camera.zoom ?? currentZoom;
      return geo.GeographicMarkerManager.calculateGeographicMarkerSize(
        currentZoom: zoom,
        markerPosition: markerPosition,
        markerType: geoMarkerType,
        customCoverageRadiusMeters: customCoverageRadiusMeters,
        minPixelSize: minPixelSize,
        maxPixelSize: maxPixelSize,
      );
    } catch (e) {
      return 40.0; // Fallback size
    }
  }
  
  /// Calculate zoom-responsive icon size
  double getZoomResponsiveIconSize({
    double baseSize = 32, 
    double minSize = 20, 
    double maxSize = 40
  }) {
    if (!isMapReady) return baseSize;
    
    try {
      final zoom = mapController?.camera.zoom ?? currentZoom;
      currentZoom = zoom;
      final double scaleFactor = ((zoom - 15) * 0.05) + 1.0;
      final double scaledSize = baseSize * scaleFactor;
      return scaledSize.clamp(minSize, maxSize);
    } catch (e) {
      if (currentZoom != 15.0) {
        final double scaleFactor = ((currentZoom - 15) * 0.05) + 1.0;
        final double scaledSize = baseSize * scaleFactor;
        return scaledSize.clamp(minSize, maxSize);
      }
      return baseSize;
    }
  }
  
  /// Builds markers based on user role and available data
  List<Marker> buildMarkers({
    required List<UserLocation> groupMembers,
    required List<Emergency> activeEmergencies, // Changed from UserLocation emergencies
    required List<UserLocation> nearbyVolunteers,
    required List<UserLocation> allVolunteers,
    required LocationData? currentLocation,
    required Function(UserLocation) onUserMarkerTap,
    Function(UserLocation)? onUserMarkerLongPress,
  }) {
    List<Marker> markers = [];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Optimization: Limit markers based on zoom level to improve performance
    final maxMarkers = _getMaxMarkersForZoom();
    
    // Get list of user IDs who have active emergencies to avoid duplicate markers
    final activeEmergencyUserIds = activeEmergencies
        .where((emergency) => emergency.status != EmergencyStatus.resolved)
        .map((emergency) => emergency.attendeeId)
        .toSet();
    
    // Filter group members - exclude those with active emergencies
    final filteredGroupMembers = groupMembers.where((member) {
      // Don't show user markers for attendees who have active emergencies
      return !activeEmergencyUserIds.contains(member.userId);
    }).toList();
    
    // Sort by distance if current location is available for better prioritization
    if (currentLocation != null) {
      _sortByDistance(filteredGroupMembers, currentLocation);
      _sortByDistance(nearbyVolunteers, currentLocation);
      _sortByDistance(allVolunteers, currentLocation);
    }
    
    // Role-based marker visibility (using filtered and limited members)
    if (userRole == 'Attendee') {
      final attendeeMarkers = filteredGroupMembers
          .where((member) => 
              member.userId != currentUserId && 
              (member.userRole == 'Attendee' || member.userRole == null))
          .take(maxMarkers) // Limit markers
          .map((member) => _buildUserMarker(
              member, 
              AppColors.mapAttendee, 
              Icons.person_pin,
              onUserMarkerTap,
              onUserMarkerLongPress,
          ));
      markers.addAll(attendeeMarkers);
    } else if (userRole == 'Volunteer') {
      // Volunteers see nearby volunteers/organizers (filtered to exclude those with emergencies)
      final volunteerMarkers = nearbyVolunteers
          .where((volunteer) => !activeEmergencyUserIds.contains(volunteer.userId))
          .take(maxMarkers) // Limit markers
          .map((volunteer) => _buildUserMarker(
              volunteer, 
              volunteer.userRole == 'Volunteer' ? AppColors.mapVolunteer : AppColors.mapOrganizer, 
              volunteer.userRole == 'Volunteer' ? Icons.local_hospital : Icons.admin_panel_settings,
              onUserMarkerTap,
              onUserMarkerLongPress,
          ));
      markers.addAll(volunteerMarkers);
    } else if (userRole == 'Organizer') {
      // Organizers see all volunteers (filtered to exclude those with emergencies)
      final organizerMarkers = allVolunteers
          .where((volunteer) => !activeEmergencyUserIds.contains(volunteer.userId))
          .take(maxMarkers) // Limit markers
          .map((volunteer) => _buildUserMarker(
              volunteer, 
              AppColors.mapVolunteer, 
              Icons.local_hospital,
              onUserMarkerTap,
              onUserMarkerLongPress,
          ));
      markers.addAll(organizerMarkers);
      
      // Organizers also see other organizers in their group (filtered)
      markers.addAll(filteredGroupMembers
          .where((member) => 
              member.userId != currentUserId && 
              member.userRole == 'Organizer')
          .take(maxMarkers ~/ 2) // Limit organizer markers too
          .map((organizer) => _buildUserMarker(
              organizer, 
              AppColors.mapOrganizer, 
              Icons.admin_panel_settings,
              onUserMarkerTap,
              onUserMarkerLongPress,
          )));
    }

    // Current user marker (only if no active emergency)
    if (currentLocation != null && currentUserId != null && !activeEmergencyUserIds.contains(currentUserId)) {
      markers.add(_buildCurrentLocationMarker(currentLocation));
    }

    return markers;
  }
  
  /// Optimization: Get maximum markers based on zoom level
  int _getMaxMarkersForZoom() {
    try {
      final zoom = mapController?.camera.zoom ?? currentZoom;
      if (zoom >= 16) return 100; // High zoom - show more markers
      if (zoom >= 14) return 50;  // Medium zoom
      if (zoom >= 12) return 25;  // Low zoom
      return 10; // Very low zoom - show only closest markers
    } catch (e) {
      return 50; // Fallback
    }
  }
  
  /// Optimization: Sort locations by distance for better prioritization
  void _sortByDistance(List<UserLocation> locations, LocationData currentLocation) {
    try {
      locations.sort((a, b) {
        final distanceA = _calculateDistance(
          currentLocation.latitude!, 
          currentLocation.longitude!, 
          a.latitude, 
          a.longitude
        );
        final distanceB = _calculateDistance(
          currentLocation.latitude!, 
          currentLocation.longitude!, 
          b.latitude, 
          b.longitude
        );
        return distanceA.compareTo(distanceB);
      });
    } catch (e) {
      // If sorting fails, keep original order
    }
  }
  
  /// Helper to calculate distance between two points
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) + 
              math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * 
              math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }
  
  /// Builds POI markers based on user role
  List<Marker> buildPOIMarkers({
    required List<POI> pois,
    required Function(POI) onPOITap,
    Function(POI)? onPOILongPress,
  }) {
    List<POI> visiblePOIs = [];
    
    if (userRole == 'Attendee') {
      visiblePOIs = pois.where((poi) => 
          poi.type == MarkerType.drinkingWater ||
          poi.type == MarkerType.restroom ||
          poi.type == MarkerType.medical ||
          poi.type == MarkerType.historical ||
          poi.type == MarkerType.accessibility ||
          poi.type == MarkerType.information ||
          poi.type == MarkerType.food ||
          poi.type == MarkerType.parking
      ).toList();
    } else if (userRole == 'Volunteer' || userRole == 'Organizer') {
      visiblePOIs = pois;
    } else {
      visiblePOIs = pois.where((poi) => 
          poi.type == MarkerType.information ||
          poi.type == MarkerType.drinkingWater ||
          poi.type == MarkerType.restroom
      ).toList();
    }
    
    return visiblePOIs.map((poi) => _buildPOIMarker(poi, onPOITap, onPOILongPress)).toList();
  }
  
  /// Builds a user marker
  Marker _buildUserMarker(
    UserLocation user, 
    Color color, 
    IconData icon,
    Function(UserLocation) onTap,
    [Function(UserLocation)? onLongPress]
  ) {
    final markerPosition = LatLng(user.latitude, user.longitude);
    final geoMarkerType = user.userRole == 'Organizer' ? geo.MarkerType.organizer : geo.MarkerType.volunteer;
    final markerSize = getGeographicMarkerSize(
      markerPosition: markerPosition,
      geoMarkerType: geoMarkerType,
      minPixelSize: 30.0,
      maxPixelSize: 80.0,
    );
    final iconSize = geo.GeographicMarkerManager.calculateIconSize(markerSize);
    final emergencySize = (iconSize * 0.5).clamp(12.0, 18.0);
    
    return Marker(
      point: LatLng(user.latitude, user.longitude),
      width: markerSize,
      height: markerSize,
      child: GestureDetector(
        onTap: () => onTap(user),
        onLongPress: onLongPress != null ? () => onLongPress(user) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: color, size: iconSize),
              if (user.isEmergency)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: emergencySize,
                    height: emergencySize,
                    decoration: BoxDecoration(
                      color: AppColors.mapEmergency,
                      borderRadius: BorderRadius.circular(emergencySize / 2),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Icon(
                      Icons.warning,
                      color: Colors.white,
                      size: emergencySize * 0.6,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Builds the current location marker
  Marker _buildCurrentLocationMarker(LocationData currentLocation) {
    final markerPosition = LatLng(currentLocation.latitude!, currentLocation.longitude!);
    final currentZoom = mapController?.camera.zoom ?? 15.0;
    
    // Use standardized sizing service
    final markerSize = MarkerSizingService.getStandardMarkerSize(
      currentZoom: currentZoom,
      geoMarkerType: geo.MarkerType.userLocation,
      useGeographicScaling: true,
    );
    final iconSize = MarkerSizingService.getIconSize(markerSize);
    final priority = MarkerSizingService.getMarkerPriority(geo.MarkerType.userLocation);
    
    return Marker(
      point: markerPosition,
      width: markerSize,
      height: markerSize,
      child: Container(
        decoration: MarkerSizingService.createStandardMarkerDecoration(
          primaryColor: AppColors.mapCurrentUser,
          backgroundColor: AppColors.mapCurrentUser,
          priority: priority,
        ),
        child: Icon(
          Icons.my_location,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }
  
  /// Builds a POI marker
  Marker _buildPOIMarker(POI poi, Function(POI) onTap, [Function(POI)? onLongPress]) {
    final currentZoom = mapController?.camera.zoom ?? 15.0;
    
    // Use standardized sizing service for POI markers
    final markerSize = MarkerSizingService.getStandardMarkerSize(
      currentZoom: currentZoom,
      poiMarkerType: poi.type,
      useGeographicScaling: false, // POIs use zoom-based scaling
    );
    final iconSize = MarkerSizingService.getIconSize(markerSize);
    final priority = MarkerSizingService.getMarkerPriority(poi.type);
    
    return Marker(
      point: LatLng(poi.latitude, poi.longitude),
      width: markerSize,
      height: markerSize,
      child: GestureDetector(
        onTap: () => onTap(poi),
        onLongPress: onLongPress != null ? () => onLongPress(poi) : null,
        child: Container(
          decoration: MarkerSizingService.createStandardMarkerDecoration(
            primaryColor: _getPOIBorderColor(poi.type),
            backgroundColor: _getPOIBackgroundColor(poi.type),
            priority: priority,
          ),
          child: Center(
            child: Icon(
              poi.type.iconData,
              size: iconSize,
              color: _getPOIIconColor(poi.type),
            ),
          ),
        ),
      ),
    );
  }
  
  /// Gets POI background color
  Color _getPOIBackgroundColor(MarkerType type) {
    switch (type) {
      case MarkerType.emergency:
        return AppColors.mapEmergency;
      case MarkerType.medical:
      case MarkerType.security:
      case MarkerType.drinkingWater:
      default:
        return Colors.white;
    }
  }

  /// Gets POI icon color
  Color _getPOIIconColor(MarkerType type) {
    switch (type) {
      case MarkerType.emergency:
        return Colors.white;
      case MarkerType.medical:
        return Colors.green.shade700;
      case MarkerType.drinkingWater:
        return Colors.blue.shade700;
      case MarkerType.accessibility:
        return Colors.blue.shade600;
      case MarkerType.historical:
        return Colors.brown.shade600;
      case MarkerType.restroom:
        return Colors.teal.shade600;
      case MarkerType.food:
        return Colors.orange.shade700;
      case MarkerType.parking:
        return Colors.indigo.shade700;
      case MarkerType.security:
        return Colors.red.shade700;
      case MarkerType.information:
        return Colors.blue.shade800;
    }
  }
  
  /// Gets POI border color
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
}
