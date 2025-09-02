/// Application-wide constants for SimhaLink
class AppConstants {
  // App Information
  static const String appName = 'SimhaLink';
  static const String appVersion = '1.0.0';
  static const String appDescription = 'Crowd management and control app';

  // Firebase Collections
  static const String usersCollection = 'users';
  static const String poisCollection = 'pois';
  static const String alertsCollection = 'alerts';
  static const String groupsCollection = 'groups';
  static const String messagesCollection = 'messages';
  static const String locationsCollection = 'user_locations';

  // User Roles
  static const List<String> userRoles = [
    'volunteer',
    'vip', 
    'organizer',
    'participant',
  ];

  // Default Values
  static const String defaultUserRole = 'participant';
  static const int defaultAlertExpiryHours = 24;
  static const int maxGroupNameLength = 50;
  static const int maxAlertTitleLength = 100;
  static const int maxAlertMessageLength = 500;
  static const int maxPOINameLength = 100;
  static const int maxPOIDescriptionLength = 300;

  // Location Settings
  static const double defaultLatitude = 12.9716; // Bangalore
  static const double defaultLongitude = 77.5946; // Bangalore
  static const double locationAccuracy = 10.0; // meters
  static const int locationUpdateIntervalMs = 30000; // 30 seconds

  // Map Settings
  static const double defaultZoomLevel = 15.0;
  static const double minZoomLevel = 10.0;
  static const double maxZoomLevel = 18.0;
  static const int maxMarkersPerScreen = 100;

  // Push Notifications
  static const String fcmTopicAll = 'all_users';
  static const String fcmTopicVolunteers = 'volunteers';
  static const String fcmTopicOrganizers = 'organizers';
  static const String fcmTopicVIPs = 'vips';
  static const String fcmTopicParticipants = 'participants';

  // Offline Support
  static const int maxOfflineStorageDays = 7;
  static const int maxCachedPOIs = 500;
  static const int maxCachedAlerts = 100;

  // UI Constants
  static const double borderRadius = 12.0;
  static const double buttonHeight = 48.0;
  static const double iconSize = 24.0;
  static const double avatarSize = 40.0;
  static const double cardElevation = 4.0;

  // Animation Durations
  static const int shortAnimationMs = 250;
  static const int mediumAnimationMs = 500;
  static const int longAnimationMs = 1000;

  // Error Messages
  static const String networkErrorMessage = 'Please check your internet connection';
  static const String locationErrorMessage = 'Location access is required';
  static const String authErrorMessage = 'Authentication failed';
  static const String permissionErrorMessage = 'Permission denied';
  static const String genericErrorMessage = 'Something went wrong. Please try again.';

  // Success Messages
  static const String loginSuccessMessage = 'Welcome to SimhaLink!';
  static const String logoutSuccessMessage = 'Signed out successfully';
  static const String alertCreatedMessage = 'Alert created successfully';
  static const String poiCreatedMessage = 'Point of interest created successfully';

  // Validation
  static const int minPasswordLength = 6;
  static const String emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
  static const String phoneRegex = r'^\+?[\d\s\-\(\)]{10,}$';

  // Feature Flags
  static const bool enablePushNotifications = true;
  static const bool enableLocationSharing = true;
  static const bool enableOfflineMode = true;
  static const bool enableVoiceMessages = false; // Future feature
  static const bool enableVideoChat = false; // Future feature

  // Development/Debug
  static const bool isDebugMode = false; // Set based on build mode
  static const bool enableAnalytics = true;
  static const bool enableCrashReporting = true;
  static const String debugTag = 'SimhaLink';

  // URLs and Links
  static const String privacyPolicyUrl = 'https://simhalink.com/privacy';
  static const String termsOfServiceUrl = 'https://simhalink.com/terms';
  static const String supportEmailUrl = 'mailto:support@simhalink.com';
  static const String githubRepoUrl = 'https://github.com/ApxllxCartxr/SimhaLink';

  // Shared Preferences Keys
  static const String keyUserRole = 'user_role';
  static const String keyUserId = 'user_id';
  static const String keyUserName = 'user_name';
  static const String keyUserEmail = 'user_email';
  static const String keyLastKnownLocation = 'last_known_location';
  static const String keyNotificationsEnabled = 'notifications_enabled';
  static const String keyLocationSharingEnabled = 'location_sharing_enabled';
  static const String keyThemeMode = 'theme_mode';
  static const String keyLanguage = 'language';
  static const String keyFirstLaunch = 'first_launch';

  // Time Formats
  static const String timeFormat24 = 'HH:mm';
  static const String timeFormat12 = 'h:mm a';
  static const String dateFormat = 'dd/MM/yyyy';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';
  static const String apiDateTimeFormat = 'yyyy-MM-ddTHH:mm:ss.SSSZ';
}

/// Route names for navigation
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String map = '/map';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String alerts = '/alerts';
  static const String createAlert = '/create-alert';
  static const String pois = '/pois';
  static const String createPOI = '/create-poi';
  static const String groups = '/groups';
  static const String createGroup = '/create-group';
  static const String groupChat = '/group-chat';
  static const String about = '/about';
  static const String help = '/help';
}

/// Asset paths
class AppAssets {
  // Images
  static const String imagesPath = 'assets/images/';
  static const String logoPath = '${imagesPath}logo.png';
  static const String splashImagePath = '${imagesPath}splash.png';
  static const String placeholderImagePath = '${imagesPath}placeholder.png';

  // Icons
  static const String iconsPath = 'assets/icons/';
  static const String markerMedicalPath = '${iconsPath}marker_medical.png';
  static const String markerWaterPath = '${iconsPath}marker_water.png';
  static const String markerEmergencyPath = '${iconsPath}marker_emergency.png';
  static const String markerAccessibilityPath = '${iconsPath}marker_accessibility.png';
  static const String markerHistoricalPath = '${iconsPath}marker_historical.png';
  static const String markerRestroomPath = '${iconsPath}marker_restroom.png';
  static const String markerFoodPath = '${iconsPath}marker_food.png';
  static const String markerParkingPath = '${iconsPath}marker_parking.png';
  static const String markerSecurityPath = '${iconsPath}marker_security.png';
  static const String markerInfoPath = '${iconsPath}marker_info.png';

  // Fonts
  static const String primaryFontFamily = 'InstrumentSerif';
}
