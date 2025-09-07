import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/transport_booking.dart';
import '../models/transport_ticket.dart';
import '../models/transport.dart';
import '../core/utils/app_logger.dart';
import 'transport_service.dart';
import 'qr_service.dart';

class TransportBookingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _bookingsCollection = 'transport_bookings';
  static const String _ticketsCollection = 'transport_tickets';

  /// Create a new booking
  static Future<TransportBooking> createBooking({
    required String transportId,
    required String bookerUserId,
    required String bookerName,
    required List<PassengerInfo> passengers,
    String? groupId,
  }) async {
    try {
      // Get transport details
      final transport = await TransportService.getTransport(transportId);
      if (transport == null) {
        throw Exception('Transport not found');
      }

      // Check availability
      final availableSeats = transport.capacity.availableSeats;
      if (passengers.length > availableSeats) {
        throw Exception('Not enough seats available. Available: $availableSeats, Requested: ${passengers.length}');
      }

      // Generate booking ID
      final bookingId = _firestore.collection(_bookingsCollection).doc().id;

      // Generate ticket IDs for each passenger
      final ticketIds = passengers.map((passenger) => 
          _firestore.collection(_ticketsCollection).doc().id).toList();

      // Update passenger info with ticket IDs
      final updatedPassengers = List<PassengerInfo>.generate(passengers.length, (index) {
        return PassengerInfo(
          userId: passengers[index].userId,
          name: passengers[index].name,
          email: passengers[index].email,
          ticketId: ticketIds[index],
        );
      });

      // Calculate total amount
      final totalAmount = transport.pricing.isFree ? 0.0 : 
          transport.pricing.pricePerTicket * passengers.length;

      // Generate QR code for the booking
      final qrCode = await QRService.generateBookingQR(
        bookingId: bookingId,
        transportTitle: transport.title,
        passengers: updatedPassengers,
        departureTime: transport.schedule.departureTime,
      );

      // Create booking object
      final booking = TransportBooking(
        id: bookingId,
        transportId: transportId,
        bookerUserId: bookerUserId,
        bookerName: bookerName,
        groupBooking: GroupBookingInfo(
          isGroupBooking: passengers.length > 1 || groupId != null,
          groupId: groupId,
          totalTickets: passengers.length,
          passengers: updatedPassengers,
        ),
        bookingDetails: BookingDetails(
          totalAmount: totalAmount,
          ticketIds: ticketIds,
          qrCode: qrCode,
        ),
        status: BookingStatus.confirmed,
        paymentStatus: transport.pricing.isFree ? PaymentStatus.free : PaymentStatus.confirmed,
        canTransfer: true,
        canCancel: true,
        bookedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Use transaction to ensure data consistency
      await _firestore.runTransaction((transaction) async {
        // Create booking
        final bookingRef = _firestore.collection(_bookingsCollection).doc(bookingId);
        transaction.set(bookingRef, booking.toMap());

        // Create individual tickets
        for (int i = 0; i < updatedPassengers.length; i++) {
          final passenger = updatedPassengers[i];
          final ticketId = ticketIds[i];

          final qrData = QRData(
            ticketId: ticketId,
            bookingId: bookingId,
            passengerName: passenger.name,
            transportTitle: transport.title,
            departureTime: transport.schedule.departureTime,
            verificationHash: QRService.generateVerificationHash(ticketId, bookingId),
          );

          final ticket = TransportTicket(
            id: ticketId,
            bookingId: bookingId,
            transportId: transportId,
            passengerName: passenger.name,
            passengerUserId: passenger.userId,
            seatNumber: null, // Can be assigned later
            qrData: qrData,
            status: TicketStatus.valid,
            createdAt: DateTime.now(),
          );

          final ticketRef = _firestore.collection(_ticketsCollection).doc(ticketId);
          transaction.set(ticketRef, ticket.toMap());
        }

        // Update transport capacity
        final transportRef = _firestore.collection('transports').doc(transportId);
        final newOccupants = transport.capacity.currentOccupants + passengers.length;
        final newCapacity = transport.capacity.copyWith(currentOccupants: newOccupants);
        final newStatus = newCapacity.isFull ? TransportStatus.full : TransportStatus.active;

        transaction.update(transportRef, {
          'capacity': newCapacity.toMap(),
          'status': newStatus.name,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      });

      AppLogger.logInfo('Booking created successfully: $bookingId');
      return booking;
    } catch (e) {
      AppLogger.logError('Error creating booking', e);
      rethrow;
    }
  }

  /// Get booking by ID
  static Future<TransportBooking?> getBooking(String bookingId) async {
    try {
      final doc = await _firestore.collection(_bookingsCollection).doc(bookingId).get();
      
      if (doc.exists) {
        return TransportBooking.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      AppLogger.logError('Error getting booking: $bookingId', e);
      return null;
    }
  }

  /// Get user's bookings
  static Stream<List<TransportBooking>> getUserBookings(String userId) {
    try {
      return _firestore.collection(_bookingsCollection)
          .where('bookerUserId', isEqualTo: userId)
          .orderBy('bookedAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => TransportBooking.fromFirestore(doc)).toList());
    } catch (e) {
      AppLogger.logError('Error getting user bookings: $userId', e);
      return Stream.value([]);
    }
  }

  /// Get bookings for a specific transport
  static Stream<List<TransportBooking>> getTransportBookings(String transportId) {
    try {
      return _firestore.collection(_bookingsCollection)
          .where('transportId', isEqualTo: transportId)
          .where('status', isEqualTo: BookingStatus.confirmed.name)
          .orderBy('bookedAt')
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => TransportBooking.fromFirestore(doc)).toList());
    } catch (e) {
      AppLogger.logError('Error getting transport bookings: $transportId', e);
      return Stream.value([]);
    }
  }

  /// Cancel a booking
  static Future<void> cancelBooking(String bookingId) async {
    try {
      await _firestore.runTransaction((transaction) async {
        // Get booking
        final bookingRef = _firestore.collection(_bookingsCollection).doc(bookingId);
        final bookingDoc = await transaction.get(bookingRef);
        
        if (!bookingDoc.exists) {
          throw Exception('Booking not found');
        }

        final booking = TransportBooking.fromFirestore(bookingDoc);
        if (booking.status != BookingStatus.confirmed) {
          throw Exception('Booking cannot be cancelled');
        }

        if (!booking.canCancel) {
          throw Exception('This booking cannot be cancelled');
        }

        // Update booking status
        transaction.update(bookingRef, {
          'status': BookingStatus.cancelled.name,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });

        // Cancel all tickets
        for (final ticketId in booking.bookingDetails.ticketIds) {
          final ticketRef = _firestore.collection(_ticketsCollection).doc(ticketId);
          transaction.update(ticketRef, {
            'status': TicketStatus.cancelled.name,
          });
        }

        // Update transport capacity
        final transport = await TransportService.getTransport(booking.transportId);
        if (transport != null) {
          final transportRef = _firestore.collection('transports').doc(booking.transportId);
          final newOccupants = transport.capacity.currentOccupants - booking.groupBooking.totalTickets;
          final newCapacity = transport.capacity.copyWith(currentOccupants: newOccupants);
          
          transaction.update(transportRef, {
            'capacity': newCapacity.toMap(),
            'status': TransportStatus.active.name, // Reopen if was full
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
        }
      });

      AppLogger.logInfo('Booking cancelled successfully: $bookingId');
    } catch (e) {
      AppLogger.logError('Error cancelling booking: $bookingId', e);
      rethrow;
    }
  }

  /// Transfer booking to another user
  static Future<void> transferBooking({
    required String bookingId,
    required String newBookerUserId,
    required String newBookerName,
  }) async {
    try {
      final booking = await getBooking(bookingId);
      if (booking == null) {
        throw Exception('Booking not found');
      }

      if (!booking.canTransfer) {
        throw Exception('This booking cannot be transferred');
      }

      if (booking.status != BookingStatus.confirmed) {
        throw Exception('Only confirmed bookings can be transferred');
      }

      await _firestore.collection(_bookingsCollection).doc(bookingId).update({
        'bookerUserId': newBookerUserId,
        'bookerName': newBookerName,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      AppLogger.logInfo('Booking transferred successfully: $bookingId');
    } catch (e) {
      AppLogger.logError('Error transferring booking: $bookingId', e);
      rethrow;
    }
  }

  /// Get tickets for a booking
  static Future<List<TransportTicket>> getBookingTickets(String bookingId) async {
    try {
      final snapshot = await _firestore.collection(_ticketsCollection)
          .where('bookingId', isEqualTo: bookingId)
          .get();

      return snapshot.docs.map((doc) => TransportTicket.fromFirestore(doc)).toList();
    } catch (e) {
      AppLogger.logError('Error getting booking tickets: $bookingId', e);
      return [];
    }
  }

  /// Get a specific ticket
  static Future<TransportTicket?> getTicket(String ticketId) async {
    try {
      final doc = await _firestore.collection(_ticketsCollection).doc(ticketId).get();
      
      if (doc.exists) {
        return TransportTicket.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      AppLogger.logError('Error getting ticket: $ticketId', e);
      return null;
    }
  }

  /// Verify and use a ticket (for QR scanning)
  static Future<bool> verifyAndUseTicket(String ticketId, String verificationHash) async {
    try {
      final ticket = await getTicket(ticketId);
      if (ticket == null) {
        AppLogger.logError('Ticket not found: $ticketId', null);
        return false;
      }

      // Verify hash
      final expectedHash = QRService.generateVerificationHash(ticketId, ticket.bookingId);
      if (expectedHash != verificationHash) {
        AppLogger.logError('Invalid verification hash for ticket: $ticketId', null);
        return false;
      }

      // Check if ticket is valid
      if (ticket.status != TicketStatus.valid) {
        AppLogger.logError('Ticket is not valid: $ticketId, status: ${ticket.status}', null);
        return false;
      }

      // Mark ticket as used
      await _firestore.collection(_ticketsCollection).doc(ticketId).update({
        'status': TicketStatus.used.name,
      });

      AppLogger.logInfo('Ticket verified and used successfully: $ticketId');
      return true;
    } catch (e) {
      AppLogger.logError('Error verifying ticket: $ticketId', e);
      return false;
    }
  }

  /// Check if user has already booked a specific transport
  static Future<bool> hasUserBookedTransport(String userId, String transportId) async {
    try {
      final snapshot = await _firestore.collection(_bookingsCollection)
          .where('bookerUserId', isEqualTo: userId)
          .where('transportId', isEqualTo: transportId)
          .where('status', isEqualTo: BookingStatus.confirmed.name)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      AppLogger.logError('Error checking user booking: $userId, $transportId', e);
      return false;
    }
  }

  /// Get booking statistics for a transport
  static Future<Map<String, dynamic>> getTransportBookingStats(String transportId) async {
    try {
      final snapshot = await _firestore.collection(_bookingsCollection)
          .where('transportId', isEqualTo: transportId)
          .get();

      int totalBookings = 0;
      int confirmedBookings = 0;
      int cancelledBookings = 0;
      int totalTickets = 0;
      double totalRevenue = 0.0;

      for (final doc in snapshot.docs) {
        final booking = TransportBooking.fromFirestore(doc);
        totalBookings++;
        
        switch (booking.status) {
          case BookingStatus.confirmed:
            confirmedBookings++;
            totalTickets += booking.groupBooking.totalTickets;
            totalRevenue += booking.bookingDetails.totalAmount;
            break;
          case BookingStatus.cancelled:
            cancelledBookings++;
            break;
          case BookingStatus.completed:
            confirmedBookings++;
            totalTickets += booking.groupBooking.totalTickets;
            totalRevenue += booking.bookingDetails.totalAmount;
            break;
        }
      }

      return {
        'totalBookings': totalBookings,
        'confirmedBookings': confirmedBookings,
        'cancelledBookings': cancelledBookings,
        'totalTickets': totalTickets,
        'totalRevenue': totalRevenue,
      };
    } catch (e) {
      AppLogger.logError('Error getting booking stats: $transportId', e);
      return {};
    }
  }

  /// Check if user can book a specific transport (prevents duplicate bookings)
  static Future<bool> canUserBookTransport(String userId, String transportId) async {
    try {
      final existingBookings = await _firestore
          .collection(_bookingsCollection)
          .where('bookerUserId', isEqualTo: userId)
          .where('transportId', isEqualTo: transportId)
          .where('status', isEqualTo: BookingStatus.confirmed.name)
          .get();
      
      return existingBookings.docs.isEmpty;
    } catch (e) {
      AppLogger.logError('Error checking user booking eligibility', e);
      return false;
    }
  }

  /// Get user's existing booking for a transport
  static Future<TransportBooking?> getUserExistingBooking(String userId, String transportId) async {
    try {
      final existingBookings = await _firestore
          .collection(_bookingsCollection)
          .where('bookerUserId', isEqualTo: userId)
          .where('transportId', isEqualTo: transportId)
          .where('status', isEqualTo: BookingStatus.confirmed.name)
          .limit(1)
          .get();
      
      if (existingBookings.docs.isNotEmpty) {
        return TransportBooking.fromFirestore(existingBookings.docs.first);
      }
      return null;
    } catch (e) {
      AppLogger.logError('Error getting user existing booking', e);
      return null;
    }
  }

  /// Get group members eligible for ticket transfer
  static Future<List<Map<String, dynamic>>> getGroupMembersForTransfer({
    required String currentUserId,
    required String groupId,
  }) async {
    try {
      // Get all group members except current user
      final groupDoc = await _firestore
          .collection('groups')
          .doc(groupId)
          .get();
      
      if (!groupDoc.exists) {
        throw Exception('Group not found');
      }
      
      final groupData = groupDoc.data()!;
      final memberIds = List<String>.from(groupData['members'] ?? []);
      
      // Remove current user from the list
      memberIds.remove(currentUserId);
      
      if (memberIds.isEmpty) {
        return [];
      }
      
      // Get user profiles for all group members
      final userProfiles = <Map<String, dynamic>>[];
      
      for (final memberId in memberIds) {
        try {
          final userDoc = await _firestore
              .collection('users')
              .doc(memberId)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data()!;
            userProfiles.add({
              'uid': memberId,
              'displayName': userData['displayName'] ?? 'Unknown User',
              'email': userData['email'] ?? '',
              'photoURL': userData['photoURL'],
            });
          }
        } catch (e) {
          AppLogger.logError('Error fetching user profile: $memberId', e);
          // Continue with other users
        }
      }
      
      return userProfiles;
    } catch (e) {
      AppLogger.logError('Error getting group members for transfer', e);
      rethrow;
    }
  }

  /// Validate if ticket transfer is allowed between users
  static Future<bool> validateTransferEligibility({
    required String fromUserId,
    required String toUserId,
    required String ticketId,
  }) async {
    try {
      // Get ticket details
      final ticketDoc = await _firestore
          .collection(_ticketsCollection)
          .doc(ticketId)
          .get();
      
      if (!ticketDoc.exists) {
        throw Exception('Ticket not found');
      }
      
      // Get booking details
      final ticketData = ticketDoc.data()!;
      final bookingId = ticketData['bookingId'];
      
      final bookingDoc = await _firestore
          .collection(_bookingsCollection)
          .doc(bookingId)
          .get();
      
      if (!bookingDoc.exists) {
        throw Exception('Booking not found');
      }
      
      final booking = TransportBooking.fromFirestore(bookingDoc);
      
      // Get both users' group IDs
      final fromUserDoc = await _firestore
          .collection('users')
          .doc(fromUserId)
          .get();
      
      final toUserDoc = await _firestore
          .collection('users')
          .doc(toUserId)
          .get();
      
      if (!fromUserDoc.exists || !toUserDoc.exists) {
        throw Exception('User not found');
      }
      
      final fromUserData = fromUserDoc.data()!;
      final toUserData = toUserDoc.data()!;
      
      final fromUserGroupId = fromUserData['groupId'] as String?;
      final toUserGroupId = toUserData['groupId'] as String?;
      
      // Validate same group membership
      if (fromUserGroupId == null || toUserGroupId == null) {
        throw Exception('Both users must be in a group');
      }
      
      if (fromUserGroupId != toUserGroupId) {
        throw Exception('Users must be in the same group to transfer tickets');
      }
      
      // Validate booking ownership or group booking participation
      if (booking.bookerUserId != fromUserId && 
          !booking.groupBooking.passengers.any((p) => p.userId == fromUserId)) {
        throw Exception('You can only transfer tickets from your own bookings');
      }
      
      // Validate ticket is not already transferred
      if (ticketData['transferredTo'] != null) {
        throw Exception('This ticket has already been transferred');
      }
      
      // Validate ticket status
      if (ticketData['status'] != TicketStatus.valid.name) {
        throw Exception('Only valid tickets can be transferred');
      }
      
      return true;
    } catch (e) {
      AppLogger.logError('Error validating transfer eligibility', e);
      rethrow;
    }
  }

  /// Transfer ticket to another group member
  static Future<bool> transferTicketToGroupMember({
    required String ticketId,
    required String fromUserId,
    required String toUserId,
    required String toUserName,
    required String toUserEmail,
    String? transferNote,
  }) async {
    try {
      // Validate transfer eligibility first
      await validateTransferEligibility(
        fromUserId: fromUserId,
        toUserId: toUserId,
        ticketId: ticketId,
      );
      
      await _firestore.runTransaction((transaction) async {
        // Get ticket and booking details
        final ticketDoc = await transaction.get(
          _firestore.collection(_ticketsCollection).doc(ticketId)
        );
        
        final ticketData = ticketDoc.data()!;
        final bookingId = ticketData['bookingId'];
        
        // Update ticket with new owner
        transaction.update(
          _firestore.collection(_ticketsCollection).doc(ticketId),
          {
            'passengerName': toUserName,
            'passengerUserId': toUserId,
            'qrData.passengerName': toUserName,
            'transferredAt': FieldValue.serverTimestamp(),
            'transferredFrom': fromUserId,
            'transferredTo': toUserId,
            'transferNote': transferNote,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        
        // Update booking passengers list
        final bookingDoc = await transaction.get(
          _firestore.collection(_bookingsCollection).doc(bookingId)
        );
        
        final booking = TransportBooking.fromFirestore(bookingDoc);
        
        // Update passenger in the booking
        final updatedPassengers = booking.groupBooking.passengers.map((passenger) {
          if (passenger.ticketId == ticketId) {
            return PassengerInfo(
              userId: toUserId,
              name: toUserName,
              email: toUserEmail.isEmpty ? null : toUserEmail,
              ticketId: ticketId,
            );
          }
          return passenger;
        }).toList();
        
        transaction.update(
          _firestore.collection(_bookingsCollection).doc(bookingId),
          {
            'groupBooking.passengers': updatedPassengers.map((p) => {
              'userId': p.userId,
              'name': p.name,
              'email': p.email,
              'ticketId': p.ticketId,
            }).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        
        // Create transfer record
        transaction.set(
          _firestore.collection('ticket_transfers').doc(),
          {
            'ticketId': ticketId,
            'bookingId': bookingId,
            'fromUserId': fromUserId,
            'toUserId': toUserId,
            'toUserName': toUserName,
            'toUserEmail': toUserEmail,
            'transferNote': transferNote,
            'transferredAt': FieldValue.serverTimestamp(),
            'status': 'completed',
          },
        );
      });
      
      AppLogger.logInfo('Ticket transferred successfully: $ticketId from $fromUserId to $toUserId');
      return true;
    } catch (e) {
      AppLogger.logError('Error transferring ticket to group member', e);
      rethrow;
    }
  }

  /// Modify existing booking (add/remove passengers)
  static Future<bool> modifyBooking({
    required String bookingId,
    required int newTicketCount,
    required List<PassengerInfo> newPassengers,
    required String modifiedBy,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        // Get current booking
        final bookingDoc = await transaction.get(
          _firestore.collection(_bookingsCollection).doc(bookingId)
        );
        
        if (!bookingDoc.exists) {
          throw Exception('Booking not found');
        }
        
        final currentBooking = TransportBooking.fromFirestore(bookingDoc);
        
        // Check transport capacity
        final transportDoc = await transaction.get(
          _firestore.collection('transports').doc(currentBooking.transportId)
        );
        
        if (!transportDoc.exists) {
          throw Exception('Transport not found');
        }
        
        final transportData = transportDoc.data()!;
        final currentOccupants = transportData['capacity']['currentOccupants'] as int;
        final maxOccupants = transportData['capacity']['maxOccupants'] as int;
        
        final capacityDifference = newTicketCount - currentBooking.groupBooking.totalTickets;
        final newOccupancy = currentOccupants + capacityDifference;
        
        if (newOccupancy > maxOccupants) {
          throw Exception('Not enough seats available');
        }
        
        // Generate new ticket IDs for new passengers
        final updatedPassengers = newPassengers.map((passenger) {
          if (passenger.ticketId.isEmpty) {
            return PassengerInfo(
              userId: passenger.userId,
              name: passenger.name,
              email: passenger.email,
              ticketId: _firestore.collection(_ticketsCollection).doc().id,
            );
          }
          return passenger;
        }).toList();
        
        // Calculate new amount
        final transport = await TransportService.getTransport(currentBooking.transportId);
        final newAmount = transport?.pricing.isFree == true ? 0.0 : 
            (transport?.pricing.pricePerTicket ?? 0.0) * newTicketCount;
        
        // Update booking document
        transaction.update(
          _firestore.collection(_bookingsCollection).doc(bookingId),
          {
            'groupBooking.totalTickets': newTicketCount,
            'groupBooking.passengers': updatedPassengers.map((p) => {
              'userId': p.userId,
              'name': p.name,
              'email': p.email,
              'ticketId': p.ticketId,
            }).toList(),
            'bookingDetails.totalAmount': newAmount,
            'bookingDetails.ticketIds': updatedPassengers.map((p) => p.ticketId).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        
        // Update transport capacity
        transaction.update(
          _firestore.collection('transports').doc(currentBooking.transportId),
          {
            'capacity.currentOccupants': newOccupancy,
            'capacity.availableSeats': maxOccupants - newOccupancy,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        
        // Create/update individual tickets for new passengers
        for (final passenger in updatedPassengers) {
          if (!currentBooking.groupBooking.passengers.any((p) => p.ticketId == passenger.ticketId)) {
            // This is a new ticket
            final qrData = QRData(
              ticketId: passenger.ticketId,
              bookingId: bookingId,
              passengerName: passenger.name,
              transportTitle: transport?.title ?? 'Transport',
              departureTime: transport?.schedule.departureTime ?? DateTime.now(),
              verificationHash: QRService.generateVerificationHash(passenger.ticketId, bookingId),
            );
            
            final ticket = TransportTicket(
              id: passenger.ticketId,
              bookingId: bookingId,
              transportId: currentBooking.transportId,
              passengerName: passenger.name,
              passengerUserId: passenger.userId,
              seatNumber: null,
              qrData: qrData,
              status: TicketStatus.valid,
              createdAt: DateTime.now(),
            );
            
            transaction.set(
              _firestore.collection(_ticketsCollection).doc(passenger.ticketId),
              ticket.toMap(),
            );
          }
        }
        
        // Add modification audit log
        transaction.set(
          _firestore.collection('booking_modifications').doc(),
          {
            'bookingId': bookingId,
            'modifiedBy': modifiedBy,
            'modificationType': 'passenger_update',
            'previousTicketCount': currentBooking.groupBooking.totalTickets,
            'newTicketCount': newTicketCount,
            'modifiedAt': FieldValue.serverTimestamp(),
          },
        );
      });
      
      AppLogger.logInfo('Booking modified successfully: $bookingId');
      return true;
    } catch (e) {
      AppLogger.logError('Error modifying booking', e);
      rethrow;
    }
  }
}
