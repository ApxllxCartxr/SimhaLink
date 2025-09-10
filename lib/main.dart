import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:simha_link/screens/auth_wrapper.dart';
import 'package:simha_link/screens/auth_screen.dart';
import 'package:simha_link/screens/group_creation_screen.dart';
import 'package:simha_link/screens/emergency_communication_screen.dart';
import 'package:simha_link/screens/emergency_communication_list_screen.dart';
import 'package:simha_link/screens/broadcast_compose_screen.dart';
import 'package:simha_link/screens/broadcast_list_screen.dart';
import 'package:simha_link/screens/main_navigation_screen.dart';
import 'package:simha_link/widgets/in_app_notification_overlay.dart';
import 'package:simha_link/firebase_options.dart';
import 'package:simha_link/config/theme.dart';
import 'package:simha_link/services/fcm_service.dart';
import 'package:simha_link/services/in_app_broadcast_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize FCM for push notifications
  await FCMService.initialize();

  // Initialize in-app broadcast listener (proof-of-concept)
  await InAppBroadcastService.initialize(_navigatorKey);
  
  runApp(const MainApp());
}

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simha Link',
      navigatorKey: _navigatorKey,
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const InAppNotificationOverlay(
        child: AuthWrapper(),
      ),
      routes: {
        // Authentication & Group routes
        '/auth': (context) => const InAppNotificationOverlay(
          child: AuthScreen(),
        ),
        '/group_creation': (context) => const InAppNotificationOverlay(
          child: GroupCreationScreen(),
        ),
        
        // Communication routes
        '/emergency_communication': (context) => const InAppNotificationOverlay(
          child: EmergencyCommunicationScreen(),
        ),
        '/emergency_communication_list': (context) => const InAppNotificationOverlay(
          child: EmergencyCommunicationListScreen(),
        ),
        '/broadcast_compose': (context) => const InAppNotificationOverlay(
          child: BroadcastComposeScreen(),
        ),
        '/broadcast_list': (context) => const InAppNotificationOverlay(
          child: BroadcastListScreen(),
        ),
      },
      onGenerateRoute: (settings) {
        // Handle dynamic routes or routes with parameters
        if (settings.name?.startsWith('/map/') ?? false) {
          // Example: /map/abc123 (groupId)
          final groupId = settings.name!.split('/').last;
          return MaterialPageRoute(
            builder: (context) => InAppNotificationOverlay(
              child: MainNavigationScreen(groupId: groupId),
            ),
          );
        }
        
        // Special case for when navigation is completely broken
        // This is a fallback to ensure users can at least get to the auth screen
        if (settings.name == '/force_auth') {
          return MaterialPageRoute(
            builder: (context) => const InAppNotificationOverlay(
              child: AuthScreen(),
            ),
          );
        }
        
        return null;
      },
    );
  }
}
