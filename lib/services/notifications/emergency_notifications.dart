import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/user_location.dart';
import 'notification_models.dart';

/// Handles emergency notifications
class EmergencyNotificationHandler {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Send emergency notification to nearest volunteers AND group members
  static Future<void> sendEmergencyNotification({
    required String groupId,
    required UserLocation emergencyUser,
  }) async {
    try {
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

      // Send to group members
      await _sendNotificationToGroup(groupId, notification);
      
      // Send to nearby volunteers
      await _notifyNearestVolunteers(emergencyUser, notification);

      print('✅ Emergency alert sent successfully for ${emergencyUser.userName}');
    } catch (e) {
      print('❌ Failed to send emergency notification: $e');
      throw Exception('Failed to send emergency notification: ${e.toString()}');
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
        print('⚠️ Group $groupId not found for emergency notification');
        return;
      }

      final List<dynamic> memberIds = groupDoc.data()?['memberIds'] ?? [];
      
      for (final memberId in memberIds) {
        if (memberId != notification.data['userId']) {
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
      }
      
      print('📤 Emergency notification sent to ${memberIds.length - 1} group members');
    } catch (e) {
      print('❌ Error sending notification to group: $e');
    }
  }

  /// Find and notify nearest volunteers from all groups within 5km radius
  static Future<void> _notifyNearestVolunteers(
    UserLocation emergencyUser,
    NotificationData notification,
  ) async {
    try {
      // Get all groups
      final groupsSnapshot = await _firestore.collection('groups').get();
      
      Set<String> notifiedVolunteers = {};
      
      for (final groupDoc in groupsSnapshot.docs) {
        try {
          final locationsSnapshot = await _firestore
              .collection('groups')
              .doc(groupDoc.id)
              .collection('locations')
              .get();
          
          for (final locationDoc in locationsSnapshot.docs) {
            final userLocation = UserLocation.fromMap(locationDoc.data());
            
            // Only notify volunteers and organizers
            if (userLocation.userRole != 'Volunteer' && userLocation.userRole != 'Organizer') {
              continue;
            }
            
            // Skip if already notified or if it's the emergency user
            if (notifiedVolunteers.contains(userLocation.userId) ||
                userLocation.userId == emergencyUser.userId) {
              continue;
            }
            
            final distance = _calculateDistance(
              emergencyUser.latitude,
              emergencyUser.longitude,
              userLocation.latitude,
              userLocation.longitude,
            );
            
            // Notify if within 5km
            if (distance <= 5000) {
              final volunteerNotificationRef = _firestore
                  .collection('users')
                  .doc(userLocation.userId)
                  .collection('notifications')
                  .doc();

              await volunteerNotificationRef.set({
                ...notification.toMap(),
                'id': volunteerNotificationRef.id,
                'distance': distance.round(),
              });
              
              notifiedVolunteers.add(userLocation.userId);
              print('🚑 Notified ${userLocation.userRole?.toLowerCase()} ${userLocation.userName} (${distance.round()}m away)');
            }
          }
        } catch (e) {
          print('❌ Error processing group ${groupDoc.id} for volunteers: $e');
        }
      }
      
      print('📤 Emergency notification sent to ${notifiedVolunteers.length} nearby volunteers/organizers');
    } catch (e) {
      print('❌ Error notifying volunteers: $e');
    }
  }

  /// Calculate distance between two points in meters
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000;
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLon = (lon2 - lon1) * (pi / 180);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
}
