import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:simha_link/services/state_sync_service.dart';
import 'package:simha_link/services/firestore_lock_service.dart';

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
      
      // Clear the "has left group" flag since user is joining a new group
      if (user != null) {
        final hasLeftGroupKey = 'has_left_group_${user.uid}';
        await prefs.remove(hasLeftGroupKey);
        debugPrint('✅ Cleared has_left_group flag - user joining new group');
      }
      
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
    
    // Check if user has intentionally left a group (flag prevents recovery)
    final hasLeftGroupKey = 'has_left_group_${user.uid}';
    final hasLeftGroup = prefs.getBool(hasLeftGroupKey) ?? false;
    
    // Try to recover from email-based backup if primary key has no value
    // BUT only if user hasn't intentionally left a group
    if (groupId == null && user.email != null && !hasLeftGroup) {
      final emailBackupKey = 'email_group_${user.email!.replaceAll('.', '_')}';
      final backupGroupId = prefs.getString(emailBackupKey);
      
      if (backupGroupId != null) {
        debugPrint('🔄 Recovered group ID from email backup: $backupGroupId');
        // Restore to the primary key
        await setUserGroupId(backupGroupId);
        groupId = backupGroupId;
      }
    } else if (hasLeftGroup && groupId == null) {
      debugPrint('🚫 Not recovering group ID - user has intentionally left');
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
    
  // Clear user-specific local preferences under a lock to avoid races
  final ownerId = user.uid;
  await FirestoreLockService.runWithLock('group_${user.uid}', ownerId, () async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserSpecificKey(_userGroupIdKey, user.uid);
    await prefs.remove(key);
    await prefs.remove('has_skipped_group_${user.uid}'); // Clear any skip flags
    
    // Set flag to prevent recovery from email backup
    final hasLeftGroupKey = 'has_left_group_${user.uid}';
    await prefs.setBool(hasLeftGroupKey, true);
    debugPrint('🚫 Set has_left_group flag to prevent recovery');
    
    // Also remove email-based backup key to avoid accidental recovery
    if (user.email != null) {
      final emailBackupKey = 'email_group_${user.email!.replaceAll('.', '_')}';
      await prefs.remove(emailBackupKey);
      debugPrint('🧹 Removed email backup key: $emailBackupKey');
    }

    debugPrint('🧹 Group data cleared for user: ${user.uid}');
  }, ttlSeconds: 8);
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
    // Remove email-based backup keys that may belong to this user
    final emailBackupKeyPrefix = 'email_group_';
    for (final key in keys) {
      if (key.startsWith(emailBackupKeyPrefix) && key.contains(userId.substring(0, 5))) {
        await prefs.remove(key);
        debugPrint('🧹 Removed email backup preference: $key');
      }
    }
    
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
      
      // Also clear the user's group reference in their user document so
      // StateSyncService sees Firebase has no group and won't restore it locally
      try {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'groupId': FieldValue.delete(),
          'lastLeftGroup': FieldValue.serverTimestamp(),
        });
        debugPrint('📝 Cleared groupId in user document for $userId');
      } catch (e) {
        debugPrint('⚠️ Failed to clear groupId in user doc: $e');
      }
      
      // Clear local preferences for this user (FIRST, before group deletion)
      final ownerId = userId;

      // Run the remove + user doc update inside a lock to avoid concurrent re-writes
      await FirestoreLockService.runWithLock('group_op_$groupId', ownerId, () async {
        await clearGroupData();
      }, ttlSeconds: 10);
      
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
      // Force a state sync to ensure local preferences match Firebase state
      try {
        await StateSyncService.forceSyncState();
        debugPrint('🔄 Forced state sync after leaving group');
      } catch (e) {
        debugPrint('⚠️ Failed to force state sync: $e');
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

  // Solo Mode Methods
  static Future<void> setUserInSoloMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final key = 'solo_mode_${user.uid}';
      await prefs.setBool(key, value);
      debugPrint('🧑‍💻 Set solo mode for user ${user.uid}: $value');
    }
  }

  static Future<bool> isUserInSoloMode() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final key = 'solo_mode_${user.uid}';
      final soloMode = prefs.getBool(key) ?? false;
      debugPrint('🧑‍💻 User ${user.uid} solo mode: $soloMode');
      return soloMode;
    }
    return false;
  }

  static Future<void> clearSoloMode() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final key = 'solo_mode_${user.uid}';
      await prefs.remove(key);
      debugPrint('🧹 Cleared solo mode for user ${user.uid}');
    }
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
        
        // Remove user from the old shared group under a lock
        await FirestoreLockService.runWithLock('group_op_default_group', user.uid, () async {
          await FirebaseFirestore.instance
              .collection('groups')
              .doc('default_group')
              .update({
            'memberIds': FieldValue.arrayRemove([user.uid])
          });
        }, ttlSeconds: 8);
        
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
