import 'package:cloud_firestore/cloud_firestore.dart';

/// Alert priority levels
enum AlertPriority {
  low('Low', 1),
  medium('Medium', 2), 
  high('High', 3),
  critical('Critical', 4);

  const AlertPriority(this.displayName, this.level);
  final String displayName;
  final int level;

  static AlertPriority fromString(String priority) {
    switch (priority.toLowerCase()) {
      case 'low':
        return AlertPriority.low;
      case 'medium':
        return AlertPriority.medium;
      case 'high':
        return AlertPriority.high;
      case 'critical':
        return AlertPriority.critical;
      default:
        return AlertPriority.medium;
    }
  }
}

/// Alert types/categories
enum AlertType {
  emergency('Emergency', 'emergency'),
  medical('Medical', 'medical'),
  security('Security', 'security'),
  weather('Weather', 'weather'),
  traffic('Traffic', 'traffic'),
  general('General', 'general'),
  evacuation('Evacuation', 'evacuation'),
  announcement('Announcement', 'announcement');

  const AlertType(this.displayName, this.iconName);
  final String displayName;
  final String iconName;

  static AlertType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'emergency':
        return AlertType.emergency;
      case 'medical':
        return AlertType.medical;
      case 'security':
        return AlertType.security;
      case 'weather':
        return AlertType.weather;
      case 'traffic':
        return AlertType.traffic;
      case 'general':
        return AlertType.general;
      case 'evacuation':
        return AlertType.evacuation;
      case 'announcement':
        return AlertType.announcement;
      default:
        return AlertType.general;
    }
  }
}

/// Alert status
enum AlertStatus {
  active('Active'),
  resolved('Resolved'),
  cancelled('Cancelled');

  const AlertStatus(this.displayName);
  final String displayName;

  static AlertStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return AlertStatus.active;
      case 'resolved':
        return AlertStatus.resolved;
      case 'cancelled':
        return AlertStatus.cancelled;
      default:
        return AlertStatus.active;
    }
  }
}

class AlertModel {
  final String id;
  final String title;
  final String message;
  final AlertType type;
  final AlertPriority priority;
  final AlertStatus status;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final double? latitude;
  final double? longitude;
  final List<String> targetRoles;
  final List<String> targetUsers;
  final Map<String, dynamic> metadata;

  const AlertModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.priority,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.latitude,
    this.longitude,
    this.targetRoles = const [],
    this.targetUsers = const [],
    this.metadata = const {},
  });

  factory AlertModel.fromMap(Map<String, dynamic> map) {
    return AlertModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      type: AlertType.fromString(map['type'] ?? ''),
      priority: AlertPriority.fromString(map['priority'] ?? ''),
      status: AlertStatus.fromString(map['status'] ?? ''),
      createdBy: map['createdBy'] ?? '',
      createdByName: map['createdByName'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      expiresAt: (map['expiresAt'] as Timestamp?)?.toDate(),
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      targetRoles: List<String>.from(map['targetRoles'] ?? []),
      targetUsers: List<String>.from(map['targetUsers'] ?? []),
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name,
      'priority': priority.name,
      'status': status.name,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'latitude': latitude,
      'longitude': longitude,
      'targetRoles': targetRoles,
      'targetUsers': targetUsers,
      'metadata': metadata,
    };
  }

  /// Create a copy with updated values
  AlertModel copyWith({
    String? id,
    String? title,
    String? message,
    AlertType? type,
    AlertPriority? priority,
    AlertStatus? status,
    String? createdBy,
    String? createdByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? expiresAt,
    double? latitude,
    double? longitude,
    List<String>? targetRoles,
    List<String>? targetUsers,
    Map<String, dynamic>? metadata,
  }) {
    return AlertModel(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      targetRoles: targetRoles ?? this.targetRoles,
      targetUsers: targetUsers ?? this.targetUsers,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Check if alert is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Check if alert has location data
  bool get hasLocation => latitude != null && longitude != null;

  /// Get time since creation
  Duration get timeElapsed => DateTime.now().difference(createdAt);

  /// Check if alert is currently active and not expired
  bool get isCurrentlyActive => 
      status == AlertStatus.active && !isExpired;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlertModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'AlertModel(id: $id, title: $title, type: $type, priority: $priority, status: $status)';
  }
}
