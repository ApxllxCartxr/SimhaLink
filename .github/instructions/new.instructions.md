# Copilot Instructions for SimhaLink

This project is a Flutter application for **crowd management and control** built with Flutter and Firebase, focused primarily on Android deployment.

## Architecture Overview

### **App Focus & Target Platform**
- **Primary Platform:** Android (iOS present but not prioritized)
- **App Type:** Real-time crowd management system for events
- **Main Entry Point:** `lib/main.dart` (uses `SimhaLinkApp` widget with Firebase integration)
- **Architecture Pattern:** Service-Manager-Widget pattern with modular components

### **Core Features Implemented**
- **Map Functionality:**
  - Real-time location tracking with role-based visibility
  - Multiple marker types: medical, emergency, accessibility, drinking water, historical POIs
  - Geographic-consistent marker sizing (maintains real-world proportions across zoom levels)  
  - Marker clustering for dense scenarios
  - Long-press marker management for organizers
  - Offline map caching capabilities

- **Role-Based Access Control:**
  - **Organizers:** Full marker management, group creation, POI placement/deletion, emergency coordination
  - **Volunteers:** View all locations, respond to emergencies, limited marker management
  - **Participants/Attendees:** Basic location sharing, emergency alerts, group messaging
  - **VIPs:** Enhanced visibility, priority notifications

- **Group Management:**
  - Dynamic group creation with invite codes
  - Role-based group assignment and permissions
  - Group leaving/joining with proper cleanup
  - Default group assignment for new users

- **Emergency System:**
  - Multi-tiered emergency alerts with escalation
  - Real-time emergency broadcasting to relevant roles
  - Geographic proximity-based emergency notifications
  - Emergency status tracking and resolution

- **Authentication & User Management:**
  - Email/password authentication via Firebase Auth
  - Google Sign-In integration
  - User preferences with role-based settings
  - Session management with proper cleanup

### **Current File Structure**
```
lib/
├── main.dart                           # App entry point with Firebase initialization
├── config/
│   ├── theme.dart                      # App theming (MaterialApp)
│   └── app_constants.dart              # Production constants and configuration
├── core/
│   └── utils/
│       └── app_logger.dart            # Centralized logging with Crashlytics integration
├── models/
│   ├── user_location.dart             # User location data model
│   ├── poi.dart                       # Points of Interest model with Material icons
│   └── group.dart                     # Group management model
├── services/
│   ├── auth_service.dart              # Firebase authentication service
│   ├── notification_service.dart      # FCM push notifications
│   ├── marker_permission_service.dart # Role-based marker permissions
│   └── offline_map_service.dart       # Map caching and offline functionality
├── screens/
│   ├── auth_screen.dart               # Login/registration UI
│   ├── auth_wrapper.dart              # Authentication state management
│   ├── group_creation_screen.dart     # Group setup and joining
│   ├── map_screen.dart                # Main map interface (current active)
│   └── map/
│       ├── managers/
│       │   ├── location_manager.dart  # Location tracking and updates
│       │   ├── emergency_manager.dart # Emergency alert handling
│       │   └── marker_manager.dart    # Marker creation and management
│       ├── services/
│       │   └── marker_sizing_service.dart # Geographic marker scaling
│       └── widgets/
│           ├── map_info_panel.dart    # Map UI information display
│           ├── map_legend.dart        # Marker type legend
│           ├── emergency_dialog.dart  # Emergency alert UI
│           └── marker_action_bottom_sheet.dart # Marker management UI
└── utils/
    └── user_preferences.dart          # SharedPreferences wrapper with user-specific storage
```

## Developer Workflows

### **Build & Deployment**
- **Development:** `flutter run --debug` on Android device/emulator
- **Production APK:** `flutter build apk --release`
- **Play Store:** `flutter build appbundle --release`
- **Dependencies:** Run `flutter pub get` after modifying `pubspec.yaml`

### **Testing Strategy**
- **Manual Testing:** Use different role accounts to test permission systems
- **Map Testing:** Test with multiple users in same geographic area
- **Emergency Testing:** Test alert propagation across different roles
- **Performance Testing:** Test with 100+ markers for clustering behavior

### **Debugging Approach**
- **Logging:** Use `AppLogger` for consistent logging with Crashlytics integration
- **Firebase Console:** Monitor Firestore operations and user authentication
- **Android Studio:** Use Flutter Inspector for UI debugging
- **Network:** Test offline scenarios for cached map functionality

## Project Conventions & Best Practices

### **Code Organization**
- **Services:** Handle business logic and external integrations (Firebase, location, etc.)
- **Managers:** Handle specific feature domains (markers, location, emergency)
- **Widgets:** Reusable UI components with clear responsibilities
- **Models:** Data structures with Firebase serialization methods

### **Widget Structure**
- **Stateless Widgets:** Preferred for UI-only components
- **Stateful Widgets:** Used for components managing local state
- **Const Constructors:** Required where possible for performance
- **Proper Disposal:** All StreamSubscriptions, Timers must be disposed

### **State Management**
- **Local State:** Use `setState()` for UI-specific state
- **Firebase State:** Use StreamBuilder for real-time data
- **User Preferences:** Persist using SharedPreferences with user-specific keys
- **Error States:** Always handle loading, error, and empty states

### **Error Handling Standards**
```dart
// Use AppLogger instead of print statements
try {
  await firestoreOperation();
  AppLogger.info('Operation completed successfully');
} catch (e) {
  AppLogger.error('Operation failed', error: e);
  // Show user-friendly error message
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Something went wrong. Please try again.')),
  );
}
```

## Integration Points

### **Firebase Services**
- **Authentication:** `firebase_auth` for login/logout
- **Database:** `cloud_firestore` for real-time data sync
- **Messaging:** `firebase_messaging` for push notifications
- **Storage:** `firebase_storage` for user-generated content
- **Analytics:** `firebase_analytics` for user behavior tracking
- **Crashlytics:** `firebase_crashlytics` for error reporting

### **Android-Specific Integrations**
- **Location Services:** `geolocator` with proper permission handling
- **Background Processing:** Foreground services for location tracking
- **Push Notifications:** FCM with proper channel configuration
- **Permissions:** Runtime permission requests with fallback handling

### **Map Integration**
- **Current:** `flutter_map` with OpenStreetMap tiles
- **Clustering:** `flutter_map_marker_cluster` for marker grouping  
- **Offline:** Custom tile caching system for poor connectivity scenarios
- **Performance:** Viewport culling and efficient marker rendering

## Backend Architecture

### **Current: Firebase (Production Ready)**
- **Firestore Collections:**
  ```
  users/           # User profiles and roles
  groups/          # Group information and member lists  
  locations/       # Real-time user locations
  pois/            # Points of Interest created by organizers
  emergencies/     # Emergency alerts and status
  ```

- **Security Rules:** Role-based access control implemented
- **Indexes:** Optimized for location queries and real-time updates
- **FCM Topics:** Group-based messaging and emergency broadcasts

### **Future Migration Path (Optional)**
- **FastAPI + Python:** Structured to allow easy service layer migration
- **JWT Authentication:** Can replace Firebase Auth if needed
- **PostgreSQL:** Can replace Firestore for relational data needs
- **Redis:** For real-time features and caching

## Key Features Deep Dive

### **Role-Based Permission System**
```dart
// Example usage in components
if (MarkerPermissionService.canDeleteMarker(userRole, poi.type, poi.createdBy)) {
  // Show delete option
}
```

### **Geographic Marker Scaling**
```dart
// Markers maintain real-world size across zoom levels
final markerSize = MarkerSizingService.getStandardMarkerSize(
  MarkerType.emergency, 
  currentZoom
);
```

### **Emergency Alert Flow**
1. User triggers emergency → Local state update
2. Firebase location update with `isEmergency: true`
3. Real-time listeners notify nearby volunteers/organizers
4. Push notifications sent to relevant users
5. Emergency resolved → Firebase update + notification

### **Long-Press Marker Management**
- **All Users:** Long-press shows marker information dialog
- **Organizers:** Long-press shows management bottom sheet with delete options
- **Permission Checks:** Role-based actions available

## Production Considerations

### **Performance Optimizations**
- **Map Rendering:** Efficient marker clustering and viewport culling
- **Firebase Queries:** Paginated with proper indexing
- **Memory Management:** Proper disposal of streams and timers
- **Battery Usage:** Adaptive location update intervals

### **Security Measures**
- **Firestore Rules:** Production-ready role-based access control
- **User Authentication:** Secure token management
- **Data Validation:** Client and server-side validation
- **Error Logging:** Crashlytics integration for production monitoring

### **Offline Capabilities**
- **Map Tiles:** Cached for offline viewing
- **Critical Data:** Cached in SharedPreferences
- **Sync Strategy:** Queue operations when offline, sync when online

## AI Assistant Guidelines

### **When Making Changes**
1. **Always explain** what files will be modified and why
2. **Show data flow** between services, managers, and widgets
3. **Consider role-based access** for any UI/functionality changes
4. **Include proper error handling** with AppLogger integration
5. **Test consideration** for manual verification steps

### **Code Quality Standards**
- **Consistent naming:** Use descriptive method and variable names
- **Proper documentation:** Explain complex business logic
- **Error boundaries:** Always handle potential failure scenarios
- **Performance impact:** Consider map rendering and Firebase costs
- **Android focus:** Prioritize Android-specific optimizations

### **Emergency Debugging**
- **Check Firebase Console** for Firestore operations
- **Verify permissions** in AndroidManifest.xml
- **Test role assignments** with different user accounts
- **Monitor memory usage** during map operations
- **Check FCM token registration** for push notifications

This architecture supports real-time crowd management with role-based access control, optimized for Android deployment with Firebase backend integration.