import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/screens/auth_screen.dart';
import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/screens/main_navigation_screen.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/services/state_sync_service.dart';
import 'package:simha_link/widgets/loading_widgets.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Debug auth state changes
        debugPrint('🔄 AuthWrapper: Auth state changed - ${snapshot.data?.uid ?? 'null'}');
        
        // CRITICAL: If user is null, immediately show auth screen without waiting
        // This ensures fast response to logout events
        if (snapshot.data == null) {
          debugPrint('🚪 AuthWrapper: User not authenticated, showing auth screen immediately');
          return const AuthScreen();
        }
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: LoadingWidget(
              message: 'Checking authentication...',
            ),
          );
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          // User is authenticated, check if they have a group
          debugPrint('👤 AuthWrapper: User authenticated, checking group...');
          return FutureBuilder<String?>(
            future: _checkUserGroupAndRole(snapshot.data!),
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
                debugPrint('🎯 AuthWrapper: No group found, showing group creation');
                return const GroupCreationScreen();
              }
              
              // User has a group, show main navigation screen with map
              debugPrint('🗺️ AuthWrapper: Group found ($groupId), showing navigation');
              return MainNavigationScreen(groupId: groupId);
            },
          );
        }
        
        // User is not authenticated, show auth screen
        debugPrint('🚪 AuthWrapper: User not authenticated, showing auth screen');
        return const AuthScreen();
      },
    );
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

        debugPrint('🔍 AuthWrapper: User ${user.uid} has role: $userRole');

        // Check and fix users who were incorrectly assigned to shared default_group
        await UserPreferences.migrateFromSharedDefaultGroup();

        // Initialize state synchronization
        await StateSyncService.initialize();

        // IMPORTANT: Clear any local group preferences that don't match the user's role
        // This prevents cross-user group contamination
        final currentLocalGroupId = await UserPreferences.getUserGroupId();
        debugPrint('📱 AuthWrapper: Local group ID: $currentLocalGroupId');

        // Handle different roles with specific logic
        if (userRole == 'Volunteer') {
          final correctGroupId = 'volunteers';
          // If local group doesn't match role, clear it
          if (currentLocalGroupId != null && currentLocalGroupId != correctGroupId) {
            debugPrint('🔄 AuthWrapper: Clearing incorrect local group for Volunteer');
            await UserPreferences.clearGroupData();
          }
          
          final groupId = await _ensureSpecialGroupExists('volunteers', 'Volunteers');
          await UserPreferences.setUserGroupId(groupId);
          await _addUserToGroup(groupId, user.uid);
          return groupId;
        } else if (userRole == 'Organizer') {
          final correctGroupId = 'organizers';
          // If local group doesn't match role, clear it
          if (currentLocalGroupId != null && currentLocalGroupId != correctGroupId) {
            debugPrint('🔄 AuthWrapper: Clearing incorrect local group for Organizer');
            await UserPreferences.clearGroupData();
          }
          
          final groupId = await _ensureSpecialGroupExists('organizers', 'Organizers');
          await _addUserToGroup(groupId, user.uid);
          return groupId;
        } else if (userRole == 'Attendee') {
          // For attendees, validate that any local group assignment is appropriate
          // If they have a volunteer/organizer group cached, clear it
          if (currentLocalGroupId == 'volunteers' || currentLocalGroupId == 'organizers') {
            debugPrint('🔄 AuthWrapper: Clearing special role group for Attendee');
            await UserPreferences.clearGroupData();
          }
          
          // Check if attendee has a valid saved group preference
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
                  // Re-save the group ID to ensure it's stored correctly
                  await UserPreferences.setUserGroupId(savedGroupId);
                  debugPrint('✅ AuthWrapper: Verified and re-saved group ID: $savedGroupId');
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
      debugPrint('Error in _checkUserGroupAndRole: $e');
      // On error, try to recover saved group instead of clearing
      final savedGroupId = await UserPreferences.getUserGroupId();
      return savedGroupId; // Return saved group or null if none exists
    }
  }

  /// Validate that user's local group matches their Firebase role and group membership
  Future<bool> _validateGroupConsistency(User user, String? localGroupId) async {
    if (localGroupId == null) return true; // No local group is always valid
    
    try {
      // Check if user is actually in the group in Firebase
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(localGroupId)
          .get();
      
      if (!groupDoc.exists) {
        debugPrint('⚠️ Local group $localGroupId does not exist in Firebase');
        return false;
      }
      
      final groupData = groupDoc.data() as Map<String, dynamic>;
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);
      
      if (!memberIds.contains(user.uid)) {
        debugPrint('⚠️ User ${user.uid} not found in group $localGroupId members');
        return false;
      }
      
      debugPrint('✅ Group consistency validated for user ${user.uid}');
      return true;
    } catch (e) {
      debugPrint('Error validating group consistency: $e');
      return false; // Assume invalid on error
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
          debugPrint('👤 Added user $userId to group $groupId');
        } else {
          debugPrint('👤 User $userId already in group $groupId');
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
        debugPrint('👤 Added user $userId to newly created group $groupId');
      } else {
        debugPrint('❌ Error adding user to group: $e');
      }
    }
  }

  /// Remove user from a group and cleanup if empty
  Future<void> _removeUserFromGroup(String groupId, String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .update({
        'memberIds': FieldValue.arrayRemove([userId])
      });
      
      debugPrint('👤 Removed user $userId from group $groupId');
      
      // Cleanup empty group
      await UserPreferences.cleanupEmptyGroup(groupId);
      
    } catch (e) {
      debugPrint('❌ Error removing user from group: $e');
    }
  }
}
