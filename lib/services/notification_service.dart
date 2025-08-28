import 'dart:async';
import 'dart:math';
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

  /// Send emergency notification to nearest volunteers AND group members
  static Future<void> sendEmergencyNotification({
    required String groupId,
    required UserLocation emergencyUser,
  }) async {
    try {
      // 1. Create basic emergency notification
      final notification = NotificationData(
        id: '',
        type: NotificationType.emergency,
        title: '🚨 Emergency Alert',
        message: '${emergencyUser.userName} needs immediate assistance!',
        data: {
          'groupId': groupId,
          'userId': emergencyUser.userId,
          'latitude': emergencyUser.latitude,
          'longitude': emergencyUser.longitude,
          'isEmergency': true,
        },
        timestamp: DateTime.now(),
      );

      // 2. Send notification to all group members first
      await _sendNotificationToGroup(groupId, notification);

      // 3. Find and notify nearest volunteers from ALL groups
      await _notifyNearestVolunteers(emergencyUser, notification);

      // 4. Send push notifications to devices
      await _sendEmergencyPushNotifications(groupId, emergencyUser);

      print('✅ Emergency alert sent successfully for ${emergencyUser.userName}');
    } catch (e) {
      print('❌ Failed to send emergency notification: $e');
      throw Exception('Failed to send emergency notification: ${e.toString()}');
    }
  }

  /// Find and notify nearest volunteers across all groups
  static Future<void> _notifyNearestVolunteers(
    UserLocation emergencyUser,
    NotificationData notification,
  ) async {
    try {
      // Get all volunteers with recent locations
      final volunteerLocations = <UserLocation>[];
      
      // Query all groups to find volunteers with recent locations
      final groupsSnapshot = await _firestore.collection('groups').get();
      
      for (final groupDoc in groupsSnapshot.docs) {
        try {
          final locationsSnapshot = await _firestore
              .collection('groups')
              .doc(groupDoc.id)
              .collection('locations')
              .where('lastUpdated', isGreaterThan: Timestamp.fromDate(
                DateTime.now().subtract(const Duration(minutes: 15))
              ))
              .get();

          for (final locationDoc in locationsSnapshot.docs) {
            final location = UserLocation.fromMap(locationDoc.data());
            
            // Check if this user is a volunteer
            final userDoc = await _firestore
                .collection('users')
                .doc(location.userId)
                .get();
            
            if (userDoc.exists && 
                userDoc.data()?['role'] == 'volunteer' ||
                userDoc.data()?['role'] == 'Volunteer') {
              volunteerLocations.add(location);
            }
          }
        } catch (e) {
          print('Error checking group ${groupDoc.id} for volunteers: $e');
          continue;
        }
      }

      if (volunteerLocations.isEmpty) {
        print('⚠️  No active volunteers found to notify');
        return;
      }

      // Calculate distances and find nearest volunteers (within 5km radius)
      final nearbyVolunteers = <MapEntry<UserLocation, double>>[];
      
      for (final volunteer in volunteerLocations) {
        if (volunteer.userId == emergencyUser.userId) continue; // Skip if it's the same user
        
        final distance = _calculateDistance(
          emergencyUser.latitude,
          emergencyUser.longitude,
          volunteer.latitude,
          volunteer.longitude,
        );
        
        // Include volunteers within 5km radius
        if (distance <= 5.0) {
          nearbyVolunteers.add(MapEntry(volunteer, distance));
        }
      }

      if (nearbyVolunteers.isEmpty) {
        print('⚠️  No volunteers found within 5km radius');
        return;
      }

      // Sort by distance and take closest 5 volunteers
      nearbyVolunteers.sort((a, b) => a.value.compareTo(b.value));
      final closestVolunteers = nearbyVolunteers.take(5).toList();

      print('🚨 Notifying ${closestVolunteers.length} nearest volunteers');

      // Send notifications to nearest volunteers
      final batch = _firestore.batch();
      
      for (final volunteerEntry in closestVolunteers) {
        final volunteer = volunteerEntry.key;
        final distance = volunteerEntry.value;
        
        // Create enhanced notification for volunteers
        final volunteerNotification = NotificationData(
          id: '',
          type: NotificationType.emergency,
          title: '🚨 EMERGENCY - ${distance.toStringAsFixed(1)}km away',
          message: '${emergencyUser.userName} needs immediate assistance! You are one of the nearest volunteers.',
          data: {
            'userId': emergencyUser.userId,
            'userName': emergencyUser.userName,
            'latitude': emergencyUser.latitude,
            'longitude': emergencyUser.longitude,
            'distance': distance,
            'isEmergency': true,
            'priority': 'HIGH',
          },
          timestamp: DateTime.now(),
        );
        
        final notificationRef = _firestore
            .collection('users')
            .doc(volunteer.userId)
            .collection('notifications')
            .doc();
            
        batch.set(notificationRef, volunteerNotification.toMap());
      }
      
      await batch.commit();
      print('✅ Notified ${closestVolunteers.length} nearest volunteers');
      
    } catch (e) {
      print('❌ Error notifying nearest volunteers: $e');
    }
  }

  /// Calculate distance between two points in kilometers using Haversine formula
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth's radius in kilometers
    
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  /// Send push notifications for emergency alerts
  static Future<void> _sendEmergencyPushNotifications(
    String groupId,
    UserLocation emergencyUser,
  ) async {
    try {
      // For now, we'll focus on in-app notifications
      // Push notifications require additional server-side setup with FCM
      print('✅ Emergency push notifications would be sent here (requires FCM server setup)');
      
      // TODO: Implement server-side FCM message sending
      // This would typically be done via:
      // 1. Cloud Functions (Firebase)
      // 2. Your own backend server
      // 3. FCM Admin SDK
      
      // The client-side FCM setup would include:
      // - Requesting notification permissions
      // - Getting FCM tokens
      // - Subscribing to topics
      // - Handling incoming messages
      
    } catch (e) {
      print('❌ Error with push notifications: $e');
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
