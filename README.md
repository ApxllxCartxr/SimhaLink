# SimhaLink

A mobile app for crowd management and control built with Flutter and Firebase.

This repository contains the Android-first Flutter application used to display maps, manage roles (volunteers, organizers, participants, VIPs), raise alerts, and provide group messaging during events.

## Key features

- Map-based UI with multiple marker types (medical, emergency, accessibility, drinking water, historical).
- Role-based access and dashboards (Volunteers, Organizers, Participants, VIPs).
- Email/password + Google sign-in authentication (Firebase Auth).
- Firestore-backed data storage for markers, alerts, groups and messages.
- Push notifications via Firebase Cloud Messaging.

## Quick start

### Prerequisites

- Flutter SDK (stable channel)
- Android SDK and an Android device or emulator
- Java (JDK 11+ recommended)

### Basic steps

1. Fetch Dart/Flutter packages:

```powershell
flutter pub get
```

1. Verify Firebase configuration:

- The Android Firebase config file is present at `android/app/google-services.json`. If you need to reconfigure, use the Firebase console and download the file to that path.
- This project also contains a generated `lib/firebase_options.dart` (used by `firebase_core`) — keep it in sync with your Firebase project.

1. Run the app on an Android device/emulator:

```powershell
flutter run -d emulator-5554
```

1. Build an APK for release:

```powershell
flutter build apk --release
```

If you need to re-run Firebase CLI configuration, consider using `flutterfire` tools or follow Firebase setup docs for Flutter.

## Project layout (important files)

- `lib/main.dart` — app entry point (MainApp)
- `lib/config/` — app-wide configuration (themes, map config)
- `lib/screens/` — feature screens (map, login, dashboards)
  - `lib/screens/map/` — modular map components (managers & widgets)
- `lib/services/` — backend integrations (Firebase, auth, messaging)
  - `lib/services/notifications/` — modular notification system
- `lib/models/` — data models used across the app
- `android/app/google-services.json` — Android Firebase config (required for builds)
- `lib/firebase_options.dart` — generated Firebase options for the app

See the `assets/` and `fonts/` folders for bundled resources.

### Architecture & Refactoring

This codebase has been recently refactored to follow modern architectural patterns. See `REFACTORING_SUMMARY.md` and `REFACTORING_COMPLETION_REPORT.md` for detailed information about:

- **Modular Architecture**: Components separated into managers (business logic) and widgets (UI)
- **75% File Size Reduction**: Large monolithic files broken down into maintainable components
- **Enhanced Maintainability**: Single responsibility principle applied throughout
- **Team-Friendly Structure**: Multiple developers can work on different components simultaneously

## Development notes

- Target platform: Android is the primary focus. iOS support files exist but are not the primary QA target.
- Use `const` where possible for widgets. Follow existing project conventions under `lib/`.
- After changing dependencies, run `flutter pub get` and re-run the app.

### Testing

- Add Flutter tests under `test/` and run them with:

```powershell
flutter test
```

### CI / Build

- Typical local build: `flutter build apk` (Android)

### Firebase

- This project uses Firebase for Auth, Firestore, and Messaging. Keep `google-services.json` and `lib/firebase_options.dart` synchronized with your Firebase project.
- Recommended plugins in `pubspec.yaml`: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`, `google_sign_in`.

### Troubleshooting

- If the app fails to find Firebase options, ensure `lib/firebase_options.dart` exists and is imported in `main.dart`.
- If Android build fails, check `local.properties` for correct SDK path and confirm `minSdkVersion` in `android/app/build.gradle.kts` meets plugin requirements.

## Contributing

- Fork, create a feature branch, add tests, and open a pull request. Follow the existing code style in `lib/` and keep commits small.

## Unique Selling Points

**SimhaLink** stands out as a comprehensive crowd management solution that combines:

- **Real-time Situational Awareness**: Live map updates with role-based visibility ensure everyone has the right information at the right time
- **Hierarchical Emergency Response**: Multi-tiered alert system from participant reports to volunteer coordination to organizer oversight
- **Context-Aware Communication**: Location-based messaging and notifications that adapt to user roles and proximity
- **Scalable Architecture**: Modular design supports events from small gatherings to large festivals with thousands of participants

Unlike generic event apps, SimhaLink is purpose-built for **crowd safety and coordination**, making it ideal for festivals, conferences, protests, emergency situations, and any large gathering where participant safety and organization are paramount.

## Roadmap & Future Features

### Phase 1: Enhanced Safety & Communication
- **Live Audio Streaming**: Broadcast announcements from organizers to specific zones or all participants
- **Offline Map Caching**: Essential functionality when network connectivity is poor
- **Medical Alert Integration**: Direct connection to on-site medical teams with participant medical info
- **Weather Integration**: Real-time weather alerts and safety recommendations
- **Multi-language Support**: Internationalization for diverse event audiences

### Phase 2: Advanced Crowd Analytics
- **Crowd Density Heatmaps**: Real-time visualization of participant concentration
- **Predictive Flow Analysis**: AI-powered crowd movement predictions to prevent bottlenecks
- **Evacuation Route Planning**: Dynamic routing based on current crowd positions and emergency locations
- **Capacity Management**: Automatic alerts when areas approach maximum safe capacity
- **Historical Analytics Dashboard**: Post-event analysis for organizers to improve future events

### Phase 3: Smart Integration & Automation
- **IoT Sensor Integration**: Connect with smart barriers, turnstiles, and environmental sensors
- **Drone Surveillance Integration**: Aerial view coordination with ground-level app data
- **Social Media Monitoring**: Track event hashtags and sentiment for early issue detection
- **Automated Resource Dispatch**: AI-driven assignment of volunteers and resources based on real-time needs
- **Wearable Device Support**: Integration with smartwatches and fitness trackers for health monitoring

### Phase 4: Platform Expansion
- **Web Dashboard**: Comprehensive organizer control panel for large screens
- **API for Third-party Integration**: Allow event management platforms to integrate SimhaLink features
- **White-label Solutions**: Customizable versions for specific industries (sports venues, airports, shopping centers)
- **Blockchain Event Logging**: Immutable record-keeping for insurance and legal compliance
- **AR Wayfinding**: Augmented reality directions and information overlays

## License

- This repository includes a `LICENSE` file. Review it for reuse and contribution terms.

## Contact

- See project owner and maintainers in the repository metadata.