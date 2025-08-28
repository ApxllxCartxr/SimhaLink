/// Enumeration of Point of Interest marker types
enum MarkerType {
  medical('Medical Aid', 'medical'),
  drinkingWater('Drinking Water', 'water'),
  emergency('Emergency', 'emergency'),
  accessibility('Accessibility', 'accessibility'), 
  historical('Historical', 'historical'),
  restroom('Restroom', 'restroom'),
  food('Food & Beverages', 'food'),
  parking('Parking', 'parking'),
  security('Security', 'security'),
  information('Information', 'info');

  const MarkerType(this.displayName, this.iconName);
  final String displayName;
  final String iconName;

  static MarkerType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'medical':
      case 'medical aid':
        return MarkerType.medical;
      case 'drinking water':
      case 'water':
        return MarkerType.drinkingWater;
      case 'emergency':
        return MarkerType.emergency;
      case 'accessibility':
        return MarkerType.accessibility;
      case 'historical':
        return MarkerType.historical;
      case 'restroom':
        return MarkerType.restroom;
      case 'food':
      case 'food & beverages':
        return MarkerType.food;
      case 'parking':
        return MarkerType.parking;
      case 'security':
        return MarkerType.security;
      case 'information':
      case 'info':
        return MarkerType.information;
      default:
        return MarkerType.information;
    }
  }

  /// Get all available marker types for UI selection
  static List<MarkerType> get allTypes => MarkerType.values;
}

class POI {
  final String id;
  final String name;
  final MarkerType type;
  final double latitude;
  final double longitude;
  final String description;
  final String createdBy;
  final DateTime createdAt;
  final bool isActive;
  final Map<String, dynamic> metadata;

  POI({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.createdBy,
    required this.createdAt,
    this.isActive = true,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
      'metadata': metadata,
    };
  }

  factory POI.fromMap(Map<String, dynamic> map) {
    return POI(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: MarkerType.fromString(map['type'] ?? ''),
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      description: map['description'] ?? '',
      createdBy: map['createdBy'] ?? '',
      createdAt: DateTime.parse(map['createdAt']),
      isActive: map['isActive'] ?? true,
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }

  /// Get all available POI types for UI selection
  static List<MarkerType> get availableTypes => MarkerType.allTypes;

  /// Create a copy with updated values
  POI copyWith({
    String? id,
    String? name,
    MarkerType? type,
    double? latitude,
    double? longitude,
    String? description,
    String? createdBy,
    DateTime? createdAt,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return POI(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Get icon string for POI type (for backward compatibility)
  static String getPoiIcon(MarkerType type) {
    switch (type) {
      case MarkerType.medical:
        return '🏥';
      case MarkerType.drinkingWater:
        return '💧';
      case MarkerType.emergency:
        return '🚨';
      case MarkerType.accessibility:
        return '♿';
      case MarkerType.historical:
        return '🏛️';
      case MarkerType.restroom:
        return '🚻';
      case MarkerType.food:
        return '🍽️';
      case MarkerType.parking:
        return '🅿️';
      case MarkerType.security:
        return '👮';
      case MarkerType.information:
        return 'ℹ️';
    }
  }

  /// Get available POI types as strings (for backward compatibility)
  static List<String> get poiTypes => MarkerType.values.map((e) => e.displayName).toList();
}
