import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:simha_link/core/utils/app_logger.dart';

/// Service for optimizing Firebase operations with batching and caching
class FirebaseOptimizationService {
  static final Map<String, Timer> _batchTimers = {};
  static final Map<String, List<BatchOperation>> _batchOperations = {};
  static final Map<String, CachedDocument> _documentCache = {};
  
  /// Batch writes to reduce Firebase costs and improve performance
  static Future<void> batchWrite(
    String batchKey, 
    DocumentReference ref, 
    Map<String, dynamic> data, {
    bool merge = true,
  }) async {
    _batchOperations[batchKey] ??= [];
    _batchOperations[batchKey]!.add(BatchOperation(ref, data, merge));
    
    // Cancel existing timer
    _batchTimers[batchKey]?.cancel();
    
    // Set new timer to execute batch after 500ms of inactivity
    _batchTimers[batchKey] = Timer(const Duration(milliseconds: 500), () async {
      await _executeBatch(batchKey);
    });
  }
  
  /// Execute batched operations
  static Future<void> _executeBatch(String batchKey) async {
    final operations = _batchOperations[batchKey];
    if (operations == null || operations.isEmpty) return;
    
    try {
      final batch = FirebaseFirestore.instance.batch();
      
      for (final operation in operations) {
        batch.set(
          operation.ref, 
          operation.data, 
          SetOptions(merge: operation.merge),
        );
      }
      
      await batch.commit();
      AppLogger.logInfo('Executed batch: $batchKey with ${operations.length} operations');
      
      _batchOperations[batchKey]!.clear();
    } catch (e) {
      AppLogger.logError('Error executing batch $batchKey', e);
      // Retry individual operations on batch failure
      for (final operation in operations) {
        try {
          await operation.ref.set(operation.data, SetOptions(merge: operation.merge));
        } catch (retryError) {
          AppLogger.logError('Failed to retry operation', retryError);
        }
      }
      _batchOperations[batchKey]!.clear();
    }
  }
  
  /// Cache frequently accessed documents
  static Future<DocumentSnapshot> getCachedDocument(
    String path, {
    Duration cacheFor = const Duration(minutes: 5),
  }) async {
    final cached = _documentCache[path];
    
    if (cached != null && DateTime.now().difference(cached.timestamp) < cacheFor) {
      AppLogger.logInfo('Using cached document: $path');
      return cached.document;
    }
    
    AppLogger.logInfo('Fetching fresh document: $path');
    final doc = await FirebaseFirestore.instance.doc(path).get();
    _documentCache[path] = CachedDocument(doc, DateTime.now());
    
    return doc;
  }
  
  /// Clear cache for a specific document
  static void clearCache(String path) {
    _documentCache.remove(path);
  }
  
  /// Clear all cached documents
  static void clearAllCache() {
    _documentCache.clear();
  }
  
  /// Force execute all pending batches (useful for app pause/resume)
  static Future<void> flushAllBatches() async {
    final futures = <Future>[];
    
    for (final batchKey in _batchTimers.keys.toList()) {
      _batchTimers[batchKey]?.cancel();
      futures.add(_executeBatch(batchKey));
    }
    
    await Future.wait(futures);
    _batchTimers.clear();
  }
}

/// Represents a batched Firebase operation
class BatchOperation {
  final DocumentReference ref;
  final Map<String, dynamic> data;
  final bool merge;
  
  BatchOperation(this.ref, this.data, this.merge);
}

/// Cached document with timestamp
class CachedDocument {
  final DocumentSnapshot document;
  final DateTime timestamp;
  
  CachedDocument(this.document, this.timestamp);
}
