import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:simha_link/models/emergency.dart';
import 'package:simha_link/core/utils/app_logger.dart';

/// Service for managing emergency database operations using ONLY Emergency objects
class EmergencyDatabaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final String _collection = 'emergencies';

  /// Create emergency with duplicate prevention - ONE EMERGENCY PER USER
  static Future<Emergency> createEmergencyWithState({
    required String attendeeId,
    required String attendeeName,
    required String groupId,
    required LatLng location,
    String? message,
  }) async {
    try {
      // ENFORCE ONE EMERGENCY PER USER: Check if user already has an active emergency
      final existingEmergency = await _firestore
          .collection(_collection)
          .where('attendeeId', isEqualTo: attendeeId)
          .where('status', whereIn: [
            EmergencyStatus.unverified.name,
            EmergencyStatus.accepted.name,
            EmergencyStatus.inProgress.name,
            EmergencyStatus.verified.name,
            EmergencyStatus.escalated.name,
          ])
          .limit(1)
          .get();
      
      if (existingEmergency.docs.isNotEmpty) {
        // Return existing emergency instead of creating a new one
        final existingDoc = existingEmergency.docs.first;
        AppLogger.logWarning('User $attendeeId already has active emergency: ${existingDoc.id}');
        return Emergency.fromFirestore(existingDoc);
      }

      final emergencyId = _firestore.collection(_collection).doc().id;
      final now = DateTime.now();

      // Create emergency document
      final emergency = Emergency(
        emergencyId: emergencyId,
        attendeeId: attendeeId,
        attendeeName: attendeeName,
        groupId: groupId,
        location: location,
        status: EmergencyStatus.unverified, // NEW: Start as unverified
        message: message,
        createdAt: now,
        updatedAt: now,
        responses: {},
        resolvedBy: const EmergencyResolution(attendee: false, hasVolunteerCompleted: false),
      );

      // Use batch write for atomic operation
      final batch = _firestore.batch();

      // Create emergency document
      batch.set(
        _firestore.collection(_collection).doc(emergencyId),
        emergency.toFirestore(),
      );

      // Update user location with emergency state
      batch.set(
        _firestore
            .collection('groups')
            .doc(groupId)
            .collection('locations')
            .doc(attendeeId),
        {
          'userId': attendeeId,
          'userName': attendeeName,
          'latitude': location.latitude,
          'longitude': location.longitude,
          'isEmergency': true,
          'emergencyId': emergencyId,
          'lastUpdated': FieldValue.serverTimestamp(),
          'userRole': 'Attendee',
          'groupId': groupId,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      AppLogger.logInfo('Emergency created with duplicate prevention: $emergencyId');
      return emergency;
    } catch (e) {
      AppLogger.logError('Error creating emergency with state', e);
      rethrow;
    }
  }

  /// Get user's active emergency (for duplicate prevention)
  static Future<Emergency?> getUserActiveEmergency(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('attendeeId', isEqualTo: userId)
          .where('status', whereIn: [
            EmergencyStatus.unverified.name,
            EmergencyStatus.accepted.name,
            EmergencyStatus.inProgress.name,
            EmergencyStatus.verified.name,
            EmergencyStatus.escalated.name,
          ])
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      
      return Emergency.fromFirestore(snapshot.docs.first);
    } catch (e) {
      AppLogger.logError('Error getting user active emergency', e);
      return null;
    }
  }

  /// Clean up old/stale emergencies for a user - enforce single emergency per user
  static Future<void> cleanupUserEmergencies(String userId) async {
    try {
      // Get ALL emergencies for this user (active, resolved, in progress)
      final allEmergencies = await _firestore
          .collection(_collection)
          .where('attendeeId', isEqualTo: userId)
          .get();

      if (allEmergencies.docs.isEmpty) {
        AppLogger.logInfo('No emergencies found for user $userId - cleanup not needed');
        return;
      }

      // Separate active from resolved/old emergencies
      final activeEmergencies = <QueryDocumentSnapshot>[];
      final staleEmergencies = <QueryDocumentSnapshot>[];
      
      for (final doc in allEmergencies.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        final createdAt = data['createdAt'] as Timestamp?;
        
        if (status == EmergencyStatus.unverified.name || 
            status == EmergencyStatus.accepted.name ||
            status == EmergencyStatus.inProgress.name ||
            status == EmergencyStatus.verified.name ||
            status == EmergencyStatus.escalated.name) {
          activeEmergencies.add(doc);
        } else if (status == EmergencyStatus.resolved.name || 
                   status == EmergencyStatus.fake.name ||
                   (createdAt != null && DateTime.now().difference(createdAt.toDate()).inHours > 24)) {
          staleEmergencies.add(doc);
        }
      }

      AppLogger.logInfo('Emergency cleanup for $userId: ${activeEmergencies.length} active, ${staleEmergencies.length} stale');

      // If user has multiple active emergencies, resolve all but the newest
      if (activeEmergencies.length > 1) {
        // Sort by creation time, keep the newest
        activeEmergencies.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>?;
          final bData = b.data() as Map<String, dynamic>?;
          final aTime = aData?['createdAt'] as Timestamp?;
          final bTime = bData?['createdAt'] as Timestamp?;
          return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(aTime?.millisecondsSinceEpoch ?? 0);
        });

        // Mark all but the first (newest) as resolved
        for (int i = 1; i < activeEmergencies.length; i++) {
          final oldEmergency = activeEmergencies[i];
          await _resolveStaleEmergency(oldEmergency.id, userId, 'Duplicate emergency cleanup');
          AppLogger.logWarning('Auto-resolved duplicate emergency: ${oldEmergency.id}');
        }
      }

      // Clean up resolved emergencies older than 24 hours
      for (final staleDoc in staleEmergencies) {
        await _cleanupStaleEmergencyData(staleDoc.id, userId);
        AppLogger.logInfo('Cleaned up stale emergency: ${staleDoc.id}');
      }

      AppLogger.logInfo('Emergency cleanup completed for user $userId');
    } catch (e) {
      AppLogger.logError('Error cleaning up user emergencies', e);
    }
  }

  /// Resolve a stale emergency (internal method)
  static Future<void> _resolveStaleEmergency(String emergencyId, String userId, String reason) async {
    try {
      final batch = _firestore.batch();

      // Update emergency document
      batch.update(
        _firestore.collection(_collection).doc(emergencyId),
        {
          'status': EmergencyStatus.resolved.name,
          'updatedAt': FieldValue.serverTimestamp(),
          'resolvedBy.attendee': true,
          'resolvedBy.reason': reason,
        },
      );

      // Update user location to remove emergency state
      final userGroupId = await _getUserGroupId(userId);
      if (userGroupId != null) {
        batch.update(
          _firestore.collection('groups').doc(userGroupId).collection('locations').doc(userId),
          {
            'isEmergency': false,
            'emergencyId': FieldValue.delete(),
            'lastUpdated': FieldValue.serverTimestamp(),
          },
        );
      }

      await batch.commit();
    } catch (e) {
      AppLogger.logError('Error resolving stale emergency $emergencyId', e);
    }
  }

  /// Clean up stale emergency data (internal method)
  static Future<void> _cleanupStaleEmergencyData(String emergencyId, String userId) async {
    try {
      // For resolved emergencies older than 24 hours, we can either:
      // 1. Delete them completely, or 
      // 2. Archive them to a separate collection
      // 3. Just ensure user location is cleaned up
      
      // For now, just ensure user location is clean
      final userGroupId = await _getUserGroupId(userId);
      if (userGroupId != null) {
        await _firestore
            .collection('groups')
            .doc(userGroupId)
            .collection('locations')
            .doc(userId)
            .update({
          'isEmergency': false,
          'emergencyId': FieldValue.delete(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      AppLogger.logError('Error cleaning up stale emergency data $emergencyId', e);
    }
  }

  /// Get user's group ID (helper method)
  static Future<String?> _getUserGroupId(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        return userData['groupId'] as String?;
      }
      return null;
    } catch (e) {
      AppLogger.logError('Error getting user group ID', e);
      return null;
    }
  }

  /// Add volunteer response to an emergency
  static Future<void> addVolunteerResponse({
    required String emergencyId,
    required String volunteerId,
    required String volunteerName,
    required LatLng volunteerLocation,
  }) async {
    try {
      final now = DateTime.now();
      final response = EmergencyVolunteerResponse(
        volunteerId: volunteerId,
        volunteerName: volunteerName,
        status: EmergencyVolunteerStatus.responding,
        respondedAt: now,
        lastUpdated: now,
        currentLocation: volunteerLocation,
      );

      await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .update({
        'responses.$volunteerId': response.toMap(),
        'status': EmergencyStatus.inProgress.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      AppLogger.logInfo('Volunteer response added: $volunteerId to $emergencyId');
    } catch (e) {
      AppLogger.logError('Error adding volunteer response', e);
      rethrow;
    }
  }

  /// Update volunteer response status
  static Future<void> updateVolunteerStatus({
    required String emergencyId,
    required String volunteerId,
    required EmergencyVolunteerStatus status,
    LatLng? currentLocation,
    List<LatLng>? routePoints,
    String? estimatedArrivalTime,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'responses.$volunteerId.status': status.name,
        'responses.$volunteerId.lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (currentLocation != null) {
        updateData['responses.$volunteerId.currentLocation'] = 
            GeoPoint(currentLocation.latitude, currentLocation.longitude);
      }

      if (routePoints != null) {
        updateData['responses.$volunteerId.routePoints'] = 
            routePoints.map((point) => GeoPoint(point.latitude, point.longitude)).toList();
      }

      if (estimatedArrivalTime != null) {
        updateData['responses.$volunteerId.estimatedArrivalTime'] = estimatedArrivalTime;
      }

      // If volunteer completed, mark hasVolunteerCompleted as true
      if (status == EmergencyVolunteerStatus.completed) {
        updateData['resolvedBy.hasVolunteerCompleted'] = true;
      }

      await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .update(updateData);

      AppLogger.logInfo('Volunteer status updated: $volunteerId -> ${status.name}');
    } catch (e) {
      AppLogger.logError('Error updating volunteer status', e);
      rethrow;
    }
  }

  /// Update volunteer location in real-time
  static Future<void> updateVolunteerLocation({
    required String emergencyId,
    required String volunteerId,
    required LatLng location,
    List<LatLng>? routePoints,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'responses.$volunteerId.currentLocation': 
            GeoPoint(location.latitude, location.longitude),
        'responses.$volunteerId.lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (routePoints != null) {
        updateData['responses.$volunteerId.routePoints'] = 
            routePoints.map((point) => GeoPoint(point.latitude, point.longitude)).toList();
      }

      await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .update(updateData);

    } catch (e) {
      AppLogger.logError('Error updating volunteer location', e);
      // Don't rethrow for location updates to avoid disrupting the user experience
    }
  }

  /// Remove volunteer response (when they cancel)
  static Future<void> removeVolunteerResponse({
    required String emergencyId,
    required String volunteerId,
  }) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .update({
        'responses.$volunteerId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      AppLogger.logInfo('Volunteer response removed: $volunteerId from $emergencyId');
    } catch (e) {
      AppLogger.logError('Error removing volunteer response', e);
      rethrow;
    }
  }

  /// Mark emergency as resolved by attendee
  static Future<void> markResolvedByAttendee(String emergencyId) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .update({
        'resolvedBy.attendee': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Check if emergency should be fully resolved
      final doc = await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .get();

      if (doc.exists) {
        final emergency = Emergency.fromFirestore(doc);
        if (emergency.isFullyResolved) {
          await _markEmergencyResolved(emergencyId);
        }
      }

      AppLogger.logInfo('Emergency marked as resolved by attendee: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error marking emergency resolved by attendee', e);
      rethrow;
    }
  }

  /// Mark emergency as fully resolved
  static Future<void> _markEmergencyResolved(String emergencyId) async {
    await _firestore
        .collection(_collection)
        .doc(emergencyId)
        .update({
      'status': EmergencyStatus.resolved.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    AppLogger.logInfo('Emergency fully resolved: $emergencyId');
  }

  /// Get active emergencies for a group
  static Stream<List<Emergency>> getGroupEmergencies(String groupId) {
    return _firestore
        .collection(_collection)
        .where('groupId', isEqualTo: groupId)
        .where('status', whereIn: [
          EmergencyStatus.unverified.name, 
          EmergencyStatus.accepted.name,
          EmergencyStatus.inProgress.name,
          EmergencyStatus.verified.name,
          EmergencyStatus.escalated.name,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Emergency.fromFirestore(doc)).toList();
    });
  }

  /// Get ALL active emergencies across ALL groups (for volunteers)
  static Stream<List<Emergency>> getAllEmergencies() {
    return _firestore
        .collection(_collection)
        .where('status', whereIn: [
          EmergencyStatus.unverified.name, 
          EmergencyStatus.accepted.name,
          EmergencyStatus.inProgress.name,
          EmergencyStatus.verified.name,
          EmergencyStatus.escalated.name,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Emergency.fromFirestore(doc)).toList();
    });
  }

  /// Resolve emergency with complete cleanup
  static Future<void> resolveEmergencyWithCleanup(String emergencyId) async {
    try {
      // Get emergency details first
      final emergencyDoc = await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .get();

      if (!emergencyDoc.exists) {
        throw Exception('Emergency not found');
      }

      final emergency = Emergency.fromFirestore(emergencyDoc);
      final batch = _firestore.batch();

      // Mark emergency as resolved
      batch.update(
        _firestore.collection(_collection).doc(emergencyId),
        {
          'status': EmergencyStatus.resolved.name,
          'updatedAt': FieldValue.serverTimestamp(),
          'resolvedBy': {
            'attendee': true,
            'hasVolunteerCompleted': emergency.responses.isNotEmpty,
            'resolvedAt': FieldValue.serverTimestamp(),
          },
        },
      );

      // Update user location to remove emergency state
      batch.update(
        _firestore
            .collection('groups')
            .doc(emergency.groupId)
            .collection('locations')
            .doc(emergency.attendeeId),
        {
          'isEmergency': false,
          'emergencyId': FieldValue.delete(),
          'lastUpdated': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();

      AppLogger.logInfo('Emergency resolved with cleanup: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error resolving emergency with cleanup', e);
      rethrow;
    }
  }

  /// Update emergency location in real-time
  static Future<void> updateEmergencyLocation({
    required String emergencyId,
    required String groupId,
    required String attendeeId,
    required LatLng location,
  }) async {
    try {
      final batch = _firestore.batch();

      // Update emergency document location
      batch.update(
        _firestore.collection(_collection).doc(emergencyId),
        {
          'location': GeoPoint(location.latitude, location.longitude),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      // Update user location
      batch.update(
        _firestore
            .collection('groups')
            .doc(groupId)
            .collection('locations')
            .doc(attendeeId),
        {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
    } catch (e) {
      AppLogger.logError('Error updating emergency location', e);
      // Don't rethrow for location updates to avoid disrupting the user experience
    }
  }

  /// Get all emergencies for a group (including resolved ones)
  static Stream<List<Emergency>> getAllGroupEmergencies(String groupId) {
    return _firestore
        .collection(_collection)
        .where('groupId', isEqualTo: groupId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Emergency.fromFirestore(doc)).toList();
    });
  }

  /// Get volunteer's active responses
  static Stream<List<Emergency>> getVolunteerActiveResponses(String volunteerId) {
    return _firestore
        .collection(_collection)
        .where('status', whereIn: [
          EmergencyStatus.unverified.name, 
          EmergencyStatus.accepted.name,
          EmergencyStatus.inProgress.name,
          EmergencyStatus.verified.name,
          EmergencyStatus.escalated.name,
        ])
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Emergency.fromFirestore(doc))
          .where((emergency) => 
              emergency.responses.containsKey(volunteerId) &&
              emergency.responses[volunteerId]!.status != EmergencyVolunteerStatus.unavailable)
          .toList();
    });
  }

  /// Get specific emergency by ID
  static Future<Emergency?> getEmergency(String emergencyId) async {
    try {
      final doc = await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .get();

      if (doc.exists) {
        return Emergency.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      AppLogger.logError('Error getting emergency', e);
      return null;
    }
  }

  /// Listen to specific emergency changes
  static Stream<Emergency?> listenToEmergency(String emergencyId) {
    return _firestore
        .collection(_collection)
        .doc(emergencyId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return Emergency.fromFirestore(doc);
      }
      return null;
    });
  }

  /// Clean up resolved emergency (for admin/organizers)
  static Future<void> deleteEmergency(String emergencyId) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(emergencyId)
          .delete();

      AppLogger.logInfo('Emergency deleted: $emergencyId');
    } catch (e) {
      AppLogger.logError('Error deleting emergency', e);
      rethrow;
    }
  }

  /// Get emergency statistics for a group
  static Future<Map<String, int>> getEmergencyStats(String groupId) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('groupId', isEqualTo: groupId)
          .get();

      int active = 0;
      int inProgress = 0;
      int resolved = 0;
      
      for (final doc in snapshot.docs) {
        final emergency = Emergency.fromFirestore(doc);
        switch (emergency.status) {
          case EmergencyStatus.unverified:
          case EmergencyStatus.accepted:
            active++;
            break;
          case EmergencyStatus.inProgress:
          case EmergencyStatus.verified:
          case EmergencyStatus.escalated:
            inProgress++;
            break;
          case EmergencyStatus.resolved:
            resolved++;
            break;
          case EmergencyStatus.fake:
            // Don't count fake emergencies in statistics
            break;
        }
      }

      return {
        'active': active,
        'inProgress': inProgress,
        'resolved': resolved,
        'total': snapshot.docs.length,
      };
    } catch (e) {
      AppLogger.logError('Error getting emergency stats', e);
      return {'active': 0, 'inProgress': 0, 'resolved': 0, 'total': 0};
    }
  }

  // ========== NEW: Enhanced Volunteer Response Pipeline Methods ==========

  /// Mark emergency as accepted by volunteer
  static Future<void> acceptEmergency({
    required String emergencyId,
    required String volunteerId,
    required String volunteerName,
    required LatLng volunteerLocation,
  }) async {
    try {
      final now = DateTime.now();
      final batch = _firestore.batch();

      // Update emergency status to accepted
      final emergencyRef = _firestore.collection(_collection).doc(emergencyId);
      batch.update(emergencyRef, {
        'status': EmergencyStatus.accepted.name,
        'acceptedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      // Add volunteer response
      batch.update(emergencyRef, {
        'responses.$volunteerId': {
          'volunteerId': volunteerId,
          'volunteerName': volunteerName,
          'status': EmergencyVolunteerStatus.responding.name,
          'respondedAt': Timestamp.fromDate(now),
          'lastUpdated': Timestamp.fromDate(now),
          'location': GeoPoint(volunteerLocation.latitude, volunteerLocation.longitude),
        }
      });

      await batch.commit();
      AppLogger.logInfo('Emergency $emergencyId accepted by volunteer $volunteerId');
    } catch (e) {
      AppLogger.logError('Error accepting emergency', e);
      rethrow;
    }
  }

  /// Mark volunteer as arrived and trigger verification
  static Future<void> markVolunteerArrived({
    required String emergencyId,
    required String volunteerId,
  }) async {
    try {
      final now = DateTime.now();
      final batch = _firestore.batch();

      // Update emergency status to in progress
      final emergencyRef = _firestore.collection(_collection).doc(emergencyId);
      batch.update(emergencyRef, {
        'status': EmergencyStatus.inProgress.name,
        'arrivedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      // Update volunteer status to arrived
      batch.update(emergencyRef, {
        'responses.$volunteerId.status': EmergencyVolunteerStatus.arrived.name,
        'responses.$volunteerId.lastUpdated': Timestamp.fromDate(now),
      });

      await batch.commit();
      AppLogger.logInfo('Volunteer $volunteerId marked as arrived at emergency $emergencyId');
    } catch (e) {
      AppLogger.logError('Error marking volunteer arrived', e);
      rethrow;
    }
  }

  /// Verify emergency as real or fake
  static Future<void> verifyEmergency({
    required String emergencyId,
    required String volunteerId,
    required bool isReal,
    String? escalationReason,
  }) async {
    try {
      final now = DateTime.now();
      final batch = _firestore.batch();

      final emergencyRef = _firestore.collection(_collection).doc(emergencyId);
      
      if (isReal) {
        // Mark as verified real emergency
        batch.update(emergencyRef, {
          'status': escalationReason != null 
              ? EmergencyStatus.escalated.name 
              : EmergencyStatus.verified.name,
          'verifiedAt': Timestamp.fromDate(now),
          'verifiedBy': volunteerId,
          'isVerified': true,
          'isSeriousEscalation': escalationReason != null,
          'escalationReason': escalationReason,
          'updatedAt': Timestamp.fromDate(now),
        });
        
        AppLogger.logInfo('Emergency $emergencyId verified as REAL by volunteer $volunteerId${escalationReason != null ? ' and ESCALATED' : ''}');
      } else {
        // Mark as fake emergency
        batch.update(emergencyRef, {
          'status': EmergencyStatus.fake.name,
          'verifiedAt': Timestamp.fromDate(now),
          'verifiedBy': volunteerId,
          'isVerified': true,
          'updatedAt': Timestamp.fromDate(now),
        });
        
        AppLogger.logInfo('Emergency $emergencyId marked as FAKE by volunteer $volunteerId');
      }

      await batch.commit();
    } catch (e) {
      AppLogger.logError('Error verifying emergency', e);
      rethrow;
    }
  }

  /// Mark emergency as resolved by volunteer (testing only)
  static Future<void> markResolvedByVolunteer({
    required String emergencyId,
    required String volunteerId,
  }) async {
    try {
      final now = DateTime.now();
      final batch = _firestore.batch();

      // Update emergency status to resolved
      final emergencyRef = _firestore.collection(_collection).doc(emergencyId);
      batch.update(emergencyRef, {
        'status': EmergencyStatus.resolved.name,
        'resolvedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'resolvedBy.hasVolunteerCompleted': true,
      });

      // Update volunteer status to completed
      batch.update(emergencyRef, {
        'responses.$volunteerId.status': EmergencyVolunteerStatus.completed.name,
        'responses.$volunteerId.lastUpdated': Timestamp.fromDate(now),
      });

      await batch.commit();
      AppLogger.logInfo('Emergency $emergencyId resolved by volunteer $volunteerId');
    } catch (e) {
      AppLogger.logError('Error resolving emergency by volunteer', e);
      rethrow;
    }
  }

  /// Get filtered emergencies for volunteers (exclude fake emergencies)
  static Stream<List<Emergency>> getVolunteerVisibleEmergencies(String groupId) {
    return _firestore
        .collection(_collection)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Emergency.fromFirestore(doc))
          .where((emergency) => emergency.status.visibleToVolunteers) // Use extension method
          .toList();
    });
  }

  /// Get distance between volunteer and attendee
  static double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double lat1Rad = point1.latitude * (pi / 180);
    final double lat2Rad = point2.latitude * (pi / 180);
    final double deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    final double deltaLonRad = (point2.longitude - point1.longitude) * (pi / 180);

    final double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
        sin(deltaLonRad / 2) * sin(deltaLonRad / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c; // Distance in meters
  }
}
