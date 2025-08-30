import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Model for broadcast messages sent by organizers
class BroadcastMessage {
  final String id;
  final String title;
  final String content;
  final String senderId;
  final String senderName;
  final String senderRole;
  final DateTime createdAt;
  final BroadcastTarget target;
  final BroadcastPriority priority;
  final String? groupId; // null for global broadcasts
  final List<String> readBy; // User IDs who have read the message
  final bool isActive;

  const BroadcastMessage({
    required this.id,
    required this.title,
    required this.content,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.createdAt,
    required this.target,
    required this.priority,
    this.groupId,
    this.readBy = const [],
    this.isActive = true,
  });

  /// Create from Firestore document
  factory BroadcastMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BroadcastMessage(
      id: doc.id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderRole: data['senderRole'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      target: BroadcastTarget.fromString(data['target'] ?? 'participants'),
      priority: BroadcastPriority.fromString(data['priority'] ?? 'normal'),
      groupId: data['groupId'],
      readBy: List<String>.from(data['readBy'] ?? []),
      isActive: data['isActive'] ?? true,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'content': content,
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'createdAt': Timestamp.fromDate(createdAt),
      'target': target.value,
      'priority': priority.value,
      'groupId': groupId,
      'readBy': readBy,
      'isActive': isActive,
    };
  }

  /// Copy with modifications
  BroadcastMessage copyWith({
    String? id,
    String? title,
    String? content,
    String? senderId,
    String? senderName,
    String? senderRole,
    DateTime? createdAt,
    BroadcastTarget? target,
    BroadcastPriority? priority,
    String? groupId,
    List<String>? readBy,
    bool? isActive,
  }) {
    return BroadcastMessage(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderRole: senderRole ?? this.senderRole,
      createdAt: createdAt ?? this.createdAt,
      target: target ?? this.target,
      priority: priority ?? this.priority,
      groupId: groupId ?? this.groupId,
      readBy: readBy ?? this.readBy,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Target audience for broadcast messages
enum BroadcastTarget {
  participantsOnly('participants', 'Participants Only'),
  allUsers('all_users', 'All Users'),
  volunteersOnly('volunteers', 'Volunteers Only'),
  vipsOnly('vips', 'VIPs Only'),
  myGroup('my_group', 'My Group Only');

  const BroadcastTarget(this.value, this.displayName);
  
  final String value;
  final String displayName;

  static BroadcastTarget fromString(String value) {
    return BroadcastTarget.values.firstWhere(
      (target) => target.value == value,
      orElse: () => BroadcastTarget.participantsOnly,
    );
  }

  /// Get roles included in this target
  List<String> getTargetRoles() {
    switch (this) {
      case BroadcastTarget.participantsOnly:
        return ['Participant', 'Attendee'];
      case BroadcastTarget.allUsers:
        return ['Participant', 'Attendee', 'Volunteer', 'Organizer', 'VIP'];
      case BroadcastTarget.volunteersOnly:
        return ['Volunteer'];
      case BroadcastTarget.vipsOnly:
        return ['VIP'];
      case BroadcastTarget.myGroup:
        return ['Participant', 'Attendee', 'Volunteer', 'Organizer', 'VIP'];
    }
  }

  /// Get description for UI
  String get description {
    switch (this) {
      case BroadcastTarget.participantsOnly:
        return 'Send to all participants in the event';
      case BroadcastTarget.allUsers:
        return 'Send to everyone using the app';
      case BroadcastTarget.volunteersOnly:
        return 'Send only to volunteers';
      case BroadcastTarget.vipsOnly:
        return 'Send only to VIP users';
      case BroadcastTarget.myGroup:
        return 'Send only to members of my group';
    }
  }
}

/// Priority levels for broadcast messages
enum BroadcastPriority {
  low('low', 'Low Priority', 0),
  normal('normal', 'Normal', 1),
  high('high', 'High Priority', 2),
  urgent('urgent', 'Urgent', 3);

  const BroadcastPriority(this.value, this.displayName, this.level);
  
  final String value;
  final String displayName;
  final int level;

  static BroadcastPriority fromString(String value) {
    return BroadcastPriority.values.firstWhere(
      (priority) => priority.value == value,
      orElse: () => BroadcastPriority.normal,
    );
  }

  /// Get color for UI
  Color get color {
    switch (this) {
      case BroadcastPriority.low:
        return Colors.grey;
      case BroadcastPriority.normal:
        return Colors.blue;
      case BroadcastPriority.high:
        return Colors.orange;
      case BroadcastPriority.urgent:
        return Colors.red;
    }
  }
}
