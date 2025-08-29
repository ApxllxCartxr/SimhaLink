import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/user_location.dart';
import 'notifications/notification_models.dart';
import 'notifications/emergency_notifications.dart';

/// Main notification service that coordinates different notification types
class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Send emergency notification
  static Future<void> sendEmergencyNotification({
    required String groupId,
    required UserLocation emergencyUser,
  }) async {
    return EmergencyNotificationHandler.sendEmergencyNotification(
      groupId: groupId,
      emergencyUser: emergencyUser,
    );
  }

  /// Send POI creation notification
  static Future<void> sendPOINotification({
    required String groupId,
    required String poiName,
    required String poiType,
    required String creatorName,
  }) async {
    try {
      final notification = NotificationData(
        id: '',
        type: NotificationType.poiCreated,
        title: '📍 New Location Added',
        message: '$creatorName added a new $poiType: $poiName',
        data: {
          'groupId': groupId,
          'poiName': poiName,
          'poiType': poiType,
          'creatorName': creatorName,
        },
        timestamp: DateTime.now(),
      );

      await _sendNotificationToGroup(groupId, notification);
      print('✅ POI notification sent for: $poiName');
    } catch (e) {
      print('❌ Failed to send POI notification: $e');
    }
  }

  /// Send group member joined notification
  static Future<void> sendMemberJoinedNotification({
    required String groupId,
    required String memberName,
    required String memberRole,
  }) async {
    try {
      final notification = NotificationData(
        id: '',
        type: NotificationType.memberJoined,
        title: '👤 New Member',
        message: '$memberName joined as $memberRole',
        data: {
          'groupId': groupId,
          'memberName': memberName,
          'memberRole': memberRole,
        },
        timestamp: DateTime.now(),
      );

      await _sendNotificationToGroup(groupId, notification);
      print('✅ Member joined notification sent for: $memberName');
    } catch (e) {
      print('❌ Failed to send member joined notification: $e');
    }
  }

  /// Send notification to all group members
  static Future<void> _sendNotificationToGroup(
    String groupId,
    NotificationData notification,
  ) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      
      if (!groupDoc.exists) {
        print('⚠️ Group $groupId not found');
        return;
      }

      final List<dynamic> memberIds = groupDoc.data()?['memberIds'] ?? [];
      
      for (final memberId in memberIds) {
        final notificationRef = _firestore
            .collection('users')
            .doc(memberId)
            .collection('notifications')
            .doc();

        await notificationRef.set({
          ...notification.toMap(),
          'id': notificationRef.id,
        });
      }
      
      print('📤 Notification sent to ${memberIds.length} group members');
    } catch (e) {
      print('❌ Error sending notification to group: $e');
    }
  }

  /// Get notifications for a user
  static Stream<List<NotificationData>> getUserNotifications(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NotificationData.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  /// Mark notification as read
  static Future<void> markAsRead(String userId, String notificationId) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  /// Clear all notifications for a user
  static Future<void> clearAllNotifications(String userId) async {
    try {
      final batch = _firestore.batch();
      final notifications = await _firestore
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .get();

      for (final doc in notifications.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('✅ All notifications cleared for user: $userId');
    } catch (e) {
      print('❌ Error clearing notifications: $e');
    }
  }
}
