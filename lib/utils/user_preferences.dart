import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class UserPreferences {
  static const String _userGroupIdKey = 'user_group_id';
  static const String _defaultGroupId = 'default_group';

  static Future<void> setUserGroupId(String? groupId) async {
    final prefs = await SharedPreferences.getInstance();
    if (groupId == null) {
      await prefs.remove(_userGroupIdKey);
    } else {
      await prefs.setString(_userGroupIdKey, groupId);
    }
  }

  static Future<String?> getUserGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userGroupIdKey);
  }

  static Future<void> clearGroupData() async {
    // Check if user is a volunteer or organizer before clearing
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
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
        }
      } catch (e) {
        debugPrint('Error checking user role before clearing group data: $e');
      }
    }
    
    // Only clear for attendees or unknown roles
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userGroupIdKey);
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
