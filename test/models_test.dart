import 'package:flutter_test/flutter_test.dart';
import 'package:simha_link/models/user_profile.dart';
import 'package:simha_link/models/poi.dart';
import 'package:simha_link/models/alert_model.dart';
import 'package:simha_link/services/auth_service.dart';
import 'package:simha_link/utils/constants.dart';

void main() {
  group('Model Tests', () {
    test('UserProfile should create from map correctly', () {
      final map = {
        'uid': 'test123',
        'displayName': 'Test User',
        'email': 'test@example.com',
        'role': 'volunteer',
        'createdAt': DateTime.now(),
        'lastSeen': DateTime.now(),
        'isOnline': true,
        'preferences': <String, dynamic>{},
      };
      
      final user = UserProfile.fromMap(map);
      
      expect(user.uid, 'test123');
      expect(user.displayName, 'Test User');
      expect(user.email, 'test@example.com');
      expect(user.role, UserRole.volunteer);
      expect(user.isOnline, true);
    });

    test('POI should create with MarkerType enum', () {
      final poi = POI(
        id: 'poi123',
        name: 'Test POI',
        type: MarkerType.medical,
        latitude: 12.9716,
        longitude: 77.5946,
        description: 'Test description',
        createdBy: 'user123',
        createdAt: DateTime.now(),
      );

      expect(poi.id, 'poi123');
      expect(poi.name, 'Test POI');
      expect(poi.type, MarkerType.medical);
      expect(poi.isActive, true); // default value
    });

    test('AlertModel should handle enums correctly', () {
      final alert = AlertModel(
        id: 'alert123',
        title: 'Test Alert',
        message: 'This is a test alert',
        type: AlertType.emergency,
        priority: AlertPriority.high,
        status: AlertStatus.active,
        createdBy: 'user123',
        createdByName: 'Test User',
        createdAt: DateTime.now(),
      );

      expect(alert.id, 'alert123');
      expect(alert.type, AlertType.emergency);
      expect(alert.priority, AlertPriority.high);
      expect(alert.status, AlertStatus.active);
      expect(alert.isCurrentlyActive, true);
    });

    test('AuthService should be singleton', () {
      final auth1 = AuthService();
      final auth2 = AuthService();
      
      expect(identical(auth1, auth2), true);
    });

    test('Constants should have proper values', () {
      expect(AppConstants.appName, 'SimhaLink');
      expect(AppConstants.defaultUserRole, 'participant');
      expect(AppConstants.usersCollection, 'users');
      expect(AppRoutes.home, '/home');
      expect(AppAssets.primaryFontFamily, 'InstrumentSerif');
    });
  });
}
