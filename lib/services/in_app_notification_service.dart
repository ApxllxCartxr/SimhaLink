import 'dart:async';
import 'package:flutter/material.dart';
import 'package:simha_link/core/utils/app_logger.dart';

/// In-app notification service for real-time alerts
class InAppNotificationService {
  static InAppNotificationService? _instance;
  static InAppNotificationService get instance => _instance ??= InAppNotificationService._();
  InAppNotificationService._();

  final StreamController<InAppNotification> _notificationController = 
      StreamController<InAppNotification>.broadcast();
  
  Stream<InAppNotification> get notificationStream => _notificationController.stream;

  /// Show notification at top of screen
  void showNotification({
    required String title,
    required String message,
    InAppNotificationType type = InAppNotificationType.info,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    Map<String, dynamic>? data,
  }) {
    final notification = InAppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      timestamp: DateTime.now(),
      duration: duration,
      onTap: onTap,
      data: data,
    );

    _notificationController.add(notification);
    AppLogger.logInfo('In-app notification shown: $title - $message');
  }

  /// Show emergency-related notification
  void showEmergencyNotification({
    required String title,
    required String message,
    required String emergencyId,
    VoidCallback? onTap,
  }) {
    showNotification(
      title: title,
      message: message,
      type: InAppNotificationType.emergency,
      duration: const Duration(seconds: 6),
      onTap: onTap,
      data: {'emergency_id': emergencyId},
    );
  }

  /// Show volunteer status update notification
  void showVolunteerStatusNotification({
    required String volunteerName,
    required String status,
    required String emergencyId,
    VoidCallback? onTap,
  }) {
    showNotification(
      title: 'Volunteer Update',
      message: '$volunteerName: $status',
      type: InAppNotificationType.volunteer,
      duration: const Duration(seconds: 5),
      onTap: onTap,
      data: {
        'emergency_id': emergencyId,
        'volunteer_name': volunteerName,
        'status': status,
      },
    );
  }

  /// Show resolution notification
  void showResolutionNotification({
    required String title,
    required String message,
    required String emergencyId,
    bool isComplete = false,
  }) {
    showNotification(
      title: title,
      message: message,
      type: isComplete ? InAppNotificationType.success : InAppNotificationType.warning,
      duration: const Duration(seconds: 5),
      data: {
        'emergency_id': emergencyId,
        'is_complete': isComplete,
      },
    );
  }

  void dispose() {
    _notificationController.close();
  }
}

class InAppNotification {
  final String id;
  final String title;
  final String message;
  final InAppNotificationType type;
  final DateTime timestamp;
  final Duration duration;
  final VoidCallback? onTap;
  final Map<String, dynamic>? data;

  const InAppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.duration,
    this.onTap,
    this.data,
  });
}

enum InAppNotificationType {
  info,
  success,
  warning,
  error,
  emergency,
  volunteer,
}

extension InAppNotificationTypeExtension on InAppNotificationType {
  Color get color {
    switch (this) {
      case InAppNotificationType.info:
        return Colors.blue;
      case InAppNotificationType.success:
        return Colors.green;
      case InAppNotificationType.warning:
        return Colors.orange;
      case InAppNotificationType.error:
        return Colors.red;
      case InAppNotificationType.emergency:
        return Colors.red.shade700;
      case InAppNotificationType.volunteer:
        return Colors.purple;
    }
  }

  IconData get icon {
    switch (this) {
      case InAppNotificationType.info:
        return Icons.info;
      case InAppNotificationType.success:
        return Icons.check_circle;
      case InAppNotificationType.warning:
        return Icons.warning;
      case InAppNotificationType.error:
        return Icons.error;
      case InAppNotificationType.emergency:
        return Icons.emergency;
      case InAppNotificationType.volunteer:
        return Icons.volunteer_activism;
    }
  }
}
