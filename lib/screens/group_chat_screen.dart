import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../config/app_colors.dart';
import '../core/utils/app_logger.dart';
import '../screens/group_info_bottom_sheet.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;

  const GroupChatScreen({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String _userRole = '';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists && mounted) {
          setState(() {
            _userRole = userDoc.data()?['role'] ?? 'Participant';
          });
        }
      }
    } catch (e) {
      AppLogger.logError('Error loading user role', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('Group Chat'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showGroupInfo,
            icon: const Icon(Icons.info_outline),
            tooltip: 'Group Information',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc(widget.groupId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Something went wrong'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index].data() as Map<String, dynamic>;
                    final isCurrentUser = message['userId'] == 
                        FirebaseAuth.instance.currentUser?.uid;

                    return Align(
                      alignment: isCurrentUser 
                          ? Alignment.centerRight 
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isCurrentUser ? AppColors.chatBubbleUser : AppColors.chatBubbleOther,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadow,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message['userName'] ?? AuthService.getUserDisplayName(FirebaseAuth.instance.currentUser),
                              style: TextStyle(
                                color: isCurrentUser ? AppColors.textOnPrimary.withOpacity(0.8) : AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              message['text'],
                              style: TextStyle(
                                color: isCurrentUser ? AppColors.chatTextUser : AppColors.chatTextOther,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.backgroundLight,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: AppColors.textHint),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send),
                    color: AppColors.textOnPrimary,
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .add({
      'text': _messageController.text.trim(),
      'userId': user.uid,
      'userName': AuthService.getUserDisplayName(user),
      'timestamp': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupInfoBottomSheet(
        groupId: widget.groupId,
        currentUserRole: _userRole,
        onGroupLeft: _handleGroupLeft,
        onGroupDeleted: _handleGroupDeleted,
        onMemberKicked: _handleMemberKicked,
      ),
    );
  }

  void _handleGroupLeft() {
    // Navigate back to main screen or group selection
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _handleGroupDeleted() {
    // Navigate back to main screen or group selection
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _handleMemberKicked() {
    // Refresh the chat or show notification
    // The UI will automatically update through streams
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}