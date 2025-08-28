# Copilot Instructions for simha_link

This project is a Flutter application focused primarily on Android. The following guidelines will help AI coding agents work productively in this codebase.

## Architecture Overview
- **App Focus:**
  - Target platform: **Android** (other platforms present but not prioritized).
  - Main entry point: `lib/main.dart` (uses `MainApp` widget).
  - Core features to implement:
    - **Map functionality**: Display and interact with maps, mark multiple locations (medical, historical, emergency, drinking water, accessibility points).
    - **Role-based access controls**: Roles include Volunteers, VIPs, Organizers, Participants. Each role has different powers and UI views.
    - **Group messaging**: Enable communication between users in groups.
    - **Alerts/Emergencies**: Volunteers and participants can raise alerts/emergencies.
    - **Login screen**: Support both email/password and Google sign-in.

## Developer Workflows
- **Build:**
  - Use `flutter build apk` for Android builds.
- **Run:**
  - Use `flutter run` to launch the app on an Android device or emulator.
- **Test:**
  - Add tests in `test/` directory using Flutter's test framework (none present yet).
- **Debug:**
  - Use `flutter run --debug` or IDE debugging tools for Android.

## Project Conventions
- **Widget Structure:**
  - Stateless widgets are preferred for simple UI (see `MainApp`).
  - Use `const` constructors where possible.
- **File Organization:**
  - Place main app code in `lib/`.
  - Platform code in respective OS folders.
- **Dependencies:**
  - Managed via `pubspec.yaml`.
  - Run `flutter pub get` after modifying dependencies.

## Integration Points
- **Platform Channels:**
  - Integrate with Android-specific APIs as needed for maps, messaging, and notifications.
- **External Services:**
  - Integrate Google Sign-In for authentication.
  - Use map APIs (e.g., Google Maps Flutter plugin) for location features.

## Backend Guidance
- **Current backend:** Use Firebase for authentication, data storage (Firestore), messaging, and notifications. Recommended plugins: `firebase_auth`, `cloud_firestore`, `firebase_messaging`.
- **Migration:** Structure code to allow easy migration to FastAPI + Python (e.g., abstract data/service layers, avoid tight coupling to Firebase APIs).
- **Pivot:** If switching to FastAPI, use REST endpoints and JWT authentication, and update service layers accordingly.

## Examples
- Main widget: `lib/main.dart`
  ```dart
  class MainApp extends StatelessWidget {
    const MainApp({super.key});
    @override
    Widget build(BuildContext context) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Hello World!'),
          ),
        ),
      );
    }
  }
  ```
  // Future features will include:
  // - Login screen (email/password, Google sign-in)
  // - Map screen with location markers
  // - Role-based dashboards
  // - Group messaging UI
  // - Alert/emergency UI

## Key Files & Directories
- `lib/main.dart`: App entry point
- `pubspec.yaml`: Dependency management
- `android/`: Main platform code (focus)
- `lib/`: Place for app logic, widgets, and features
- `test/`: Add tests here

If any section is unclear or missing important details, please provide feedback to improve these instructions.
