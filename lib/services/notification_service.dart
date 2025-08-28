import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/user_location.dart';

enum NotificationType {
  emergency,
  poiCreated,
  memberJoined,
  memberLeft,
  groupMessage,
}

class NotificationData {
  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final bool isRead;

  const NotificationData({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.data,
    required this.timestamp,
    this.isRead = false,
  });

  factory NotificationData.fromMap(Map<String, dynamic> map, String id) {
    return NotificationData(
      id: id,
      type: NotificationType.values.firstWhere(
        (e) => e.toString().split('.').last == map['type'],
        orElse: () => NotificationType.groupMessage,
      ),
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      data: Map<String, dynamic>.from(map['data'] ?? {}),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: map['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.toString().split('.').last,
      'title': title,
      'message': message,
      'data': data,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
    };
  }
}

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Send emergency notification to all group members
  static Future<void> sendEmergencyNotification({
    required String groupId,
    required UserLocation emergencyUser,
  }) async {
    try {
      final notification = NotificationData(
        id: '',
        type: NotificationType.emergency,
        title: '🚨 Emergency Alert',
        message: '${emergencyUser.userName} needs assistance!',
        data: {
          'groupId': groupId,
          'userId': emergencyUser.userId,
          'latitude': emergencyUser.latitude,
          'longitude': emergencyUser.longitude,
        },
        timestamp: DateTime.now(),
      );

      await _sendNotificationToGroup(groupId, notification);
    } catch (e) {
      throw Exception('Failed to send emergency notification: ${e.toString()}');
    }
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
        title: '📍 New Point of Interest',
        message: '$creatorName added "$poiName" ($poiType)',
        data: {
          'groupId': groupId,
          'poiName': poiName,
          'poiType': poiType,
          'creatorName': creatorName,
        },
        timestamp: DateTime.now(),
      );

      await _sendNotificationToGroup(groupId, notification);
    } catch (e) {
      throw Exception('Failed to send POI notification: ${e.toString()}');
    }
  }

  /// Send member joined notification
  static Future<void> sendMemberJoinedNotification({
    required String groupId,
    required String memberName,
    required String memberRole,
  }) async {
    try {
      final notification = NotificationData(
        id: '',
        type: NotificationType.memberJoined,
        title: '👋 New Member',
        message: '$memberName joined as $memberRole',
        data: {
          'groupId': groupId,
          'memberName': memberName,
          'memberRole': memberRole,
        },
        timestamp: DateTime.now(),
      );

      await _sendNotificationToGroup(groupId, notification);
    } catch (e) {
      throw Exception('Failed to send member joined notification: ${e.toString()}');
    }
  }

  /// Send group message notification
  static Future<void> sendGroupMessageNotification({
    required String groupId,
    required String senderName,
    required String messagePreview,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final notification = NotificationData(
        id: '',
        type: NotificationType.groupMessage,
        title: '💬 New Message',
        message: '$senderName: $messagePreview',
        data: {
          'groupId': groupId,
          'senderName': senderName,
          'senderId': currentUser.uid,
        },
        timestamp: DateTime.now(),
      );

      await _sendNotificationToGroup(groupId, notification, excludeUserId: currentUser.uid);
    } catch (e) {
      throw Exception('Failed to send message notification: ${e.toString()}');
    }
  }

  /// Send notification to all group members
  static Future<void> _sendNotificationToGroup(
    String groupId,
    NotificationData notification, {
    String? excludeUserId,
  }) async {
    try {
      // Get group members
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final memberIds = List<String>.from(groupDoc.data()?['memberIds'] ?? []);

      // Send notification to each member (except excluded user)
      final batch = _firestore.batch();
      
      for (final memberId in memberIds) {
        if (excludeUserId != null && memberId == excludeUserId) continue;
        
        final notificationRef = _firestore
            .collection('users')
            .doc(memberId)
            .collection('notifications')
            .doc();
            
        batch.set(notificationRef, notification.toMap());
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to send notification to group: ${e.toString()}');
    }
  }

  /// Get user notifications stream
  static Stream<List<NotificationData>> getUserNotifications() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return NotificationData.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  /// Mark notification as read
  static Future<void> markAsRead(String notificationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      throw Exception('Failed to mark notification as read: ${e.toString()}');
    }
  }

  /// Mark all notifications as read
  static Future<void> markAllAsRead() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('notifications')
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to mark all notifications as read: ${e.toString()}');
    }
  }

  /// Delete notification
  static Future<void> deleteNotification(String notificationId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .collection('notifications')
          .doc(notificationId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete notification: ${e.toString()}');
    }
  }

  /// Get unread notification count
  static Stream<int> getUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value(0);

    return _firestore
        .collection('users')
        .doc(currentUser.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
