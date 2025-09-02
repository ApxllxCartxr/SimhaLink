import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/services/auth_service.dart';

/// Manages location tracking and updates for the map screen
class LocationManager {
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  
  LocationData? currentLocation;
  final String groupId;
  String? userRole;
  bool isEmergency;
  
  LocationManager({
    required this.groupId,
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
  
  /// Starts listening to location changes
  void startLocationUpdates(Function(LocationData) onLocationUpdate) {
    _locationSubscription?.cancel();
    _locationSubscription = _location.onLocationChanged.listen(onLocationUpdate);
  }
  
  /// Updates user location in Firebase
  Future<void> updateUserLocationInFirebase(LocationData locationData) async {
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

      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('locations')
          .doc(user.uid)
          .set(location.toMap());
          
      debugPrint('✅ Location updated successfully in group $groupId - Emergency: $isEmergency');
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
  
  /// Disposes location subscription
  void dispose() {
    _locationSubscription?.cancel();
  }
}
