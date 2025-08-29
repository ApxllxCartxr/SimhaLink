import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/models/poi.dart';
import 'package:simha_link/config/app_colors.dart';
import 'package:simha_link/services/geographic_marker_service.dart' as geo;
import 'package:simha_link/services/marker_sizing_service.dart';
import 'package:simha_link/services/marker_permission_service.dart';

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

  /// Convert POI MarkerType to geo.MarkerType
  geo.MarkerType _convertPOITypeToGeoType(MarkerType poiType) {
    switch (poiType) {
      case MarkerType.emergency:
        return geo.MarkerType.emergency;
      case MarkerType.medical:
        return geo.MarkerType.medical;
      case MarkerType.drinkingWater:
        return geo.MarkerType.drinkingWater;
      case MarkerType.accessibility:
        return geo.MarkerType.accessibility;
      case MarkerType.historical:
        return geo.MarkerType.historical;
      default:
        return geo.MarkerType.userLocation; // Default fallback
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
    required List<UserLocation> emergencies,
    required List<UserLocation> nearbyVolunteers,
    required List<UserLocation> allVolunteers,
    required LocationData? currentLocation,
    required Function(UserLocation) onUserMarkerTap,
  }) {
    List<Marker> markers = [];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    
    // Role-based marker visibility
    if (userRole == 'Attendee') {
      markers.addAll(groupMembers
          .where((member) => 
              member.userId != currentUserId && 
              (member.userRole == 'Attendee' || member.userRole == null))
          .map((member) => _buildUserMarker(
              member, 
              AppColors.mapAttendee, 
              Icons.person_pin,
              onUserMarkerTap,
          )));
    } else if (userRole == 'Volunteer') {
      markers.addAll(nearbyVolunteers
          .map((volunteer) => _buildUserMarker(
              volunteer, 
              volunteer.userRole == 'Volunteer' ? AppColors.mapVolunteer : AppColors.mapOrganizer, 
              volunteer.userRole == 'Volunteer' ? Icons.local_hospital : Icons.admin_panel_settings,
              onUserMarkerTap,
          )));
      
      markers.addAll(emergencies.map((emergency) {
        final isAlreadyShown = nearbyVolunteers.any((volunteer) => 
            volunteer.userId == emergency.userId && emergency.isEmergency);
        
        if (isAlreadyShown) return null;
        
        return _buildEmergencyMarker(emergency, onUserMarkerTap);
      }).where((marker) => marker != null).cast<Marker>());
    } else if (userRole == 'Organizer') {
      markers.addAll(allVolunteers
          .map((volunteer) => _buildUserMarker(
              volunteer, 
              AppColors.mapVolunteer, 
              Icons.local_hospital,
              onUserMarkerTap,
          )));
      
      markers.addAll(groupMembers
          .where((member) => 
              member.userId != currentUserId && 
              member.userRole == 'Organizer')
          .map((organizer) => _buildUserMarker(
              organizer, 
              AppColors.mapOrganizer, 
              Icons.admin_panel_settings,
              onUserMarkerTap,
          )));
    }

    // Everyone sees their current location marker
    if (currentLocation != null && currentUserId != null) {
      markers.add(_buildCurrentLocationMarker(currentLocation));
    }

    return markers;
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
  
  /// Builds an emergency marker
  Marker _buildEmergencyMarker(UserLocation emergency, Function(UserLocation) onTap) {
    final markerPosition = LatLng(emergency.latitude, emergency.longitude);
    final currentZoom = mapController?.camera.zoom ?? 15.0;
    
    // Use standardized sizing service
    final markerSize = MarkerSizingService.getStandardMarkerSize(
      currentZoom: currentZoom,
      geoMarkerType: geo.MarkerType.emergency,
      useGeographicScaling: true,
    );
    final iconSize = MarkerSizingService.getIconSize(markerSize);
    final priority = MarkerSizingService.getMarkerPriority(geo.MarkerType.emergency);
    
    return Marker(
      point: LatLng(emergency.latitude, emergency.longitude),
      width: markerSize,
      height: markerSize,
      child: GestureDetector(
        onTap: () => onTap(emergency),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: Container(
            decoration: MarkerSizingService.createStandardMarkerDecoration(
              primaryColor: AppColors.mapEmergency,
              backgroundColor: AppColors.mapEmergency,
              priority: priority,
              isPulsing: true, // Emergency markers pulse
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
