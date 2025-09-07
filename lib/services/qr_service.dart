import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/transport_booking.dart';

class QRService {
  static const String _secretKey = 'simha_link_transport_qr_secret_2024';

  /// Generate QR code data for a booking
  static Future<String> generateBookingQR({
    required String bookingId,
    required String transportTitle,
    required List<PassengerInfo> passengers,
    required DateTime departureTime,
  }) async {
    try {
      final qrData = {
        'type': 'transport_booking',
        'bookingId': bookingId,
        'transportTitle': transportTitle,
        'passengerCount': passengers.length,
        'departureTime': departureTime.toIso8601String(),
        'timestamp': DateTime.now().toIso8601String(),
        'hash': generateVerificationHash(bookingId, bookingId),
      };

      // Convert to JSON string
      final jsonString = jsonEncode(qrData);
      
      // Encode to base64 for QR code
      final qrCode = base64Encode(utf8.encode(jsonString));
      
      return qrCode;
    } catch (e) {
      throw Exception('Failed to generate QR code: $e');
    }
  }

  /// Generate verification hash for security
  static String generateVerificationHash(String ticketId, String bookingId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ (1000 * 60 * 5); // 5-minute windows
    final data = '$ticketId:$bookingId:$_secretKey:$timestamp';
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // First 16 characters
  }

  /// Verify QR code data
  static Map<String, dynamic>? verifyQRCode(String qrCode) {
    try {
      // Decode from base64
      final decodedBytes = base64Decode(qrCode);
      final jsonString = utf8.decode(decodedBytes);
      
      // Parse JSON
      final qrData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Basic validation
      if (qrData['type'] != 'transport_booking') {
        return null;
      }

      // Check if QR code is not too old (24 hours)
      final timestamp = DateTime.parse(qrData['timestamp']);
      final now = DateTime.now();
      if (now.difference(timestamp).inHours > 24) {
        return null;
      }

      return qrData;
    } catch (e) {
      return null;
    }
  }

  /// Generate a simple ticket reference code
  static String generateTicketReference() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
        8, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  /// Generate a booking reference code
  static String generateBookingReference() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return 'SL-' + String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  /// Create QR data for display
  static Map<String, dynamic> createQRDisplayData({
    required String bookingId,
    required String transportTitle,
    required String passengerName,
    required DateTime departureTime,
    required String ticketId,
  }) {
    return {
      'bookingId': bookingId,
      'transportTitle': transportTitle,
      'passengerName': passengerName,
      'departureTime': departureTime.toIso8601String(),
      'ticketId': ticketId,
      'reference': generateTicketReference(),
      'validUntil': departureTime.add(const Duration(hours: 2)).toIso8601String(),
    };
  }

  /// Validate hash with time tolerance
  static bool validateHashWithTolerance(String providedHash, String ticketId, String bookingId) {
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ (1000 * 60 * 5);
    
    // Check current 5-minute window and previous one
    for (int i = 0; i <= 1; i++) {
      final timestamp = currentTime - i;
      final data = '$ticketId:$bookingId:$_secretKey:$timestamp';
      final bytes = utf8.encode(data);
      final digest = sha256.convert(bytes);
      final expectedHash = digest.toString().substring(0, 16);
      
      if (expectedHash == providedHash) {
        return true;
      }
    }
    
    return false;
  }

  /// Create QR code URL for display (placeholder)
  static String getQRCodeUrl(String qrData) {
    // In a real app, you might use a QR code generation service
    // For now, return a placeholder URL
    final encodedData = Uri.encodeComponent(qrData);
    return 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$encodedData';
  }
}
