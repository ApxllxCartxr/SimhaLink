import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/services/auth_service.dart';
import 'package:simha_link/services/group_management_service.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/screens/group_info_screen.dart';
import 'package:simha_link/screens/auth_wrapper.dart';
import 'package:simha_link/core/utils/app_logger.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  String? _groupId;
  String? _groupName;
  String? _userRole;
  String? _displayName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (_user == null) return;
    
    try {
      // Load group ID from preferences
      final groupId = await UserPreferences.getUserGroupId();
      
      // Fetch user data from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();
      
      String? userRole;
      String? displayName;
      
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        userRole = userData['role'] as String?;
        displayName = userData['displayName'] as String?;
      }
      
      // Fetch group name if user is in a group
      String? groupName;
      if (groupId != null) {
        try {
          final groupInfo = await GroupManagementService.getGroupInfo(groupId);
          groupName = groupInfo?.name;
        } catch (e) {
          AppLogger.logError('Error fetching group info', e);
        }
      }
      
      if (!mounted) return;
      setState(() {
        _groupId = groupId;
        _groupName = groupName;
        _userRole = userRole ?? 'Participant';
        _displayName = displayName ?? _user?.displayName;
        _loading = false;
      });
    } catch (e) {
      AppLogger.logError('Error loading user data', e);
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Logout?', style: TextStyle(color: Colors.white)),
        content: const Text('You will be signed out of your account.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false), 
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70))
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('LOGOUT')
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Capture a root navigator context synchronously so we can safely
    // dismiss the modal and navigate even if this State is unmounted
    // by auth state listeners during sign-out.
    final BuildContext rootNavContext = Navigator.of(context, rootNavigator: true).context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: const Row(
          children: [
            CircularProgressIndicator(color: Colors.white), 
            SizedBox(width: 20), 
            Text('Logging out...', style: TextStyle(color: Colors.white))
          ],
        ),
      ),
    );

    try {
      await AuthService().signOut();

      // Use the saved root navigator context to pop the dialog and navigate
      Navigator.of(rootNavContext).pop();
      Navigator.of(rootNavContext).pushAndRemoveUntil(
        MaterialPageRoute(builder: (ctx) => const AuthWrapper()),
        (_) => false,
      );
    } catch (e) {
      // Ensure dialog is dismissed even if this State is gone.
      try {
        Navigator.of(rootNavContext).pop();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error logging out: $e')));
      } else {
        // Fallback: use root context to show an error if possible.
        try {
          ScaffoldMessenger.of(rootNavContext).showSnackBar(SnackBar(content: Text('Error logging out: $e')));
        } catch (_) {}
      }
    }
  }

  void _openGroupInfo() {
    if (_groupId == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const GroupCreationScreen()));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (c) => GroupInfoScreen(groupId: _groupId!))).then((_) => _loadUserData());
  }

  Future<void> _handleLeaveGroup() async {
    if (_groupId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Leave Group?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to leave "${_groupName ?? _groupId}"? You will lose access to group messages and locations.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('LEAVE GROUP'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: const Row(
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(width: 20),
            Text('Leaving group...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final user = _user;
      if (user == null) {
        Navigator.of(context).pop(); // Dismiss loading dialog
        return;
      }

      // Use the same method as working implementations
      await UserPreferences.leaveGroupAndCleanup(_groupId!, user.uid);
      
      // Dismiss loading dialog
      Navigator.of(context).pop();
      
      // Reload user data to update UI
      _loadUserData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have left the group. Restarting app...'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate back to AuthWrapper to restart the app flow with updated group status
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (ctx) => const AuthWrapper()),
            (route) => false,
          );
        }
      });
    } catch (e) {
      // Dismiss loading dialog
      Navigator.of(context).pop();
      
      AppLogger.logError('Error leaving group', e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error leaving group: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _displayName ?? _user?.displayName ?? _user?.email?.split('@').first ?? 'User';
    final email = _user?.email ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Profile Card
                  Card(
                    color: Colors.grey[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(email, style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getRoleColor(_userRole ?? 'Participant'),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _userRole ?? 'Participant',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Group Section
                  Text('Group:', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.grey[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _groupId == null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Not in a group', style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                    ),
                                    onPressed: () => Navigator.pushReplacement(
                                        context, MaterialPageRoute(builder: (c) => const GroupCreationScreen())),
                                    child: const Text('Create / Join Group'),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Group: ${_groupName ?? _groupId}',
                                  style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white, fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _openGroupInfo,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: const BorderSide(color: Colors.white70),
                                        ),
                                        child: const Text('Group Info'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                        ),
                                        onPressed: _handleLeaveGroup,
                                        child: const Text('Leave Group'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Centered Logout Button
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _handleLogout,
                        child: const Text('Logout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'organizer':
        return Colors.purple;
      case 'volunteer':
        return Colors.green;
      case 'vip':
        return Colors.orange;
      case 'participant':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
