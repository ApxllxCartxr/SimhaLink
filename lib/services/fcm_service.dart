import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Initialize FCM service
  static Future<void> initialize() async {
    try {
      // Request notification permissions
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        criticalAlert: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ FCM: User granted notification permissions');
        
        // Get and store FCM token
        await _updateFCMToken();
        
        // Subscribe to topics based on user role
        await _subscribeToTopics();
        
        // Listen for token refresh
        _messaging.onTokenRefresh.listen(_onTokenRefresh);
        
        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_onForegroundMessage);
        
        // Handle background message taps
        FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
        
        print('✅ FCM: Initialization complete');
      } else {
        print('⚠️  FCM: User denied notification permissions');
      }
    } catch (e) {
      print('❌ FCM: Initialization failed: $e');
    }
  }

  /// Update user's FCM token in Firestore
  static Future<void> _updateFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await _messaging.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': token,
          'fcmTokenUpdated': FieldValue.serverTimestamp(),
        });
        print('✅ FCM: Token updated for user ${user.uid}');
      }
    } catch (e) {
      print('❌ FCM: Failed to update token: $e');
    }
  }

  /// Subscribe to FCM topics based on user role
  static Future<void> _subscribeToTopics() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Subscribe to general topic
      await _messaging.subscribeToTopic('all_users');

      // Get user role and subscribe to role-specific topic
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final role = userDoc.data()?['role'] as String?;
      
      if (role != null) {
        switch (role.toLowerCase()) {
          case 'volunteer':
            await _messaging.subscribeToTopic('volunteers');
            print('✅ FCM: Subscribed to volunteers topic');
            break;
          case 'organizer':
            await _messaging.subscribeToTopic('organizers');
            print('✅ FCM: Subscribed to organizers topic');
            break;
          case 'vip':
            await _messaging.subscribeToTopic('vips');
            print('✅ FCM: Subscribed to VIPs topic');
            break;
          default:
            await _messaging.subscribeToTopic('participants');
            print('✅ FCM: Subscribed to participants topic');
            break;
        }
      }
    } catch (e) {
      print('❌ FCM: Failed to subscribe to topics: $e');
    }
  }

  /// Handle token refresh
  static void _onTokenRefresh(String token) async {
    print('📱 FCM: Token refreshed');
    await _updateFCMToken();
  }

  /// Handle foreground messages (when app is open)
  static void _onForegroundMessage(RemoteMessage message) {
    print('📱 FCM: Foreground message received: ${message.notification?.title}');
    
    // Show in-app notification or handle as needed
    if (message.data['type'] == 'emergency' || message.data['type'] == 'volunteer_emergency') {
      _handleEmergencyMessage(message);
    }
  }

  /// Handle background message taps (when user taps notification)
  static void _onMessageOpenedApp(RemoteMessage message) {
    print('📱 FCM: Message opened app: ${message.notification?.title}');
    
    // Navigate to appropriate screen based on message type
    if (message.data['type'] == 'emergency' || message.data['type'] == 'volunteer_emergency') {
      // TODO: Navigate to map screen and focus on emergency location
      _handleEmergencyMessage(message);
    }
  }

  /// Handle emergency-specific messages
  static void _handleEmergencyMessage(RemoteMessage message) {
    print('🚨 FCM: Emergency message received');
    print('  - User: ${message.data['userName']}');
    print('  - Location: ${message.data['latitude']}, ${message.data['longitude']}');
    
    // TODO: Integrate with your navigation system to:
    // 1. Show emergency dialog
    // 2. Navigate to map
    // 3. Focus on emergency location
    // 4. Show navigation route
  }

  /// Subscribe to group-specific topic
  static Future<void> subscribeToGroup(String groupId) async {
    try {
      await _messaging.subscribeToTopic('group_$groupId');
      print('✅ FCM: Subscribed to group $groupId topic');
    } catch (e) {
      print('❌ FCM: Failed to subscribe to group topic: $e');
    }
  }

  /// Unsubscribe from group-specific topic
  static Future<void> unsubscribeFromGroup(String groupId) async {
    try {
      await _messaging.unsubscribeFromTopic('group_$groupId');
      print('✅ FCM: Unsubscribed from group $groupId topic');
    } catch (e) {
      print('❌ FCM: Failed to unsubscribe from group topic: $e');
    }
  }

  /// Clean up when user logs out
  static Future<void> cleanup() async {
    try {
      // Unsubscribe from all topics
      await _messaging.unsubscribeFromTopic('all_users');
      await _messaging.unsubscribeFromTopic('volunteers');
      await _messaging.unsubscribeFromTopic('organizers');
      await _messaging.unsubscribeFromTopic('vips');
      await _messaging.unsubscribeFromTopic('participants');
      
      // Clear FCM token from user document
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': FieldValue.delete(),
        });
      }
      
      print('✅ FCM: Cleanup complete');
    } catch (e) {
      print('❌ FCM: Cleanup failed: $e');
    }
  }
}
