import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/services/auth_service.dart';
import 'package:simha_link/services/firebase_optimization_service.dart';

/// Manages location tracking and updates for the map screen
class LocationManager {
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  
  // Optimization: Add debouncing for location updates
  Timer? _debounceTimer;
  LocationData? _pendingLocationUpdate;
  
  LocationData? currentLocation;
  final String? groupId; // Made nullable for solo mode
  String? userRole;
  bool isEmergency;
  
  LocationManager({
    this.groupId, // Can be null for solo mode
    this.userRole,
    this.isEmergency = false,
  });
  
  /// Sets up location permissions and background tracking
  Future<bool> setupLocationTracking() async {
    try {
      final permissionStatus = await _location.requestPermission();
      if (permissionStatus != PermissionStatus.granted) {
        return false;
      }
      
      await _location.enableBackgroundMode(enable: true);
      return true;
    } catch (e) {
      debugPrint('Error setting up location: $e');
      return false;
    }
  }
  
  /// Starts listening to location changes with emergency-aware intervals
  void startLocationUpdates(Function(LocationData) onLocationUpdate) {
    _locationSubscription?.cancel();
    
    // Configure location settings based on emergency status
    _location.changeSettings(
      accuracy: isEmergency ? LocationAccuracy.high : LocationAccuracy.balanced,
      interval: isEmergency ? 3000 : 10000, // 3s for emergency, 10s normal
      distanceFilter: isEmergency ? 2 : 10, // 2m for emergency, 10m normal
    );
    
    _locationSubscription = _location.onLocationChanged.listen(onLocationUpdate);
  }
  
  /// Update emergency status and reconfigure location tracking
  void updateEmergencyStatus(bool newEmergencyStatus) {
    if (isEmergency != newEmergencyStatus) {
      isEmergency = newEmergencyStatus;
      
      // Reconfigure location tracking with new settings
      if (_locationSubscription != null) {
        _location.changeSettings(
          accuracy: isEmergency ? LocationAccuracy.high : LocationAccuracy.balanced,
          interval: isEmergency ? 3000 : 10000,
          distanceFilter: isEmergency ? 2 : 10,
        );
        
        debugPrint('📍 Location tracking reconfigured for emergency: $isEmergency');
      }
    }
  }
  
  /// Updates user location in Firebase with debouncing optimization
  Future<void> updateUserLocationInFirebase(LocationData locationData) async {
    // Store pending location
    _pendingLocationUpdate = locationData;
    
    // Cancel existing timer
    _debounceTimer?.cancel();
    
    // For emergencies, update immediately - no debouncing
    if (isEmergency) {
      await _performLocationUpdate(locationData);
      return;
    }
    
    // For normal updates, debounce for 3 seconds
    _debounceTimer = Timer(const Duration(seconds: 3), () async {
      if (_pendingLocationUpdate != null) {
        await _performLocationUpdate(_pendingLocationUpdate!);
        _pendingLocationUpdate = null;
      }
    });
  }
  
  /// Performs the actual location update to Firebase
  Future<void> _performLocationUpdate(LocationData locationData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final location = UserLocation(
        userId: user.uid,
        userName: AuthService.getUserDisplayName(user),
        latitude: locationData.latitude ?? 0,
        longitude: locationData.longitude ?? 0,
        isEmergency: isEmergency,
        lastUpdated: DateTime.now(),
        userRole: userRole,
        groupId: groupId,
      );

      debugPrint('📍 Updating user location - Emergency: $isEmergency (User: ${location.userName})');

      if (groupId != null) {
        // Group mode - use optimization service for batching
        final docRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId!)
            .collection('locations')
            .doc(user.uid);
            
        await FirebaseOptimizationService.batchWrite(
          isEmergency ? 'location_emergency' : 'location_normal',
          docRef,
          location.toMap(),
        );
            
        debugPrint('✅ Location updated successfully in group $groupId - Emergency: $isEmergency');
      } else {
        // Solo mode - use optimization service for batching
        final docRef = FirebaseFirestore.instance
            .collection('solo_user_locations')
            .doc(user.uid);
            
        await FirebaseOptimizationService.batchWrite(
          isEmergency ? 'solo_location_emergency' : 'solo_location_normal',
          docRef,
          location.toMap(),
        );
            
        debugPrint('✅ Location updated successfully in solo mode - Emergency: $isEmergency');
      }
    } catch (e) {
      debugPrint('Error updating user location: $e');
      rethrow;
    }
  }
  
  /// Gets current location once
  Future<LocationData?> getCurrentLocation() async {
    try {
      return await _location.getLocation();
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }
  
  /// Disposes location subscription and timers
  void dispose() {
    _locationSubscription?.cancel();
    _debounceTimer?.cancel();
  }
}
