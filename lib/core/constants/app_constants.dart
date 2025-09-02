/// Critical app constants for production deployment
/// These values are essential for proper app functionality
class AppConstants {
  // App Information
  static const String appName = 'SimhaLink';
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';
  
  // Map Configuration
  static const double emergencyRadiusMeters = 50.0;
  static const double normalMarkerRadiusMeters = 25.0;
  static const double baseMarkerSize = 40.0;
  static const double minMarkerSize = 30.0;
  static const double maxMarkerSize = 80.0;
  static const double currentLocationAccuracy = 50.0; // meters
  
  // Location Update Intervals
  static const int locationUpdateIntervalMs = 5000; // 5 seconds
  static const int emergencyLocationUpdateIntervalMs = 2000; // 2 seconds
  static const int backgroundLocationIntervalMs = 30000; // 30 seconds
  
  // Group Management
  static const int maxGroupSize = 50;
  static const int minGroupSize = 2;
  static const int maxGroupNameLength = 50;
  static const Duration groupSessionTimeout = Duration(hours: 2);
  static const Duration emergencyTimeout = Duration(minutes: 10);
  
  // Map Rendering
  static const double initialMapZoom = 15.0;
  static const double maxMapZoom = 18.0;
  static const double minMapZoom = 3.0;
  static const int maxCachedTiles = 1000;
  static const int markerClusterMaxZoom = 15;
  
  // Firebase Configuration
  static const int firestoreTimeoutSeconds = 30;
  static const int maxRetryAttempts = 3;
  static const Duration networkTimeout = Duration(seconds: 10);
  
  // UI Constants
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration snackBarDuration = Duration(seconds: 3);
  static const double mapBottomPadding = 100.0;
  static const double fabSpacing = 8.0;
  
  // Security & Performance
  static const Duration sessionTimeout = Duration(hours: 2);
  static const int maxConcurrentRequests = 5;
  static const int maxMarkerDisplay = 500; // Prevent UI lag
  
  // Emergency Settings
  static const double emergencyAlertRadius = 100.0; // meters
  static const Duration emergencyAlertCooldown = Duration(minutes: 5);
  static const int maxEmergencyAlertsPerHour = 5;
  
  // Routing & Navigation
  static const double routeLineWidth = 4.0;
  static const double routeBufferMeters = 10.0;
  static const Duration routeCalculationTimeout = Duration(seconds: 15);
  
  // Production Environment Flags
  static const bool enableAnalytics = true;
  static const bool enableCrashReporting = true;
  static const bool enablePerformanceMonitoring = true;
}
