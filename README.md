# Togetherly

Togetherly is a Flutter app for couples and small private groups. It combines shared memories, mood tracking, relationship timers, drawings, widgets, location moments, and lightweight social interactions in one private space.

## What The App Does

- Create a personal profile and sign in with Google or email/password
- Connect a partner or group with an invite link, code, or QR flow
- Save shared memories with photos, video links, music, text notes, and places
- Track mood entries for yourself and view mood history for connected partners
- Use relationship timers and a system timer tied to the connection start date
- Send "miss you" events and receive push notifications
- Create and browse shared drawings
- Sync selected data to home screen widgets
- Export memories and timers into a shareable archive

## First-Run User Flow

The intended first-time experience is:

1. Open the welcome screen and create an account
2. Complete profile setup
3. Enter the app and connect a partner from the Connect tab
4. Add the first memory, mood entry, or timer
5. Personalize the shared space with widgets, drawings, and profile settings

## Main Product Areas

### Welcome and Auth

- `lib/screens/welcome_screen.dart`
- `lib/screens/setup_screen.dart`
- `lib/screens/login_screen.dart`

The onboarding flow introduces the app, registration, sign-in, and first profile setup.

### Home

- `lib/screens/home_screen.dart`

The home screen is the main hub for relationship status, mood previews, memory previews, timers, navigation, and connected features.

### Connect Partner

- `lib/screens/connect_partner_screen.dart`
- `lib/services/deep_link_service.dart`

Users can connect via invite link, code, or QR. The app supports active connection switching and partner presence.

### Memory Lane

- `lib/screens/memory_lane_screen.dart`
- `lib/models/memory.dart`

Shared memories support multiple formats including text, photo, video links, music, and geolocation.

### Mood Calendar

- `lib/screens/mood_calendar_screen.dart`
- `lib/services/mood_service.dart`

Tracks daily mood entries and presents shared history and statistics.

### Profile and Settings

- `lib/screens/profile_screen.dart`

Contains account info, notification preferences, relationship stats, export, privacy policy, and app links.

## Tech Stack

- Flutter
- Firebase Auth
- Cloud Firestore
- Firebase Storage
- Firebase Messaging
- Firebase Hosting
- Firebase Cloud Functions

## Project Structure

```text
lib/
  main.dart
  models/
  screens/
  services/
  theme/
  widgets/
functions/
hosting/
test/
```

## Local Development

### Requirements

- Flutter SDK
- Firebase project configuration for Android/iOS
- A configured Google Sign-In setup if you want to test auth flows

### Install Dependencies

```bash
flutter pub get
```

### Run The App

```bash
flutter run
```

### Run Tests

```bash
flutter test
```

### Analyze

```bash
flutter analyze
```

## Web And Static Pages

The repository also contains hosted pages for:

- landing page
- privacy policy
- delete account flow
- store/support banners

Files live in `hosting/` and are served through Firebase Hosting.

## Cloud Functions

Cloud Functions live in `functions/` and currently include notification-related backend behavior such as the miss-you event push flow.

## Notes For Contributors

- This is not a starter Flutter app anymore; product behavior lives across several large screens and services
- Before adding new features, inspect the existing flows in `home_screen.dart`, `memory_lane_screen.dart`, `profile_screen.dart`, and `firebase_service.dart`
- Keep product copy aligned across the app, hosted pages, and store-facing materials
