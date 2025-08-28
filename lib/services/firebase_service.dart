import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/user_location.dart';
import 'package:simha_link/models/poi.dart';
import 'package:simha_link/models/user_profile.dart';

class LocationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Updates user location in Firestore
  static Future<void> updateUserLocation({
    required String groupId,
    required double latitude,
    required double longitude,
    bool isEmergency = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('locations')
          .doc(user.uid)
          .set({
        'userId': user.uid,
        'userName': user.displayName ?? 'Unknown User',
        'latitude': latitude,
        'longitude': longitude,
        'isEmergency': isEmergency,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update location: ${e.toString()}');
    }
  }

  /// Stream of group member locations
  static Stream<List<UserLocation>> getGroupLocations(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('locations')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return UserLocation.fromMap(doc.data());
      }).toList();
    });
  }

  /// Stream of emergency locations only
  static Stream<List<UserLocation>> getEmergencyLocations(String groupId) {
    return _firestore
        .collection('groups')
        .doc(groupId)
        .collection('locations')
        .where('isEmergency', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return UserLocation.fromMap(doc.data());
      }).toList();
    });
  }

  /// Get nearby group members within radius (in meters)
  static Future<List<UserLocation>> getNearbyMembers({
    required String groupId,
    required double centerLat,
    required double centerLng,
    required double radiusInMeters,
  }) async {
    // For simplicity, get all locations and filter client-side
    // In production, consider using GeoFlutterFire for geoqueries
    final snapshot = await _firestore
        .collection('groups')
        .doc(groupId)
        .collection('locations')
        .get();

    final allLocations = snapshot.docs
        .map((doc) => UserLocation.fromMap(doc.data()))
        .toList();

    // Filter by distance
    return allLocations.where((location) {
      final distance = _calculateDistance(
        centerLat,
        centerLng,
        location.latitude,
        location.longitude,
      );
      return distance <= radiusInMeters;
    }).toList();
  }

  /// Calculate distance between two points in meters
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
}

class POIService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Create a new POI
  static Future<void> createPOI({
    required String groupId,
    required String name,
    required String type,
    required String description,
    required double latitude,
    required double longitude,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      await _firestore.collection('pois').add({
        'groupId': groupId,
        'name': name,
        'type': type,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to create POI: ${e.toString()}');
    }
  }

  /// Stream of POIs for a group
  static Stream<List<POI>> getGroupPOIs(String groupId) {
    return _firestore
        .collection('pois')
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return POI.fromMap(data);
      }).toList();
    });
  }

  /// Delete a POI (only if user created it or is organizer)
  static Future<void> deletePOI(String poiId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    try {
      await _firestore.collection('pois').doc(poiId).delete();
    } catch (e) {
      throw Exception('Failed to delete POI: ${e.toString()}');
    }
  }

  /// Get POIs by type
  static Stream<List<POI>> getPOIsByType(String groupId, String type) {
    return _firestore
        .collection('pois')
        .where('groupId', isEqualTo: groupId)
        .where('type', isEqualTo: type)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return POI.fromMap(data);
      }).toList();
    });
  }
}

class UserService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get user profile
  static Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return UserProfile.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get user profile: ${e.toString()}');
    }
  }

  /// Create or update user profile
  static Future<void> createOrUpdateUserProfile(UserProfile profile) async {
    try {
      await _firestore
          .collection('users')
          .doc(profile.uid)
          .set(profile.toMap(), SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update user profile: ${e.toString()}');
    }
  }

  /// Update user online status
  static Future<void> updateOnlineStatus(String userId, bool isOnline) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update online status: ${e.toString()}');
    }
  }

  /// Stream of user profile
  static Stream<UserProfile?> getUserProfileStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return UserProfile.fromMap(doc.data()!);
      }
      return null;
    });
  }

  /// Get group members profiles
  static Future<List<UserProfile>> getGroupMembersProfiles(
      List<String> memberIds) async {
    if (memberIds.isEmpty) return [];

    try {
      final List<UserProfile> profiles = [];
      
      // Firestore 'in' query limit is 10, so batch the requests
      for (int i = 0; i < memberIds.length; i += 10) {
        final batch = memberIds.skip(i).take(10).toList();
        final querySnapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        profiles.addAll(
          querySnapshot.docs.map((doc) => UserProfile.fromMap(doc.data())),
        );
      }

      return profiles;
    } catch (e) {
      throw Exception('Failed to get group members profiles: ${e.toString()}');
    }
  }
}
