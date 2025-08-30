import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:simha_link/services/state_sync_service.dart';

class UserPreferences {
  static const String _userGroupIdKey = 'user_group_id';

  /// Get user-specific key to prevent cross-user preference conflicts
  static String _getUserSpecificKey(String baseKey, String? userId) {
    if (userId == null) return baseKey;
    return '${baseKey}_$userId';
  }

  static Future<void> setUserGroupId(String? groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final key = _getUserSpecificKey(_userGroupIdKey, user?.uid);
    
    if (groupId == null) {
      await prefs.remove(key);
      debugPrint('🗑️ Removed group ID for user: ${user?.uid}');
    } else {
      await prefs.setString(key, groupId);
      debugPrint('💾 Set group ID for user ${user?.uid}: $groupId (using key: $key)');
      
      // Also backup to a user-email based key for persistence across login sessions
      if (user != null && user.email != null) {
        final emailBackupKey = 'email_group_${user.email!.replaceAll('.', '_')}';
        await prefs.setString(emailBackupKey, groupId);
        debugPrint('💾 Backed up group ID to email-based key: $emailBackupKey');
      }
    }
  }

  static Future<String?> getUserGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      debugPrint('⚠️ Cannot get group ID: No authenticated user');
      return null;
    }
    
    final key = _getUserSpecificKey(_userGroupIdKey, user.uid);
    var groupId = prefs.getString(key);
    
    // Try to recover from email-based backup if primary key has no value
    if (groupId == null && user.email != null) {
      final emailBackupKey = 'email_group_${user.email!.replaceAll('.', '_')}';
      final backupGroupId = prefs.getString(emailBackupKey);
      
      if (backupGroupId != null) {
        debugPrint('🔄 Recovered group ID from email backup: $backupGroupId');
        // Restore to the primary key
        await setUserGroupId(backupGroupId);
        groupId = backupGroupId;
      }
    }
    
    // Debug logging with more details to help troubleshoot
    debugPrint('📖 Get user group ID for ${user.uid}: $groupId (using key: $key)');
    
    return groupId;
  }

  static Future<void> clearGroupData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // If no user, clear any old preferences that might exist
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userGroupIdKey); // Clear old non-user-specific key
      debugPrint('🧹 Cleared group data (no user)');
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
          
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final userRole = userData['role'] as String?;
        
        // Prevent volunteers and organizers from clearing their group data
        if (userRole == 'Volunteer' || userRole == 'Organizer') {
          debugPrint('⛔ Prevented ${userRole} from clearing group data');
          return; // Don't clear group data for special roles
        }
        
        // For attendees, also clear any restrictions that might prevent joining new groups
        if (userRole == 'Attendee') {
          await _clearAttendeeGroupRestrictions(user.uid);
        }
      }
    } catch (e) {
      debugPrint('Error checking user role before clearing group data: $e');
    }
    
    // Clear user-specific local preferences
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserSpecificKey(_userGroupIdKey, user.uid);
    await prefs.remove(key);
    await prefs.remove('has_skipped_group_${user.uid}'); // Clear any skip flags
    debugPrint('🧹 Group data cleared for user: ${user.uid}');
  }

  /// Clear any restrictions that might prevent attendees from joining new groups
  static Future<void> _clearAttendeeGroupRestrictions(String userId) async {
    try {
      // Update user document to ensure they can join new groups
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'canJoinGroups': true,
        'lastLeftGroup': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Cleared attendee group restrictions');
    } catch (e) {
      debugPrint('Error clearing attendee restrictions: $e');
    }
  }

  /// Clear all user-specific preferences on logout
  static Future<void> clearAllUserPreferences(String? userId) async {
    if (userId == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    // Remove all keys that contain the user ID
    for (final key in keys) {
      if (key.endsWith('_$userId')) {
        await prefs.remove(key);
        debugPrint('🗑️ Removed preference: $key');
      }
    }
    
    // Also remove old non-user-specific keys for cleanup
    await prefs.remove(_userGroupIdKey);
    await prefs.remove('has_skipped_group');
    
    debugPrint('🧹 All preferences cleared for user: $userId');
  }

  /// Remove user from Firebase group and delete group if empty (ONLY for intentional group leaving)
  static Future<void> leaveGroupAndCleanup(String groupId, String userId) async {
    try {
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(groupId);
      
      // Remove user from group
      await groupRef.update({
        'memberIds': FieldValue.arrayRemove([userId])
      });
      
      debugPrint('🚪 User $userId removed from group $groupId');
      
      // Clear local preferences for this user (FIRST, before group deletion)
      await clearGroupData();
      
      // Check if group is now empty and cleanup if needed
      if (groupId.isNotEmpty) {
        // Never delete special groups (volunteers, organizers) or personal groups
        if (groupId == 'volunteers' || 
            groupId == 'organizers' || 
            groupId.startsWith('default_')) {
          debugPrint('🔒 Skipping cleanup for special/personal group: $groupId');
          return;
        }
        
        // Check if group is now empty
        final groupDoc = await groupRef.get();
        if (groupDoc.exists) {
          final groupData = groupDoc.data() as Map<String, dynamic>;
          final memberIds = List<String>.from(groupData['memberIds'] ?? []);
          
          if (memberIds.isEmpty) {
            debugPrint('🗑️ Deleting empty group: $groupId');
            
            // Delete the group document
            await groupRef.delete();
            
            // Also clean up any sub-collections (messages, locations, etc.)
            await _deleteGroupSubCollections(groupId);
            
            debugPrint('✅ Successfully deleted empty group: $groupId');
          } else {
            debugPrint('👥 Group $groupId still has ${memberIds.length} members');
          }
        }
      }
      
    } catch (e) {
      debugPrint('❌ Error leaving group and cleaning up: $e');
      rethrow;
    }
  }

  /// Check if a group is empty and delete it if so (except special groups)
  static Future<void> cleanupEmptyGroup(String groupId) async {
    if (groupId.isEmpty) return;
    
    // Never delete special groups (volunteers, organizers) or personal groups
    if (groupId == 'volunteers' || 
        groupId == 'organizers' || 
        groupId.startsWith('default_')) {
      debugPrint('🔒 Skipping cleanup for special/personal group: $groupId');
      return;
    }
    
    try {
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();
      
      if (!groupDoc.exists) {
        debugPrint('⚠️ Group $groupId does not exist, nothing to cleanup');
        return;
      }
      
      final groupData = groupDoc.data() as Map<String, dynamic>;
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);
      
      if (memberIds.isEmpty) {
        debugPrint('🗑️ Deleting empty group: $groupId');
        
        // Delete the group document
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .delete();
        
        // Also clean up any sub-collections (messages, locations, etc.)
        await _deleteGroupSubCollections(groupId);
        
        debugPrint('✅ Successfully deleted empty group: $groupId');
      } else {
        debugPrint('👥 Group $groupId has ${memberIds.length} members, keeping it');
      }
    } catch (e) {
      debugPrint('❌ Error cleaning up group $groupId: $e');
    }
  }

  /// Delete sub-collections of a group
  static Future<void> _deleteGroupSubCollections(String groupId) async {
    try {
      // Delete messages sub-collection
      final messagesQuery = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .get();
      
      for (final doc in messagesQuery.docs) {
        await doc.reference.delete();
      }
      debugPrint('🗑️ Deleted ${messagesQuery.docs.length} messages for group $groupId');
      
      // Delete locations sub-collection  
      final locationsQuery = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('locations')
          .get();
      
      for (final doc in locationsQuery.docs) {
        await doc.reference.delete();
      }
      debugPrint('🗑️ Deleted ${locationsQuery.docs.length} location records for group $groupId');
      
    } catch (e) {
      debugPrint('❌ Error deleting sub-collections for group $groupId: $e');
    }
  }

  static Future<String?> createDefaultGroupIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      // Create a unique default group for each user instead of using a shared one
      final userDefaultGroupId = 'default_${user.uid}';
      
      final defaultGroupRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(userDefaultGroupId);

      final defaultGroup = await defaultGroupRef.get();

      if (!defaultGroup.exists) {
        await defaultGroupRef.set({
          'id': userDefaultGroupId,
          'name': 'My Group',
          'type': 'personal',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
          'memberIds': [user.uid],
          'description': 'Personal group for solo use',
          'joinCode': '', // Personal groups don't need join codes
        });
        await setUserGroupId(userDefaultGroupId);
      } else {
        // Add user to existing default group if not already a member
        final memberIds = (defaultGroup.data()?['memberIds'] as List<dynamic>?) ?? [];
        if (!memberIds.contains(user.uid)) {
          await defaultGroupRef.update({
            'memberIds': FieldValue.arrayUnion([user.uid])
          });
        }
        // Always set the user group ID to their personal group
        await setUserGroupId(userDefaultGroupId);
      }

      return userDefaultGroupId;
    } catch (e) {
      debugPrint('Error creating default group: $e');
      return null;
    } finally {
      // Force state sync after group creation/assignment
      try {
        await StateSyncService.forceSyncState();
      } catch (e) {
        debugPrint('Error syncing state after default group creation: $e');
      }
    }
  }

  static Future<bool> isDefaultGroup(String groupId) async {
    // Check if it's a personal default group (format: default_<userId>)
    return groupId.startsWith('default_');
  }

  static Future<void> setHasSkippedGroup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_skipped_group', value);
  }

  static Future<bool> hasSkippedGroup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_skipped_group') ?? false;
  }

  /// Fix for users who were incorrectly assigned to the shared default_group
  /// This migrates them to their own personal group
  static Future<bool> migrateFromSharedDefaultGroup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final currentGroupId = await getUserGroupId();
      
      // Check if user is in the old shared default_group
      if (currentGroupId == 'default_group') {
        debugPrint('🔄 Migrating user ${user.uid} from shared default_group to personal group');
        
        // Remove user from the old shared group
        await FirebaseFirestore.instance
            .collection('groups')
            .doc('default_group')
            .update({
          'memberIds': FieldValue.arrayRemove([user.uid])
        });
        
        // Clear their current group assignment
        await clearGroupData();
        
        // Create their new personal group
        final newGroupId = await createDefaultGroupIfNeeded();
        
        if (newGroupId != null) {
          debugPrint('✅ Successfully migrated user to personal group: $newGroupId');
          return true;
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Error during migration: $e');
      return false;
    }
  }
}
