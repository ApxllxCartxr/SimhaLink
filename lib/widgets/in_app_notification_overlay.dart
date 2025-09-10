import 'dart:async';
import 'package:flutter/material.dart';
import 'package:simha_link/services/in_app_notification_service.dart';

/// Overlay widget to display in-app notifications at the top of the screen
class InAppNotificationOverlay extends StatefulWidget {
  final Widget child;

  const InAppNotificationOverlay({
    super.key,
    required this.child,
  });

  @override
  State<InAppNotificationOverlay> createState() => _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay>
    with TickerProviderStateMixin {
  StreamSubscription<InAppNotification>? _notificationSubscription;
  final List<_NotificationItem> _activeNotifications = [];

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    _notificationSubscription = InAppNotificationService.instance.notificationStream
        .listen((notification) {
      _showNotification(notification);
    });
  }

  void _showNotification(InAppNotification notification) {
    final animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    final item = _NotificationItem(
      notification: notification,
      controller: animationController,
    );

    setState(() {
      _activeNotifications.add(item);
    });

    // Start animation
    animationController.forward();

    // Auto-dismiss after duration
    Timer(notification.duration, () {
      _dismissNotification(item);
    });
  }

  void _dismissNotification(_NotificationItem item) {
    if (!_activeNotifications.contains(item)) return;

    item.controller.reverse().then((_) {
      if (mounted) {
        setState(() {
          _activeNotifications.remove(item);
        });
        item.controller.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          widget.child,
          // Notification overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Column(
              children: _activeNotifications
                  .map((item) => _buildNotificationCard(item))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(_NotificationItem item) {
    return AnimatedBuilder(
      animation: item.controller,
      builder: (context, child) {
        final slideAnimation = Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: item.controller,
          curve: Curves.easeInOut,
        ));

        final fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: item.controller,
          curve: Curves.easeInOut,
        ));

        return SlideTransition(
          position: slideAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: _NotificationCard(
                notification: item.notification,
                onDismiss: () => _dismissNotification(item),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    for (final item in _activeNotifications) {
      item.controller.dispose();
    }
    super.dispose();
  }
}

class _NotificationItem {
  final InAppNotification notification;
  final AnimationController controller;

  _NotificationItem({
    required this.notification,
    required this.controller,
  });
}

class _NotificationCard extends StatelessWidget {
  final InAppNotification notification;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        notification.onTap?.call();
        onDismiss();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notification.type.color,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: notification.type.color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                notification.type.icon,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
