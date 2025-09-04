import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

/// Represents an emergency in the system
class Emergency {
  final String emergencyId;
  final String attendeeId;
  final String attendeeName;
  final String groupId;
  final LatLng location;
  final String? message;
  final EmergencyStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, EmergencyVolunteerResponse> responses;
  final EmergencyResolution resolvedBy;
  
  // NEW: Verification and timeline fields
  final DateTime? acceptedAt;        // When volunteer accepted
  final DateTime? arrivedAt;         // When volunteer marked as arrived
  final DateTime? verifiedAt;        // When volunteer verified emergency
  final DateTime? resolvedAt;        // When emergency was resolved
  final String? verifiedBy;          // Volunteer ID who verified
  final bool isVerified;             // Whether emergency has been verified
  final bool isSeriousEscalation;    // Whether marked for escalation
  final String? escalationReason;    // Reason for escalation

  const Emergency({
    required this.emergencyId,
    required this.attendeeId,
    required this.attendeeName,
    required this.groupId,
    required this.location,
    this.message,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.responses,
    required this.resolvedBy,
    // NEW: Verification and timeline fields
    this.acceptedAt,
    this.arrivedAt,
    this.verifiedAt,
    this.resolvedAt,
    this.verifiedBy,
    this.isVerified = false,
    this.isSeriousEscalation = false,
    this.escalationReason,
  });

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'emergencyId': emergencyId,
      'attendeeId': attendeeId,
      'attendeeName': attendeeName,
      'groupId': groupId,
      'location': GeoPoint(location.latitude, location.longitude),
      'message': message,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'responses': responses.map((key, value) => MapEntry(key, value.toMap())),
      'resolvedBy': resolvedBy.toMap(),
      // NEW: Verification and timeline fields
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'arrivedAt': arrivedAt != null ? Timestamp.fromDate(arrivedAt!) : null,
      'verifiedAt': verifiedAt != null ? Timestamp.fromDate(verifiedAt!) : null,
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'verifiedBy': verifiedBy,
      'isVerified': isVerified,
      'isSeriousEscalation': isSeriousEscalation,
      'escalationReason': escalationReason,
    };
  }

  /// Create from Firestore document
  factory Emergency.fromFirestore(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      final locationGeo = data['location'] as GeoPoint;
      
      return Emergency(
        emergencyId: data['emergencyId'] ?? doc.id,
        attendeeId: data['attendeeId'] ?? '',
        attendeeName: data['attendeeName'] ?? '',
        groupId: data['groupId'] ?? '',
        location: LatLng(locationGeo.latitude, locationGeo.longitude),
        message: data['message'],
        status: EmergencyStatus.values.firstWhere(
          (e) => e.name == data['status'],
          orElse: () => EmergencyStatus.unverified, // NEW: Default to unverified
        ),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        responses: (data['responses'] as Map<String, dynamic>? ?? {})
            .map((key, value) => MapEntry(
                  key,
                  EmergencyVolunteerResponse.fromMap(value as Map<String, dynamic>),
                )),
        resolvedBy: EmergencyResolution.fromMap(
          data['resolvedBy'] as Map<String, dynamic>? ?? {},
        ),
        // NEW: Verification and timeline fields
        acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
        arrivedAt: (data['arrivedAt'] as Timestamp?)?.toDate(),
        verifiedAt: (data['verifiedAt'] as Timestamp?)?.toDate(),
        resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
        verifiedBy: data['verifiedBy'] as String?,
        isVerified: data['isVerified'] as bool? ?? false,
        isSeriousEscalation: data['isSeriousEscalation'] as bool? ?? false,
        escalationReason: data['escalationReason'] as String?,
      );
    } catch (e) {
      // Log the error for debugging
      print('🚨 Error creating Emergency from Firestore document ${doc.id}: $e');
      rethrow;
    }
  }

  /// Create copy with updated fields
  Emergency copyWith({
    String? emergencyId,
    String? attendeeId,
    String? attendeeName,
    String? groupId,
    LatLng? location,
    String? message,
    EmergencyStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, EmergencyVolunteerResponse>? responses,
    EmergencyResolution? resolvedBy,
    // NEW: Verification and timeline fields
    DateTime? acceptedAt,
    DateTime? arrivedAt,
    DateTime? verifiedAt,
    DateTime? resolvedAt,
    String? verifiedBy,
    bool? isVerified,
    bool? isSeriousEscalation,
    String? escalationReason,
  }) {
    return Emergency(
      emergencyId: emergencyId ?? this.emergencyId,
      attendeeId: attendeeId ?? this.attendeeId,
      attendeeName: attendeeName ?? this.attendeeName,
      groupId: groupId ?? this.groupId,
      location: location ?? this.location,
      message: message ?? this.message,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      responses: responses ?? this.responses,
      resolvedBy: resolvedBy ?? this.resolvedBy,
      // NEW: Verification and timeline fields
      acceptedAt: acceptedAt ?? this.acceptedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      isVerified: isVerified ?? this.isVerified,
      isSeriousEscalation: isSeriousEscalation ?? this.isSeriousEscalation,
      escalationReason: escalationReason ?? this.escalationReason,
    );
  }

  /// Check if emergency is active (not resolved or fake)
  bool get isActive => status != EmergencyStatus.resolved && status != EmergencyStatus.fake;

  /// Check if emergency is fully resolved
  bool get isFullyResolved => resolvedBy.attendee && resolvedBy.hasVolunteerCompleted;

  /// Get active volunteer responses
  List<EmergencyVolunteerResponse> get activeResponses {
    return responses.values
        .where((response) => response.status != EmergencyVolunteerStatus.unavailable)
        .toList();
  }
}

/// Emergency status enum
enum EmergencyStatus {
  unverified,    // NEW: Initial state - emergency created but not verified
  accepted,      // NEW: Volunteer has accepted and is responding
  inProgress,    // Existing: Volunteer has arrived and is handling
  verified,      // NEW: Emergency confirmed as real by volunteer
  resolved,      // Existing: Emergency completed successfully
  fake,          // NEW: Emergency marked as fake by volunteer
  escalated,     // NEW: Emergency escalated for serious situations
}

extension EmergencyStatusExtension on EmergencyStatus {
  /// Get display name for status
  String get displayName {
    switch (this) {
      case EmergencyStatus.unverified:
        return 'Unverified';
      case EmergencyStatus.accepted:
        return 'Help Coming';
      case EmergencyStatus.inProgress:
        return 'In Progress';
      case EmergencyStatus.verified:
        return 'Verified';
      case EmergencyStatus.resolved:
        return 'Resolved';
      case EmergencyStatus.fake:
        return 'Fake';
      case EmergencyStatus.escalated:
        return 'Escalated';
    }
  }

  /// Get color for status
  Color get statusColor {
    switch (this) {
      case EmergencyStatus.unverified:
        return Colors.orange;
      case EmergencyStatus.accepted:
        return Colors.blue;
      case EmergencyStatus.inProgress:
        return Colors.purple;
      case EmergencyStatus.verified:
        return Colors.red;
      case EmergencyStatus.resolved:
        return Colors.green;
      case EmergencyStatus.fake:
        return Colors.grey;
      case EmergencyStatus.escalated:
        return Colors.deepOrange;
    }
  }

  /// Check if emergency should be visible to volunteers
  bool get visibleToVolunteers {
    switch (this) {
      case EmergencyStatus.unverified:
      case EmergencyStatus.accepted:
      case EmergencyStatus.inProgress:
      case EmergencyStatus.verified:
      case EmergencyStatus.escalated:
        return true;
      case EmergencyStatus.resolved:
      case EmergencyStatus.fake:
        return false; // Hide resolved and fake emergencies
    }
  }
}

/// Emergency volunteer response within an emergency
class EmergencyVolunteerResponse {
  final String volunteerId;
  final String volunteerName;
  final EmergencyVolunteerStatus status;
  final DateTime respondedAt;
  final DateTime lastUpdated;
  final LatLng? currentLocation;
  final List<LatLng>? routePoints;
  final String? estimatedArrivalTime;

  const EmergencyVolunteerResponse({
    required this.volunteerId,
    required this.volunteerName,
    required this.status,
    required this.respondedAt,
    required this.lastUpdated,
    this.currentLocation,
    this.routePoints,
    this.estimatedArrivalTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'volunteerId': volunteerId,
      'volunteerName': volunteerName,
      'status': status.name,
      'respondedAt': Timestamp.fromDate(respondedAt),
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'currentLocation': currentLocation != null
          ? GeoPoint(currentLocation!.latitude, currentLocation!.longitude)
          : null,
      'routePoints': routePoints?.map((point) => 
          GeoPoint(point.latitude, point.longitude)).toList(),
      'estimatedArrivalTime': estimatedArrivalTime,
    };
  }

  factory EmergencyVolunteerResponse.fromMap(Map<String, dynamic> map) {
    final locationGeo = map['currentLocation'] as GeoPoint?;
    final routePointsGeo = map['routePoints'] as List<dynamic>?;
    
    return EmergencyVolunteerResponse(
      volunteerId: map['volunteerId'] ?? '',
      volunteerName: map['volunteerName'] ?? '',
      status: EmergencyVolunteerStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => EmergencyVolunteerStatus.notified,
      ),
      respondedAt: (map['respondedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUpdated: (map['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      currentLocation: locationGeo != null 
          ? LatLng(locationGeo.latitude, locationGeo.longitude)
          : null,
      routePoints: routePointsGeo?.map((geoPoint) {
        final geo = geoPoint as GeoPoint;
        return LatLng(geo.latitude, geo.longitude);
      }).toList(),
      estimatedArrivalTime: map['estimatedArrivalTime'],
    );
  }
}

/// Emergency volunteer status
enum EmergencyVolunteerStatus {
  notified,
  responding,
  enRoute,
  arrived,
  verified,    // NEW: Emergency verified by volunteer
  assisting,
  completed,
  unavailable,
}

/// Extension for volunteer status display
extension EmergencyVolunteerStatusExtension on EmergencyVolunteerStatus {
  String get displayName {
    switch (this) {
      case EmergencyVolunteerStatus.notified:
        return 'Notified';
      case EmergencyVolunteerStatus.responding:
        return 'Responding';
      case EmergencyVolunteerStatus.enRoute:
        return 'En Route';
      case EmergencyVolunteerStatus.arrived:
        return 'Arrived';
      case EmergencyVolunteerStatus.verified:
        return 'Verified';
      case EmergencyVolunteerStatus.assisting:
        return 'Assisting';
      case EmergencyVolunteerStatus.completed:
        return 'Completed';
      case EmergencyVolunteerStatus.unavailable:
        return 'Unavailable';
    }
  }
}

/// Emergency resolution tracking
class EmergencyResolution {
  final bool attendee;
  final bool hasVolunteerCompleted;

  const EmergencyResolution({
    required this.attendee,
    required this.hasVolunteerCompleted,
  });

  Map<String, dynamic> toMap() {
    return {
      'attendee': attendee,
      'hasVolunteerCompleted': hasVolunteerCompleted,
    };
  }

  factory EmergencyResolution.fromMap(Map<String, dynamic> map) {
    return EmergencyResolution(
      attendee: map['attendee'] ?? false,
      hasVolunteerCompleted: map['hasVolunteerCompleted'] ?? false,
    );
  }

  EmergencyResolution copyWith({
    bool? attendee,
    bool? hasVolunteerCompleted,
  }) {
    return EmergencyResolution(
      attendee: attendee ?? this.attendee,
      hasVolunteerCompleted: hasVolunteerCompleted ?? this.hasVolunteerCompleted,
    );
  }
}
