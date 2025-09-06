import 'package:flutter/material.dart';
import '../../../models/feed_post.dart';
import '../../../models/user_profile.dart';

class FeedPostWidget extends StatelessWidget {
  final FeedPost post;
  final UserProfile currentUser;
  final Function(FeedPost) onEdit;
  final Function(FeedPost) onDelete;
  final Function(FeedPost) onTap;
  final Function(FeedPost)? onReply;

  const FeedPostWidget({
    super.key,
    required this.post,
    required this.currentUser,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final isOwner = post.userId == currentUser.uid;
    final canReply = _canCurrentUserReply();
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => onTap(post),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: post.userName.isNotEmpty 
                        ? null 
                        : const AssetImage('assets/images/default_avatar.png'),
                    child: post.userName.isNotEmpty 
                        ? Text(post.userName[0].toUpperCase())
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              post.userName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(width: 8),
                            _buildRoleBadge(context),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                post.locationName ?? 'Unknown location',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions menu
                  if (isOwner)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit(post);
                            break;
                          case 'delete':
                            onDelete(post);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete),
                              SizedBox(width: 8),
                              Text('Delete'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Content
              Text(
                post.content,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              
              const SizedBox(height: 8),
              
              // Hashtags
              if (post.hashtags.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: post.hashtags.map((hashtag) => Chip(
                    label: Text('#$hashtag'),
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    labelStyle: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 12,
                    ),
                  )).toList(),
                ),
              
              const SizedBox(height: 12),
              
              // Footer with reply button
              Row(
                children: [
                  Text(
                    _formatTimeAgo(post.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (post.isEdited) ...[
                    const SizedBox(width: 8),
                    Text(
                      '• edited',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const Spacer(),
                  // Reply count and button
                  if (post.replyCount > 0) ...[
                    Icon(
                      Icons.comment_outlined,
                      size: 16,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.replyCount}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                  ],
                  // Reply button for volunteers/organizers
                  if (canReply && onReply != null)
                    TextButton.icon(
                      onPressed: () => onReply!(post),
                      icon: const Icon(Icons.reply, size: 16),
                      label: const Text('Reply'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
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

  Widget _buildRoleBadge(BuildContext context) {
    final UserRole role = UserRole.fromString(post.userRole);
    Color badgeColor;
    IconData icon;

    switch (role) {
      case UserRole.organizer:
        badgeColor = Colors.purple;
        icon = Icons.admin_panel_settings;
        break;
      case UserRole.volunteer:
        badgeColor = Colors.blue;
        icon = Icons.volunteer_activism;
        break;
      case UserRole.vip:
        badgeColor = Colors.amber;
        icon = Icons.star;
        break;
      case UserRole.participant:
        badgeColor = Colors.green;
        icon = Icons.person;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: badgeColor,
          ),
          const SizedBox(width: 4),
          Text(
            role.displayName,
            style: TextStyle(
              fontSize: 10,
              color: badgeColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  bool _canCurrentUserReply() {
    return currentUser.role == UserRole.volunteer || 
           currentUser.role == UserRole.organizer;
  }

  String _formatTimeAgo(DateTime dateTime) {
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
