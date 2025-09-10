import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/services/auth_service.dart';
// import 'package:simha_link/services/firebase_optimization_service.dart'; // Temporarily commented out for direct writes

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
      print('🔧 DEBUG LocationManager: Setting up location tracking...');
      
      // Check if location service is enabled
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        print('🔧 DEBUG LocationManager: Location service not enabled, requesting...');
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          print('❌ DEBUG LocationManager: Location service still not enabled');
          return false;
        }
      }
      print('✅ DEBUG LocationManager: Location service is enabled');
      
      // Check permission status
      PermissionStatus permissionGranted = await _location.hasPermission();
      print('🔧 DEBUG LocationManager: Current permission status: $permissionGranted');
      
      if (permissionGranted == PermissionStatus.denied) {
        print('🔧 DEBUG LocationManager: Permission denied, requesting...');
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          print('❌ DEBUG LocationManager: Permission not granted: $permissionGranted');
          return false;
        }
      }
      print('✅ DEBUG LocationManager: Location permission granted');
      
      // Try to enable background mode, but don't fail if it's denied
      try {
        print('🔧 DEBUG LocationManager: Attempting to enable background mode...');
        await _location.enableBackgroundMode(enable: true);
        print('✅ DEBUG LocationManager: Background mode enabled');
      } catch (e) {
        print('⚠️ DEBUG LocationManager: Background mode denied, continuing with foreground tracking: $e');
        // Continue anyway - foreground tracking is sufficient for now
      }
      
      print('✅ DEBUG LocationManager: Location tracking setup completed successfully');
      return true;
    } catch (e) {
      print('❌ DEBUG LocationManager: Error setting up location: $e');
      debugPrint('Error setting up location: $e');
      return false;
    }
  }
  
  /// Starts listening to location changes with emergency-aware intervals
  void startLocationUpdates(Function(LocationData) onLocationUpdate) {
    print('🔧 DEBUG LocationManager: Starting location updates...');
    _locationSubscription?.cancel();
    
    // Configure location settings based on emergency status
    print('🔧 DEBUG LocationManager: Configuring location settings - isEmergency: $isEmergency');
    _location.changeSettings(
      accuracy: isEmergency ? LocationAccuracy.high : LocationAccuracy.balanced,
      interval: isEmergency ? 3000 : 10000, // 3s for emergency, 10s normal
      distanceFilter: isEmergency ? 2 : 10, // 2m for emergency, 10m normal
    );
    
    print('🔧 DEBUG LocationManager: Setting up location stream listener...');
    _locationSubscription = _location.onLocationChanged.listen(
      (locationData) {
        print('📍 DEBUG LocationManager: Location changed! lat=${locationData.latitude}, lng=${locationData.longitude}');
        onLocationUpdate(locationData);
      },
      onError: (error) {
        print('❌ DEBUG LocationManager: Location stream error: $error');
      },
      onDone: () {
        print('🔚 DEBUG LocationManager: Location stream completed');
      },
    );
    print('✅ DEBUG LocationManager: Location updates started successfully');
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
    print('🔧 DEBUG LocationManager: updateUserLocationInFirebase called - lat: ${locationData.latitude}, lng: ${locationData.longitude}, isEmergency: $isEmergency');
    
    // Store pending location
    _pendingLocationUpdate = locationData;
    
    // Cancel existing timer
    _debounceTimer?.cancel();
    print('🔧 DEBUG LocationManager: Debounce timer cancelled');
    
    // For emergencies, update immediately - no debouncing
    if (isEmergency) {
      print('🚨 DEBUG LocationManager: Emergency mode - updating immediately');
      await _performLocationUpdate(locationData);
      return;
    }
    
    // REDUCED: For normal updates, debounce for 1 second only (was 3 seconds)
    // This ensures faster updates for testing distance-based filtering
    print('⏱️ DEBUG LocationManager: Starting 1-second debounce timer...');
    _debounceTimer = Timer(const Duration(seconds: 1), () async {
      print('⏰ DEBUG LocationManager: Debounce timer fired! Executing update...');
      if (_pendingLocationUpdate != null) {
        await _performLocationUpdate(_pendingLocationUpdate!);
        _pendingLocationUpdate = null;
        print('✅ DEBUG LocationManager: Debounced update completed');
      } else {
        print('⚠️ DEBUG LocationManager: No pending location update');
      }
    });
    print('✅ DEBUG LocationManager: Debounce timer set up');
  }
  
  /// Performs the actual location update to Firebase
  Future<void> _performLocationUpdate(LocationData locationData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ DEBUG LocationManager: No authenticated user');
      return;
    }

    try {
      print('🔍 DEBUG LocationManager: Updating location for user: ${user.uid}');
      print('🔍 DEBUG LocationManager: Group ID: $groupId');
      print('🔍 DEBUG LocationManager: User role: $userRole');
      print('🔍 DEBUG LocationManager: Location: ${locationData.latitude}, ${locationData.longitude}');
      print('🔍 DEBUG LocationManager: Is emergency: $isEmergency');

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

      print('🔍 DEBUG LocationManager: Created UserLocation object: ${location.toMap()}');

      debugPrint('📍 Updating user location - Emergency: $isEmergency (User: ${location.userName})');

      if (groupId != null) {
        // Group mode - use optimization service for batching
        final docRef = FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId!)
            .collection('locations')
            .doc(user.uid);
            
        final docPath = 'groups/$groupId/locations/${user.uid}';
        print('🔍 DEBUG LocationManager: Writing to Firestore path: $docPath');
        
        // TEMPORARY: Direct write for testing distance-based filtering
        // This bypasses FirebaseOptimizationService batching to ensure immediate updates
        await docRef.set(location.toMap());
        
        // Original batched approach (commented out for testing):
        // await FirebaseOptimizationService.batchWrite(
        //   isEmergency ? 'location_emergency' : 'location_normal',
        //   docRef,
        //   location.toMap(),
        // );
            
        print('✅ DEBUG LocationManager: Location successfully written to Firestore directly');
        debugPrint('✅ Location updated successfully in group $groupId - Emergency: $isEmergency');
      } else {
        // Solo mode - use optimization service for batching
        final docRef = FirebaseFirestore.instance
            .collection('solo_user_locations')
            .doc(user.uid);
            
        print('🔍 DEBUG LocationManager: Writing to solo mode path: solo_user_locations/${user.uid}');
        
        // TEMPORARY: Direct write for testing
        await docRef.set(location.toMap());
        
        // Original batched approach (commented out for testing):
        // await FirebaseOptimizationService.batchWrite(
        //   isEmergency ? 'solo_location_emergency' : 'solo_location_normal',
        //   docRef,
        //   location.toMap(),
        // );
            
        print('✅ DEBUG LocationManager: Location successfully written to solo mode directly');
        debugPrint('✅ Location updated successfully in solo mode - Emergency: $isEmergency');
      }
    } catch (e, stackTrace) {
      print('❌ DEBUG LocationManager: Error updating location: $e');
      print('❌ DEBUG LocationManager: Stack trace: $stackTrace');
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
