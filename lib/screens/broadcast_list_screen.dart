import 'package:flutter/material.dart';
import 'package:simha_link/models/broadcast_message.dart';
import 'package:simha_link/services/broadcast_service.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/widgets/app_snackbar.dart';
import 'package:simha_link/screens/broadcast_compose_screen.dart';
import 'package:simha_link/utils/role_utils.dart';

/// Screen showing broadcast messages for current user
class BroadcastListScreen extends StatefulWidget {
  const BroadcastListScreen({super.key});

  @override
  State<BroadcastListScreen> createState() => _BroadcastListScreenState();
}

class _BroadcastListScreenState extends State<BroadcastListScreen> {
  bool _isOrganizer = false;

  @override
  void initState() {
    super.initState();
    _checkOrganizerPermission();
  }

  Future<void> _checkOrganizerPermission() async {
    try {
      final isOrganizer = await RoleUtils.isUserOrganizer();
      if (mounted) {
        setState(() {
          _isOrganizer = isOrganizer;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Error checking organizer permission', e, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Broadcasts'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Only show compose button for organizers
          if (_isOrganizer)
            IconButton(
              onPressed: _navigateToCompose,
              icon: const Icon(Icons.add),
              tooltip: 'Send Broadcast',
            ),
        ],
      ),
      body: StreamBuilder<List<BroadcastMessage>>(
        stream: BroadcastService.getBroadcastStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            AppLogger.logError('Error loading broadcasts', snapshot.error, snapshot.stackTrace);
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load broadcasts',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final broadcasts = snapshot.data ?? [];

          if (broadcasts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.campaign_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No broadcasts yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isOrganizer 
                        ? 'Tap the + button to send a broadcast'
                        : 'Organizers can send announcements here',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: broadcasts.length,
            itemBuilder: (context, index) {
              final broadcast = broadcasts[index];
              return BroadcastCard(
                broadcast: broadcast,
                onTap: () => _markAsReadAndShowDetails(broadcast),
              );
            },
          );
        },
      ),
      floatingActionButton: _isOrganizer ? FloatingActionButton(
        onPressed: _navigateToCompose,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  Future<void> _navigateToCompose() async {
    try {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => const BroadcastComposeScreen(),
        ),
      );

      if (result == true && mounted) {
        // Broadcast was sent successfully - stream will auto-update
        AppSnackbar.showSuccess(context, 'Broadcast sent successfully!');
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Error navigating to compose screen', e, stackTrace);
      if (mounted) {
        AppSnackbar.showError(context, 'Unable to open compose screen');
      }
    }
  }

  Future<void> _markAsReadAndShowDetails(BroadcastMessage broadcast) async {
    // Mark as read
    await BroadcastService.markAsRead(broadcast.id);

    // Show details in bottom sheet
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => BroadcastDetailSheet(broadcast: broadcast),
      );
    }
  }
}

/// Card widget for displaying broadcast message in list
class BroadcastCard extends StatelessWidget {
  final BroadcastMessage broadcast;
  final VoidCallback onTap;

  const BroadcastCard({
    super.key,
    required this.broadcast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final timeAgo = _getTimeAgo(broadcast.createdAt);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with priority and time
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: broadcast.priority.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getPriorityIcon(broadcast.priority),
                          size: 12,
                          color: broadcast.priority.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          broadcast.priority.displayName,
                          style: TextStyle(
                            color: broadcast.priority.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title
              Text(
                broadcast.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),

              // Content preview
              Text(
                broadcast.content,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Footer with sender and target
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${broadcast.senderName} (${broadcast.senderRole})',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      broadcast.target.displayName,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getPriorityIcon(BroadcastPriority priority) {
    switch (priority) {
      case BroadcastPriority.low:
        return Icons.info_outline;
      case BroadcastPriority.normal:
        return Icons.notifications_outlined;
      case BroadcastPriority.high:
        return Icons.priority_high_outlined;
      case BroadcastPriority.urgent:
        return Icons.warning_outlined;
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

/// Bottom sheet for showing broadcast details
class BroadcastDetailSheet extends StatelessWidget {
  final BroadcastMessage broadcast;

  const BroadcastDetailSheet({
    super.key,
    required this.broadcast,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Priority badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: broadcast.priority.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: broadcast.priority.color.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      broadcast.priority == BroadcastPriority.urgent
                          ? Icons.warning
                          : Icons.info_outline,
                      size: 16,
                      color: broadcast.priority.color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      broadcast.priority.displayName,
                      style: TextStyle(
                        color: broadcast.priority.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                broadcast.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        broadcast.content,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Metadata
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMetadataRow(
                              icon: Icons.person,
                              label: 'From',
                              value: '${broadcast.senderName} (${broadcast.senderRole})',
                            ),
                            const SizedBox(height: 8),
                            _buildMetadataRow(
                              icon: Icons.group,
                              label: 'To',
                              value: broadcast.target.displayName,
                            ),
                            const SizedBox(height: 8),
                            _buildMetadataRow(
                              icon: Icons.access_time,
                              label: 'Sent',
                              value: _formatDateTime(broadcast.createdAt),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Close button
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.grey[800],
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final isToday = dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;

    final timeStr = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    if (isToday) {
      return 'Today at $timeStr';
    }

    final dayStr = '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    return '$dayStr at $timeStr';
  }
}
