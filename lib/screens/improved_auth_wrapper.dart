import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/screens/auth_screen.dart';
import 'package:simha_link/screens/map_screen.dart';
import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/widgets/loading_widgets.dart';
import 'dart:async';

class ImprovedAuthWrapper extends StatefulWidget {
  const ImprovedAuthWrapper({super.key});

  @override
  State<ImprovedAuthWrapper> createState() => _ImprovedAuthWrapperState();
}

class _ImprovedAuthWrapperState extends State<ImprovedAuthWrapper> {
  StreamSubscription<User?>? _authSubscription;
  User? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initAuthListener();
  }

  void _initAuthListener() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (User? user) {
        debugPrint('🔄 ImprovedAuthWrapper: Auth state changed - ${user?.uid ?? 'null'}');
        if (mounted) {
          setState(() {
            _currentUser = user;
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        debugPrint('❌ ImprovedAuthWrapper: Auth stream error - $error');
        if (mounted) {
          setState(() {
            _currentUser = null;
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: LoadingWidget(
          message: 'Checking authentication...',
        ),
      );
    }

    if (_currentUser != null) {
      // User is authenticated, check if they have a group
      debugPrint('👤 ImprovedAuthWrapper: User authenticated, checking group...');
      return FutureBuilder<String?>(
        future: _checkUserGroupAndRole(_currentUser!),
        builder: (context, groupSnapshot) {
          if (groupSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: LoadingWidget(
                message: 'Loading your group...',
              ),
            );
          }
          
          final groupId = groupSnapshot.data;
          
          // If user has no group, show group creation screen
          if (groupId == null) {
            debugPrint('🎯 ImprovedAuthWrapper: No group found, showing group creation');
            return const GroupCreationScreen();
          }
          
          // User has a group, show map screen
          debugPrint('🗺️ ImprovedAuthWrapper: Group found ($groupId), showing map');
          return MapScreen(groupId: groupId);
        },
      );
    }
    
    // User is not authenticated, show auth screen
    debugPrint('🚪 ImprovedAuthWrapper: User not authenticated, showing auth screen');
    return const AuthScreen();
  }

  Future<String?> _checkUserGroupAndRole(User user) async {
    try {
      // Add retry logic for new users - sometimes Firestore write hasn't completed
      DocumentSnapshot? userDoc;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (retryCount < maxRetries) {
        userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
            
        if (userDoc.exists) {
          break;
        }
        
        retryCount++;
        if (retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }

      if (userDoc != null && userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final userRole = userData['role'] as String?;

        // Handle different roles with specific logic
        if (userRole == 'Volunteer') {
          final groupId = await _ensureSpecialGroupExists('volunteers', 'Volunteers');
          await UserPreferences.setUserGroupId(groupId);
          await _addUserToGroup(groupId, user.uid);
          return groupId;
        } else if (userRole == 'Organizer') {
          final groupId = await _ensureSpecialGroupExists('organizers', 'Organizers');
          await UserPreferences.setUserGroupId(groupId);
          await _addUserToGroup(groupId, user.uid);
          return groupId;
        } else if (userRole == 'Attendee') {
          // Check if attendee has a saved group preference
          final savedGroupId = await UserPreferences.getUserGroupId();
          
          if (savedGroupId != null && savedGroupId.isNotEmpty) {
            // Verify the group still exists and user is still a member
            try {
              final groupDoc = await FirebaseFirestore.instance
                  .collection('groups')
                  .doc(savedGroupId)
                  .get();
              
              if (groupDoc.exists) {
                final groupData = groupDoc.data() as Map<String, dynamic>;
                final memberIds = List<String>.from(groupData['memberIds'] ?? []);
                
                if (memberIds.contains(user.uid)) {
                  // User is still a valid member
                  return savedGroupId;
                } else {
                  // User was removed from group, clear their data and let them choose a new one
                  await UserPreferences.clearGroupData();
                  return null; // Will show group creation screen
                }
              } else {
                // Group no longer exists, clear data
                await UserPreferences.clearGroupData();
                return null; // Will show group creation screen
              }
            } catch (e) {
              debugPrint('Error checking attendee group status: $e');
              // On error, let user choose a new group instead of blocking them
              await UserPreferences.clearGroupData();
              return null;
            }
          }
          
          // Attendee has no valid group, show group creation screen
          return null;
        }
      }

      // User has no role document, show group creation screen
      return null;
    } catch (e) {
      // On error, try to recover saved group instead of clearing
      final savedGroupId = await UserPreferences.getUserGroupId();
      return savedGroupId; // Return saved group or null if none exists
    }
  }

  Future<String> _ensureSpecialGroupExists(String groupId, String groupName) async {
    final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);
    final groupDoc = await groupRef.get();

    if (!groupDoc.exists) {
      // Create the special group
      await groupRef.set({
        'id': groupId,
        'name': groupName,
        'type': 'special', // Mark as special group
        'createdAt': FieldValue.serverTimestamp(),
        'memberIds': [],
        'joinCode': '', // Special groups don't need join codes
      });
    }

    return groupId;
  }

  Future<void> _addUserToGroup(String groupId, String userId) async {
    try {
      // Check if user is already a member to avoid unnecessary updates
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();

      if (groupDoc.exists) {
        final groupData = groupDoc.data() as Map<String, dynamic>;
        final memberIds = List<String>.from(groupData['memberIds'] ?? []);
        
        // Only add if not already a member
        if (!memberIds.contains(userId)) {
          await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .update({
            'memberIds': FieldValue.arrayUnion([userId])
          });
        }
      }
    } catch (e) {
      // If the group doesn't exist, create it (for special groups)
      if (groupId == 'volunteers' || groupId == 'organizers') {
        await _ensureSpecialGroupExists(groupId, groupId == 'volunteers' ? 'Volunteers' : 'Organizers');
        // Retry adding user
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .update({
          'memberIds': FieldValue.arrayUnion([userId])
        });
      } else {
        print('Error adding user to group: $e');
      }
    }
  }
}
