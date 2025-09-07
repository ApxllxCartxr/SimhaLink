import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transport.dart';
import '../models/user_profile.dart';
import '../core/utils/app_logger.dart';

class TransportService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _transportsCollection = 'transports';

  /// Create a new transport
  static Future<String> createTransport(Transport transport) async {
    try {
      final docRef = await _firestore.collection(_transportsCollection).add(transport.toMap());
      
      // Update the transport with the generated ID
      await docRef.update({'id': docRef.id});
      
      AppLogger.logInfo('Transport created successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      AppLogger.logError('Error creating transport', e);
      rethrow;
    }
  }

  /// Get a transport by ID
  static Future<Transport?> getTransport(String transportId) async {
    try {
      final doc = await _firestore.collection(_transportsCollection).doc(transportId).get();
      
      if (doc.exists) {
        return Transport.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      AppLogger.logError('Error getting transport: $transportId', e);
      return null;
    }
  }

  /// Update a transport
  static Future<void> updateTransport(String transportId, Map<String, dynamic> updates) async {
    try {
      updates['updatedAt'] = Timestamp.fromDate(DateTime.now());
      await _firestore.collection(_transportsCollection).doc(transportId).update(updates);
      AppLogger.logInfo('Transport updated successfully: $transportId');
    } catch (e) {
      AppLogger.logError('Error updating transport: $transportId', e);
      rethrow;
    }
  }

  /// Update transport capacity
  static Future<void> updateTransportCapacity(String transportId, int newOccupants) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final transportRef = _firestore.collection(_transportsCollection).doc(transportId);
        final transportDoc = await transaction.get(transportRef);
        
        if (!transportDoc.exists) {
          throw Exception('Transport not found');
        }

        final transport = Transport.fromFirestore(transportDoc);
        final newCapacity = transport.capacity.copyWith(currentOccupants: newOccupants);
        final newStatus = newCapacity.isFull ? TransportStatus.full : TransportStatus.active;

        transaction.update(transportRef, {
          'capacity': newCapacity.toMap(),
          'status': newStatus.name,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      });
      
      AppLogger.logInfo('Transport capacity updated: $transportId, occupants: $newOccupants');
    } catch (e) {
      AppLogger.logError('Error updating transport capacity: $transportId', e);
      rethrow;
    }
  }

  /// Delete a transport
  static Future<void> deleteTransport(String transportId) async {
    try {
      await _firestore.collection(_transportsCollection).doc(transportId).delete();
      AppLogger.logInfo('Transport deleted successfully: $transportId');
    } catch (e) {
      AppLogger.logError('Error deleting transport: $transportId', e);
      rethrow;
    }
  }

  /// Get all available transports for a user
  static Stream<List<Transport>> getAvailableTransports({
    UserProfile? userProfile,
    String? groupId,
  }) {
    try {
      Query query = _firestore.collection(_transportsCollection)
          .where('status', whereIn: [TransportStatus.active.name, TransportStatus.full.name])
          .orderBy('schedule.departureTime');

      return query.snapshots().map((snapshot) {
        final transports = snapshot.docs.map((doc) => Transport.fromFirestore(doc)).toList();
        
        // Filter based on user access
        return transports.where((transport) {
          // Public transports are available to everyone
          if (transport.visibility == TransportVisibility.public) {
            return true;
          }
          
          // Group-only transports
          if (transport.visibility == TransportVisibility.groupOnly) {
            // Solo users can't access group-only transports
            if (groupId == null) return false;
            
            // Check if user's group is in allowed groups
            return transport.allowedGroupIds.isEmpty || 
                   transport.allowedGroupIds.contains(groupId);
          }
          
          return false;
        }).toList();
      });
    } catch (e) {
      AppLogger.logError('Error getting available transports', e);
      return Stream.value([]);
    }
  }

  /// Get transports created by a specific organizer
  static Stream<List<Transport>> getOrganizerTransports(String organizerId) {
    try {
      return _firestore.collection(_transportsCollection)
          .where('organizerId', isEqualTo: organizerId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => Transport.fromFirestore(doc)).toList());
    } catch (e) {
      AppLogger.logError('Error getting organizer transports: $organizerId', e);
      return Stream.value([]);
    }
  }

  /// Get upcoming transports (departing in the future)
  static Stream<List<Transport>> getUpcomingTransports({
    UserProfile? userProfile,
    String? groupId,
  }) {
    try {
      final now = Timestamp.fromDate(DateTime.now());
      
      Query query = _firestore.collection(_transportsCollection)
          .where('schedule.departureTime', isGreaterThan: now)
          .where('status', isEqualTo: TransportStatus.active.name)
          .orderBy('schedule.departureTime');

      return query.snapshots().map((snapshot) {
        final transports = snapshot.docs.map((doc) => Transport.fromFirestore(doc)).toList();
        
        // Apply the same filtering as getAvailableTransports
        return transports.where((transport) {
          if (transport.visibility == TransportVisibility.public) {
            return true;
          }
          
          if (transport.visibility == TransportVisibility.groupOnly) {
            if (groupId == null) return false;
            return transport.allowedGroupIds.isEmpty || 
                   transport.allowedGroupIds.contains(groupId);
          }
          
          return false;
        }).toList();
      });
    } catch (e) {
      AppLogger.logError('Error getting upcoming transports', e);
      return Stream.value([]);
    }
  }

  /// Search transports by route (from/to addresses)
  static Future<List<Transport>> searchTransports({
    String? fromAddress,
    String? toAddress,
    DateTime? departureDate,
    UserProfile? userProfile,
    String? groupId,
  }) async {
    try {
      Query query = _firestore.collection(_transportsCollection)
          .where('status', isEqualTo: TransportStatus.active.name);

      // Add date filter if provided
      if (departureDate != null) {
        final startOfDay = DateTime(departureDate.year, departureDate.month, departureDate.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        
        query = query
            .where('schedule.departureTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('schedule.departureTime', isLessThan: Timestamp.fromDate(endOfDay));
      }

      final snapshot = await query.get();
      List<Transport> transports = snapshot.docs.map((doc) => Transport.fromFirestore(doc)).toList();

      // Filter by addresses if provided
      if (fromAddress != null && fromAddress.isNotEmpty) {
        transports = transports.where((transport) => 
            transport.route.fromAddress.toLowerCase().contains(fromAddress.toLowerCase())).toList();
      }

      if (toAddress != null && toAddress.isNotEmpty) {
        transports = transports.where((transport) => 
            transport.route.toAddress.toLowerCase().contains(toAddress.toLowerCase())).toList();
      }

      // Apply access filtering
      transports = transports.where((transport) {
        if (transport.visibility == TransportVisibility.public) {
          return true;
        }
        
        if (transport.visibility == TransportVisibility.groupOnly) {
          if (groupId == null) return false;
          return transport.allowedGroupIds.isEmpty || 
                 transport.allowedGroupIds.contains(groupId);
        }
        
        return false;
      }).toList();

      return transports;
    } catch (e) {
      AppLogger.logError('Error searching transports', e);
      return [];
    }
  }

  /// Check if user can access a transport
  static bool canUserAccessTransport(Transport transport, {String? groupId}) {
    if (transport.visibility == TransportVisibility.public) {
      return true;
    }
    
    if (transport.visibility == TransportVisibility.groupOnly) {
      if (groupId == null) return false;
      return transport.allowedGroupIds.isEmpty || 
             transport.allowedGroupIds.contains(groupId);
    }
    
    return false;
  }

  /// Check if user can modify a transport (only creator/organizer)
  static bool canUserModifyTransport(Transport transport, {String? userId}) {
    if (userId == null) return false;
    return transport.organizerId == userId;
  }

  /// Update transport status
  static Future<void> updateTransportStatus(String transportId, TransportStatus status) async {
    try {
      await updateTransport(transportId, {
        'status': status.name,
      });
    } catch (e) {
      AppLogger.logError('Error updating transport status: $transportId', e);
      rethrow;
    }
  }

  /// Mark transport as departed
  static Future<void> markTransportDeparted(String transportId) async {
    await updateTransportStatus(transportId, TransportStatus.departed);
  }

  /// Cancel transport
  static Future<void> cancelTransport(String transportId) async {
    await updateTransportStatus(transportId, TransportStatus.cancelled);
  }
}
