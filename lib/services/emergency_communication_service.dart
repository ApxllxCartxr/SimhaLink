import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/emergency_communication.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/services/fcm_service.dart';

/// Service for managing emergency communications between volunteers and organizers
class EmergencyCommunicationService {
  static const String _emergencyCommsCollection = 'emergency_communications';
  static const String _usersCollection = 'users';
  static const String _groupsCollection = 'groups';
  
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Send an emergency communication from a volunteer to organizers
  /// Returns the ID of the created communication if successful, null otherwise
  static Future<String?> sendEmergencyCommunication({
    required String title,
    required String message,
    required EmergencyPriority priority,
    String? location,
  }) async {
    try {
      AppLogger.logInfo('Starting emergency communication creation');
      
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot send emergency comm: User not authenticated');
        return null;
      }

      // Get sender information from Firestore
      final userDoc = await _firestore
          .collection(_usersCollection)
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) {
        AppLogger.logWarning('Cannot send emergency comm: User document not found');
        return null;
      }

      final userData = userDoc.data()!;
      final senderRole = userData['role'] ?? '';
      
      // Verify sender is a volunteer
      if (senderRole.toLowerCase() != 'volunteer') {
        AppLogger.logWarning('Cannot send emergency comm: User is not a volunteer, role: $senderRole');
        return null;
      }

      // Get group ID
      final groupId = await UserPreferences.getUserGroupId();
      if (groupId == null) {
        AppLogger.logWarning('Cannot send emergency comm: No group ID found');
        return null;
      }

      // Create emergency communication
      final emergencyComm = EmergencyCommunication(
        id: '', // Will be set by Firestore
        title: title.trim(),
        message: message.trim(),
        senderId: user.uid,
        senderName: userData['name'] ?? 'Volunteer',
        senderRole: senderRole,
        createdAt: DateTime.now(),
        priority: priority,
        location: location,
        groupId: groupId,
      );

      // Save to Firestore
      final docRef = await _firestore
          .collection(_emergencyCommsCollection)
          .add(emergencyComm.toFirestore());

      AppLogger.logInfo('Emergency communication created: ${docRef.id}, priority: ${priority.value}');

      // Send notifications to organizers asynchronously
      _notifyOrganizers(emergencyComm.copyWith(id: docRef.id));

      return docRef.id;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to send emergency communication', e, stackTrace);
      return null;
    }
  }

  /// Get emergency communications for current user
  /// Organizers see all communications for their groups
  /// Volunteers see only communications they sent
  static Stream<List<EmergencyCommunication>> getEmergencyCommunicationsStream() {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('No authenticated user for emergency comms stream');
        return Stream.value([]);
      }

      AppLogger.logInfo('Setting up emergency communications stream for user: ${user.uid}');

      return _firestore
          .collection(_emergencyCommsCollection)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .asyncMap((snapshot) async {
            final communications = <EmergencyCommunication>[];
            final userDoc = await _firestore.collection(_usersCollection).doc(user.uid).get();
            
            if (!userDoc.exists) {
              return communications;
            }
            
            final userData = userDoc.data()!;
            final userRole = userData['role'] as String? ?? '';
            final userGroupId = await UserPreferences.getUserGroupId();
            
            if (userGroupId == null) {
              return communications;
            }

            for (final doc in snapshot.docs) {
              try {
                final communication = EmergencyCommunication.fromFirestore(doc);
                
                // Filter communications based on user role and group
                if (communication.groupId == userGroupId) {
                  if (userRole.toLowerCase() == 'organizer' || 
                      communication.senderId == user.uid) {
                    communications.add(communication);
                  }
                }
              } catch (e) {
                AppLogger.logError('Error processing emergency communication: ${doc.id}', e);
              }
            }

            return communications;
          });
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to create emergency communications stream', e, stackTrace);
      return Stream.value([]);
    }
  }

  /// Mark emergency communication as read by current user
  static Future<void> markAsRead(String communicationId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore
          .collection(_emergencyCommsCollection)
          .doc(communicationId)
          .update({
        'readBy': FieldValue.arrayUnion([user.uid]),
      });

      AppLogger.logInfo('Marked emergency communication as read: $communicationId');
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to mark emergency communication as read', e, stackTrace);
    }
  }

  /// Mark emergency communication as responded to by current user (organizers only)
  static Future<void> markAsResponded(String communicationId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Verify user is an organizer
      final userDoc = await _firestore.collection(_usersCollection).doc(user.uid).get();
      if (!userDoc.exists) return;
      
      final userData = userDoc.data()!;
      final userRole = userData['role'] as String? ?? '';
      
      if (userRole.toLowerCase() != 'organizer') {
        AppLogger.logWarning('Only organizers can mark comms as responded');
        return;
      }

      await _firestore
          .collection(_emergencyCommsCollection)
          .doc(communicationId)
          .update({
        'respondedBy': FieldValue.arrayUnion([user.uid]),
      });

      AppLogger.logInfo('Marked emergency communication as responded: $communicationId');
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to mark emergency communication as responded', e, stackTrace);
    }
  }

  /// Mark emergency communication as resolved (organizers only)
  static Future<bool> resolveEmergencyCommunication({
    required String communicationId,
    required String resolution,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Verify user is an organizer
      final userDoc = await _firestore.collection(_usersCollection).doc(user.uid).get();
      if (!userDoc.exists) return false;
      
      final userData = userDoc.data()!;
      final userRole = userData['role'] as String? ?? '';
      
      if (userRole.toLowerCase() != 'organizer') {
        AppLogger.logWarning('Only organizers can resolve emergency communications');
        return false;
      }

      await _firestore
          .collection(_emergencyCommsCollection)
          .doc(communicationId)
          .update({
        'isResolved': true,
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': user.uid,
        'resolution': resolution.trim(),
      });

      AppLogger.logInfo('Resolved emergency communication: $communicationId');
      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to resolve emergency communication', e, stackTrace);
      return false;
    }
  }

  /// Get unread emergency communications count
  static Stream<int> getUnreadCountStream() {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return Stream.value(0);
      }

      // For organizers, show all unread comms in their group
      // For volunteers, show only responses to their comms
      return _firestore
          .collection(_emergencyCommsCollection)
          .snapshots()
          .asyncMap((snapshot) async {
            final userDoc = await _firestore.collection(_usersCollection).doc(user.uid).get();
            
            if (!userDoc.exists) {
              return 0;
            }
            
            final userData = userDoc.data()!;
            final userRole = userData['role'] as String? ?? '';
            final userGroupId = await UserPreferences.getUserGroupId();
            
            if (userGroupId == null) {
              return 0;
            }
            
            int count = 0;

            for (final doc in snapshot.docs) {
              try {
                final communication = EmergencyCommunication.fromFirestore(doc);
                
                if (communication.groupId != userGroupId) continue;
                
                // For organizers: show all unread comms in their group
                if (userRole.toLowerCase() == 'organizer' && 
                    !communication.readBy.contains(user.uid) &&
                    !communication.isResolved) {
                  count++;
                }
                
                // For volunteers: show only their comms that have new responses
                else if (userRole.toLowerCase() == 'volunteer' && 
                         communication.senderId == user.uid &&
                         communication.respondedBy.isNotEmpty &&
                         !communication.readBy.contains(user.uid)) {
                  count++;
                }
              } catch (e) {
                AppLogger.logError('Error processing emergency communication count: ${doc.id}', e);
              }
            }

            return count;
          });
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to get unread emergency communications count', e, stackTrace);
      return Stream.value(0);
    }
  }

  /// Notify organizers of a new emergency communication
  static Future<void> _notifyOrganizers(EmergencyCommunication communication) async {
    try {
      // Get all organizers in the group
      final groupDoc = await _firestore
          .collection(_groupsCollection)
          .doc(communication.groupId)
          .get();
          
      if (!groupDoc.exists) return;
      
      final groupData = groupDoc.data()!;
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);
      
      // Get organizers
      final organizerDocs = await _firestore
          .collection(_usersCollection)
          .where('role', isEqualTo: 'organizer')
          .get();
          
      // Filter to only include group members
      final organizers = organizerDocs.docs
          .where((doc) => memberIds.contains(doc.id))
          .map((doc) => doc.id)
          .toList();
      
      // Send push notifications to organizers
      for (final organizerId in organizers) {
        FCMService.sendPushNotification(
          userId: organizerId,
          title: '${communication.priority.displayName} Alert from ${communication.senderName}',
          body: communication.title,
          data: {
            'type': 'volunteer_emergency',
            'communicationId': communication.id,
            'priority': communication.priority.value,
          },
        );
      }
      
      AppLogger.logInfo('Sent notifications to ${organizers.length} organizers');
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to notify organizers', e, stackTrace);
    }
  }
}
