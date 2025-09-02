import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/services/state_sync_service.dart';

/// Service for managing group operations, member management, and permissions
class GroupManagementService {
  static const String _groupsCollection = 'groups';
  static const String _usersCollection = 'users';
  
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get detailed group information including member statistics
  static Future<GroupInfo?> getGroupInfo(String groupId) async {
    try {
      AppLogger.logInfo('Fetching group info for: $groupId');
      
      final groupDoc = await _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .get();

      if (!groupDoc.exists) {
        AppLogger.logWarning('Group not found: $groupId');
        return null;
      }

      final groupData = groupDoc.data()!;
      
      // Get member IDs from the group document
      final memberIds = List<String>.from(groupData['memberIds'] ?? []);
      
      final members = <GroupMember>[];
      int activeCount = 0;
      final now = DateTime.now();
      
      // Fetch member details from users collection
      for (final memberId in memberIds) {
        try {
          final userDoc = await _firestore
              .collection(_usersCollection)
              .doc(memberId)
              .get();
              
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            final member = GroupMember(
              id: memberId,
              name: userData['displayName'] ?? userData['name'] ?? 'Unknown User',
              email: userData['email'] ?? '',
              role: userData['role'] ?? 'Participant',
              joinedAt: (userData['joinedAt'] as Timestamp?)?.toDate() ?? 
                       (userData['createdAt'] as Timestamp?)?.toDate() ?? 
                       DateTime.now(),
              lastSeen: (userData['lastSeen'] as Timestamp?)?.toDate(),
              isActive: userData['isActive'] ?? false,
            );
            members.add(member);
            
            // Consider active if last seen within 10 minutes
            if (member.lastSeen != null && 
                now.difference(member.lastSeen!).inMinutes <= 10) {
              activeCount++;
            }
          }
        } catch (e) {
          AppLogger.logWarning('Failed to fetch member $memberId: $e');
        }
      }

      return GroupInfo(
        id: groupId,
        name: groupData['name'] ?? 'Unknown Group',
        code: groupData['joinCode'] ?? groupData['code'] ?? '',
        description: groupData['description'] ?? '',
        createdBy: groupData['createdBy'] ?? '',
        createdAt: (groupData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        members: members,
        totalMembers: members.length,
        activeMembers: activeCount,
        maxMembers: groupData['maxMembers'] ?? 50,
        isActive: groupData['isActive'] ?? true,
      );
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to get group info', e, stackTrace);
      return null;
    }
  }

  /// Get real-time stream of group information
  static Stream<GroupInfo?> getGroupInfoStream(String groupId) {
    return _firestore
        .collection(_groupsCollection)
        .doc(groupId)
        .snapshots()
        .asyncMap((groupSnapshot) async {
      if (!groupSnapshot.exists) return null;

      try {
        final groupData = groupSnapshot.data()!;
        
        // Get member IDs from the group document
        final memberIds = List<String>.from(groupData['memberIds'] ?? []);
        
        final members = <GroupMember>[];
        int activeCount = 0;
        final now = DateTime.now();
        
        // Fetch member details from users collection
        for (final memberId in memberIds) {
          try {
            final userDoc = await _firestore
                .collection(_usersCollection)
                .doc(memberId)
                .get();
                
            if (userDoc.exists) {
              final userData = userDoc.data()!;
              final member = GroupMember(
                id: memberId,
                name: userData['displayName'] ?? userData['name'] ?? 'Unknown User',
                email: userData['email'] ?? '',
                role: userData['role'] ?? 'Participant',
                joinedAt: (userData['joinedAt'] as Timestamp?)?.toDate() ?? 
                         (userData['createdAt'] as Timestamp?)?.toDate() ?? 
                         DateTime.now(),
                lastSeen: (userData['lastSeen'] as Timestamp?)?.toDate(),
                isActive: userData['isActive'] ?? false,
              );
              members.add(member);
              
              if (member.lastSeen != null && 
                  now.difference(member.lastSeen!).inMinutes <= 10) {
                activeCount++;
              }
            }
          } catch (e) {
            AppLogger.logWarning('Failed to fetch member $memberId: $e');
          }
        }

        return GroupInfo(
          id: groupId,
          name: groupData['name'] ?? 'Unknown Group',
          code: groupData['joinCode'] ?? groupData['code'] ?? '',
          description: groupData['description'] ?? '',
          createdBy: groupData['createdBy'] ?? '',
          createdAt: (groupData['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          members: members,
          totalMembers: members.length,
          activeMembers: activeCount,
          maxMembers: groupData['maxMembers'] ?? 50,
          isActive: groupData['isActive'] ?? true,
        );
      } catch (e, stackTrace) {
        AppLogger.logError('Error in group info stream', e, stackTrace);
        return null;
      }
    });
  }

  /// Leave group (user removes themselves)
  static Future<bool> leaveGroup(String groupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot leave group: No authenticated user');
        return false;
      }

      AppLogger.logInfo('User leaving group: $groupId');

      final batch = _firestore.batch();

      // Remove from group members
      final memberRef = _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('members')
          .doc(user.uid);
      batch.delete(memberRef);

      // Remove group reference from user document
      final userRef = _firestore.collection(_usersCollection).doc(user.uid);
      batch.update(userRef, {
        'groupId': FieldValue.delete(),
        'leftGroups': FieldValue.arrayUnion([groupId]),
      });

      // Update group member count
      final groupRef = _firestore.collection(_groupsCollection).doc(groupId);
      batch.update(groupRef, {
        'memberCount': FieldValue.increment(-1),
      });

      await batch.commit();

      // Clear local preferences
      await UserPreferences.setUserGroupId(null);
      
      AppLogger.logInfo('Successfully left group: $groupId');
      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to leave group', e, stackTrace);
      return false;
    }
  }

  /// Delete entire group (organizers only)
  static Future<bool> deleteGroup(String groupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot delete group: No authenticated user');
        return false;
      }

      // Verify user is organizer
      final groupDoc = await _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .get();

      if (!groupDoc.exists) {
        AppLogger.logWarning('Group not found for deletion: $groupId');
        return false;
      }

      final createdBy = groupDoc.data()?['createdBy'];
      if (createdBy != user.uid) {
        AppLogger.logWarning('User not authorized to delete group: $groupId');
        return false;
      }

      AppLogger.logInfo('Deleting group: $groupId');

      // Get all members to notify them
      final membersSnapshot = await _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('members')
          .get();

      final batch = _firestore.batch();

      // Delete all member documents
      for (final memberDoc in membersSnapshot.docs) {
        batch.delete(memberDoc.reference);
        
        // Update user documents to remove group reference
        final userRef = _firestore.collection(_usersCollection).doc(memberDoc.id);
        batch.update(userRef, {
          'groupId': FieldValue.delete(),
          'deletedGroups': FieldValue.arrayUnion([groupId]),
        });
      }

      // Delete messages subcollection (if exists)
      final messagesSnapshot = await _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('messages')
          .limit(500) // Process in batches for large groups
          .get();

      for (final messageDoc in messagesSnapshot.docs) {
        batch.delete(messageDoc.reference);
      }

      // Delete the main group document
      final groupRef = _firestore.collection(_groupsCollection).doc(groupId);
      batch.delete(groupRef);

      await batch.commit();
      
      // Clear local preferences
      await UserPreferences.setUserGroupId(null);
      
      AppLogger.logInfo('Successfully deleted group: $groupId');
      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to delete group', e, stackTrace);
      return false;
    }
  }

  /// Kick user from group (organizers only)
  static Future<bool> kickMember(String groupId, String memberId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot kick member: No authenticated user');
        return false;
      }

      // Verify current user is organizer
      final currentUserRole = await _getUserRoleInGroup(groupId, user.uid);
      if (currentUserRole != 'Organizer') {
        AppLogger.logWarning('User not authorized to kick members from group: $groupId');
        return false;
      }

      // Cannot kick yourself
      if (memberId == user.uid) {
        AppLogger.logWarning('User cannot kick themselves from group');
        return false;
      }

      AppLogger.logInfo('Kicking member $memberId from group: $groupId');

      final batch = _firestore.batch();

      // Remove from group members
      final memberRef = _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('members')
          .doc(memberId);
      batch.delete(memberRef);

      // Update user document
      final userRef = _firestore.collection(_usersCollection).doc(memberId);
      batch.update(userRef, {
        'groupId': FieldValue.delete(),
        'kickedFromGroups': FieldValue.arrayUnion([groupId]),
      });

      // Update group member count
      final groupRef = _firestore.collection(_groupsCollection).doc(groupId);
      batch.update(groupRef, {
        'memberCount': FieldValue.increment(-1),
      });

      // Add kick record for audit trail
      final kickRef = _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('audit_log')
          .doc();
      batch.set(kickRef, {
        'action': 'member_kicked',
        'kickedUserId': memberId,
        'kickedBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'reason': 'Removed by organizer',
      });

      await batch.commit();
      
      AppLogger.logInfo('Successfully kicked member $memberId from group: $groupId');
      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to kick member from group', e, stackTrace);
      return false;
    }
  }

  /// Change member role (organizers only)
  static Future<bool> changeMemberRole(String groupId, String memberId, String newRole) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot change member role: No authenticated user');
        return false;
      }

      // Verify current user is organizer
      final currentUserRole = await _getUserRoleInGroup(groupId, user.uid);
      if (currentUserRole != 'Organizer') {
        AppLogger.logWarning('User not authorized to change member roles');
        return false;
      }

      // Validate new role
      final validRoles = ['Participant', 'Volunteer', 'Organizer', 'VIP'];
      if (!validRoles.contains(newRole)) {
        AppLogger.logWarning('Invalid role specified: $newRole');
        return false;
      }

      AppLogger.logInfo('Changing role for member $memberId to $newRole in group: $groupId');

      final batch = _firestore.batch();

      // Update member role in group
      final memberRef = _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('members')
          .doc(memberId);
      batch.update(memberRef, {
        'role': newRole,
        'roleChangedAt': FieldValue.serverTimestamp(),
        'roleChangedBy': user.uid,
      });

      // Update user's main role
      final userRef = _firestore.collection(_usersCollection).doc(memberId);
      batch.update(userRef, {
        'role': newRole,
      });

      // Add audit log entry
      final auditRef = _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('audit_log')
          .doc();
      batch.set(auditRef, {
        'action': 'role_changed',
        'targetUserId': memberId,
        'newRole': newRole,
        'changedBy': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      
      AppLogger.logInfo('Successfully changed member role');
      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to change member role', e, stackTrace);
      return false;
    }
  }

  /// Get user's role in a specific group
  static Future<String> _getUserRoleInGroup(String groupId, String userId) async {
    try {
      final memberDoc = await _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .get();

      if (memberDoc.exists) {
        return memberDoc.data()?['role'] ?? 'Participant';
      }
      return '';
    } catch (e) {
      AppLogger.logError('Failed to get user role in group', e);
      return '';
    }
  }

  /// Update member's last seen timestamp
  static Future<void> updateMemberActivity(String groupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore
          .collection(_groupsCollection)
          .doc(groupId)
          .collection('members')
          .doc(user.uid)
          .update({
        'lastSeen': FieldValue.serverTimestamp(),
        'isActive': true,
      });
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to update member activity', e, stackTrace);
    }
  }
}

/// Data class for group information
class GroupInfo {
  final String id;
  final String name;
  final String code;
  final String description;
  final String createdBy;
  final DateTime createdAt;
  final List<GroupMember> members;
  final int totalMembers;
  final int activeMembers;
  final int maxMembers;
  final bool isActive;

  const GroupInfo({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.createdBy,
    required this.createdAt,
    required this.members,
    required this.totalMembers,
    required this.activeMembers,
    required this.maxMembers,
    required this.isActive,
  });
}

/// Data class for group member information
class GroupMember {
  final String id;
  final String name;
  final String email;
  final String role;
  final DateTime joinedAt;
  final DateTime? lastSeen;
  final bool isActive;

  const GroupMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
    this.lastSeen,
    required this.isActive,
  });

  String get roleDisplayName {
    switch (role.toLowerCase()) {
      case 'organizer':
        return '👑 Organizer';
      case 'volunteer':
        return '🚀 Volunteer';
      case 'vip':
        return '⭐ VIP';
      default:
        return '👤 Participant';
    }
  }

  bool get isOnline {
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen!).inMinutes <= 10;
  }
}
