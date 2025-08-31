import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/services/firestore_lock_service.dart';
import 'package:simha_link/screens/group_creation_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  const GroupInfoScreen({super.key, required this.groupId});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _firestore = FirebaseFirestore.instance;
  DocumentSnapshot<Map<String, dynamic>>? _groupDoc;
  bool _loading = true;
  User? _user;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    final doc = await _firestore.collection('groups').doc(widget.groupId).get();
    if (!mounted) return;
    setState(() {
      _groupDoc = doc;
      _loading = false;
    });
  }

  Future<void> _leaveGroup() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      if (_user == null) return;
      await UserPreferences.leaveGroupAndCleanup(widget.groupId, _user!.uid);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const GroupCreationScreen()), (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error leaving group: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteGroup() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final gid = widget.groupId;
      final groupRef = _firestore.collection('groups').doc(gid);
      final doc = await groupRef.get();
      final data = doc.data();
      final memberIds = <String>[];
      if (data != null && data['memberIds'] is List) {
        for (final m in List.from(data['memberIds'])) {
          if (m is String) memberIds.add(m);
        }
      }

      final batch = _firestore.batch();
      for (final mid in memberIds) {
        final userRef = _firestore.collection('users').doc(mid);
        batch.update(userRef, {'groupId': FieldValue.delete()});
      }
      batch.delete(groupRef);

      final ownerId = _user?.uid ?? 'system';
      final resourceId = 'group_op_${gid}';

      // Run the delete under an advisory lock to avoid races with other clients
      final res = await FirestoreLockService.runWithLock(resourceId, ownerId, () async {
        await batch.commit();
      }, ttlSeconds: 12);

      if (res == null) {
        throw Exception('Could not acquire lock to delete group $gid');
      }

      if (_user != null) {
        await UserPreferences.clearGroupData();
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (c) => const GroupCreationScreen()), (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting group: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLeader = _groupDoc?.data()?['leaderId'] == _user?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Group Info'), backgroundColor: Colors.red.shade800),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Group ID:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(widget.groupId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Text('Leader:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(_groupDoc?.data()?['leaderId'] ?? 'Unknown'),
                const SizedBox(height: 16),
                Text('Members:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if ((_groupDoc?.data()?['memberIds'] as List?)?.isNotEmpty ?? false)
                  ...List<Widget>.from(((_groupDoc?.data()?['memberIds'] as List).map((m) => Text(m.toString()))))
                else
                  const Text('No members found'),
                const Spacer(),
                FilledButton.tonal(onPressed: _leaveGroup, child: const Text('Leave Group')),
                const SizedBox(height: 12),
                if (isLeader)
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: _deleteGroup, child: const Text('Delete Group', style: TextStyle(color: Colors.white))),
              ]),
            ),
    );
  }
}
