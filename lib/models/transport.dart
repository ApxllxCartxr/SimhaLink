import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

enum TransportType { bus, shuttle }

enum TransportStatus { active, full, departed, cancelled }

enum TransportVisibility { public, groupOnly }

class TransportRoute {
  final LatLng fromLocation;
  final LatLng toLocation;
  final String fromAddress;
  final String toAddress;
  final List<LatLng> routePath;
  final double distance;

  const TransportRoute({
    required this.fromLocation,
    required this.toLocation,
    required this.fromAddress,
    required this.toAddress,
    required this.routePath,
    required this.distance,
  });

  Map<String, dynamic> toMap() {
    return {
      'fromLocation': GeoPoint(fromLocation.latitude, fromLocation.longitude),
      'toLocation': GeoPoint(toLocation.latitude, toLocation.longitude),
      'fromAddress': fromAddress,
      'toAddress': toAddress,
      'routePath': routePath.map((point) => GeoPoint(point.latitude, point.longitude)).toList(),
      'distance': distance,
    };
  }

  factory TransportRoute.fromMap(Map<String, dynamic> map) {
    final fromGeo = map['fromLocation'] as GeoPoint;
    final toGeo = map['toLocation'] as GeoPoint;
    final routePathData = map['routePath'] as List<dynamic>? ?? [];
    
    return TransportRoute(
      fromLocation: LatLng(fromGeo.latitude, fromGeo.longitude),
      toLocation: LatLng(toGeo.latitude, toGeo.longitude),
      fromAddress: map['fromAddress'] ?? '',
      toAddress: map['toAddress'] ?? '',
      routePath: routePathData.map((point) {
        final geoPoint = point as GeoPoint;
        return LatLng(geoPoint.latitude, geoPoint.longitude);
      }).toList(),
      distance: (map['distance'] ?? 0.0).toDouble(),
    );
  }
}

class TransportSchedule {
  final DateTime departureTime;
  final DateTime estimatedArrival;
  final bool isRecurring;

  const TransportSchedule({
    required this.departureTime,
    required this.estimatedArrival,
    required this.isRecurring,
  });

  Map<String, dynamic> toMap() {
    return {
      'departureTime': Timestamp.fromDate(departureTime),
      'estimatedArrival': Timestamp.fromDate(estimatedArrival),
      'isRecurring': isRecurring,
    };
  }

  factory TransportSchedule.fromMap(Map<String, dynamic> map) {
    return TransportSchedule(
      departureTime: (map['departureTime'] as Timestamp).toDate(),
      estimatedArrival: (map['estimatedArrival'] as Timestamp).toDate(),
      isRecurring: map['isRecurring'] ?? false,
    );
  }
}

class TransportCapacity {
  final int maxOccupants;
  final int currentOccupants;

  const TransportCapacity({
    required this.maxOccupants,
    required this.currentOccupants,
  });

  int get availableSeats => maxOccupants - currentOccupants;
  bool get isFull => currentOccupants >= maxOccupants;

  Map<String, dynamic> toMap() {
    return {
      'maxOccupants': maxOccupants,
      'currentOccupants': currentOccupants,
      'availableSeats': availableSeats,
    };
  }

  factory TransportCapacity.fromMap(Map<String, dynamic> map) {
    return TransportCapacity(
      maxOccupants: map['maxOccupants'] ?? 0,
      currentOccupants: map['currentOccupants'] ?? 0,
    );
  }

  TransportCapacity copyWith({
    int? maxOccupants,
    int? currentOccupants,
  }) {
    return TransportCapacity(
      maxOccupants: maxOccupants ?? this.maxOccupants,
      currentOccupants: currentOccupants ?? this.currentOccupants,
    );
  }
}

class TransportPricing {
  final bool isFree;
  final double pricePerTicket;
  final String currency;

  const TransportPricing({
    required this.isFree,
    required this.pricePerTicket,
    required this.currency,
  });

  Map<String, dynamic> toMap() {
    return {
      'isFree': isFree,
      'pricePerTicket': pricePerTicket,
      'currency': currency,
    };
  }

  factory TransportPricing.fromMap(Map<String, dynamic> map) {
    return TransportPricing(
      isFree: map['isFree'] ?? true,
      pricePerTicket: (map['pricePerTicket'] ?? 0.0).toDouble(),
      currency: map['currency'] ?? 'USD',
    );
  }
}

class Transport {
  final String id;
  final String organizerId;
  final String organizerName;
  final TransportType type;
  final String title;
  final String description;
  final TransportRoute route;
  final TransportSchedule schedule;
  final TransportCapacity capacity;
  final TransportPricing pricing;
  final TransportStatus status;
  final TransportVisibility visibility;
  final List<String> allowedGroupIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Transport({
    required this.id,
    required this.organizerId,
    required this.organizerName,
    required this.type,
    required this.title,
    required this.description,
    required this.route,
    required this.schedule,
    required this.capacity,
    required this.pricing,
    required this.status,
    required this.visibility,
    required this.allowedGroupIds,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'organizerId': organizerId,
      'organizerName': organizerName,
      'type': type.name,
      'title': title,
      'description': description,
      'route': route.toMap(),
      'schedule': schedule.toMap(),
      'capacity': capacity.toMap(),
      'pricing': pricing.toMap(),
      'status': status.name,
      'visibility': visibility.name,
      'allowedGroupIds': allowedGroupIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory Transport.fromMap(Map<String, dynamic> map) {
    return Transport(
      id: map['id'] ?? '',
      organizerId: map['organizerId'] ?? '',
      organizerName: map['organizerName'] ?? '',
      type: TransportType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => TransportType.bus,
      ),
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      route: TransportRoute.fromMap(map['route'] ?? {}),
      schedule: TransportSchedule.fromMap(map['schedule'] ?? {}),
      capacity: TransportCapacity.fromMap(map['capacity'] ?? {}),
      pricing: TransportPricing.fromMap(map['pricing'] ?? {}),
      status: TransportStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => TransportStatus.active,
      ),
      visibility: TransportVisibility.values.firstWhere(
        (e) => e.name == map['visibility'],
        orElse: () => TransportVisibility.public,
      ),
      allowedGroupIds: List<String>.from(map['allowedGroupIds'] ?? []),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Transport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return Transport.fromMap(data);
  }

  Transport copyWith({
    String? id,
    String? organizerId,
    String? organizerName,
    TransportType? type,
    String? title,
    String? description,
    TransportRoute? route,
    TransportSchedule? schedule,
    TransportCapacity? capacity,
    TransportPricing? pricing,
    TransportStatus? status,
    TransportVisibility? visibility,
    List<String>? allowedGroupIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transport(
      id: id ?? this.id,
      organizerId: organizerId ?? this.organizerId,
      organizerName: organizerName ?? this.organizerName,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      route: route ?? this.route,
      schedule: schedule ?? this.schedule,
      capacity: capacity ?? this.capacity,
      pricing: pricing ?? this.pricing,
      status: status ?? this.status,
      visibility: visibility ?? this.visibility,
      allowedGroupIds: allowedGroupIds ?? this.allowedGroupIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isAvailable => status == TransportStatus.active && !capacity.isFull;
  bool get hasDeparted => status == TransportStatus.departed;
  bool get isCancelled => status == TransportStatus.cancelled;

  String get statusDisplayText {
    switch (status) {
      case TransportStatus.active:
        return capacity.isFull ? 'Full' : 'Available';
      case TransportStatus.full:
        return 'Full';
      case TransportStatus.departed:
        return 'Departed';
      case TransportStatus.cancelled:
        return 'Cancelled';
    }
  }

  String get typeDisplayText {
    switch (type) {
      case TransportType.bus:
        return 'Bus';
      case TransportType.shuttle:
        return 'Shuttle';
    }
  }
}
