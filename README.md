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

**UHC** is a full-featured, production-ready Flutter application designed for university health centers. It provides a seamless experience for **students** and **staff** to book medical appointments, a dedicated **doctor dashboard** for managing appointments and schedules with QR-verified check-ins, and powerful **admin tools** for managing doctors, departments, and analytics — all backed by Firebase's real-time infrastructure.

### ✨ Why UHC?

| | |
|---|---|
| 🌐 **Multilingual** | Full RTL support with English, Arabic, and Kurdish translations |
| ⚡ **Performant** | Scalability-audited for large users, bounded Firestore queries, parallel fetching, and composite indexes |
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

- **Dashboard Overview** — Personalized greeting, daily stats (patients, appointments, completed, pending), and quick access to upcoming appointments
- **Appointment Management** — View upcoming and past appointments with staggered card animations, patient avatars, and status badges
- **QR-Verified Check-In** — Time-gated confirm button (5 min before → 10 min after appointment); opens camera QR scanner to verify patient presence; manual fallback after 5 failed scans
- **Schedule Management** — Interactive calendar with day/week/month views, color-coded time slots (booked, available, past, blocked)
- **Appointment Details** — Full appointment view with patient info, medical notes editor, and action buttons (confirm, complete, cancel, no-show)
- **Patient Profiles** — View patient details, profile photos, medical info, and appointment history from within appointment context
- **Doctor Profile & Settings** — Edit specialization, bio, qualifications; configure notifications, language, and theme
- **Push Notifications** — Real-time alerts for new bookings, cancellations, and status changes
- **Consistent Design Language** — Matches patient/staff UI with shared widgets, staggered animations, skeleton loaders, and theme-aware styling

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
| **QR Codes** | qr_flutter, mobile_scanner | Patient QR generation & doctor-side scanning |
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
│   │   ├── constants/              # Colors, strings, asset paths
│   │   ├── localization/           # Kurdish material localizations
│   │   ├── theme/                  # Material 3 theme configuration
│   │   ├── utils/                  # Locale helpers, utilities
│   │   └── widgets/                # Shared widgets (buttons, text fields, cards, skeletons)
│   ├── data/
│   │   ├── models/                 # User, Doctor, Appointment, Department, Notification models
│   │   └── repositories/           # Firestore data access layer
│   ├── l10n/
│   │   ├── app_en.arb              # 🇬🇧 English translations
│   │   ├── app_ar.arb              # 🇸🇦 Arabic translations
│   │   ├── app_ku.arb              # Kurdish translations
│   │   └── app_localizations*.dart # Generated localization classes
│   ├── providers/                  # ChangeNotifier providers (auth, appointments, doctor, theme, locale, notifications)
│   ├── screens/
│   │   ├── auth/                   # Login, forgot password, Google linking
│   │   ├── splash/                 # Animated splash screen
│   │   ├── onboarding/             # First-launch walkthrough
│   │   ├── shared/                 # Screens used by ALL roles
│   │   │   ├── notifications_screen.dart
│   │   │   ├── notification_settings_screen.dart
│   │   │   └── change_password_screen.dart
│   │   ├── patient/                # Student / Staff / Admin patient portal
│   │   │   ├── main_shell.dart     # Bottom navigation shell
│   │   │   ├── home/               # Home feed
│   │   │   ├── appointments/       # My appointments, reschedule, cancel, waiting list, emergency
│   │   │   ├── booking/            # Appointment booking flow
│   │   │   ├── browse_doctors/     # Doctor list & schedule viewer
│   │   │   ├── departments/        # Department browsing & filtering
│   │   │   ├── documents/          # Medical document upload & viewer
│   │   │   ├── profile/            # Profile & edit profile
│   │   │   └── location/           # Health center map & directions
│   │   ├── doctor/                 # Doctor dashboard (separate shell)
│   │   │   ├── doctor_shell.dart   # 5-tab bottom navigation shell
│   │   │   ├── dashboard/          # Overview, stats, today's appointments
│   │   │   ├── appointments/       # Appointment list, detail, patient info
│   │   │   ├── schedule/           # Calendar-based schedule management
│   │   │   ├── profile/            # Doctor profile & edit profile
│   │   │   └── qr/                 # QR code scanner for appointment check-in
│   │   └── admin/                  # Admin management console
│   │       ├── dashboard/          # Admin KPI dashboard
│   │       ├── departments/        # Department CRUD with form dialog
│   │       ├── doctors/            # Doctor CRUD with schedule dialog
│   │       ├── users/              # User management with form dialog
│   │       ├── analytics/          # Appointment analytics & charts
│   │       └── reports/            # CSV report generation & export
│   ├── services/                   # Auth, FCM, local notifications, Cloud Function wrappers
│   └── utils/                      # Helper functions
├── functions/                      # Firebase Cloud Functions (TypeScript)
├── assets/
│   ├── images/                     # Static images
│   ├── animations/                 # Lottie animation files
│   └── icons/                      # Custom icon assets
├── android/                        # Android platform configuration
├── ios/                            # iOS platform configuration
├── web/                            # Web platform configuration
├── docs/                           # Internal documentation & audit reports
├── firestore.rules                 # Firestore security rules (role-based)
├── firestore.indexes.json          # Composite index definitions for optimized queries
└── pubspec.yaml                    # Dependencies & metadata
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
<uses-permission android:name="android.permission.CAMERA"/>
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
| `appointments` | Booking records with status tracking, QR check-in, and scan failure counts |
| `notifications` | Per-user notification history |
| `user_tokens` | FCM device tokens per user (used by Cloud Functions for push delivery) |
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
| `createUserAccount` | Creates a user account in Auth + Firestore with a specified role | 🔒 Admin |
| `onNotificationCreated` | Firestore trigger — sends FCM push when a notification document is created | 🔄 Auto |
| `sendTopicNotification` | Sends broadcast push notifications to FCM topics (e.g. announcements) | 🔒 Admin |

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

<details open>
<summary><b>v1.10.0</b> — April 2026</summary>

#### ⚡ Scalability & Performance Audit (20k–50k Concurrent Users)
A comprehensive code audit identified and resolved 13 scalability issues to ensure the app performs smoothly at scale (20,000–50,000 concurrent users).

##### 🔴 Critical Fixes
- **Bounded Firestore Queries** — Added `.limit()` to every unbounded query across the entire codebase. Previously, methods like `getUpcomingAppointments()`, `getPastAppointments()`, and `getAllDoctorAppointments()` would download entire document collections (potentially 500k+ docs at scale). All queries now have appropriate limits (500–1000 docs per method).
- **N+1 Query Elimination** — Replaced sequential `for`-loop photo fetching with `Future.wait()` for parallel execution. Loading 10 doctor photos now takes ~200ms instead of ~3,000ms (one network round-trip vs. ten sequential ones).
- **Admin User Stream Limit** — Added `.limit(200)` to the admin User Management screen's real-time stream, preventing out-of-memory crashes when streaming 50k+ user documents.
- **Notification Query Optimization** — Replaced `getUnreadCount()` (which downloaded all unread documents) with Firestore's `.count()` aggregation — zero document downloads, server-side counting.

##### 🟡 Moderate Fixes
- **8 Composite Firestore Indexes** — Defined composite indexes for the most common query patterns (`doctorId + appointmentDate`, `patientId + appointmentDate`, `userId + createdAt`, `userId + isRead`, etc.) to enable efficient server-side filtering instead of client-side in-memory filtering.
- **Batch Operation Chunking** — All batch write operations (`markAllAsRead`, `deleteAllNotifications`, `deleteAllUserAppointments`, `deleteFutureDailySummaries`) now chunk into groups of 500 to respect Firestore's batch limit. Previously, batches with >500 operations would fail silently.
- **Booking Screen Query Limit** — Added `.limit(500)` to the booking screen's appointment fetch, preventing download of a doctor's entire appointment history on every calendar date tap.
- **Doctor Search Caching** — `searchDoctors()` now caches the doctor list in memory and filters locally, instead of re-fetching the entire `doctors` collection on every keystroke.
- **Analytics & Reports Limits** — Added `.limit(5000)` to analytics queries and `.limit(10000)` / `.limit(5000)` to CSV report generation queries to prevent timeouts and OOM crashes.

##### 🟢 Minor Fixes
- **FCM Token Refresh Leak** — Fixed duplicate `onTokenRefresh` listeners by cancelling previous subscriptions before re-registering.
- **Notification Tap Listener Leak** — Fixed `onMessageTapped` listeners being registered multiple times upon re-initialization, causing duplicate navigation.
- **Server-Side Daily Summary Filtering** — `deleteFutureDailySummaries()` now uses a `where('type', isEqualTo: 'dailySummary')` server-side filter instead of downloading all user notifications.

##### 📊 Projected Impact

| Metric | Before | After |
|:---|:---|:---|
| Firestore reads (50k users/day) | ~40,000,000+ | ~5,000,000 |
| Estimated monthly cost (50k users) | $150–250+ | $15–25 |
| Doctor appointment load time (2k+ appointments) | 3–8 seconds | <500ms |
| Doctor photo fetching (10 unique doctors) | ~3,000ms sequential | ~200ms parallel |

#### 📁 Files Changed

| File | Key Changes |
|:---|:---|
| `lib/data/repositories/appointment_repository.dart` | `.limit()` on all 5 query methods, chunked batch deletes |
| `lib/data/repositories/notification_repository.dart` | `count()` aggregation, stream limits, chunked batches, server-side filtering |
| `lib/providers/appointment_provider.dart` | Parallel doctor photo fetching via `Future.wait()` |
| `lib/providers/doctor_appointment_provider.dart` | Parallel patient photo fetching via `Future.wait()` |
| `lib/providers/doctor_provider.dart` | In-memory caching for doctor search |
| `lib/providers/notification_provider.dart` | Fixed FCM listener memory leak (`_messageTapSubscription`) |
| `lib/screens/admin/users/user_management_screen.dart` | `.limit(200)` on user stream |
| `lib/screens/patient/booking/booking_screen.dart` | `.limit(500)` on booked slots query |
| `lib/screens/admin/analytics/appointment_analytics_screen.dart` | `.limit(5000)` on analytics query |
| `lib/screens/admin/reports/reports_screen.dart` | `.limit()` on 3 report generation queries |
| `lib/services/fcm_service.dart` | Fixed duplicate token refresh listeners |
| `firestore.indexes.json` | Added 8 composite indexes |

</details>

<details>
<summary><b>v1.9.0</b> — March 2026</summary>

#### ⏱ Auto No-Show System
- **Automated Status Updates** — Pending appointments that have passed their scheduled time by 60 minutes (30-minute slot + 30-minute grace period) are automatically marked as "No Show" when the doctor opens their dashboard.
- **System Attribution** — Auto no-show updates are tagged with `statusUpdatedBy: 'system_auto'` to distinguish them from manual doctor actions.

#### 📷 Profile Image Size Limits
- **25 MB Upload Limit** — All profile image uploads (patient, doctor, and admin) now enforce a 25 MB file size limit with a clear error message, preventing excessive storage consumption.

#### 🔐 Google Authentication Hardening
- **Account-Only Sign-In** — Google Sign-In now only allows existing, admin-created accounts to log in. Signing in with a Google account that isn't already registered is blocked, preventing unauthorized account creation.
- **Profile Photo Preservation** — Signing in with a linked Google account no longer overwrites the user's custom profile image with the generic Google avatar.

#### 📅 Doctor Appointment Display Fix
- **Today's Appointments Visible** — Fixed a date comparison bug where today's appointments were not showing in the doctor's "Upcoming" tab. Corrected the start-of-day boundary logic to include the current date.

#### 📁 Document Screen Fixes
- **Stream Caching** — Fixed Firestore stream recreation during document uploads that caused performance issues and UI churn. The stream is now cached in widget state and only recreated when the user ID changes.
- **Mounted Check** — Added `mounted` guard before accessing context after async dialog operations to prevent "context used after dispose" errors.

#### 📁 Files Changed

| File | Key Changes |
|:---|:---|
| `lib/providers/doctor_appointment_provider.dart` | Auto no-show logic with 60-minute cutoff |
| `lib/screens/patient/profile/edit_profile_screen.dart` | 25 MB image upload limit |
| `lib/screens/doctor/profile/edit_doctor_profile_screen.dart` | 25 MB image upload limit |
| `lib/providers/auth_provider.dart` | Google sign-in restricted to existing accounts, photo preservation |
| `lib/screens/doctor/appointments/doctor_appointments_screen.dart` | Fixed today's appointment date boundary |
| `lib/screens/patient/documents/medical_documents_screen.dart` | Stream caching, mounted check |
| `lib/screens/doctor/documents/doctor_patient_documents_screen.dart` | Stream caching, mounted check |

</details>

<details>
<summary><b>v1.8.0</b> — March 2026</summary>

#### 🔔 FCM Push Notification Infrastructure (BUGs 6–10)
- **Server-Side FCM Sending** — Added `onNotificationCreated` Cloud Function: a Firestore `onDocumentCreated` trigger that automatically sends FCM push notifications when a notification document is created. Looks up user FCM tokens from the `user_tokens` collection and sends via `admin.messaging().send()` with Android high-priority channel and iOS alert/badge/sound support. Automatically cleans up stale tokens on `invalid-registration-token` errors.
- **Topic Broadcast Function** — Added `sendTopicNotification` callable Cloud Function for admins to send push notifications to FCM topics (e.g. `announcements`, `department_*`).
- **Patient FCM Token Registration** — Fixed `main_shell.dart` to call `notificationProvider.initialize(userId)` instead of `loadNotifications()`, ensuring patient devices register their FCM token, subscribe to topics, and start notification listeners.
- **FCMService Singleton** — Refactored `FCMService` into a proper singleton with a factory constructor and `_initialized` guard, preventing duplicate notification handlers across `main.dart` and `NotificationProvider`.
- **Platform Detection** — Replaced hardcoded `'android'` platform string with dynamic `Platform.isIOS ? 'ios' : 'android'` detection in both initial token save and `onTokenRefresh` listener.
- **Logout FCM Cleanup** — `AuthProvider.signOut()` now calls `FCMService.removeTokenFromDatabase()` and `unsubscribeUserFromTopics()` before Firebase Auth sign-out, preventing stale token accumulation.

#### 🔔 Notification System Consolidation
- **Unified Notification Settings** — Removed individual push/email notification toggles from patient `ProfileScreen` and doctor `DoctorProfileScreen`. All notification preferences are now managed exclusively through the shared `NotificationSettingsScreen`.
- **Real-Time Notification Streams** — `NotificationProvider` now uses Firestore real-time streams (`streamNotifications`, `streamUnreadCount`) instead of one-time fetches, so the UI auto-updates when new notifications arrive.
- **Doctor Daily Summary Settings** — Consolidated daily summary toggle and time picker into `NotificationSettingsScreen`, visible only to doctors. Time selection uses `SharedPreferences` and syncs to the scheduling system.
- **Dead Code Removal** — Removed unused `showAppointmentConfirmed()` and `showAppointmentCancelled()` methods from `LocalNotificationService`.

#### ⏰ Appointment Reminder Timing Fix
- **Exact Appointment Time** — Reminders now use `exactAppointmentTime` (date + timeSlot combined) instead of `appointmentDate` (midnight), so 1-week, 24-hour, and 1-hour reminders fire relative to the actual appointment time, not midnight.
- **Reschedule Reminders** — Rescheduled appointments correctly rebuild the exact DateTime from the new date and time slot.

#### 📬 Doctor Status Notifications to Patients
- **Confirmation Notification** — When a doctor confirms an appointment, the patient now receives a Firestore notification with the doctor's name, date, and time slot.
- **No-Show Notification** — When a doctor marks a patient as no-show, the patient receives a notification and old reminders are cleaned up.
- **Completion Notification** — When an appointment is completed, the patient receives a thank-you notification and old reminders are deleted.

#### 📷 Doctor Profile Photo Editing
- **Large Avatar Editor** — Doctor edit profile screen now features a 120px tappable photo circle (matching patient profile style) with camera icon overlay and "Tap to change photo" text.
- **Image Picker** — Camera, gallery, and remove options via bottom sheet with themed icons.
- **Firebase Storage Upload** — Photo is uploaded on save and the URL is synced to both `doctors` and `users` Firestore collections.
- **Read-Only Card Cleanup** — Removed duplicate small avatar from the read-only card, replaced with an info icon to avoid visual clutter.

#### 🎨 UI Improvements
- **Appointment Detail Layout** — Fixed text overflow in the doctor appointment detail info rows by switching to `Expanded` flex layout instead of `Spacer` + `Flexible`.
- **Patient Detail FittedBox** — Patient info values now scale down gracefully using `FittedBox` instead of being truncated with `TextOverflow.ellipsis`.
- **Home Screen Book Button** — "Book Appointment Now" text is now wrapped in `Flexible` with `maxLines: 1` to prevent overflow on narrow screens or long translations.

#### 📁 Files Changed

| File | Key Changes |
|:---|:---|
| `functions/src/index.ts` | Added `onNotificationCreated` and `sendTopicNotification` Cloud Functions |
| `lib/services/fcm_service.dart` | Singleton pattern, idempotent init, platform detection |
| `lib/providers/auth_provider.dart` | FCM cleanup on sign-out |
| `lib/providers/notification_provider.dart` | Real-time streams, `startListening()`, stream cleanup |
| `lib/providers/appointment_provider.dart` | `exactAppointmentTime` for reminders, `_buildExactTime()` helper |
| `lib/providers/doctor_appointment_provider.dart` | Patient status notifications, daily summary SharedPrefs sync, `_formatDate()` |
| `lib/screens/patient/main_shell.dart` | Calls `initialize()` instead of `loadNotifications()` |
| `lib/screens/patient/profile/profile_screen.dart` | Removed push/email toggles (moved to settings screen) |
| `lib/screens/doctor/doctor_shell.dart` | Calls `initialize()` instead of `loadNotifications()` |
| `lib/screens/doctor/profile/doctor_profile_screen.dart` | Removed push/email toggles (moved to settings screen) |
| `lib/screens/doctor/profile/edit_doctor_profile_screen.dart` | Photo picker, upload, name editing, read-only card cleanup |
| `lib/screens/doctor/appointments/doctor_appointment_detail_screen.dart` | Expanded flex layout for info rows |
| `lib/screens/doctor/appointments/patient_detail_screen.dart` | FittedBox for patient info values |
| `lib/screens/patient/home/home_screen.dart` | Flexible book button text |
| `lib/screens/shared/notification_settings_screen.dart` | Push/email toggles, doctor daily summary with time picker |
| `lib/screens/shared/notifications_screen.dart` | Real-time stream init |
| `lib/services/local_notification_service.dart` | Removed unused notification methods |

</details>

<details>
<summary><b>v1.7.0</b> — February 2026</summary>

#### 🔔 Doctor Daily Notifications
- **Customizable Timing** — Admins can now configure the exact time doctors receive their daily appointment summary directly from the Doctor Management panel.
- **Smart Working Days** — Daily notifications automatically respect the doctor's weekly schedule. Doctors will not receive alerts on their days off, preventing unnecessary spam.
- **Accurate Pending Counts** — Notifications explicitly tell doctors exactly how many *pending* appointments they have, clearly differentiating them from completed or cancelled ones.

#### 📷 QR Check-In System
- **Time-Gated Verification** — Doctors can now utilize a built-in QR scanner to confirm patient attendance securely.
- **Scan Attempt Monitoring** — Safely falls back to manual confirmation if multiple QR scans fail, with metrics stored in Firestore.
- **Localized** — Fully integrated QR UI messages across English, Arabic, and Kurdish.

</details>

<details>
<summary><b>v1.6.0</b> — February 2026</summary>

#### 🔧 Admin UI Refinements
- **Standardized Detail Sheets** — Users, Doctors, and Departments now share a unified, polished bottom sheet design
- **Improved Consistency** — "View Details" screens now feature consistent styling, layout, and action button placement
- **Department Status** — "Closed" days are now clearly marked in red with dimmed text in the details view

#### 🔐 Authentication Flow
- **Enhanced Google Linking** — Added "Sign Out" option to the mandatory link screen, preventing users from getting stuck
- **Navigation Safety** — Implemented `PopScope` to properly handle back navigation during the linking process
- **Lint Fixes** — Resolved `use_build_context_synchronously` issues in authentication flows

</details>

<details>
<summary><b>v1.5.0</b> — February 2026</summary>

#### 🎨 Doctor Screen Restyling
- **Unified Design Language** — All 8 doctor screens now match the patient/staff UI for a consistent cross-role experience
- **Staggered Animations** — Added `flutter_animate` fade-in and slide transitions to every doctor screen section (300→600ms stagger delays, `index * 100` per list item)
- **Skeleton Loaders** — Replaced bare `CircularProgressIndicator` with `CardSkeleton`, `AppointmentCardSkeleton`, and `SkeletonList` across dashboard, schedule, and patient detail screens
- **Theme-Aware Colors** — Replaced all hardcoded `Colors.white` backgrounds with `AppColors.surfaceLight` / `AppColors.surfaceDark` tokens for consistent light/dark mode support
- **Typography Hierarchy** — Enforced consistent font usage: `Poppins` for headings, `Plus Jakarta Sans` for subtitles, `Roboto` for body text, `Outfit` for avatar initials
- **Shared Widgets** — Adopted `GradientCard` for hero cards (dashboard greeting, patient profile header) instead of manual gradient containers
- **Improved Empty States** — Enlarged icons (80px), descriptive titles with `Poppins w600`, body text with `textAlign: center`, wrapped in scrollable containers for pull-to-refresh
- **Loading Overlays** — Appointment detail screen now uses a semi-transparent overlay during save operations instead of replacing content with a blank spinner
- **Layout Standardization** — Consistent 20px horizontal padding, 100px bottom clearance for nav bar, 16px border radius on all cards, and box shadows (`blur: 10, offset: (0,2)`) across all screens
- **SafeArea & Scaffold** — Schedule screen migrated from bare `SafeArea` + manual title to proper `Scaffold` + `AppBar`; Profile screen wrapped in `SafeArea`
- **Nav Bar Tokens** — Doctor shell nav bar light mode updated from `Colors.white` to `AppColors.surfaceLight` for token consistency

#### 📁 Screens Updated
| Screen | File | Key Changes |
|:---|:---|:---|
| Navigation Shell | `doctor_shell.dart` | Token-consistent nav bar colors |
| Dashboard | `doctor_dashboard_screen.dart` | GradientCard, stagger animations, skeleton loading |
| Appointments | `doctor_appointments_screen.dart` | Scrollable empty states, corrected icon colors, consistent animation timing |
| Schedule | `doctor_schedule_management_screen.dart` | Scaffold+AppBar, stagger animations, CardSkeleton loading |
| Appointment Detail | `doctor_appointment_detail_screen.dart` | Save overlay, section animations, Outfit avatar font |
| Patient Detail | `patient_detail_screen.dart` | GradientCard header, stagger animations, improved skeletons |
| Doctor Profile | `doctor_profile_screen.dart` | SafeArea, section shadows, PlusJakartaSans subtitle |
| Edit Profile | `edit_doctor_profile_screen.dart` | Stagger animations, Outfit avatar font, card shadow |

</details>

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
