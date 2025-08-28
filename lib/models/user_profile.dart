import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String role;
  final String? photoURL;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool isOnline;
  final Map<String, dynamic> preferences;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    this.photoURL,
    this.phoneNumber,
    required this.createdAt,
    required this.lastSeen,
    this.isOnline = false,
    this.preferences = const {},
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      displayName: map['displayName'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'Attendee',
      photoURL: map['photoURL'],
      phoneNumber: map['phoneNumber'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastSeen: (map['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: map['isOnline'] ?? false,
      preferences: Map<String, dynamic>.from(map['preferences'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'role': role,
      'photoURL': photoURL,
      'phoneNumber': phoneNumber,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastSeen': Timestamp.fromDate(lastSeen),
      'isOnline': isOnline,
      'preferences': preferences,
    };
  }

  UserProfile copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? role,
    String? photoURL,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? lastSeen,
    bool? isOnline,
    Map<String, dynamic>? preferences,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      role: role ?? this.role,
      photoURL: photoURL ?? this.photoURL,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      preferences: preferences ?? this.preferences,
    );
  }

  bool get isOrganizer => role == 'Organizer';
  bool get isVolunteer => role == 'Volunteer';
  bool get isAttendee => role == 'Attendee';

  bool get hasLocationPermission => preferences['locationEnabled'] == true;
  bool get hasNotificationPermission => preferences['notificationsEnabled'] == true;

  @override
  String toString() {
    return 'UserProfile(uid: $uid, displayName: $displayName, role: $role, isOnline: $isOnline)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserProfile && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
