import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Represents a volunteer's response to an emergency
class EmergencyResponse {
  final String responseId;
  final String emergencyId;
  final String volunteerId;
  final String volunteerName;
  final EmergencyResponseStatus status;
  final DateTime timestamp;
  final DateTime? lastUpdated;
  final LatLng? volunteerLocation;
  final String? estimatedArrivalTime;
  final String? notes;
  final List<LatLng>? routePoints; // For route tracking
  final double? distanceToEmergency;

  const EmergencyResponse({
    required this.responseId,
    required this.emergencyId,
    required this.volunteerId,
    required this.volunteerName,
    required this.status,
    required this.timestamp,
    this.lastUpdated,
    this.volunteerLocation,
    this.estimatedArrivalTime,
    this.notes,
    this.routePoints,
    this.distanceToEmergency,
  });

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'responseId': responseId,
      'emergencyId': emergencyId,
      'volunteerId': volunteerId,
      'volunteerName': volunteerName,
      'status': status.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : null,
      'volunteerLocation': volunteerLocation != null
          ? GeoPoint(volunteerLocation!.latitude, volunteerLocation!.longitude)
          : null,
      'estimatedArrivalTime': estimatedArrivalTime,
      'notes': notes,
      'routePoints': routePoints?.map((point) => GeoPoint(point.latitude, point.longitude)).toList(),
      'distanceToEmergency': distanceToEmergency,
    };
  }

  /// Create from Firestore document
  factory EmergencyResponse.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EmergencyResponse(
      responseId: doc.id,
      emergencyId: data['emergencyId'] ?? '',
      volunteerId: data['volunteerId'] ?? '',
      volunteerName: data['volunteerName'] ?? '',
      status: EmergencyResponseStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => EmergencyResponseStatus.notified,
      ),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate(),
      volunteerLocation: data['volunteerLocation'] != null
          ? LatLng(
              (data['volunteerLocation'] as GeoPoint).latitude,
              (data['volunteerLocation'] as GeoPoint).longitude,
            )
          : null,
      estimatedArrivalTime: data['estimatedArrivalTime'],
      notes: data['notes'],
      routePoints: (data['routePoints'] as List<dynamic>?)
          ?.map((point) => LatLng(
                (point as GeoPoint).latitude,
                point.longitude,
              ))
          .toList(),
      distanceToEmergency: data['distanceToEmergency']?.toDouble(),
    );
  }

  /// Create a copy with updated fields
  EmergencyResponse copyWith({
    EmergencyResponseStatus? status,
    DateTime? lastUpdated,
    LatLng? volunteerLocation,
    String? estimatedArrivalTime,
    String? notes,
    List<LatLng>? routePoints,
    double? distanceToEmergency,
  }) {
    return EmergencyResponse(
      responseId: responseId,
      emergencyId: emergencyId,
      volunteerId: volunteerId,
      volunteerName: volunteerName,
      status: status ?? this.status,
      timestamp: timestamp,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      volunteerLocation: volunteerLocation ?? this.volunteerLocation,
      estimatedArrivalTime: estimatedArrivalTime ?? this.estimatedArrivalTime,
      notes: notes ?? this.notes,
      routePoints: routePoints ?? this.routePoints,
      distanceToEmergency: distanceToEmergency ?? this.distanceToEmergency,
    );
  }

  /// Check if this response is active (volunteer is currently involved)
  bool get isActive => status != EmergencyResponseStatus.completed && 
                      status != EmergencyResponseStatus.unavailable;

  /// Check if volunteer should be tracked (en route or assisting)
  bool get shouldTrackLocation => status == EmergencyResponseStatus.enRoute ||
                                 status == EmergencyResponseStatus.assisting;
}

/// Status of volunteer response to emergency
enum EmergencyResponseStatus {
  notified('Notified', 'Emergency alert received'),
  responding('Responding', 'Confirmed to help'),
  enRoute('En Route', 'On the way to location'),
  arrived('Arrived', 'At the emergency location'),
  assisting('Assisting', 'Providing help'),
  completed('Completed', 'Emergency resolved'),
  unavailable('Unavailable', 'Cannot help at this time');

  const EmergencyResponseStatus(this.displayName, this.description);
  
  final String displayName;
  final String description;

  /// Get the next logical status in the workflow
  EmergencyResponseStatus? get nextStatus {
    switch (this) {
      case EmergencyResponseStatus.notified:
        return EmergencyResponseStatus.responding;
      case EmergencyResponseStatus.responding:
        return EmergencyResponseStatus.enRoute;
      case EmergencyResponseStatus.enRoute:
        return EmergencyResponseStatus.arrived;
      case EmergencyResponseStatus.arrived:
        return EmergencyResponseStatus.assisting;
      case EmergencyResponseStatus.assisting:
        return EmergencyResponseStatus.completed;
      default:
        return null;
    }
  }

  /// Get appropriate color for this status
  Color get statusColor {
    switch (this) {
      case EmergencyResponseStatus.notified:
        return Colors.grey;
      case EmergencyResponseStatus.responding:
        return Colors.blue;
      case EmergencyResponseStatus.enRoute:
        return Colors.orange;
      case EmergencyResponseStatus.arrived:
        return Colors.purple;
      case EmergencyResponseStatus.assisting:
        return Colors.red;
      case EmergencyResponseStatus.completed:
        return Colors.green;
      case EmergencyResponseStatus.unavailable:
        return Colors.grey;
    }
  }

  /// Get appropriate icon for this status
  IconData get statusIcon {
    switch (this) {
      case EmergencyResponseStatus.notified:
        return Icons.notifications;
      case EmergencyResponseStatus.responding:
        return Icons.volunteer_activism;
      case EmergencyResponseStatus.enRoute:
        return Icons.directions_run;
      case EmergencyResponseStatus.arrived:
        return Icons.location_on;
      case EmergencyResponseStatus.assisting:
        return Icons.medical_services;
      case EmergencyResponseStatus.completed:
        return Icons.check_circle;
      case EmergencyResponseStatus.unavailable:
        return Icons.cancel;
    }
  }
}
