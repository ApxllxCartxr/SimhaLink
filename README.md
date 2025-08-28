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
- `lib/services/` — backend integrations (Firebase, auth, messaging)
- `lib/models/` — data models used across the app
- `android/app/google-services.json` — Android Firebase config (required for builds)
- `lib/firebase_options.dart` — generated Firebase options for the app

See the `assets/` and `fonts/` folders for bundled resources.

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

## License

- This repository includes a `LICENSE` file. Review it for reuse and contribution terms.

## Contact

- See project owner and maintainers in the repository metadata.

---