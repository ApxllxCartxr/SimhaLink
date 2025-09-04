import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/utils/user_preferences.dart';
import 'package:simha_link/core/utils/app_logger.dart';
import 'package:simha_link/services/firestore_lock_service.dart';

/// Service to ensure local state is always synchronized with Firebase state
class StateSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  
  static StreamSubscription<DocumentSnapshot>? _userDocSubscription;
  static StreamSubscription<DocumentSnapshot>? _groupDocSubscription;
  
  static String? _currentUserId;
  static String? _currentGroupId;
  
  /// Initialize state synchronization for the current user
  static Future<void> initialize() async {
    final user = _auth.currentUser;
    if (user == null) {
      AppLogger.logWarning('Cannot initialize state sync: No authenticated user');
      return;
    }
    
    _currentUserId = user.uid;
    AppLogger.logInfo('Initializing state sync for user: ${user.uid}');
    
    // Clean up any existing subscriptions
    dispose();
    
    // Start syncing user document
    await _syncUserDocument();
    
    // Start syncing group document
    await _syncGroupDocument();
  }
  /// Sync user document with local preferences
  static Future<void> _syncUserDocument() async {
    if (_currentUserId == null) return;
    
    _userDocSubscription?.cancel();
    _userDocSubscription = _firestore
        .collection('users')
        .doc(_currentUserId!)
        .snapshots()
        .listen((snapshot) async {
      try {
        if (!snapshot.exists) {
          AppLogger.logWarning('User document does not exist: $_currentUserId');
          return;
        }
        
        final userData = snapshot.data() as Map<String, dynamic>;
        final firebaseGroupId = userData['groupId'] as String?;
        final localGroupId = await UserPreferences.getUserGroupId();
        
        // Check if local and Firebase group IDs are out of sync
        if (firebaseGroupId != localGroupId) {
          AppLogger.logWarning(
            'Group ID sync mismatch - Local: $localGroupId, Firebase: $firebaseGroupId'
          );
          
          // Firebase is the source of truth
          if (firebaseGroupId != null && firebaseGroupId.isNotEmpty) {
            await UserPreferences.setUserGroupId(firebaseGroupId);
            _currentGroupId = firebaseGroupId;
            AppLogger.logInfo('✅ Synced local group ID to Firebase: $firebaseGroupId');
            
            // Start syncing the new group
            await _syncGroupDocument();
          } else {
            // Firebase has no group, clear local
            await UserPreferences.setUserGroupId(null);
            _currentGroupId = null;
            AppLogger.logInfo('✅ Cleared local group ID to match Firebase');
            
            // Stop group sync
            _groupDocSubscription?.cancel();
            _groupDocSubscription = null;
          }
        }
        
        AppLogger.logInfo('📱 User document synced successfully');
      } catch (e, stackTrace) {
        AppLogger.logError('Error syncing user document', e, stackTrace);
      }
    });
  }
  
  /// Sync group document and ensure user membership is consistent
  static Future<void> _syncGroupDocument() async {
    if (_currentUserId == null) return;
    
    final groupId = await UserPreferences.getUserGroupId();
    if (groupId == null || groupId.isEmpty) {
      _groupDocSubscription?.cancel();
      _groupDocSubscription = null;
      return;
    }
    
    if (_currentGroupId == groupId && _groupDocSubscription != null) {
      // Already syncing this group
      return;
    }
    
    _currentGroupId = groupId;
    _groupDocSubscription?.cancel();
    _groupDocSubscription = _firestore
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .listen((snapshot) async {
      try {
        if (!snapshot.exists) {
          AppLogger.logWarning('Group document does not exist: $groupId');
          
          // Group doesn't exist, clear local reference
          await UserPreferences.setUserGroupId(null);
          await _updateUserGroupInFirestore(null);
          
          AppLogger.logInfo('✅ Cleared references to non-existent group: $groupId');
          return;
        }
        
        final groupData = snapshot.data() as Map<String, dynamic>;
        final memberIds = List<String>.from(groupData['memberIds'] ?? []);
        
        // Check if current user is actually a member
        if (!memberIds.contains(_currentUserId)) {
          AppLogger.logWarning(
            'User $_currentUserId not found in group $groupId members'
          );
          
          // User is not a member, clear local reference
          await UserPreferences.setUserGroupId(null);
          await _updateUserGroupInFirestore(null);
          
          AppLogger.logInfo('✅ Removed user from group they are not a member of: $groupId');
        } else {
          AppLogger.logInfo('📱 Group membership verified for user: $_currentUserId');
        }
        
        AppLogger.logInfo('📱 Group document synced successfully');
      } catch (e, stackTrace) {
        AppLogger.logError('Error syncing group document', e, stackTrace);
      }
    });
  }
  
  /// Update user's group reference in Firestore
  static Future<void> _updateUserGroupInFirestore(String? groupId) async {
    if (_currentUserId == null) return;
    
    try {
      final userRef = _firestore.collection('users').doc(_currentUserId!);
      final ownerId = _currentUserId!;
      final resourceId = 'user_group_${_currentUserId!}';

      // Use a short advisory lock to avoid other clients re-writing user's group concurrently
      await FirestoreLockService.runWithLock(resourceId, ownerId, () async {
        if (groupId != null) {
          await userRef.update({'groupId': groupId});
        } else {
          await userRef.update({'groupId': FieldValue.delete()});
        }
      }, ttlSeconds: 8);

      AppLogger.logInfo('📝 Updated user group in Firestore: $groupId (with lock)');
    } catch (e, stackTrace) {
      AppLogger.logError('Error updating user group in Firestore', e, stackTrace);
    }
  }
  
  /// Force synchronization of user and group state
  static Future<void> forceSyncState() async {
    AppLogger.logInfo('🔄 Force syncing state...');
    
    final user = _auth.currentUser;
    if (user == null) {
      AppLogger.logWarning('Cannot force sync: No authenticated user');
      return;
    }
    
    try {
      // Get fresh data from Firestore
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) {
        AppLogger.logWarning('User document does not exist during force sync');
        await UserPreferences.clearGroupData();
        return;
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      final firebaseGroupId = userData['groupId'] as String?;
      final localGroupId = await UserPreferences.getUserGroupId();
      
      if (firebaseGroupId != localGroupId) {
        AppLogger.logInfo(
          '🔄 Force sync: Local ($localGroupId) → Firebase ($firebaseGroupId)'
        );
        
        if (firebaseGroupId != null && firebaseGroupId.isNotEmpty) {
          // Verify group exists and user is a member
          final groupDoc = await _firestore
              .collection('groups')
              .doc(firebaseGroupId)
              .get();
          
          if (groupDoc.exists) {
            final groupData = groupDoc.data() as Map<String, dynamic>;
            final memberIds = List<String>.from(groupData['memberIds'] ?? []);
            
            if (memberIds.contains(user.uid)) {
              await UserPreferences.setUserGroupId(firebaseGroupId);
              AppLogger.logInfo('✅ Force sync: Updated local group ID');
            } else {
              AppLogger.logWarning('Force sync: User not in group members, clearing');
              await UserPreferences.setUserGroupId(null);
              await _updateUserGroupInFirestore(null);
            }
          } else {
            AppLogger.logWarning('Force sync: Group does not exist, clearing');
            await UserPreferences.setUserGroupId(null);
            await _updateUserGroupInFirestore(null);
          }
        } else {
          await UserPreferences.setUserGroupId(null);
          AppLogger.logInfo('✅ Force sync: Cleared local group ID');
        }
      }
      
      AppLogger.logInfo('✅ Force sync completed successfully');
    } catch (e, stackTrace) {
      AppLogger.logError('Error during force sync', e, stackTrace);
    }
  }
  
  /// Validate current state consistency
  static Future<bool> validateStateConsistency() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) {
        AppLogger.logWarning('State validation: User document missing');
        return false;
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      final firebaseGroupId = userData['groupId'] as String?;
      final localGroupId = await UserPreferences.getUserGroupId();
      
      if (firebaseGroupId != localGroupId) {
        AppLogger.logWarning(
          'State inconsistency detected - Local: $localGroupId, Firebase: $firebaseGroupId'
        );
        return false;
      }
      
      if (firebaseGroupId != null) {
        final groupDoc = await _firestore
            .collection('groups')
            .doc(firebaseGroupId)
            .get();
        
        if (!groupDoc.exists) {
          AppLogger.logWarning('State validation: Group document missing');
          return false;
        }
        
        final groupData = groupDoc.data() as Map<String, dynamic>;
        final memberIds = List<String>.from(groupData['memberIds'] ?? []);
        
        if (!memberIds.contains(user.uid)) {
          AppLogger.logWarning('State validation: User not in group members');
          return false;
        }
      }
      
      AppLogger.logInfo('✅ State consistency validated');
      return true;
    } catch (e, stackTrace) {
      AppLogger.logError('Error validating state consistency', e, stackTrace);
      return false;
    }
  }
  
  /// Clean up subscriptions
  static void dispose() {
    _userDocSubscription?.cancel();
    _groupDocSubscription?.cancel();
    _userDocSubscription = null;
    _groupDocSubscription = null;
    _currentUserId = null;
    _currentGroupId = null;
    
    AppLogger.logInfo('🧹 StateSyncService disposed');
  }
  
  /// Get current sync status
  static Map<String, dynamic> getSyncStatus() {
    return {
      'userId': _currentUserId,
      'groupId': _currentGroupId,
      'userDocSyncing': _userDocSubscription != null,
      'groupDocSyncing': _groupDocSubscription != null,
    };
  }
}
