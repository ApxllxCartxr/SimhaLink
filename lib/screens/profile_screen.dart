import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/services/auth_service.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/screens/group_info_screen.dart';
import 'package:simha_link/screens/auth_wrapper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  String? _groupId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    if (_user == null) return;
    final gid = await UserPreferences.getUserGroupId();
    if (!mounted) return;
    setState(() {
      _groupId = gid;
      _loading = false;
    });
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('You will be signed out of your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('LOGOUT')),
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
      builder: (c) => const AlertDialog(
        content: Row(
          children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Logging out...')],
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
    Navigator.push(context, MaterialPageRoute(builder: (c) => GroupInfoScreen(groupId: _groupId!))).then((_) => _loadGroup());
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _user?.displayName ?? _user?.email?.split('@').first ?? 'User';
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
                  ListTile(
                    tileColor: Colors.grey[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    subtitle: Text(email, style: const TextStyle(color: Colors.white70)),
                  ),
                  const SizedBox(height: 24),
                  Text('Group:', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: 8),
                  _groupId == null
                      ? Row(
                          children: [
                            const Text('Not in a group', style: TextStyle(color: Colors.white70)),
                            const SizedBox(width: 12),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () => Navigator.pushReplacement(
                                  context, MaterialPageRoute(builder: (c) => const GroupCreationScreen())),
                              child: const Text('Create / Join'),
                            )
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_groupId!, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
                            TextButton(
                              onPressed: _openGroupInfo,
                              style: TextButton.styleFrom(foregroundColor: Colors.white),
                              child: const Text('Group Info'),
                            )
                          ],
                        ),
                  const Spacer(),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.grey[900],
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _openGroupInfo,
                    child: const Text('Group Info'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: _handleLogout,
                    child: const Text('Logout'),
                  ),
                ],
              ),
            ),
    );
  }
}
