# Cinna Tracker Operator App

MVP operator flow:
- Open app → Scan bus QR (gets public_code)
- Start session → backend returns publish token
- Begin tracking → background location stream sends pings every few seconds
- End trip → closes session

Run

```
# 1) Make sure you're in the correct folder (underscores, not hyphens)
cd /Users/ramy/Documents/Personal/Cinna/Github/cinna_tracker_operator_app

# By default, the app talks to production at https://www.cinna.app

# For local/dev testing you can override the backend URL:
# iOS simulator (localhost works)
flutter run -d ios --dart-define=BACKEND_URL=http://localhost:3000

# Android emulator (use 10.0.2.2 for host machine localhost)
flutter run -d android --dart-define=BACKEND_URL=http://10.0.2.2:3000

# Physical device on same Wi‑Fi (replace with your Mac's LAN IP)
flutter run --dart-define=BACKEND_URL=http://192.168.x.x:3000
```
# Main method (debugger)
flutter run --dart-define-from-file=dart_defines.json

# Main method (release) - more stable atm
flutter run --release --dart-define-from-file=dart_defines.json

iOS setup
- In Xcode, enable Background Modes → Location updates
- Info.plist keys:
  - NSLocationWhenInUseUsageDescription
  - NSLocationAlwaysAndWhenInUseUsageDescription

Android setup
- AndroidManifest permissions:
  - ACCESS_FINE_LOCATION
  - ACCESS_COARSE_LOCATION
  - ACCESS_BACKGROUND_LOCATION (Android 10+)
- Foreground service is recommended for production (e.g., flutter_foreground_task)

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
