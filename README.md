# University Health Center (UHC) App

A comprehensive Flutter mobile application for managing university health center appointments, doctors, and medical services.

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)
![Firebase](https://img.shields.io/badge/Firebase-Enabled-orange.svg)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web-green.svg)
![Languages](https://img.shields.io/badge/Languages-English%20%7C%20Arabic%20%7C%20Kurdish-blueviolet.svg)

## Features

### 👤 User Features
- **Authentication**: Email/password login, Google Sign-In, password recovery
- **Appointment Booking**: Browse doctors, select time slots, book appointments
- **Appointment Management**: View, reschedule, cancel appointments
- **Medical Documents**: Upload and manage medical records (lab results, prescriptions, imaging)
- **Notifications**: Push notifications and in-app reminders for appointments
- **Profile Management**: Edit profile, change password, upload photo
- **Dark Mode**: Toggle between light and dark themes
- **Multi-Language Support**: Full localization in English, Arabic, and Kurdish

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

### 🏥 Departments
- General Medicine
- Pediatrics
- Dermatology
- Psychiatry
- Rehabilitation
- Pharmacy
- Orthopedics
- Laboratory
- Radiology
- Cardiology

## Tech Stack

| Category | Technology |
|----------|------------|
| Framework | Flutter 3.x |
| State Management | Provider |
| Backend | Firebase (Auth, Firestore, Storage, Cloud Messaging, Cloud Functions) |
| Local Storage | SharedPreferences |
| Notifications | flutter_local_notifications, Firebase Cloud Messaging |
| UI | Material Design 3, Google Fonts |
| Localization | ARB files, flutter_localizations (EN, AR, KU) |

## Project Structure

```
lib/
├── core/
│   ├── constants/       # App colors, strings, assets
│   └── theme/           # App theme configuration
├── data/
│   ├── models/          # Data models (User, Doctor, Appointment)
│   └── repositories/    # Data repositories
├── l10n/                # Localization files (EN, AR, KU)
│   ├── app_en.arb       # English translations
│   ├── app_ar.arb       # Arabic translations
│   └── app_ku.arb       # Kurdish translations
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
│   ├── profile/         # User profile, settings, and account management
│   ├── reviews/         # Doctor ratings and reviews
│   └── splash/          # Splash screen
└── services/            # FCM, local notifications
└── functions/           # Firebase Cloud Functions (TypeScript)
```

## Firebase Cloud Functions

The project uses Firebase Cloud Functions (TypeScript) for secure administrative tasks that require privileged access:

| Function Name | Description | Access Level |
|---------------|-------------|--------------|
| `createDoctorAccount` | Creates a new Doctor account in Firebase Auth and Firestore with the 'doctor' role. | Admin Only |
| `updateDoctorEmail` | Updates a doctor's email address in both Auth and Firestore. | Admin Only |
| `deleteDoctorAccount` | Completely removes a doctor's account from Auth and Firestore. | Admin Only |
| `resetDoctorPassword` | Securely resets a doctor's password without requiring old password. | Admin Only |

> **Note**: These functions ensure that critical operations like creating accounts with specific roles are handled securely on the backend, preventing unauthorized privilege escalation.

## Getting Started

### Prerequisites
- Flutter SDK 3.x
- Dart SDK
- Firebase project with enabled services:
  - Authentication (Email, Google)
  - Cloud Firestore
  - Cloud Messaging
  - Firebase Storage
  - Firebase Cloud Functions

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

## Changelog

### v1.3.0 (February 2026)

#### ⚡ Performance Optimizations
- **Lazy Loading for Navigation Screens**: Implemented lazy loading in `MainShell` to prevent simultaneous initialization of all screens
  - Added `_visitedScreens` tracking set to defer screen building
  - Screens are now only built when first accessed via tab navigation
  - Reduced startup frame drops from 449+ to under 50 frames
  - Eliminated ANR (Application Not Responding) errors during startup

- **Deferred Service Initialization**: Restructured app startup for faster initial render
  - Only Firebase Core is initialized before `runApp()`
  - LocalNotificationService and FCMService are now initialized asynchronously after the first frame
  - Used `WidgetsBinding.instance.addPostFrameCallback()` for non-blocking initialization

- **Deferred Data Loading**: Optimized data fetching in screens
  - HomeScreen's `_loadDepartments()` now deferred to after first frame render
  - Prevents data loading from blocking UI during initial render

#### 🔒 Booking System Fixes
- **Booked Time Slots Prevention**: Fixed critical bug where booked time slots were still selectable
  - Fixed field name mismatch: `'dateTime'` → `'appointmentDate'` in Firestore query
  - Booked slots now correctly appear grayed out with strikethrough text
  - Prevents double-booking by blocking selection of already-booked time slots
  - Added immediate clearing of stale booked slots data when selecting new dates

#### 🔧 Technical Improvements
- **Firestore Query Optimization**: Changed from real-time subscription to one-time fetch for booked appointments
  - Reduces unnecessary Firestore read operations
  - Improves performance on booking screen
  - Added local filtering for date and status

### v1.2.0 (February 2026)

#### 🌍 Localization
- **Multi-Language Support**: Added full localization for English, Arabic, and Kurdish
- **Doctor Bios**: Translated all doctor biographies into Kurdish and Arabic
- **Appointment Screens**: Localized cancellation dialogs and rescheduling screens
- **Kurdish Localization**: Implemented custom Kurdish material localizations

#### 🏥 Departments
- **Cardiology Department**: Added new Cardiology department with full support across all screens
  - Updated `doctor_model.dart` Department enum
  - Integrated into emergency request screen
  - Added to department browsing screen

#### 👤 Profile & UI Improvements
- **Profile Screen Refinement**:
  - Developer Testing and Admin sections now only visible to admin users
  - Moved "Account" section (Edit Profile, Change Password) from Settings to Profile screen
  - Removed redundant Settings screen navigation
- **Dialog Size Consistency**: Fixed AlertDialog sizes for Add Doctor/Edit Doctor to be consistent
- **FAB Enhancement**: Added "Appointments" text label to floating action button with proper placement

#### 🔔 Notifications
- **Android 12+ Compatibility**: Fixed exact alarm permission handling
- **Production Ready**: Removed test notification code, keeping only production features
- **Scheduling Improvements**: Enhanced appointment reminder scheduling and cancellation

#### 🔧 Technical Improvements
- **Deprecated Code Fixes**:
  - Replaced `value` with `initialValue` in DropdownButtonFormField
  - Updated deprecated `withOpacity` calls to `withValues`
  - Fixed deprecated RadioListTile properties
  - Replaced underscore parameters with explicit names in errorBuilder callbacks
- **Sample Data System**: Added admin functionality to seed sample doctors, appointments, and departments
- **Gradle Updates**: Updated Android Gradle plugin and enabled core library desugaring
- **Asset Fixes**: Corrected font asset paths in pubspec.yaml

### v1.1.0 (January 2026)
- Initial feature-complete release
- Firebase integration (Auth, Firestore, Storage, Cloud Messaging)
- Complete appointment booking workflow
- Admin dashboard with analytics
- Doctor management system

---

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
