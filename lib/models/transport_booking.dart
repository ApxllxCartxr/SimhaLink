import 'package:cloud_firestore/cloud_firestore.dart';

enum BookingStatus { confirmed, cancelled, completed }

enum PaymentStatus { free, confirmed, pending }

class PassengerInfo {
  final String? userId;
  final String name;
  final String? email;
  final String ticketId;

  const PassengerInfo({
    this.userId,
    required this.name,
    this.email,
    required this.ticketId,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'ticketId': ticketId,
    };
  }

  factory PassengerInfo.fromMap(Map<String, dynamic> map) {
    return PassengerInfo(
      userId: map['userId'],
      name: map['name'] ?? '',
      email: map['email'],
      ticketId: map['ticketId'] ?? '',
    );
  }
}

class GroupBookingInfo {
  final bool isGroupBooking;
  final String? groupId;
  final int totalTickets;
  final List<PassengerInfo> passengers;

  const GroupBookingInfo({
    required this.isGroupBooking,
    this.groupId,
    required this.totalTickets,
    required this.passengers,
  });

  Map<String, dynamic> toMap() {
    return {
      'isGroupBooking': isGroupBooking,
      'groupId': groupId,
      'totalTickets': totalTickets,
      'passengers': passengers.map((p) => p.toMap()).toList(),
    };
  }

  factory GroupBookingInfo.fromMap(Map<String, dynamic> map) {
    final passengersData = map['passengers'] as List<dynamic>? ?? [];
    return GroupBookingInfo(
      isGroupBooking: map['isGroupBooking'] ?? false,
      groupId: map['groupId'],
      totalTickets: map['totalTickets'] ?? 1,
      passengers: passengersData.map((p) => PassengerInfo.fromMap(p)).toList(),
    );
  }
}

class BookingDetails {
  final double totalAmount;
  final List<String> ticketIds;
  final String qrCode;

  const BookingDetails({
    required this.totalAmount,
    required this.ticketIds,
    required this.qrCode,
  });

  Map<String, dynamic> toMap() {
    return {
      'totalAmount': totalAmount,
      'ticketIds': ticketIds,
      'qrCode': qrCode,
    };
  }

  factory BookingDetails.fromMap(Map<String, dynamic> map) {
    return BookingDetails(
      totalAmount: (map['totalAmount'] ?? 0.0).toDouble(),
      ticketIds: List<String>.from(map['ticketIds'] ?? []),
      qrCode: map['qrCode'] ?? '',
    );
  }
}

class TransportBooking {
  final String id;
  final String transportId;
  final String bookerUserId;
  final String bookerName;
  final GroupBookingInfo groupBooking;
  final BookingDetails bookingDetails;
  final BookingStatus status;
  final PaymentStatus paymentStatus;
  final bool canTransfer;
  final bool canCancel;
  final DateTime bookedAt;
  final DateTime updatedAt;

  const TransportBooking({
    required this.id,
    required this.transportId,
    required this.bookerUserId,
    required this.bookerName,
    required this.groupBooking,
    required this.bookingDetails,
    required this.status,
    required this.paymentStatus,
    required this.canTransfer,
    required this.canCancel,
    required this.bookedAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transportId': transportId,
      'bookerUserId': bookerUserId,
      'bookerName': bookerName,
      'groupBooking': groupBooking.toMap(),
      'bookingDetails': bookingDetails.toMap(),
      'status': status.name,
      'paymentStatus': paymentStatus.name,
      'canTransfer': canTransfer,
      'canCancel': canCancel,
      'bookedAt': Timestamp.fromDate(bookedAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory TransportBooking.fromMap(Map<String, dynamic> map) {
    return TransportBooking(
      id: map['id'] ?? '',
      transportId: map['transportId'] ?? '',
      bookerUserId: map['bookerUserId'] ?? '',
      bookerName: map['bookerName'] ?? '',
      groupBooking: GroupBookingInfo.fromMap(map['groupBooking'] ?? {}),
      bookingDetails: BookingDetails.fromMap(map['bookingDetails'] ?? {}),
      status: BookingStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => BookingStatus.confirmed,
      ),
      paymentStatus: PaymentStatus.values.firstWhere(
        (e) => e.name == map['paymentStatus'],
        orElse: () => PaymentStatus.free,
      ),
      canTransfer: map['canTransfer'] ?? true,
      canCancel: map['canCancel'] ?? true,
      bookedAt: (map['bookedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory TransportBooking.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return TransportBooking.fromMap(data);
  }

  TransportBooking copyWith({
    String? id,
    String? transportId,
    String? bookerUserId,
    String? bookerName,
    GroupBookingInfo? groupBooking,
    BookingDetails? bookingDetails,
    BookingStatus? status,
    PaymentStatus? paymentStatus,
    bool? canTransfer,
    bool? canCancel,
    DateTime? bookedAt,
    DateTime? updatedAt,
  }) {
    return TransportBooking(
      id: id ?? this.id,
      transportId: transportId ?? this.transportId,
      bookerUserId: bookerUserId ?? this.bookerUserId,
      bookerName: bookerName ?? this.bookerName,
      groupBooking: groupBooking ?? this.groupBooking,
      bookingDetails: bookingDetails ?? this.bookingDetails,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      canTransfer: canTransfer ?? this.canTransfer,
      canCancel: canCancel ?? this.canCancel,
      bookedAt: bookedAt ?? this.bookedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isActive => status == BookingStatus.confirmed;
  bool get isCancelled => status == BookingStatus.cancelled;
  bool get isCompleted => status == BookingStatus.completed;

  String get statusDisplayText {
    switch (status) {
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Completed';
    }
  }

  String get paymentStatusDisplayText {
    switch (paymentStatus) {
      case PaymentStatus.free:
        return 'Free';
      case PaymentStatus.confirmed:
        return 'Paid';
      case PaymentStatus.pending:
        return 'Payment Pending';
    }
  }
}
