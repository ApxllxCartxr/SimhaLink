import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simha_link/services/group_management_service.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/widgets/app_snackbar.dart';
import 'package:simha_link/widgets/loading_button.dart';

/// Bottom sheet showing comprehensive group information and management options
class GroupInfoBottomSheet extends StatefulWidget {
  final String groupId;
  final String currentUserRole;
  final VoidCallback? onGroupLeft;
  final VoidCallback? onGroupDeleted;
  final VoidCallback? onMemberKicked;

  const GroupInfoBottomSheet({
    super.key,
    required this.groupId,
    required this.currentUserRole,
    this.onGroupLeft,
    this.onGroupDeleted,
    this.onMemberKicked,
  });

  @override
  State<GroupInfoBottomSheet> createState() => _GroupInfoBottomSheetState();
}

class _GroupInfoBottomSheetState extends State<GroupInfoBottomSheet> {
  bool _showMembers = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Update member activity when viewing group info
    GroupManagementService.updateMemberActivity(widget.groupId);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: StreamBuilder<GroupInfo?>(
            stream: GroupManagementService.getGroupInfoStream(widget.groupId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _buildErrorView();
              }

              final groupInfo = snapshot.data;
              if (groupInfo == null) {
                return _buildNotFoundView();
              }

              return _buildGroupInfoContent(groupInfo, scrollController);
            },
          ),
        );
      },
    );
  }

  Widget _buildGroupInfoContent(GroupInfo groupInfo, ScrollController scrollController) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: _buildHeader(groupInfo),
        ),

        // Group Stats
        SliverToBoxAdapter(
          child: _buildGroupStats(groupInfo),
        ),

        // Members Section
        SliverToBoxAdapter(
          child: _buildMembersSection(groupInfo),
        ),

        // Members List (if expanded)
        if (_showMembers)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildMemberTile(groupInfo.members[index]),
              childCount: groupInfo.members.length,
            ),
          ),

        // Actions Section
        SliverToBoxAdapter(
          child: _buildActionsSection(groupInfo),
        ),

        // Bottom padding
        const SliverToBoxAdapter(
          child: SizedBox(height: 20),
        ),
      ],
    );
  }

  Widget _buildHeader(GroupInfo groupInfo) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Group icon and name
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Theme.of(context).primaryColor,
                child: const Icon(
                  Icons.group,
                  size: 30,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupInfo.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (groupInfo.description.isNotEmpty)
                      Text(
                        groupInfo.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupStats(GroupInfo groupInfo) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Group Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),

          // Group code with copy functionality (only show if join code exists)
          if (groupInfo.code.isNotEmpty) ...[
            _buildInfoRow(
              icon: Icons.qr_code,
              label: 'Join Code',
              value: groupInfo.code,
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copyGroupCode(groupInfo.code),
                tooltip: 'Copy join code',
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildInfoRow(
            icon: Icons.people,
            label: 'Total Members',
            value: '${groupInfo.totalMembers}/${groupInfo.maxMembers}',
          ),

          const SizedBox(height: 8),
          _buildInfoRow(
            icon: Icons.radio_button_checked,
            label: 'Active Now',
            value: groupInfo.activeMembers.toString(),
            valueColor: Colors.green,
          ),

          const SizedBox(height: 8),
          _buildInfoRow(
            icon: Icons.calendar_today,
            label: 'Created',
            value: _formatDate(groupInfo.createdAt),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection(GroupInfo groupInfo) {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline, size: 20),
              const SizedBox(width: 8),
              Text(
                'Members (${groupInfo.totalMembers})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _showMembers = !_showMembers),
                child: Text(_showMembers ? 'Hide' : 'Show All'),
              ),
            ],
          ),

          if (!_showMembers) ...[
            const SizedBox(height: 8),
            // Show first 3 members as preview
            ...groupInfo.members
                .take(3)
                .map((member) => _buildMemberPreview(member))
                .toList(),
            if (groupInfo.members.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 4),
                child: Text(
                  '+${groupInfo.members.length - 3} more members',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberPreview(GroupMember member) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: member.isOnline ? Colors.green : Colors.grey,
            child: Text(
              member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              member.name,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            member.roleDisplayName,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(GroupMember member) {
    final isOrganizer = widget.currentUserRole == 'Organizer';
    final canKick = isOrganizer && member.role != 'Organizer';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _getRoleColor(member.role),
                child: Text(
                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              if (member.isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  member.roleDisplayName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (member.lastSeen != null)
                  Text(
                    member.isOnline ? 'Online' : 'Last seen ${_getTimeAgo(member.lastSeen!)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: member.isOnline ? Colors.green : Colors.grey[500],
                    ),
                  ),
              ],
            ),
          ),

          if (canKick)
            PopupMenuButton<String>(
              onSelected: (action) => _handleMemberAction(action, member),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'change_role',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 16),
                      SizedBox(width: 8),
                      Text('Change Role'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'kick',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Remove', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              child: const Icon(Icons.more_vert),
            ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(GroupInfo groupInfo) {
    final isOrganizer = widget.currentUserRole == 'Organizer';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Leave Group Button
          OutlinedButton.icon(
            onPressed: _isLoading ? null : () => _showLeaveGroupDialog(groupInfo),
            icon: const Icon(Icons.exit_to_app, color: Colors.orange),
            label: const Text('Leave Group', style: TextStyle(color: Colors.orange)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.orange),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),

          if (isOrganizer) ...[
            const SizedBox(height: 12),
            // Delete Group Button (Organizers only)
            LoadingButton(
              onPressed: _isLoading ? null : () => _showDeleteGroupDialog(groupInfo),
              isLoading: _isLoading,
              color: Colors.red,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_forever, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Delete Group', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.grey[800],
              fontSize: 14,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildErrorView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red),
          SizedBox(height: 16),
          Text('Failed to load group information'),
          Text('Please try again later', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildNotFoundView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_off, size: 48, color: Colors.grey),
          SizedBox(height: 16),
          Text('Group not found'),
          Text('This group may have been deleted', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _copyGroupCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    AppSnackbar.showSuccess(context, 'Group code copied to clipboard');
  }

  void _handleMemberAction(String action, GroupMember member) {
    switch (action) {
      case 'change_role':
        _showChangeRoleDialog(member);
        break;
      case 'kick':
        _showKickMemberDialog(member);
        break;
    }
  }

  void _showChangeRoleDialog(GroupMember member) {
    final roles = ['Participant', 'Volunteer', 'VIP', 'Organizer'];
    String selectedRole = member.role;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Change Role for ${member.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: roles.map((role) => RadioListTile<String>(
              title: Text(role),
              value: role,
              groupValue: selectedRole,
              onChanged: (value) {
                if (value != null) {
                  setState(() => selectedRole = value);
                }
              },
            )).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedRole != member.role
                  ? () => _changeRole(member, selectedRole)
                  : null,
              child: const Text('Change Role'),
            ),
          ],
        ),
      ),
    );
  }

  void _showKickMemberDialog(GroupMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Are you sure you want to remove ${member.name} from this group? '
          'They will lose access immediately and need a new invite to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _kickMember(member),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLeaveGroupDialog(GroupInfo groupInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text(
          'Are you sure you want to leave "${groupInfo.name}"? '
          'You will lose access to the group chat and location sharing. '
          'You\'ll need a new invite to rejoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: _leaveGroup,
            child: const Text('Leave Group', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog(GroupInfo groupInfo) {
    final confirmationController = TextEditingController();
    bool canDelete = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete "${groupInfo.name}" and remove all ${groupInfo.totalMembers} members. '
                'This action cannot be undone.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text('Type "${groupInfo.name}" to confirm:'),
              const SizedBox(height: 8),
              TextField(
                controller: confirmationController,
                onChanged: (value) {
                  setState(() {
                    canDelete = value.trim() == groupInfo.name;
                  });
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Group name...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: canDelete ? _deleteGroup : null,
              child: const Text('Delete Group', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeRole(GroupMember member, String newRole) async {
    Navigator.pop(context); // Close dialog
    
    setState(() => _isLoading = true);
    
    try {
      final success = await GroupManagementService.changeMemberRole(
        widget.groupId,
        member.id,
        newRole,
      );

      if (mounted) {
        if (success) {
          AppSnackbar.showSuccess(context, '${member.name}\'s role changed to $newRole');
        } else {
          AppSnackbar.showError(context, 'Failed to change member role');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Error changing member role', e, stackTrace);
      if (mounted) {
        AppSnackbar.showError(context, 'An error occurred while changing the role');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _kickMember(GroupMember member) async {
    Navigator.pop(context); // Close dialog
    
    setState(() => _isLoading = true);
    
    try {
      final success = await GroupManagementService.kickMember(
        widget.groupId,
        member.id,
      );

      if (mounted) {
        if (success) {
          AppSnackbar.showSuccess(context, '${member.name} has been removed from the group');
          widget.onMemberKicked?.call();
        } else {
          AppSnackbar.showError(context, 'Failed to remove member');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Error kicking member', e, stackTrace);
      if (mounted) {
        AppSnackbar.showError(context, 'An error occurred while removing the member');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _leaveGroup() async {
    Navigator.pop(context); // Close dialog
    setState(() => _isLoading = true);
    
    try {
      final success = await GroupManagementService.leaveGroup(widget.groupId);

      if (mounted) {
        if (success) {
          AppSnackbar.showSuccess(context, 'You have left the group');
          Navigator.pop(context); // Close bottom sheet
          widget.onGroupLeft?.call();
        } else {
          AppSnackbar.showError(context, 'Failed to leave group');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Error leaving group', e, stackTrace);
      if (mounted) {
        AppSnackbar.showError(context, 'An error occurred while leaving the group');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteGroup() async {
    Navigator.pop(context); // Close dialog
    setState(() => _isLoading = true);
    
    try {
      final success = await GroupManagementService.deleteGroup(widget.groupId);

      if (mounted) {
        if (success) {
          AppSnackbar.showSuccess(context, 'Group has been deleted');
          Navigator.pop(context); // Close bottom sheet
          widget.onGroupDeleted?.call();
        } else {
          AppSnackbar.showError(context, 'Failed to delete group');
        }
      }
    } catch (e, stackTrace) {
      AppLogger.logError('Error deleting group', e, stackTrace);
      if (mounted) {
        AppSnackbar.showError(context, 'An error occurred while deleting the group');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'organizer':
        return Colors.purple;
      case 'volunteer':
        return Colors.blue;
      case 'vip':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
