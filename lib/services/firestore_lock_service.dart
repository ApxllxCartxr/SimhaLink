import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/core/utils/app_logger.dart';

/// Simple Firestore-backed lock to protect short critical sections across
/// multiple clients/listeners. Locks are advisory and have a TTL to avoid
/// permanent deadlocks. This is intentionally small and dependency-free.
class FirestoreLockService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _locksCollection = 'locks';

  /// Acquire a lock on [resourceId]. Returns true if lock acquired.
  /// [ownerId] is an identifier for the locker (for debugging / release).
  /// [ttlSeconds] controls how long the lock is considered valid.
  static Future<bool> acquireLock(
    String resourceId,
    String ownerId, {
    int ttlSeconds = 10,
  }) async {
    final lockRef = _firestore.collection(_locksCollection).doc(resourceId);

    try {
      return await _firestore.runTransaction<bool>((tx) async {
        final snapshot = await tx.get(lockRef);

        if (!snapshot.exists) {
          final expiresAt = Timestamp.fromDate(
            DateTime.now().add(Duration(seconds: ttlSeconds)),
          );
          tx.set(lockRef, {
            'ownerId': ownerId,
            'expiresAt': expiresAt,
            'createdAt': FieldValue.serverTimestamp(),
          });
          AppLogger.logInfo('Lock acquired: $resourceId by $ownerId');
          return true;
        }

        final data = snapshot.data();
        if (data == null) return false;
        final expiresAt = data['expiresAt'] as Timestamp?;

        // If lock expired, steal it
        if (expiresAt == null || expiresAt.toDate().isBefore(DateTime.now())) {
          final newExpires = Timestamp.fromDate(
            DateTime.now().add(Duration(seconds: ttlSeconds)),
          );
          tx.update(lockRef, {
            'ownerId': ownerId,
            'expiresAt': newExpires,
          });
          AppLogger.logInfo('Expired lock stolen: $resourceId by $ownerId');
          return true;
        }

        // Lock exists and not expired
        AppLogger.logInfo('Failed to acquire lock (held): $resourceId by $ownerId');
        return false;
      });
    } catch (e, st) {
      AppLogger.logError('Error acquiring lock $resourceId', e, st);
      return false;
    }
  }

  /// Release a lock only if owned by [ownerId]. Returns true if released.
  static Future<bool> releaseLock(String resourceId, String ownerId) async {
    final lockRef = _firestore.collection(_locksCollection).doc(resourceId);

    try {
      return await _firestore.runTransaction<bool>((tx) async {
        final snapshot = await tx.get(lockRef);
        if (!snapshot.exists) return true; // nothing to release

        final data = snapshot.data();
        final currentOwner = data?['ownerId'] as String?;

        if (currentOwner == ownerId) {
          tx.delete(lockRef);
          AppLogger.logInfo('Lock released: $resourceId by $ownerId');
          return true;
        }

        AppLogger.logInfo('Lock not released (owner mismatch): $resourceId expected $ownerId got $currentOwner');
        return false;
      });
    } catch (e, st) {
      AppLogger.logError('Error releasing lock $resourceId', e, st);
      return false;
    }
  }

  /// Helper that retries acquiring a lock a few times with backoff then runs [fn]
  /// if the lock is acquired. The lock is released afterwards if owned.
  static Future<T?> runWithLock<T>(
    String resourceId,
    String ownerId,
    Future<T> Function() fn, {
    int ttlSeconds = 10,
    int maxAttempts = 5,
    Duration initialDelay = const Duration(milliseconds: 200),
  }) async {
    var attempt = 0;
    var delay = initialDelay;
    var acquired = false;

    while (attempt < maxAttempts && !acquired) {
      acquired = await acquireLock(resourceId, ownerId, ttlSeconds: ttlSeconds);
      if (acquired) break;
      await Future.delayed(delay);
      attempt++;
      delay *= 2;
    }

    if (!acquired) {
      AppLogger.logWarning('Could not acquire lock after $maxAttempts attempts: $resourceId');
      return null;
    }

    try {
      return await fn();
    } finally {
      // Best-effort release
      await releaseLock(resourceId, ownerId);
    }
  }
}
