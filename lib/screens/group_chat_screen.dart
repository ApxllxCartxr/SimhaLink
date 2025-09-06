import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../config/app_colors.dart';
import '../core/utils/app_logger.dart';
import '../screens/group_info_bottom_sheet.dart';
import '../screens/group_creation_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final String? groupId; // Made nullable for solo mode

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
    print('[DEBUG] GroupChatScreen: initState called with groupId: ${widget.groupId}');
    
    // Only load user role and check group if not in solo mode
    if (widget.groupId != null) {
      _loadUserRole();
      _checkGroupExists();
    } else {
      print('[DEBUG] GroupChatScreen: In solo mode, skipping group checks');
    }
  }

  Future<void> _checkGroupExists() async {
    if (widget.groupId == null) return;
    
    print('[DEBUG] GroupChatScreen: Checking if group exists...');
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId!)
          .get();
      
      print('[DEBUG] GroupChatScreen: Group exists: ${groupDoc.exists}');
      if (groupDoc.exists) {
        final groupData = groupDoc.data();
        print('[DEBUG] GroupChatScreen: Group data: $groupData');
      } else {
        print('[WARNING] GroupChatScreen: Group does not exist!');
      }
    } catch (e) {
      print('[ERROR] GroupChatScreen: Error checking group: $e');
    }
  }

  Future<void> _loadUserRole() async {
    print('[DEBUG] GroupChatScreen: Starting _loadUserRole()');
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        print('[DEBUG] GroupChatScreen: User found: ${user.uid}');
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        print('[DEBUG] GroupChatScreen: User doc exists: ${userDoc.exists}');
        if (userDoc.exists && mounted) {
          final role = userDoc.data()?['role'] ?? 'Participant';
          print('[DEBUG] GroupChatScreen: User role: $role');
          setState(() {
            _userRole = role;
          });
        } else if (!userDoc.exists) {
          print('[WARNING] GroupChatScreen: User document does not exist');
        }
      } else {
        print('[WARNING] GroupChatScreen: No current user');
      }
    } catch (e) {
      print('[ERROR] GroupChatScreen: Error loading user role: $e');
      AppLogger.logError('Error loading user role', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If in solo mode, show join/create group UI
    if (widget.groupId == null) {
      return _buildSoloModeUI();
    }

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
                  .doc(widget.groupId!)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                print('[DEBUG] GroupChatScreen: StreamBuilder state - hasError: ${snapshot.hasError}, hasData: ${snapshot.hasData}, connectionState: ${snapshot.connectionState}');
                
                if (snapshot.hasError) {
                  print('[ERROR] GroupChatScreen: Stream error: ${snapshot.error}');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Error loading messages: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {}); // Trigger rebuild
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  print('[DEBUG] GroupChatScreen: Waiting for data...');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text('Loading messages...'),
                        const SizedBox(height: 8),
                        Text('Group: ${widget.groupId}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  print('[DEBUG] GroupChatScreen: No data available');
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Connecting to group chat...'),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!.docs;
                print('[DEBUG] GroupChatScreen: Loaded ${messages.length} messages');

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

  Widget _buildSoloModeUI() {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        title: const Text('Chat'),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                'You\'re in Solo Mode',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Join or create a group to start chatting with others!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToGroupCreation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.group_add),
                  label: const Text('Join or Create Group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToGroupCreation() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const GroupCreationScreen(),
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || widget.groupId == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId!)
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
    if (widget.groupId == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GroupInfoBottomSheet(
        groupId: widget.groupId!,
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