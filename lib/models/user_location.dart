class UserLocation {
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;
  final bool isEmergency;
  final DateTime lastUpdated;

  UserLocation({
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
    this.isEmergency = false,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'latitude': latitude,
      'longitude': longitude,
      'isEmergency': isEmergency,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  factory UserLocation.fromMap(Map<String, dynamic> map) {
    return UserLocation(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      isEmergency: map['isEmergency'] ?? false,
      lastUpdated: DateTime.parse(map['lastUpdated']),
    );
  }
}
