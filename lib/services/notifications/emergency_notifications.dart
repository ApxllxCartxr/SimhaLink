import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/models/emergency.dart';
import 'notification_models.dart';

/// Handles emergency notifications
class EmergencyNotificationHandler {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Send emergency notification to nearest volunteers AND group members
  static Future<void> sendEmergencyNotification({
    required String groupId,
    required Emergency emergency,
  }) async {
    try {
      final notification = NotificationData(
        id: '',
        type: NotificationType.emergency,
        title: '🚨 Emergency Alert',
        message: '${emergency.attendeeName} needs immediate assistance!',
        data: {
          'groupId': groupId,
          'emergencyId': emergency.emergencyId,
          'userId': emergency.attendeeId,
          'latitude': emergency.location.latitude,
          'longitude': emergency.location.longitude,
          'isEmergency': true,
        },
        timestamp: DateTime.now(),
      );

      // Send to group members
      await _sendNotificationToGroup(groupId, notification);
      
      // Send to nearby volunteers
      await _notifyNearestVolunteers(emergency, notification);

      print('✅ Emergency alert sent successfully for ${emergency.attendeeName}');
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
        print('❌ Group $groupId not found');
        return;
      }

      final groupData = groupDoc.data();
      final List<dynamic> members = groupData?['members'] ?? [];

      for (final memberId in members) {
        try {
          final memberNotificationRef = _firestore
              .collection('users')
              .doc(memberId)
              .collection('notifications')
              .doc();

          await memberNotificationRef.set({
            ...notification.toMap(),
            'id': memberNotificationRef.id,
          });
        } catch (e) {
          print('❌ Failed to send notification to member $memberId: $e');
        }
      }

      print('📱 Emergency notification sent to ${members.length} group members');
    } catch (e) {
      print('❌ Error sending notifications to group: $e');
    }
  }

  /// Find and notify nearest volunteers from all groups within 5km radius
  static Future<void> _notifyNearestVolunteers(
    Emergency emergency,
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
            final locationData = locationDoc.data();
            final userId = locationData['userId'] as String?;
            final userRole = locationData['userRole'] as String?;
            final latitude = (locationData['latitude'] as num?)?.toDouble();
            final longitude = (locationData['longitude'] as num?)?.toDouble();
            
            // Skip if missing essential data
            if (userId == null || userRole == null || latitude == null || longitude == null) {
              continue;
            }
            
            // Only notify volunteers and organizers
            if (userRole != 'Volunteer' && userRole != 'Organizer') {
              continue;
            }
            
            // Skip if already notified or if it's the emergency user
            if (notifiedVolunteers.contains(userId) || userId == emergency.attendeeId) {
              continue;
            }
            
            final distance = _calculateDistance(
              emergency.location.latitude,
              emergency.location.longitude,
              latitude,
              longitude,
            );
            
            // Notify if within 5km radius
            if (distance <= 5000) {
              final volunteerNotificationRef = _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('notifications')
                  .doc();

              await volunteerNotificationRef.set({
                ...notification.toMap(),
                'id': volunteerNotificationRef.id,
                'distance': distance.round(),
              });
              
              notifiedVolunteers.add(userId);
              final userName = locationData['userName'] as String? ?? 'Unknown';
              print('🚑 Notified ${userRole.toLowerCase()} $userName (${distance.round()}m away)');
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
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);
    
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
        
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }
}
