<div align="center">

# 🏥 University Health Center (UHC)

### A Modern Healthcare Appointment & Management Platform

*Streamline university healthcare — from booking to administration — all in one beautiful, multilingual app.*

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Powered-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

[![Platform](https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white)]()
[![Platform](https://img.shields.io/badge/iOS-000000?style=flat-square&logo=apple&logoColor=white)]()
[![Platform](https://img.shields.io/badge/Web-4285F4?style=flat-square&logo=googlechrome&logoColor=white)]()
[![i18n](https://img.shields.io/badge/i18n-EN%20%7C%20AR%20%7C%20KU-blueviolet?style=flat-square)]()

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Architecture & Tech Stack](#-architecture--tech-stack)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
- [Firebase Configuration](#-firebase-configuration)
- [Cloud Functions](#-cloud-functions)
- [User Roles & Permissions](#-user-roles--permissions)
- [Building for Production](#-building-for-production)
- [Changelog](#-changelog)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🔭 Overview

**UHC** is a full-featured, production-ready Flutter application designed for university health centers. It provides a seamless experience for **students** and **staff** to book medical appointments, while giving **administrators** powerful tools for managing doctors, departments, and analytics — all backed by Firebase's real-time infrastructure.

### ✨ Why UHC?

| | |
|---|---|
| 🌐 **Multilingual** | Full RTL support with English, Arabic, and Kurdish translations |
| ⚡ **Performant** | Lazy-loaded screens, deferred initialization, and optimized Firestore queries |
| 🔒 **Secure** | Role-based access control with server-side Cloud Functions for privileged operations |
| 🎨 **Modern UI** | Material Design 3, smooth animations, dark mode, and responsive layouts |
| 📱 **Cross-Platform** | Single codebase for Android, iOS, and Web |

---

## 🚀 Key Features

<details>
<summary><b>👤 Patient Portal</b></summary>

- **Smart Authentication** — Email/password, Google Sign-In, and password recovery
- **Appointment Booking** — Browse by department or doctor, pick available time slots, and confirm instantly
- **Appointment Management** — View upcoming/past appointments, reschedule, or cancel with reason tracking
- **Medical Documents** — Upload and organize lab results, prescriptions, and imaging reports
- **Push Notifications** — Appointment reminders and in-app notification center
- **Profile Management** — Edit personal info, change password, upload profile photo
- **QR Code** — Generate QR codes for appointments
- **Dark Mode** — System-aware or manual theme toggle

</details>

<details>
<summary><b>👨‍⚕️ Doctor Dashboard</b></summary>

- View daily/weekly scheduled appointments
- Manage personal availability and time slots
- Access patient information and appointment history

</details>

<details>
<summary><b>🔧 Admin Console</b></summary>

- **Real-Time Dashboard** — Live KPIs: total users, doctors, appointments, and revenue
- **Department Management** — Create departments with custom color, icon (155+ options), and per-day working hours
- **Doctor Management** — Full CRUD with schedule constraints tied to department hours
- **User Management** — View all users, assign roles, toggle account status
- **Analytics** — Interactive charts for appointment trends and department performance
- **Reports** — Export CSV reports for appointments, doctors, users, and revenue

</details>

<details>
<summary><b>🏥 Supported Departments</b></summary>

| Department | Department |
|:---|:---|
| General Medicine | Orthopedics |
| Pediatrics | Laboratory |
| Dermatology | Radiology |
| Psychiatry | Cardiology |
| Rehabilitation | Pharmacy |

> Departments are fully configurable via the admin console — add new ones with custom icons, colors, and working hours.

</details>

---

## 🏗 Architecture & Tech Stack

### Technology Overview

| Layer | Technology | Purpose |
|:---|:---|:---|
| **Framework** | Flutter 3.x / Dart 3.5+ | Cross-platform UI toolkit |
| **State Management** | Provider | Reactive state with ChangeNotifier |
| **Authentication** | Firebase Auth, Google Sign-In | Secure multi-method authentication |
| **Database** | Cloud Firestore | Real-time NoSQL document database |
| **File Storage** | Firebase Storage | Medical document & image hosting |
| **Messaging** | Firebase Cloud Messaging | Push notifications |
| **Server Logic** | Firebase Cloud Functions (TypeScript) | Privileged admin operations |
| **Local Storage** | SharedPreferences | User preferences & theme persistence |
| **Notifications** | flutter_local_notifications | Scheduled local reminders |
| **UI Framework** | Material Design 3, Google Fonts | Modern design language |
| **Animations** | Lottie, flutter_animate | Smooth onboarding & micro-interactions |
| **Charts** | fl_chart | Admin analytics & dashboards |
| **Calendar** | table_calendar | Date selection for appointments |
| **Localization** | ARB files, flutter_localizations | EN / AR / KU with RTL support |

### Application Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Presentation Layer                   │
│         Screens  ·  Widgets  ·  Animations              │
├─────────────────────────────────────────────────────────┤
│                   State Management                      │
│                     Provider                            │
├─────────────────────────────────────────────────────────┤
│                     Data Layer                          │
│            Models  ·  Repositories                      │
├─────────────────────────────────────────────────────────┤
│                   Services Layer                        │
│       FCM  ·  Local Notifications  ·  Utilities         │
├─────────────────────────────────────────────────────────┤
│                   Firebase Backend                      │
│  Auth  ·  Firestore  ·  Storage  ·  Functions  ·  FCM   │
└─────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
uhc/
├── lib/
│   ├── core/
│   │   ├── constants/          # Colors, strings, asset paths
│   │   └── theme/              # Material 3 theme configuration
│   ├── data/
│   │   ├── models/             # User, Doctor, Appointment, Department models
│   │   └── repositories/      # Firestore data access layer
│   ├── l10n/
│   │   ├── app_en.arb          # 🇬🇧 English translations
│   │   ├── app_ar.arb          # 🇸🇦 Arabic translations
│   │   └── app_ku.arb          # Kurdish translations
│   ├── providers/              # ChangeNotifier providers
│   ├── screens/
│   │   ├── admin/              # Dashboard, doctor/user/department management
│   │   ├── appointments/       # Booking flow, history, rescheduling
│   │   ├── auth/               # Login, register, forgot password
│   │   ├── departments/        # Department browsing & filtering
│   │   ├── doctors/            # Doctor list, profiles, reviews
│   │   ├── documents/          # Medical document upload & viewer
│   │   ├── home/               # Home feed & main navigation shell
│   │   ├── location/           # Health center map & directions
│   │   ├── notifications/      # Notification center
│   │   ├── onboarding/         # First-launch walkthrough
│   │   ├── profile/            # Profile, account settings
│   │   ├── reviews/            # Ratings & review system
│   │   └── splash/             # Animated splash screen
│   ├── services/               # FCM, local notifications, utilities
│   └── utils/                  # Helper functions
├── functions/                  # Firebase Cloud Functions (TypeScript)
├── assets/
│   ├── images/                 # Static images
│   ├── animations/             # Lottie animation files
│   └── icons/                  # Custom icon assets
├── android/                    # Android platform configuration
├── ios/                        # iOS platform configuration
├── web/                        # Web platform configuration
└── pubspec.yaml                # Dependencies & metadata
```

---

## 🚀 Getting Started

### Prerequisites

| Requirement | Version |
|:---|:---|
| Flutter SDK | 3.x or later |
| Dart SDK | 3.5+ |
| Node.js | 18+ *(for Cloud Functions)* |
| Firebase CLI | Latest |
| Android Studio / Xcode | For platform builds |

### Quick Start

```bash
# 1. Clone the repository
git clone <repository-url>
cd uhc

# 2. Install Flutter dependencies
flutter pub get

# 3. Configure Firebase (see next section)

# 4. Generate localization files
flutter gen-l10n

# 5. Run the app
flutter run
```

### Cloud Functions Setup

```bash
# Navigate to functions directory
cd functions

# Install Node.js dependencies
npm install

# Deploy functions to Firebase
firebase deploy --only functions
```

---

## 🔥 Firebase Configuration

### Required Services

Enable the following in your [Firebase Console](https://console.firebase.google.com):

- ✅ **Authentication** — Enable Email/Password and Google Sign-In providers
- ✅ **Cloud Firestore** — Create database in production mode
- ✅ **Firebase Storage** — Enable for file uploads
- ✅ **Cloud Messaging** — Enable for push notifications
- ✅ **Cloud Functions** — Upgrade project to Blaze plan (required for Node.js functions)

### Platform Configuration

| Platform | Config File | Location | Instructions |
|:---|:---|:---|:---|
| Android | `google-services.json` | `android/app/` | Download from Firebase Console |
| iOS | `GoogleService-Info.plist` | `ios/Runner/` | Download from Firebase Console |
| Web | Firebase config object | `web/index.html` | Copy config from Firebase Console |

### Android Configuration

Ensure your `android/app/src/main/AndroidManifest.xml` includes these permissions:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

### iOS Configuration

Add these keys to `ios/Runner/Info.plist` for permissions:

```xml
<!-- Camera & Photo Library for Profile/Document Uploads -->
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take profile photos and scan medical documents.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to upload profile photos and medical records.</string>

<!-- Notifications -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

### Firestore Collections

| Collection | Description |
|:---|:---|
| `users` | User profiles, roles, and preferences |
| `doctors` | Doctor profiles, specializations, and schedules |
| `departments` | Department metadata — name, icon, color, working hours |
| `appointments` | Booking records with status tracking |
| `reviews` | Doctor ratings and patient reviews |
| `notifications` | Per-user notification history |
| `medical_documents` | Uploaded file metadata and storage references |

---

## ⚙️ Cloud Functions

Server-side functions handle privileged operations that require Firebase Admin SDK access:

| Function | Description | Access |
|:---|:---|:---|
| `createDoctorAccount` | Creates a doctor account in Auth + Firestore with the `doctor` role | 🔒 Admin |
| `updateDoctorEmail` | Updates a doctor's email in both Auth and Firestore | 🔒 Admin |
| `deleteDoctorAccount` | Removes a doctor from Auth and Firestore completely | 🔒 Admin |
| `resetDoctorPassword` | Resets a doctor's password without requiring the old one | 🔒 Admin |

> **Security Note:** These functions enforce admin-only access to prevent unauthorized privilege escalation. All critical account mutations are handled server-side.

---

## 🔐 User Roles & Permissions

| Role | Capabilities |
|:---|:---|
| **Student** | Book/manage appointments, upload documents, view own records |
| **Staff** | Same as Student — campus staff access |
| **Doctor** | View assigned appointments, manage schedule and availability |
| **Admin** | Full system access — manage users, doctors, departments, view analytics, export reports |

> **Note:** The first admin user must be created manually in Firestore.
> 
> **How to create an Admin:**
> 1. Sign up as a regular user in the app.
> 2. Go to Firebase Console > Firestore Database > `users` collection.
> 3. Find your user document.
> 4. Change the `role` field from `"student"` to `"admin"`.
> 5. Restart the app to see the Admin Dashboard.

---

## 📦 Building for Production

```bash
# ── Android ──────────────────────────
flutter build apk --release          # APK
flutter build appbundle --release     # AAB (Play Store)

# ── iOS ──────────────────────────────
flutter build ios --release

# ── Web ──────────────────────────────
flutter build web --release
```

---

## 🛠 Configuration Reference

| File | Purpose |
|:---|:---|
| `lib/core/constants/app_colors.dart` | Color scheme & palette |
| `lib/core/constants/app_strings.dart` | App-wide string constants |
| `lib/core/constants/app_assets.dart` | Asset path references |
| `lib/core/theme/` | Material 3 light & dark theme definitions |
| `l10n.yaml` | Localization generation config |
| `firestore.rules` | Firestore security rules |
| `firestore.indexes.json` | Composite index definitions |

---

## 📝 Changelog

<details>
<summary><b>v1.4.0</b> — February 2026</summary>

#### 🏥 Department Working Hours
- Fixed persistent working hours — custom times no longer reset after toggling days
- All 7 days saved with `start`, `end`, and `enabled` fields; backward-compatible
- Mon–Fri default to ON (08:00–20:00), Sat–Sun default to OFF for new departments
- Fixed oversized Switch widgets in the working hours section

#### 👨‍⚕️ Doctor Schedule Improvements
- Doctor schedules now respect department `enabled` flags for closed days
- Time slot picker constrained to department working hours range
- Closed days auto-disabled in doctor schedule dialog
- Replaced hidden SnackBars with visible AlertDialogs for validation errors

#### ⚡ Color Picker Performance
- Cached color, hex, and gradient values — eliminates per-frame recalculations
- Unified HSL mutations through `_setHSL()` → `_recomputeCache()` pipeline
- Hex field syncs on `onChangeEnd` only — no unnecessary rebuilds

#### 🎨 Expanded Icons
- 155+ department icons (up from ~85), organized into clear categories

#### 🔧 Technical
- Migrated deprecated `color.value` → `color.toARGB32()`
- Migrated `RadioListTile` to `RadioGroup` ancestor widget (Flutter 3.32+)
- Wrapped bare `if` statements per Dart lint rules

</details>

<details>
<summary><b>v1.3.0</b> — February 2026</summary>

#### ⚡ Performance
- Lazy-loaded navigation screens — reduced startup frame drops from 449+ to under 50
- Deferred service initialization (notifications, FCM) after first frame
- Deferred data loading in HomeScreen to prevent UI blocking

#### 🔒 Booking Fixes
- Fixed critical double-booking bug: corrected field name mismatch in Firestore query
- Booked slots now appear grayed out with strikethrough styling
- Switched from real-time subscription to one-time fetch for booked appointments

</details>

<details>
<summary><b>v1.2.0</b> — February 2026</summary>

#### 🌍 Localization
- Full multi-language support: English, Arabic, Kurdish
- Localized doctor bios, cancellation dialogs, and rescheduling screens
- Custom Kurdish material localizations

#### 🏥 Departments
- Added Cardiology department with full integration across all screens

#### 👤 Profile & UI
- Admin-only visibility for Developer Testing and Admin sections
- Consolidated account settings into Profile screen
- Consistent dialog sizing; enhanced FAB with text label

#### 🔔 Notifications
- Android 12+ exact alarm permission handling
- Cleaned up test notification code for production readiness

#### 🔧 Technical
- Deprecated API migrations (`withOpacity` → `withValues`, `value` → `initialValue`)
- Sample data seeder for admin testing
- Gradle plugin update + core library desugaring

</details>

<details>
<summary><b>v1.1.0</b> — January 2026</summary>

- Initial feature-complete release
- Firebase integration (Auth, Firestore, Storage, Cloud Messaging)
- Complete appointment booking workflow
- Admin dashboard with analytics
- Doctor management system

</details>

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. **Fork** the repository
2. **Create** your feature branch
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. **Commit** your changes with a descriptive message
   ```bash
   git commit -m "feat: add amazing feature"
   ```
4. **Push** to your branch
   ```bash
   git push origin feature/amazing-feature
   ```
5. **Open** a Pull Request

> Please ensure your code follows the project's lint rules (`flutter analyze`) and includes appropriate tests.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## 📬 Support

For questions, bug reports, or feature requests:

- 📧 Email: [aleaskamil1234@gmail.com](mailto:aleaskamil1234@gmail.com)
- 🐛 Issues: [Open an issue](../../issues)

---

<div align="center">

**Built with ❤️ using Flutter & Firebase**

*University Health Center © 2026*

</div>
