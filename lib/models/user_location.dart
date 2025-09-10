import 'package:cloud_firestore/cloud_firestore.dart';

class UserLocation {
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final bool isEmergency;
  final DateTime lastUpdated;
  final String? userRole; // Add user role to identify volunteers/organizers
  final String? groupId; // Add group ID for emergency tracking
  final String? emergencyMessage; // Optional emergency message

  UserLocation({
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    this.isEmergency = false,
    required this.lastUpdated,
    this.userRole,
    this.groupId,
    this.emergencyMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'latitude': latitude,
      'longitude': longitude,
      'isEmergency': isEmergency,
      'lastUpdated': lastUpdated.toIso8601String(),
      'userRole': userRole,
      'groupId': groupId,
      'emergencyMessage': emergencyMessage,
    };
  }

  factory UserLocation.fromMap(Map<String, dynamic> map) {
    // Handle both Timestamp (from Firebase) and String (from ISO8601) formats
    DateTime parseLastUpdated(dynamic lastUpdatedValue) {
      if (lastUpdatedValue is Timestamp) {
        return lastUpdatedValue.toDate();
      } else if (lastUpdatedValue is String) {
        return DateTime.parse(lastUpdatedValue);
      } else {
        return DateTime.now(); // Fallback
      }
    }

    return UserLocation(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      isEmergency: map['isEmergency'] ?? false,
      lastUpdated: parseLastUpdated(map['lastUpdated']),
      userRole: map['userRole'] as String?,
      groupId: map['groupId'] as String?,
      emergencyMessage: map['emergencyMessage'] as String?,
    );
  }
}
