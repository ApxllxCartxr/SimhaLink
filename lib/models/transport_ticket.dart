import 'package:cloud_firestore/cloud_firestore.dart';

enum TicketStatus { valid, used, cancelled }

class QRData {
  final String ticketId;
  final String bookingId;
  final String passengerName;
  final String transportTitle;
  final DateTime departureTime;
  final String verificationHash;

  const QRData({
    required this.ticketId,
    required this.bookingId,
    required this.passengerName,
    required this.transportTitle,
    required this.departureTime,
    required this.verificationHash,
  });

  Map<String, dynamic> toMap() {
    return {
      'ticketId': ticketId,
      'bookingId': bookingId,
      'passengerName': passengerName,
      'transportTitle': transportTitle,
      'departureTime': departureTime.toIso8601String(),
      'verificationHash': verificationHash,
    };
  }

  factory QRData.fromMap(Map<String, dynamic> map) {
    return QRData(
      ticketId: map['ticketId'] ?? '',
      bookingId: map['bookingId'] ?? '',
      passengerName: map['passengerName'] ?? '',
      transportTitle: map['transportTitle'] ?? '',
      departureTime: DateTime.parse(map['departureTime'] ?? DateTime.now().toIso8601String()),
      verificationHash: map['verificationHash'] ?? '',
    );
  }

  String toJsonString() {
    final Map<String, dynamic> data = toMap();
    return data.toString(); // In production, use proper JSON encoding
  }

  factory QRData.fromJsonString(String jsonString) {
    // In production, use proper JSON decoding
    // For now, return a placeholder
    return QRData(
      ticketId: '',
      bookingId: '',
      passengerName: '',
      transportTitle: '',
      departureTime: DateTime.now(),
      verificationHash: '',
    );
  }
}

class TransportTicket {
  final String id;
  final String bookingId;
  final String transportId;
  final String passengerName;
  final String? passengerUserId;
  final String? seatNumber;
  final QRData qrData;
  final TicketStatus status;
  final DateTime createdAt;

  const TransportTicket({
    required this.id,
    required this.bookingId,
    required this.transportId,
    required this.passengerName,
    this.passengerUserId,
    this.seatNumber,
    required this.qrData,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bookingId': bookingId,
      'transportId': transportId,
      'passengerName': passengerName,
      'passengerUserId': passengerUserId,
      'seatNumber': seatNumber,
      'qrData': qrData.toMap(),
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory TransportTicket.fromMap(Map<String, dynamic> map) {
    return TransportTicket(
      id: map['id'] ?? '',
      bookingId: map['bookingId'] ?? '',
      transportId: map['transportId'] ?? '',
      passengerName: map['passengerName'] ?? '',
      passengerUserId: map['passengerUserId'],
      seatNumber: map['seatNumber'],
      qrData: QRData.fromMap(map['qrData'] ?? {}),
      status: TicketStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => TicketStatus.valid,
      ),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory TransportTicket.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return TransportTicket.fromMap(data);
  }

  TransportTicket copyWith({
    String? id,
    String? bookingId,
    String? transportId,
    String? passengerName,
    String? passengerUserId,
    String? seatNumber,
    QRData? qrData,
    TicketStatus? status,
    DateTime? createdAt,
  }) {
    return TransportTicket(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      transportId: transportId ?? this.transportId,
      passengerName: passengerName ?? this.passengerName,
      passengerUserId: passengerUserId ?? this.passengerUserId,
      seatNumber: seatNumber ?? this.seatNumber,
      qrData: qrData ?? this.qrData,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isValid => status == TicketStatus.valid;
  bool get isUsed => status == TicketStatus.used;
  bool get isCancelled => status == TicketStatus.cancelled;

  String get statusDisplayText {
    switch (status) {
      case TicketStatus.valid:
        return 'Valid';
      case TicketStatus.used:
        return 'Used';
      case TicketStatus.cancelled:
        return 'Cancelled';
    }
  }
}
