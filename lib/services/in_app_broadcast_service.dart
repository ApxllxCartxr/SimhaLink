import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:simha_link/models/broadcast_message.dart';
import 'package:simha_link/utils/user_preferences.dart';

/// Simple in-app broadcast listener for proof-of-concept.
/// Listens to new documents in `broadcasts` and shows a SnackBar when a
/// broadcast targeted to the current user appears.
class InAppBroadcastService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static StreamSubscription<QuerySnapshot>? _subs;
  static DateTime _lastSeen = DateTime.now();

  /// Initialize the listener. Requires a navigator key to show SnackBars.
  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Seed lastSeen time so we don't show historical broadcasts on startup
      _lastSeen = DateTime.now();

      // Listen for new active broadcasts
      _subs = _firestore
          .collection('broadcasts')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) async {
        final userRole = await _getCurrentUserRole();
        final userGroupId = await UserPreferences.getUserGroupId();

        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            try {
              final broadcast = BroadcastMessage.fromFirestore(change.doc);
              final createdAt = broadcast.createdAt;

              // only consider broadcasts newer than lastSeen
              if (createdAt.isAfter(_lastSeen)) {
                if (_shouldReceiveBroadcast(broadcast, userRole, userGroupId)) {
                  _showSnack(navigatorKey, broadcast);
                }
              }
            } catch (_) {
              // ignore parsing errors
            }
          }
        }

        // update lastSeen
        _lastSeen = DateTime.now();
      });
    } catch (e) {
      // ignore init errors for POC
    }
  }

  static void dispose() {
    _subs?.cancel();
    _subs = null;
  }

  static Future<String> _getCurrentUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return '';
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) return doc.data()?['role'] ?? '';
    } catch (_) {}
    return '';
  }

  static bool _shouldReceiveBroadcast(BroadcastMessage broadcast, String userRole, String? userGroupId) {
    final targetRoles = broadcast.target.getTargetRoles();
    final userRoleCapitalized = userRole.isNotEmpty
        ? userRole[0].toUpperCase() + userRole.substring(1).toLowerCase()
        : '';

    if (!targetRoles.contains(userRoleCapitalized)) return false;
    if (broadcast.target == BroadcastTarget.myGroup) {
      return userGroupId != null && userGroupId == broadcast.groupId;
    }
    return true;
  }

  static void _showSnack(GlobalKey<NavigatorState> navigatorKey, BroadcastMessage broadcast) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final content = broadcast.message != null && broadcast.message!.isNotEmpty
        ? broadcast.message!
        : (broadcast.content.length > 120 ? '${broadcast.content.substring(0, 120)}…' : broadcast.content);

    // Show a SnackBar with action to open Broadcast List
    final snack = SnackBar(
      content: Text('${broadcast.title}\n$content'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'View',
        onPressed: () {
          Navigator.of(ctx).pushNamed('/broadcast_list');
        },
      ),
    );

    ScaffoldMessenger.of(ctx).showSnackBar(snack);
  }
}
