import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/services/notification_service.dart';
import 'package:simha_link/services/auth_service.dart';

/// Manages emergency functionality including alerts and volunteer coordination
class EmergencyManager {
  StreamSubscription<QuerySnapshot>? _emergenciesSubscription;
  StreamSubscription<QuerySnapshot>? _volunteersSubscription;
  StreamSubscription<QuerySnapshot>? _organizersSubscription;
  
  List<UserLocation> emergencies = [];
  List<UserLocation> nearbyVolunteers = [];
  List<UserLocation> allVolunteers = [];
  
  final String? userRole;
  final String groupId;
  
  EmergencyManager({required this.userRole, required this.groupId});
  
  /// Starts listening to emergencies across all groups (for volunteers)
  void listenToEmergencies(VoidCallback onEmergenciesChanged) {
    if (userRole != 'Volunteer') return;
    
    debugPrint('🚨 Volunteer: Starting to listen for emergencies across all groups');
    
    _emergenciesSubscription = FirebaseFirestore.instance
        .collection('groups')
        .snapshots()
        .listen((groupSnapshot) async {
      await _updateEmergencyList();
      onEmergenciesChanged();
    });
  }
  
  /// Updates the list of emergencies from all groups
  Future<void> _updateEmergencyList() async {
    if (userRole != 'Volunteer') return;
    
    try {
      List<UserLocation> allEmergencies = [];
      
      final groupSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .get();
      
      for (final groupDoc in groupSnapshot.docs) {
        try {
          final locationsSnapshot = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupDoc.id)
              .collection('locations')
              .get();
          
          final groupEmergencies = locationsSnapshot.docs
              .map((doc) => UserLocation.fromMap(doc.data()))
              .where((location) => location.isEmergency == true)
              .toList();
          
          allEmergencies.addAll(groupEmergencies);
        } catch (e) {
          debugPrint('Error fetching emergencies from group ${groupDoc.id}: $e');
        }
      }
      
      final previousEmergencyCount = emergencies.length;
      emergencies = allEmergencies;
      
      if (allEmergencies.length != previousEmergencyCount) {
        debugPrint('🚨 Emergency count changed: $previousEmergencyCount → ${allEmergencies.length}');
        if (allEmergencies.length < previousEmergencyCount) {
          debugPrint('✅ Some emergencies were resolved');
        }
      }
      
      if (allEmergencies.isNotEmpty) {
        debugPrint('🚨 Volunteer sees ${allEmergencies.length} active emergencies');
        for (final emergency in allEmergencies) {
          debugPrint('   - Emergency: ${emergency.userName} (${emergency.userId})');
        }
      } else {
        debugPrint('✅ No active emergencies detected');
      }
    } catch (e) {
      debugPrint('Error updating emergency list: $e');
    }
  }
  
  /// Listens to nearby volunteers for volunteers
  void listenToNearbyVolunteers(LocationData? currentLocation, VoidCallback onVolunteersChanged) {
    if (userRole != 'Volunteer') return;
    
    debugPrint('👮 Volunteer: Listening for nearby volunteers and organizers');
    
    _volunteersSubscription = FirebaseFirestore.instance
        .collection('groups')
        .snapshots()
        .listen((groupSnapshot) async {
      await _updateNearbyVolunteers(currentLocation);
      onVolunteersChanged();
    });
  }
  
  /// Updates nearby volunteers list
  Future<void> _updateNearbyVolunteers(LocationData? currentLocation) async {
    if (userRole != 'Volunteer' || currentLocation == null) return;
    
    List<UserLocation> nearby = [];
    
    final groupSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .get();
    
    for (final groupDoc in groupSnapshot.docs) {
      try {
        final locationsSnapshot = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupDoc.id)
            .collection('locations')
            .get();
        
        final allUsers = locationsSnapshot.docs
            .map((doc) => UserLocation.fromMap(doc.data()))
            .toList();
        
        final staffUsers = allUsers.where((user) => 
          user.userRole == 'Volunteer' || user.userRole == 'Organizer'
        ).toList();
        
        for (final user in staffUsers) {
          final distance = _calculateDistance(
            currentLocation.latitude!,
            currentLocation.longitude!,
            user.latitude,
            user.longitude,
          );
          
          if (distance <= 2000 && user.userId != FirebaseAuth.instance.currentUser?.uid) {
            nearby.add(user);
          }
        }
      } catch (e) {
        debugPrint('Error fetching staff from group ${groupDoc.id}: $e');
      }
    }
    
    nearbyVolunteers = nearby;
    debugPrint('👮 Found ${nearby.length} nearby volunteers/organizers');
  }
  
  /// Listens to all volunteers for organizers
  void listenToAllVolunteers(VoidCallback onVolunteersChanged) {
    if (userRole != 'Organizer') return;
    
    debugPrint('👑 Organizer: Listening for all volunteers');
    
    _organizersSubscription = FirebaseFirestore.instance
        .collection('groups')
        .snapshots()
        .listen((groupSnapshot) async {
      await _updateAllVolunteers();
      onVolunteersChanged();
    });
  }
  
  /// Updates all volunteers list for organizers
  Future<void> _updateAllVolunteers() async {
    if (userRole != 'Organizer') return;
    
    List<UserLocation> volunteers = [];
    
    final groupSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .get();
    
    for (final groupDoc in groupSnapshot.docs) {
      try {
        final locationsSnapshot = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupDoc.id)
            .collection('locations')
            .get();
        
        final groupVolunteers = locationsSnapshot.docs
            .map((doc) => UserLocation.fromMap(doc.data()))
            .where((user) => user.userRole == 'Volunteer')
            .toList();
        
        volunteers.addAll(groupVolunteers);
      } catch (e) {
        debugPrint('Error fetching volunteers from group ${groupDoc.id}: $e');
      }
    }
    
    allVolunteers = volunteers;
    debugPrint('👑 Organizer sees ${volunteers.length} volunteers across all groups');
  }
  
  /// Toggles emergency status and sends notifications
  Future<void> toggleEmergency({
    required bool currentEmergencyStatus,
    required LocationData? currentLocation,
    required Function(bool) onEmergencyChanged,
    required BuildContext context,
  }) async {
    if (currentLocation == null) return;
    
    try {
      final newEmergencyStatus = !currentEmergencyStatus;
      onEmergencyChanged(newEmergencyStatus);
      
      debugPrint('🔄 Updating emergency status in database: $newEmergencyStatus');
      
      if (newEmergencyStatus && !currentEmergencyStatus) {
        // Emergency activated - send notification
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final emergencyUser = UserLocation(
            userId: user.uid,
            userName: AuthService.getUserDisplayName(user),
            latitude: currentLocation.latitude!,
            longitude: currentLocation.longitude!,
            isEmergency: true,
            lastUpdated: DateTime.now(),
            groupId: groupId,
          );

          await NotificationService.sendEmergencyNotification(
            groupId: groupId,
            emergencyUser: emergencyUser,
          );

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🚨 Emergency alert sent! Volunteers and group members have been notified.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      } else if (!newEmergencyStatus && currentEmergencyStatus) {
        // Emergency deactivated
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Emergency status turned off'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      onEmergencyChanged(currentEmergencyStatus); // Revert on error
      rethrow;
    }
  }
  
  /// Calculates distance between two points in meters
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
  
  /// Disposes all subscriptions
  void dispose() {
    _emergenciesSubscription?.cancel();
    _volunteersSubscription?.cancel();
    _organizersSubscription?.cancel();
  }
}
