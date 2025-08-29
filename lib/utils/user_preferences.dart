import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UserPreferences {
  static const String _userGroupIdKey = 'user_group_id';
  static const String _defaultGroupId = 'default_group';

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
      debugPrint('💾 Set group ID for user ${user?.uid}: $groupId');
    }
  }

  static Future<String?> getUserGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final key = _getUserSpecificKey(_userGroupIdKey, user?.uid);
    final groupId = prefs.getString(key);
    debugPrint('📖 Get user group ID for ${user?.uid ?? 'unknown'}: $groupId');
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
        // Never delete special groups (volunteers, organizers, default_group)
        if (groupId == 'volunteers' || 
            groupId == 'organizers' || 
            groupId == _defaultGroupId) {
          debugPrint('🔒 Skipping cleanup for special group: $groupId');
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
    
    // Never delete special groups (volunteers, organizers, default_group)
    if (groupId == 'volunteers' || 
        groupId == 'organizers' || 
        groupId == _defaultGroupId) {
      debugPrint('🔒 Skipping cleanup for special group: $groupId');
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
      final defaultGroupRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(_defaultGroupId);

      final defaultGroup = await defaultGroupRef.get();

      if (!defaultGroup.exists) {
        await defaultGroupRef.set({
          'id': _defaultGroupId,
          'name': 'Default Group',
          'type': 'default',
          'createdAt': FieldValue.serverTimestamp(),
          'memberIds': [user.uid],
        });
        await setUserGroupId(_defaultGroupId);
      } else {
        // Add user to existing default group if not already a member
        final memberIds = (defaultGroup.data()?['memberIds'] as List<dynamic>?) ?? [];
        if (!memberIds.contains(user.uid)) {
          await defaultGroupRef.update({
            'memberIds': FieldValue.arrayUnion([user.uid])
          });
        }
        // Always set the user group ID to default group
        await setUserGroupId(_defaultGroupId);
      }

      return _defaultGroupId;
    } catch (e) {
      debugPrint('Error creating default group: $e');
      return null;
    }
  }

  static Future<bool> isDefaultGroup(String groupId) async {
    return groupId == _defaultGroupId;
  }

  static Future<void> setHasSkippedGroup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_skipped_group', value);
  }

  static Future<bool> hasSkippedGroup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_skipped_group') ?? false;
  }
}
