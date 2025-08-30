import 'package:cloud_firestore/cloud_firestore.dart';

/// Defines the priority level of emergency communications
enum EmergencyPriority {
  low('low', 'Low Priority'),
  medium('medium', 'Medium Priority'),
  high('high', 'High Priority'),
  critical('critical', 'CRITICAL');
  
  final String value;
  final String displayName;
  
  const EmergencyPriority(this.value, this.displayName);
}

/// Model class for emergency communications between volunteers and organizers
class EmergencyCommunication {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String title;
  final String message;
  final DateTime createdAt;
  final EmergencyPriority priority;
  final String? location;
  final String groupId;
  final List<String> readBy;
  final List<String> respondedBy;
  final bool isResolved;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? resolution;
  
  EmergencyCommunication({
    required this.id,
    required this.senderId, 
    required this.senderName,
    required this.senderRole,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.priority,
    this.location,
    required this.groupId,
    this.readBy = const [],
    this.respondedBy = const [],
    this.isResolved = false,
    this.resolvedAt,
    this.resolvedBy,
    this.resolution,
  });
  
  /// Create a EmergencyCommunication from Firestore data
  factory EmergencyCommunication.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return EmergencyCommunication(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderRole: data['senderRole'] ?? 'volunteer',
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      priority: _priorityFromString(data['priority'] ?? 'medium'),
      location: data['location'],
      groupId: data['groupId'] ?? '',
      readBy: List<String>.from(data['readBy'] ?? []),
      respondedBy: List<String>.from(data['respondedBy'] ?? []),
      isResolved: data['isResolved'] ?? false,
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: data['resolvedBy'],
      resolution: data['resolution'],
    );
  }
  
  /// Convert EmergencyCommunication to a Map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'title': title,
      'message': message,
      'createdAt': Timestamp.fromDate(createdAt),
      'priority': priority.value,
      'location': location,
      'groupId': groupId,
      'readBy': readBy,
      'respondedBy': respondedBy,
      'isResolved': isResolved,
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'resolvedBy': resolvedBy,
      'resolution': resolution,
    };
  }
  
  /// Create a copy of this EmergencyCommunication with optional field updates
  EmergencyCommunication copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? senderRole,
    String? title,
    String? message,
    DateTime? createdAt,
    EmergencyPriority? priority,
    String? location,
    String? groupId,
    List<String>? readBy,
    List<String>? respondedBy,
    bool? isResolved,
    DateTime? resolvedAt,
    String? resolvedBy,
    String? resolution,
  }) {
    return EmergencyCommunication(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderRole: senderRole ?? this.senderRole,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      priority: priority ?? this.priority,
      location: location ?? this.location,
      groupId: groupId ?? this.groupId,
      readBy: readBy ?? this.readBy,
      respondedBy: respondedBy ?? this.respondedBy,
      isResolved: isResolved ?? this.isResolved,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      resolution: resolution ?? this.resolution,
    );
  }
  
  /// Helper to convert string to EmergencyPriority enum
  static EmergencyPriority _priorityFromString(String value) {
    return EmergencyPriority.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EmergencyPriority.medium,
    );
  }
}
