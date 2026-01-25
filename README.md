# University Health Center (UHC) App

A comprehensive Flutter mobile application for managing university health center appointments, doctors, and medical services.

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)
![Firebase](https://img.shields.io/badge/Firebase-Enabled-orange.svg)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web-green.svg)

## Features

### 👤 User Features
- **Authentication**: Email/password login, Google Sign-In, password recovery
- **Appointment Booking**: Browse doctors, select time slots, book appointments
- **Appointment Management**: View, reschedule, cancel appointments
- **Medical Documents**: Upload and manage medical records (lab results, prescriptions, imaging)
- **Notifications**: Push notifications and in-app reminders for appointments
- **Profile Management**: Edit profile, change password, upload photo
- **Dark Mode**: Toggle between light and dark themes

### 👨‍⚕️ Doctor Features
- View scheduled appointments
- Manage availability and schedule
- Patient information access

### 🔧 Admin Features
- **Dashboard**: Statistics overview (users, doctors, appointments, revenue)
- **Doctor Management**: Add, edit, delete, activate/deactivate doctors
- **User Management**: View users, change roles, toggle status
- **Analytics**: Appointment statistics with charts and trends
- **Reports**: Generate CSV reports (appointments, doctors, users, revenue)

## Tech Stack

| Category | Technology |
|----------|------------|
| Framework | Flutter 3.x |
| State Management | Provider |
| Backend | Firebase (Auth, Firestore, Storage, Cloud Messaging) |
| Local Storage | SharedPreferences |
| Notifications | flutter_local_notifications, Firebase Cloud Messaging |
| UI | Material Design 3, Google Fonts |

## Project Structure

```
lib/
├── core/
│   ├── constants/       # App colors, strings, assets
│   └── theme/           # App theme configuration
├── data/
│   ├── models/          # Data models (User, Doctor, Appointment)
│   └── repositories/    # Data repositories
├── providers/           # State management providers
├── screens/
│   ├── admin/           # Admin dashboard, doctor/user management
│   ├── appointments/    # Booking, viewing, rescheduling
│   ├── auth/            # Login, register, forgot password
│   ├── departments/     # Department browsing
│   ├── doctors/         # Doctor list and details
│   ├── documents/       # Medical document upload
│   ├── home/            # Home screen, main shell
│   ├── location/        # Health center map
│   ├── notifications/   # Notification center
│   ├── onboarding/      # First-time user onboarding
│   ├── profile/         # User profile management
│   ├── reviews/         # Doctor ratings and reviews
│   ├── settings/        # App settings
│   └── splash/          # Splash screen
└── services/            # FCM, local notifications
```

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- Dart SDK
- Firebase project with enabled services:
  - Authentication (Email, Google)
  - Cloud Firestore
  - Cloud Messaging

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd uhc
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com)
   - Enable Authentication, Firestore, and Cloud Messaging
   - Download and add configuration files:
     - `google-services.json` (Android) → `android/app/`
     - `GoogleService-Info.plist` (iOS) → `ios/Runner/`
   - For web, update `web/index.html` with Firebase config

4. **Run the app**
   ```bash
   flutter run
   ```

## Firebase Collections

| Collection | Description |
|------------|-------------|
| `users` | User profiles and roles |
| `doctors` | Doctor information and schedules |
| `appointments` | Appointment bookings |
| `reviews` | Doctor ratings and reviews |
| `notifications` | User notifications |
| `medical_documents` | Uploaded medical files metadata |

## User Roles

| Role | Permissions |
|------|-------------|
| `student` | Book appointments, view own records |
| `staff` | Book appointments, view own records |
| `doctor` | View assigned appointments, manage schedule |
| `admin` | Full access to all features and management |

## Configuration

### Environment Variables
Update `lib/core/constants/` for:
- `app_colors.dart` - Color scheme
- `app_strings.dart` - String constants
- `app_assets.dart` - Asset paths

### Notification Setup
- Android: Configure in `android/app/src/main/AndroidManifest.xml`
- iOS: Enable Push Notifications capability in Xcode

## Building for Production

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support, email support@uhc.edu or open an issue in the repository.

---

Built with ❤️ using Flutter
