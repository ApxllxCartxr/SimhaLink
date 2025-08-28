class POI {
  final String id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final String description;
  final String createdBy;
  final DateTime createdAt;

  POI({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.description,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'latitude': latitude,
      'longitude': longitude,
      'description': description,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory POI.fromMap(Map<String, dynamic> map) {
    return POI(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      description: map['description'] ?? '',
      createdBy: map['createdBy'] ?? '',
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  static const List<String> poiTypes = [
    'Drinking Water',
    'Medical Aid',
    'Emergency Exit',
    'Restroom',
    'Food & Beverages',
    'Information Desk',
    'Lost & Found',
    'Security',
    'Accessibility Point',
    'Other'
  ];

  static String getPoiIcon(String type) {
    switch (type) {
      case 'Drinking Water':
        return '💧';
      case 'Medical Aid':
        return '🏥';
      case 'Emergency Exit':
        return '🚪';
      case 'Restroom':
        return '🚻';
      case 'Food & Beverages':
        return '🍴';
      case 'Information Desk':
        return 'ℹ️';
      case 'Lost & Found':
        return '📦';
      case 'Security':
        return '🛡️';
      case 'Accessibility Point':
        return '♿';
      default:
        return '📍';
    }
  }
}
