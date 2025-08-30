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
import 'package:simha_link/firebase_options.dart';
import 'package:simha_link/config/theme.dart';
import 'package:simha_link/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize FCM for push notifications
  await FCMService.initialize();
  
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simha Link',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
      routes: {
        // Authentication & Group routes
        '/auth': (context) => const AuthScreen(),
        '/group_creation': (context) => const GroupCreationScreen(),
        
        // Communication routes
        '/emergency_communication': (context) => const EmergencyCommunicationScreen(),
        '/emergency_communication_list': (context) => const EmergencyCommunicationListScreen(),
        '/broadcast_compose': (context) => const BroadcastComposeScreen(),
        '/broadcast_list': (context) => const BroadcastListScreen(),
      },
      onGenerateRoute: (settings) {
        // Handle dynamic routes or routes with parameters
        if (settings.name?.startsWith('/map/') ?? false) {
          // Example: /map/abc123 (groupId)
          final groupId = settings.name!.split('/').last;
          return MaterialPageRoute(
            builder: (context) => MainNavigationScreen(groupId: groupId),
          );
        }
        
        // Special case for when navigation is completely broken
        // This is a fallback to ensure users can at least get to the auth screen
        if (settings.name == '/force_auth') {
          return MaterialPageRoute(
            builder: (context) => const AuthScreen(),
          );
        }
        
        return null;
      },
    );
  }
}
