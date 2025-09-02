import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/core/utils/app_logger.dart';

/// Utility functions for role-based checks
class RoleUtils {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Check if the current user is an organizer
  /// Returns false if check fails or user is not an organizer
  static Future<bool> isUserOrganizer() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        AppLogger.logWarning('Cannot check role: User not authenticated');
        return false;
      }

      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) {
        AppLogger.logWarning('Cannot check role: User document not found');
        return false;
      }

      final userData = userDoc.data()!;
      final role = userData['role'] as String?;
      
      return role?.toLowerCase() == 'organizer';
    } catch (e, stackTrace) {
      AppLogger.logError('Failed to check if user is organizer', e, stackTrace);
      return false;
    }
  }
}
