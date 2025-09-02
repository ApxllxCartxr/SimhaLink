import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/screens/main_navigation_screen.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/services/state_sync_service.dart';

class GroupCreationScreen extends StatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  State<GroupCreationScreen> createState() => _GroupCreationScreenState();
}

class _GroupCreationScreenState extends State<GroupCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  final _joinCodeController = TextEditingController();
  bool _isLoading = false;
  int _selectedTab = 0; // 0 = Create, 1 = Join

  @override
  void dispose() {
    _groupNameController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Generate a unique group ID
      final groupRef = FirebaseFirestore.instance.collection('groups').doc();
      final groupId = groupRef.id;
      final joinCode = _generateJoinCode();

      // Create the group
      await groupRef.set({
        'id': groupId,
        'name': _groupNameController.text.trim(),
        'type': 'custom',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'memberIds': [user.uid],
        'joinCode': joinCode,
      });

      // Set this as the user's current group
      await UserPreferences.setUserGroupId(groupId);

      // Force state synchronization after group creation
      await StateSyncService.forceSyncState();

      // Update user document to ensure they can join/create groups
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'canJoinGroups': true,
        'lastCreatedGroup': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        // Show join code dialog before navigating to map
        _showJoinCodeDialog(_groupNameController.text.trim(), joinCode, groupId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _joinGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Find group with the join code
      final querySnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('joinCode', isEqualTo: _joinCodeController.text.trim().toUpperCase())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception('Invalid join code');
      }

      final groupDoc = querySnapshot.docs.first;
      final groupId = groupDoc.id;
      final groupData = groupDoc.data() as Map<String, dynamic>;

      // Check if user is already in the group
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);
      
      if (memberIds.contains(user.uid)) {
        // User is already in this group, just set it as active
        await UserPreferences.setUserGroupId(groupId);
        
        // Force state synchronization after reactivating group
        await StateSyncService.forceSyncState();
      } else {
        // Add user to the group
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .update({
          'memberIds': FieldValue.arrayUnion([user.uid])
        });

        // Set this as the user's current group
        await UserPreferences.setUserGroupId(groupId);

        // Force state synchronization after joining group
        await StateSyncService.forceSyncState();

        // Update user document to mark they can join groups (clear any restrictions)
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'canJoinGroups': true,
          'lastJoinedGroup': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => MainNavigationScreen(groupId: groupId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error joining group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _skipAndUseSoloMode() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Create a default group for solo mode
      final groupId = await UserPreferences.createDefaultGroupIfNeeded();
      if (groupId != null) {
        await UserPreferences.setUserGroupId(groupId);
        
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MainNavigationScreen(groupId: groupId),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error setting up solo mode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showJoinCodeDialog(String groupName, String joinCode, String groupId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Group Created!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your group "$groupName" has been created successfully!'),
              const SizedBox(height: 16),
              Text(
                'Share this join code with others:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        joinCode,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: joinCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Join code copied to clipboard!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Others can use this code to join your group.',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MainNavigationScreen(groupId: groupId),
                  ),
                );
              },
              child: const Text('Continue to Map'),
            ),
          ],
        );
      },
    );
  }

  String _generateJoinCode() {
    // Generate a 6-character alphanumeric code
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    String result = '';
    final random = DateTime.now().millisecondsSinceEpoch;
    
    for (int i = 0; i < 6; i++) {
      result += chars[(random + i * 7) % chars.length];
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo and Title
                const Text(
                  'Join or Create a Group',
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create your own group or join an existing one',
                  style: TextStyle(
                    fontFamily: 'InstrumentSerif',
                    color: Colors.black54,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 48),
                
                // Group Creation/Join Container
                Container(
                  width: 400,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Tab Selection
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: _selectedTab == 0 ? Colors.black : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Create Group',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _selectedTab == 0 ? Colors.black : Colors.black54,
                                    fontWeight: _selectedTab == 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: _selectedTab == 1 ? Colors.black : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Join Group',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _selectedTab == 1 ? Colors.black : Colors.black54,
                                    fontWeight: _selectedTab == 1 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Form
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (_selectedTab == 0) ...[
                              // Create Group Form
                              TextFormField(
                                controller: _groupNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Group Name',
                                  prefixIcon: Icon(Icons.group),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a group name';
                                  }
                                  if (value.trim().length < 3) {
                                    return 'Group name must be at least 3 characters';
                                  }
                                  return null;
                                },
                              ),
                            ] else ...[
                              // Join Group Form
                              TextFormField(
                                controller: _joinCodeController,
                                decoration: const InputDecoration(
                                  labelText: 'Join Code',
                                  prefixIcon: Icon(Icons.key),
                                  border: OutlineInputBorder(),
                                  hintText: 'Enter 6-character code',
                                ),
                                textCapitalization: TextCapitalization.characters,
                                maxLength: 6,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a join code';
                                  }
                                  if (value.trim().length != 6) {
                                    return 'Join code must be 6 characters';
                                  }
                                  return null;
                                },
                              ),
                            ],
                            const SizedBox(height: 24),
                            
                            // Action Button
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading 
                                    ? null 
                                    : (_selectedTab == 0 ? _createGroup : _joinGroup),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : Text(_selectedTab == 0 ? 'Create Group' : 'Join Group'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Skip button for solo mode
                TextButton(
                  onPressed: _isLoading ? null : _skipAndUseSoloMode,
                  child: const Text(
                    'Skip - Use Solo Mode',
                    style: TextStyle(
                      color: Colors.black54,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
