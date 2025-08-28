import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/screens/auth_screen.dart';
import 'package:simha_link/screens/map_screen.dart';
import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/widgets/loading_widgets.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: LoadingWidget(
              message: 'Checking authentication...',
            ),
          );
        }
        
        if (snapshot.hasData) {
          // User is authenticated, check if they have a group
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
                return const GroupCreationScreen();
              }
              
              // User has a group, show map screen
              return MapScreen(groupId: groupId);
            },
          );
        }
        
        // User is not authenticated, show auth screen
        return const AuthScreen();
      },
    );
  }

  Future<String?> _checkUserGroupAndRole(User user) async {
    try {
      print('🔍 Checking user group and role for: ${user.email}');
      
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
          print('✅ User document found on attempt ${retryCount + 1}');
          break;
        }
        
        retryCount++;
        if (retryCount < maxRetries) {
          print('⏳ User document not found, retrying... ($retryCount/$maxRetries)');
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }

      if (userDoc != null && userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final userRole = userData['role'] as String?;
        print('👤 User role found: $userRole');

        // Handle different roles with specific logic
        if (userRole == 'Volunteer') {
          print('🚨 Volunteer detected - assigning to volunteers group');
          final groupId = await _ensureSpecialGroupExists('volunteers', 'Volunteers');
          await UserPreferences.setUserGroupId(groupId);
          await _addUserToGroup(groupId, user.uid);
          return groupId;
        } else if (userRole == 'Organizer') {
          print('👨‍💼 Organizer detected - assigning to organizers group');
          final groupId = await _ensureSpecialGroupExists('organizers', 'Organizers');
          await UserPreferences.setUserGroupId(groupId);
          await _addUserToGroup(groupId, user.uid);
          return groupId;
        } else if (userRole == 'Attendee') {
          print('🎫 Attendee detected - checking for existing group');
          
          // Check if attendee has a saved group preference
          final savedGroupId = await UserPreferences.getUserGroupId();
          print('💾 Saved group ID: $savedGroupId');
          
          if (savedGroupId != null && savedGroupId.isNotEmpty) {
            // Verify the group still exists and user is a member
            final groupDoc = await FirebaseFirestore.instance
                .collection('groups')
                .doc(savedGroupId)
                .get();
            if (groupDoc.exists) {
              final groupData = groupDoc.data() as Map<String, dynamic>;
              final memberIds = List<String>.from(groupData['memberIds'] ?? []);
              
              if (memberIds.contains(user.uid)) {
                print('✅ User is member of existing group, going to map');
                return savedGroupId;
              } else {
                print('❌ User not a member of saved group, clearing preference');
                await UserPreferences.clearGroupData();
              }
            } else {
              print('❌ Saved group no longer exists, clearing preference');
              await UserPreferences.clearGroupData();
            }
          }
          
          // Attendee has no valid group, show group creation screen
          print('🏗️ NEW ATTENDEE - Showing group creation screen');
          return null;
        }
      } else {
        print('❓ No user document found in Firestore after retries - treating as new user');
      }

      // User has no role document or unknown role, show group creation screen
      print('🏗️ Fallback - Showing group creation screen');
      return null;
    } catch (e) {
      print('❌ Error checking user group and role: $e');
      return null; // Show group creation screen on error
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
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .update({
        'memberIds': FieldValue.arrayUnion([userId])
      });
    } catch (e) {
      print('Error adding user to group: $e');
    }
  }
}
