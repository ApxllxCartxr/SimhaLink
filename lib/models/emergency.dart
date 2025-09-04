import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

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
          orElse: () => EmergencyStatus.active,
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
    );
  }

  /// Check if emergency is active (not resolved)
  bool get isActive => status == EmergencyStatus.active || status == EmergencyStatus.inProgress;

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
  active,
  inProgress,
  resolved,
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
