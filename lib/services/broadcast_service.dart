import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/broadcast_message.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/utils/role_utils.dart';

/// Service for managing broadcast messages
/// Handles creation, delivery, and tracking of organizer broadcasts
class BroadcastService {
  static const String _broadcastCollection = 'broadcasts';
  static const String _usersCollection = 'users';
  
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  
  /// Send a broadcast message (organizers only)
  /// Returns true if broadcast was sent successfully
  static Future<bool> sendBroadcast({
    required String title,
    required String content,
    required BroadcastTarget target,
    required BroadcastPriority priority,
    String? groupId,
  }) async {
    try {
      AppLogger.logInfo('Starting broadcast creation process');
      
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot send broadcast: User not authenticated');
        return false;
      }

      // Check if user is an organizer using RoleUtils
      final isOrganizer = await RoleUtils.isUserOrganizer();
      if (!isOrganizer) {
        AppLogger.logWarning('Cannot send broadcast: User is not an organizer');
        return false;
      }

      // Get sender information from Firestore
      final userDoc = await _firestore
          .collection(_usersCollection)
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) {
        AppLogger.logWarning('Cannot send broadcast: User document not found');
        return false;
      }

      final userData = userDoc.data()!;
      final senderRole = userData['role'] ?? '';

      // For group-specific broadcasts, get group ID if not provided
      if (target == BroadcastTarget.myGroup && groupId == null) {
        groupId = await UserPreferences.getUserGroupId();
        if (groupId == null) {
          AppLogger.logWarning('Cannot send group broadcast: No group ID found');
          return false;
        }
      }

      // Create broadcast message
      final broadcast = BroadcastMessage(
        id: '', // Will be set by Firestore
        title: title.trim(),
        content: content.trim(),
        senderId: user.uid,
        senderName: userData['name'] ?? 'Organizer',
        senderRole: senderRole,
        createdAt: DateTime.now(),
        target: target,
        priority: priority,
        groupId: target == BroadcastTarget.myGroup ? groupId : null,
      );

      // Save to Firestore
      final docRef = await _firestore
          .collection(_broadcastCollection)
          .add(broadcast.toFirestore());

      AppLogger.logInfo('Broadcast created successfully: ${docRef.id}, target: ${target.value}, priority: ${priority.value}');

      // Send push notifications asynchronously (don't block success response)
      _sendPushNotifications(broadcast.copyWith(id: docRef.id));

      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to send broadcast', e, stackTrace);
      return false;
    }
  }

  /// Get broadcast messages for current user
  /// Returns stream of broadcasts the user should see based on role/group
  static Stream<List<BroadcastMessage>> getBroadcastStream() {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('No authenticated user for broadcast stream');
        return Stream.value([]);
      }

      AppLogger.logInfo('Setting up broadcast stream for user: ${user.uid}');

      return _firestore
          .collection(_broadcastCollection)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(50) // Limit to prevent excessive data transfer
          .snapshots()
          .asyncMap((snapshot) async {
            final broadcasts = <BroadcastMessage>[];
            final userRole = await _getCurrentUserRole();
            final userGroupId = await UserPreferences.getUserGroupId();

            AppLogger.logInfo('Processing ${snapshot.docs.length} broadcasts for user role: $userRole');

            for (final doc in snapshot.docs) {
              try {
                final broadcast = BroadcastMessage.fromFirestore(doc);
                
                // Check if user should see this broadcast
                if (_shouldReceiveBroadcast(broadcast, userRole, userGroupId)) {
                  broadcasts.add(broadcast);
                }
              } catch (e) {
                AppLogger.logError('Error processing broadcast document: ${doc.id}', e);
              }
            }

            AppLogger.logInfo('Filtered to ${broadcasts.length} broadcasts for user');
            return broadcasts;
          });
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to create broadcast stream', e, stackTrace);
      return Stream.value([]);
    }
  }

  /// Mark broadcast as read by current user
  /// This helps track message engagement and reduces notification noise
  static Future<void> markAsRead(String broadcastId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot mark broadcast as read: No authenticated user');
        return;
      }

      await _firestore
          .collection(_broadcastCollection)
          .doc(broadcastId)
          .update({
        'readBy': FieldValue.arrayUnion([user.uid]),
      });

      AppLogger.logInfo('Marked broadcast as read: $broadcastId by user: ${user.uid}');
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to mark broadcast as read', e, stackTrace);
    }
  }

  /// Get unread broadcast count for current user
  /// Used to show notification badges in the UI
  static Stream<int> getUnreadCountStream() {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return Stream.value(0);
      }

      return _firestore
          .collection(_broadcastCollection)
          .where('isActive', isEqualTo: true)
          .snapshots()
          .asyncMap((snapshot) async {
            final userRole = await _getCurrentUserRole();
            final userGroupId = await UserPreferences.getUserGroupId();
            int count = 0;

            for (final doc in snapshot.docs) {
              try {
                final broadcast = BroadcastMessage.fromFirestore(doc);
                
                // Check if user should receive this broadcast and hasn't read it
                if (_shouldReceiveBroadcast(broadcast, userRole, userGroupId) &&
                    !broadcast.readBy.contains(user.uid)) {
                  count++;
                }
              } catch (e) {
                AppLogger.logError('Error processing broadcast for unread count: ${doc.id}', e);
              }
            }

            return count;
          });
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to get unread count stream', e, stackTrace);
      return Stream.value(0);
    }
  }

  /// Send push notifications to target users
  /// This prepares the notification payload but actual sending requires server implementation
  static Future<void> _sendPushNotifications(BroadcastMessage broadcast) async {
    try {
      AppLogger.logInfo('Preparing push notifications for broadcast: ${broadcast.id}');
      
      // Get target users based on broadcast settings
      Query query = _firestore.collection(_usersCollection);
      
      // Filter by target roles
      final targetRoles = broadcast.target.getTargetRoles();
      // Convert to lowercase for database compatibility
      final lowerCaseRoles = targetRoles.map((role) => role.toLowerCase()).toList();
      
      if (lowerCaseRoles.isNotEmpty) {
        // Note: Firestore 'whereIn' has a limit of 10 items
        if (lowerCaseRoles.length <= 10) {
          query = query.where('role', whereIn: lowerCaseRoles);
        } else {
          // For more than 10 roles, we'd need multiple queries or server-side filtering
          AppLogger.logWarning('Too many target roles for single query: ${lowerCaseRoles.length}');
        }
      }
      
      // Filter by group if needed
      if (broadcast.target == BroadcastTarget.myGroup && broadcast.groupId != null) {
        query = query.where('groupId', isEqualTo: broadcast.groupId);
      }

      final snapshot = await query.get();
      
      // Collect FCM tokens from target users
      final tokens = <String>[];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final token = data['fcmToken'] as String?;
        if (token != null && token.isNotEmpty) {
          tokens.add(token);
        }
      }

      if (tokens.isEmpty) {
        AppLogger.logInfo('No FCM tokens found for broadcast recipients');
        return;
      }

      // Create notification payload based on priority
      // ignore: unused_local_variable
      final notification = {
        'title': broadcast.priority == BroadcastPriority.urgent 
            ? '🚨 ${broadcast.title}'
            : broadcast.title,
        'body': broadcast.content,
        'priority': broadcast.priority == BroadcastPriority.urgent ? 'high' : 'normal',
        'sound': broadcast.priority.level >= BroadcastPriority.high.level ? 'default' : null,
      };

      // ignore: unused_local_variable
      final data = {
        'type': 'broadcast',
        'broadcastId': broadcast.id,
        'priority': broadcast.priority.value,
        'senderId': broadcast.senderId,
        'createdAt': broadcast.createdAt.toIso8601String(),
      };

      // Log notification preparation (actual sending requires server implementation)
      AppLogger.logInfo('Prepared push notification for ${tokens.length} users for broadcast: ${broadcast.id}');
      
      // TODO: Use notification and data payload for actual FCM sending
      // Example: await FirebaseMessaging.instance.sendMulticast(MulticastMessage(tokens: tokens, notification: notification, data: data));

      // TODO: Implement actual FCM sending via cloud function or server
      // For now, we simulate the notification preparation

    } catch (e, stackTrace) {
      AppLogger.logError('Failed to send push notifications', e, stackTrace);
    }
  }

  /// Check if user should receive a specific broadcast based on role and group
  /// This implements the targeting logic for broadcasts
  static bool _shouldReceiveBroadcast(
    BroadcastMessage broadcast, 
    String userRole, 
    String? userGroupId,
  ) {
    // Check role-based targeting
    final targetRoles = broadcast.target.getTargetRoles();
    final userRoleCapitalized = userRole.isNotEmpty 
        ? userRole[0].toUpperCase() + userRole.substring(1).toLowerCase()
        : '';
    
    if (!targetRoles.contains(userRoleCapitalized)) {
      return false;
    }

    // Check group-specific targeting
    if (broadcast.target == BroadcastTarget.myGroup) {
      return userGroupId != null && userGroupId == broadcast.groupId;
    }

    return true;
  }

  /// Get current user's role from Firestore
  /// Used for broadcast filtering and permissions
  static Future<String> _getCurrentUserRole() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return '';

      final doc = await _firestore
          .collection(_usersCollection)
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        return data['role'] ?? '';
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to get current user role', e, stackTrace);
    }
    return '';
}

  /// Check if current user is an organizer
  /// Used to control UI access to broadcast composition
  static Future<bool> isCurrentUserOrganizer() async {
    try {
      return await RoleUtils.isUserOrganizer();
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to check if user is organizer', e, stackTrace);
      return false;
    }
  }
}
