import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:simha_link/screens/auth_wrapper.dart';
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
    );
  }
}
