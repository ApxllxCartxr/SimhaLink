import 'package:cloud_firestore/cloud_firestore.dart';

/// Enumeration of user roles in the SimhaLink app
enum UserRole {
  volunteer('Volunteer'),
  vip('VIP'), 
  organizer('Organizer'),
  participant('Participant');

  const UserRole(this.displayName);
  final String displayName;

  /// Get UserRole from string
  static UserRole fromString(String role) {
    switch (role.toLowerCase()) {
      case 'volunteer':
        return UserRole.volunteer;
      case 'vip':
        return UserRole.vip;
      case 'organizer':
        return UserRole.organizer;
      case 'participant':
      default:
        return UserRole.participant;
    }
  }

  /// Check if this role has elevated permissions
  bool get hasElevatedPermissions => 
      this == UserRole.organizer || this == UserRole.volunteer;

  /// Check if this role can manage alerts
  bool get canManageAlerts => 
      this == UserRole.organizer || this == UserRole.volunteer;

  /// Check if this role can access VIP features
  bool get hasVipAccess => this == UserRole.vip || this == UserRole.organizer;
}

class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final UserRole role;
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
      role: UserRole.fromString(map['role'] ?? 'participant'),
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
      'role': role.name,
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
    UserRole? role,
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
