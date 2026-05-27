<div align="center">

# 🏥 University Health Center (UHC)

### A Modern Healthcare Appointment & Management Platform

*Streamline university healthcare — from booking to administration — all in one beautiful, multilingual app.*

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Powered-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Dart](https://img.shields.io/badge/Dart-3.5+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

[![Platform](https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white)](android)
[![Platform](https://img.shields.io/badge/iOS-000000?style=flat-square&logo=apple&logoColor=white)](ios)
[![Platform](https://img.shields.io/badge/Web-4285F4?style=flat-square&logo=googlechrome&logoColor=white)](web)
[![i18n](https://img.shields.io/badge/i18n-EN%20%7C%20AR%20%7C%20KU-blueviolet?style=flat-square)](lib/l10n)

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
- [Super Admin Bootstrap](#-super-admin-bootstrap)
- [Building for Production](#-building-for-production)
- [Changelog](#-changelog)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🔭 Overview

**UHC** is a full-featured, production-ready Flutter application designed for university health centers. It provides a seamless experience for **students** and **staff** to book medical appointments, a dedicated **doctor dashboard** for managing appointments and schedules with QR-verified check-ins, robust **admin operations**, and a dedicated **Super Admin governance layer** for RBAC, permission control, slot governance, and auditability — all backed by Firebase's real-time infrastructure.

### ✨ Why UHC?

| | |
|---|---|
| 🌐 **Multilingual** | Full RTL support with English, Arabic, and Kurdish translations |
| ⚡ **Performant** | Scalability-audited for large users, cursor-paginated Firestore queries, scheduled push delivery, parallel fetching, and composite indexes |
| 🔒 **Secure** | Role-based access control with server-side Cloud Functions for privileged operations |
| 🎨 **Modern UI** | Material Design 3, smooth animations, dark mode, and responsive layouts |
| 📱 **Cross-Platform** | Single codebase for Android, iOS, and Web |

---

## 🚀 Key Features

<details>
<summary><b>👤 Patient Portal</b></summary>

- **Smart Authentication** — Email/password, Google Sign-In, and password recovery
- **Appointment Booking** — Browse by department or doctor, pick available time slots, and confirm instantly; unavailable or inactive doctors are locked in the UI and rejected by the backend
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
- **Availability Requests** — Request unavailable status with a note for admin approval, stay available while pending, and sync the dashboard switch in real time when admin changes availability
- **Push Notifications** — Real-time alerts for new bookings, cancellations, and status changes
- **Consistent Design Language** — Matches patient/staff UI with shared widgets, staggered animations, skeleton loaders, and theme-aware styling

</details>

<details>
<summary><b>🔧 Admin Console</b></summary>

- **Real-Time Dashboard** — Live KPIs: total users, doctors, appointments, and revenue
- **Department Management** — Create departments with custom color, icon (155+ options), and per-day working hours
- **Doctor Management** — Full CRUD with schedule constraints, active/inactive filters, visible availability badges, and admin controls to make doctors available or unavailable
- **Doctor Availability Review** — High-priority availability request notifications let doctor-managing admins approve or reject unavailable requests
- **User Management** — View all users with role-safe controls and account status management
- **Permission-Aware UI** — Admin actions are gated by granular permission keys (`users.manageNonAdmin`, `doctors.manage`, `departments.manage`, etc.)
- **Analytics** — Interactive charts for appointment trends and department performance
- **Reports** — Export professional styled XLSX reports for appointments, doctors, users, and departments (permission-gated)
- **Permission-Safe Dashboard** — KPI stats gracefully degrade to zero when the admin lacks the corresponding view permission
</details>

<details>
<summary><b>🛡️ Super Admin Governance</b></summary>

- **Dedicated Super Admin Shell** — Separate governance experience for web and mobile
- **Strict Slot Model** — Exactly two Super Admin slots (`primary` + `backup`) with transactional server-side enforcement
- **Admin Governance Actions** — Create admin, promote/demote roles, activate/deactivate, reset password, delete admin, force sign-out
- **Permissions Matrix** — Per-admin granular permission assignment with presets (Full / Operations / Read-Only)
- **Audit Logs** — Filterable governance audit trail by actor, target, action, and date
- **Hardened Trust Boundary** — Sensitive mutations moved to Cloud Functions; Firestore rules block client-side privilege escalation
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
| **Excel Reports** | Syncfusion Flutter XlsIO | Professional styled XLSX report generation |
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
│   │   ├── auth/                   # Login, forgot password, Google linking, initial password change
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
│   │   ├── admin/                  # Admin management console
│   │   │   ├── dashboard/          # Admin KPI dashboard
│   │   │   ├── departments/        # Department CRUD with form dialog
│   │   │   ├── doctors/            # Doctor CRUD with schedule dialog
│   │   │   ├── users/              # User management with form dialog
│   │   │   ├── notifications/      # Admin notification sender and recipient targeting
│   │   │   ├── analytics/          # Appointment analytics & charts
│   │   │   └── reports/            # Professional XLSX report generation & export
│   │   └── super_admin/            # Super Admin governance shell & screens
│   │       ├── super_admin_shell.dart
│   │       ├── super_admin_dashboard_screen.dart
│   │       ├── admin_control_screen.dart
│   │       └── audit_log_screen.dart
│   ├── services/                   # Auth, FCM, local notifications, admin notifications, Cloud Function wrappers
│   ├── utils/                      # Helper functions & cross-platform file utilities
│   │   ├── save_file.dart          # Conditional export: routes to web or IO implementation
│   │   ├── save_file_web.dart      # Web: Blob download via dart:js_interop
│   │   ├── save_file_io.dart       # Mobile/Desktop: save to temp + share via share_plus
│   │   └── save_file_stub.dart     # Stub for unsupported platforms
├── functions/                      # Firebase Cloud Functions (TypeScript)
├── test/                           # Security, notification theme, and integration tests
├── assets/
│   ├── images/                     # Static images
│   ├── animations/                 # Lottie animation files
│   └── icons/                      # Custom icon assets
├── android/                        # Android platform configuration
├── ios/                            # iOS platform configuration
├── web/                            # Web platform configuration
├── docs/                           # Internal documentation, plans, and runbooks
├── firestore.rules                 # Firestore security rules (role-based)
├── storage.rules                   # Firebase Storage security rules (scoped uploads)
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
- ✅ **Cloud Scheduler** — Required by scheduled notification delivery (`deliverScheduledNotifications`)

### Platform Configuration

| Platform | Config File | Location | Instructions |
|:---|:---|:---|:---|
| Android | `google-services.json` | `android/app/` | Download from Firebase Console |
| iOS | `GoogleService-Info.plist` | `ios/Runner/` | Download from Firebase Console |
| Web | Firebase config object | `web/index.html` | Copy config from Firebase Console |

### Authentication Email Deliverability (SMTP)

To improve password-reset inbox delivery (and reduce spam placement), configure custom SMTP in:

- `Firebase Console → Authentication → Templates → SMTP settings`

Recommended:

- Use a real sender mailbox (for example: `no-reply@yourdomain.com`)
- Use your SMTP provider's real host/port/security values (not placeholders)
- Verify sender DNS with your provider (SPF, DKIM, DMARC)

Without SMTP/domain authentication, default email senders are more likely to land in spam.

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
| `users` | User profiles, roles, preferences, language, and theme mode |
| `doctors` | Doctor profiles, specializations, and schedules |
| `departments` | Department metadata — name, icon, color, working hours |
| `appointments` | Booking records with status tracking, QR check-in, and scan failure counts |
| `appointment_slot_locks` | Transactional slot lock documents preventing double-booking (server-managed) |
| `notifications` | Per-user notification history |
| `user_tokens` | FCM device tokens per user (used by Cloud Functions for push delivery) |
| `doctor_availability_requests` | Server-owned doctor unavailable requests with admin review status and request notes |
| `doctor_availability_usage` | Monthly usage counters enforcing the two approved unavailable requests per doctor per calendar month |
| `admin_notification_sends` | Idempotency and audit records for admin-created notification sends |
| `admin_notification_rate_limits` | Per-admin cooldown records for notification sending |
| `medical_documents` | Uploaded file metadata and storage references |
| `doctor_patient_access` | Doctor-to-patient access grants for scoped medical document visibility |
| `admin_audit_logs` | Immutable governance audit trail for Super Admin actions |

---

## ⚙️ Cloud Functions

Server-side functions handle privileged operations that require Firebase Admin SDK access:

| Function | Description | Access |
|:---|:---|:---|
| **Appointment Lifecycle** | | |
| `createAppointment` | Validates doctor active/available status, slot availability, acquires transactional slot lock, creates appointment + patient notification | 🔒 Authenticated |
| `rescheduleAppointment` | Releases old slot lock, acquires new slot lock, updates appointment date/time atomically | 🔒 Authenticated |
| `cancelAppointment` | Cancels appointment and releases the slot lock | 🔒 Authenticated |
| `updateAppointmentStatus` | Updates status (confirmed, completed, noShow) with role-based access checks | 🔒 Doctor / Admin |
| `updateMedicalNotes` | Updates doctor medical notes on an appointment | 🔒 Doctor |
| `incrementQrScanFailures` | Atomically increments QR scan failure counter for an appointment | 🔒 Doctor |
| `deleteAppointment` | Permanently deletes an appointment and releases the slot lock | 🔒 Admin |
| **Doctor Management** | | |
| `createDoctorAccount` | Creates a doctor account in Auth + Firestore with the `doctor` role | 🔒 Admin |
| `updateDoctorEmail` | Updates a doctor's email in both Auth and Firestore | 🔒 Admin |
| `deleteDoctorAccount` | Removes a doctor from Auth and Firestore completely | 🔒 Admin |
| `resetDoctorPassword` | Resets a doctor's password without requiring the old one | 🔒 Admin |
| `completeInitialPasswordChange` | Forces doctor/student/staff users to replace an admin-created initial password | 🔒 Authenticated |
| `updateDoctorProfile` | Updates admin-safe doctor profile fields | 🔒 Admin |
| `setDoctorActiveStatus` | Activates/deactivates doctor records | 🔒 Admin |
| `updateDoctorSchedule` | Updates a doctor's weekly schedule | 🔒 Admin |
| `requestDoctorUnavailable` | Doctor submits an unavailable request with a note for admin review | 🔒 Doctor |
| `setDoctorAvailability` | Doctor returns to available immediately; unavailable requires admin approval | 🔒 Doctor |
| `setDoctorAvailabilityByAdmin` | Admin directly marks a doctor available/unavailable from Doctor Management | 🔒 Admin |
| `reviewDoctorAvailabilityRequest` | Admin approves/rejects a doctor unavailable request, cancels affected appointments, and notifies the doctor/patients | 🔒 Admin |
| **Department Management** | | |
| `createDepartment` | Creates a department with metadata and working hours | 🔒 Admin |
| `updateDepartment` | Updates department details and working hours | 🔒 Admin |
| `setDepartmentActiveStatus` | Activates/deactivates departments | 🔒 Admin |
| `deleteDepartment` | Deletes a department record | 🔒 Admin |
| **User Management** | | |
| `createUserAccount` | Creates student/staff accounts in Auth + Firestore | 🔒 Admin |
| `bootstrapSelfUserDocument` | Creates self-registration user profile document securely (`student` role) | 🔒 Authenticated |
| `setUserActiveStatus` | Activates/deactivates non-admin users | 🔒 Admin |
| `changeUserRoleByAdmin` | Changes non-admin user roles within allowed patient roles | 🔒 Admin |
| `unlinkGoogleProviderByAdmin` | Unlinks Google provider for managed users | 🔒 Admin |
| `updateUserProfileByAdmin` | Admin-safe profile updates without direct privilege writes | 🔒 Admin |
| `deleteUserAccount` | Deletes non-admin user accounts through server-side validation | 🔒 Admin |
| **Notifications** | | |
| `onNotificationCreated` | Firestore trigger — sends immediate FCM push and defers future scheduled notifications | 🔄 Auto |
| `deliverScheduledNotifications` | Scheduled function — delivers due notification documents every 5 minutes | 🔄 Auto |
| `searchAdminNotificationRecipients` | Searches valid notification recipients without broad client-side user listing | 🔒 Admin |
| `previewAdminNotificationRecipients` | Counts recipients before sending an admin notification | 🔒 Admin |
| `sendAdminNotification` | Creates audited in-app notifications for selected patient/doctor audiences | 🔒 Admin |
| `sendTopicNotification` | Disabled legacy topic sender; directs admins to audited in-app notifications | 🔒 Admin |
| **Super Admin Governance** | | |
| `createAdminAccount` | Creates admin account with default permission map | 🛡️ Super Admin |
| `changeAdminRole` | Promotes/demotes admin role (excluding superAdmin assignment) | 🛡️ Super Admin |
| `setAdminActiveStatus` | Activates/deactivates admin accounts | 🛡️ Super Admin |
| `resetAdminPassword` | Resets an admin password (12-char minimum enforced) | 🛡️ Super Admin |
| `deleteAdminAccount` | Deletes admin account from Auth + Firestore | 🛡️ Super Admin |
| `forceSignOutUser` | Revokes user refresh tokens, clears FCM tokens | 🛡️ Super Admin |
| `setAdminPermissions` | Updates granular admin permission map | 🛡️ Super Admin |
| `assignSuperAdminSlot` | Assigns `primary`/`backup` super admin slot with transaction checks | 🛡️ Super Admin |
| `rotateSuperAdminSlot` | Rotates slot holder atomically (demote + promote) | 🛡️ Super Admin |
| `listAdminAuditLogs` | Returns filtered governance audit logs | 🛡️ Super Admin |

> **Security Note:** All appointment mutations and sensitive account/role operations are callable-only with server-side validation. Firestore rules block client-side writes to privileged fields (`role`, `isActive`, `superAdminType`, `adminPermissions`). Inactive accounts are rejected at the callable gateway. Storage rules enforce scoped uploads with content-type and size validation.

---

## 🔐 User Roles & Permissions

| Role | Capabilities |
|:---|:---|
| **Student** | Book/manage appointments, upload documents, view own records |
| **Staff** | Same as Student — campus staff access |
| **Doctor** | View assigned appointments, manage schedule and availability |
| **Admin** | Permission-scoped operations (view/manage non-admin users, doctors, departments, analytics, reports, notifications) |
| **Super Admin** | Full admin powers + admin governance, slot management (`primary`/`backup`), permissions control, audit log access |

> **RBAC Model:** Admin actions are permission-driven, and Super Admin bypasses permission checks for governance tasks.

---

## 🛡 Super Admin Bootstrap

Use the runbook: `docs/SUPER_ADMIN_BOOTSTRAP_RUNBOOK.md`

Quick bootstrap summary:

1. Create/login the target account in Firebase Authentication.
2. Ensure Firestore profile document exists at `users/{authUid}` (document ID must equal Auth UID).
3. Set:
   - `role: "superAdmin"`
   - `superAdminType: "primary"`
   - `isActive: true`
4. Restart the app and verify routing goes to `SuperAdminShell`.
5. Assign backup slot through Super Admin UI or `assignSuperAdminSlot`.

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
<summary><b>v2.4.0</b> — May 15, 2026</summary>

#### 🎨 Premium Onboarding Redesign (May 27, 2026)
- **Full onboarding rewrite** — Replaced the legacy onboarding screen with a modern, immersive design featuring per-slide gradient backgrounds, custom `CustomPainter` vector illustrations, smooth animated transitions, and a clean bottom content area.
- **Custom vector illustrations** — Three programmatic illustrations (calendar with clock, notification bell with pulse rings, clipboard with heartbeat line) built entirely with `CustomPainter` — no external image assets required.
- **Per-slide gradient themes** — Each slide uses the app's own color palette: primary blue gradient (Appointments), secondary teal gradient (Reminders), warm amber-to-brown gradient (Health Records).
- **Smooth page transitions** — Proper `PageView` with swipe navigation, `AnimatedSwitcher` for title/description cross-fades, and `AnimatedContainer` pill indicators.
- **Richer onboarding copy** — Expanded all three onboarding descriptions from brief one-liners to detailed, 2-sentence explanations in English, Arabic, and Kurdish.
- **Simplified visual effects** — Removed heavy visual effects (frosted glass `BackdropFilter`, liquid `CustomPainter` indicators, floating bokeh particles) in favor of a clean, comfortable design that matches the app's overall style.
- **Zero new dependencies** — Uses only existing project packages: `google_fonts`, `flutter_animate`, and built-in Flutter painting APIs.

#### 🩺 Doctor Availability Approval & Booking Locks (May 27, 2026)
- **Admin-approved unavailable workflow** — Doctors now request unavailable status with a short note; only admins with `doctors.manage` can approve or reject the request.
- **Monthly unavailable limit** — Approved doctor unavailable requests are capped at 2 per calendar month using server-owned `doctor_availability_usage` counters.
- **High-priority admin notifications** — Doctor availability requests render as special notification cards with Approve/Reject actions, clear pending/approved/rejected status, and permission-gated controls.
- **Real-time doctor dashboard sync** — Doctor dashboard availability state listens to the doctor document, so admin approvals or manual admin availability changes update the switch without app refresh.
- **Admin Doctor Management controls** — Doctor cards now show both account status and availability badges, hide inactive doctors by default, expose an Inactive filter, and include `Make Available` / `Make Unavailable` in the three-dot menu.
- **Patient booking protection** — Patients cannot open/book unavailable doctors from the doctor browser, schedule page, or booking flow; `createAppointment` also rejects unavailable doctors server-side.
- **Appointment cancellation on approval** — When an unavailable request is approved, active future appointments for that doctor are cancelled, slot locks are released, and patients are notified to book another available time.
- **Firestore rule hardening** — `doctor_availability_requests` are readable only by the requesting doctor or doctor-managing admins, and client-side writes to sensitive doctor availability fields are blocked.

#### 🔔 Admin Notifications & Account Operations (May 27, 2026)
- **Audited admin notifications** — Added recipient search, preview, idempotency, cooldown, and audited send records for targeted patient/doctor notifications.
- **Legacy topic send disabled** — `sendTopicNotification` now blocks topic broadcast sends and points admins to audited in-app notification delivery.
- **Initial password change flow** — Admin-created doctor/student/staff accounts can be forced through `completeInitialPasswordChange` before normal use.
- **Server-owned profile photo operations** — Storage rules and helper functions now support permission-gated doctor/user profile photo uploads and cleanup.

#### 🩺 Stability Follow-Up (May 24, 2026)
- **Scheduled reminder delivery** — Added `deliverScheduledNotifications` so future notification documents are delivered when due instead of being skipped by the create trigger.
- **Cursor-paginated appointment reads** — Patient, doctor, admin, slot-availability, and doctor/patient history queries now page through bounded Firestore batches with server-side filters instead of applying hard `.limit(500/1000)` before in-memory filtering.
- **Admin hard-delete slot release** — `deleteAppointment` releases its `appointment_slot_locks` document before deleting the appointment so the same doctor/date/time does not stay blocked.
- **Doctor status notification reliability** — Confirmed, completed, and no-show status updates create patient notifications from trusted backend code.
- **Super Admin list completeness** — Admin/permission lists support Load More, and audit logs use backend `hasMore` pagination so filtered views do not silently hide older matches.
- **Android notification channel alignment** — Local Android channel setup now includes the backend FCM channel ID (`uhc_notifications`) to avoid fallback-channel behavior.
- **Release metadata aligned** — `pubspec.yaml` is now `2.4.0+24`; Android package ID and release signing remain intentionally unchanged until the final Play Store package, Firebase config, and keystore are chosen.

#### 🔒 Server-Side Appointment Lifecycle (Client → Cloud Functions Migration)
- **All appointment mutations moved server-side** — `createAppointment`, `rescheduleAppointment`, `cancelAppointment`, `updateAppointmentStatus`, `updateMedicalNotes`, `incrementQrScanFailures`, and `deleteAppointment` are now Cloud Functions callables with full server-side validation.
- **Transactional Slot Locking** — New `appointment_slot_locks` collection with atomic lock/release within Firestore transactions prevents double-booking race conditions. Each slot lock document is keyed by `{doctorId}_{date}_{timeSlot}`.
- **Server-Side Notifications** — Appointment confirmation, completion, and no-show notifications are now created by Cloud Functions instead of client-side writes, ensuring trusted notification delivery.

#### 🛡 Security Hardening
- **Inactive account gateway** — All Cloud Function callables now reject requests from inactive accounts (`isActive !== true`) at the entry point.
- **Explicit permission enforcement** — Legacy admins without an `adminPermissions` object are no longer granted implicit full access; explicit permission map is now required.
- **Password policy tightened** — `resetAdminPassword` and `resetDoctorPassword` now enforce a 12-character minimum (up from 6).
- **Session revocation consolidation** — `forceSignOutUser` now also clears FCM tokens from `user_tokens` collection alongside refresh token revocation.
- **Firebase Storage rules** — Added `storage.rules` with:
  - Content-type validation (images for profiles, PDF/DOCX/images for medical docs)
  - File size limits (5 MB profile images, 20 MB medical documents)
  - Scoped medical document uploads (`self` scope for patients, appointment-scoped for doctors)
  - Doctor-patient access grants via `doctor_patient_access` subcollection checks
  - Permission-gated admin/superAdmin read access

#### 📱 FCM Token & Topic Consolidation
- **Removed dual token storage** — FCM tokens are no longer written to the `users` collection; `user_tokens` is now the single source of truth for Cloud Functions push delivery.
- **Removed per-user/role/department topic subscriptions** — Private notifications are now delivered by token from Cloud Functions. Only the broadcast `announcements` topic subscription remains.

#### 👤 User Preferences Sync
- **Theme mode persistence** — Added `themeMode` field to `UserModel` and Firestore `users` document, synced on change via `AuthProvider.updateThemeMode()`.
- **Language preference persistence** — Added `AuthProvider.updateLanguage()` to write the selected language code back to Firestore.

#### 🔐 Sign-Out Resilience
- **Pre-signout state clearing** — Local user state is cleared *before* `FirebaseAuth.signOut()` so role-scoped Firestore streams are disposed while permissions are still valid. On sign-out failure, state is rolled back with error feedback.

#### 🏥 Medical Documents Scoping
- **Storage path scoping** — Medical document uploads now include a `scope` segment (`self` for patient-uploaded, `{appointmentId}` for doctor-uploaded), aligning with the new Storage rules.
- **Upload metadata** — `contentType` metadata is now attached to Storage uploads for accurate content-type validation.

#### 🧩 Admin Dashboard Reliability
- **Permission-safe KPI stats** — Dashboard stat queries are now guarded by the admin's view permissions; stats gracefully return zero instead of throwing permission errors.
- **Firestore exception tolerance** — Wrapped aggregation queries in `_countSafely()` to prevent a single failed stat from crashing the dashboard.

#### 📁 Files Changed

| File | Key Changes |
|:---|:---|
| `functions/src/index.ts` | Appointment callables, slot-lock release on hard delete, scheduled notification delivery, inactive-account gateway, explicit permission enforcement, 12-char password policy, session + FCM revocation |
| `lib/data/repositories/appointment_repository.dart` | All mutations routed through `FirebaseFunctions.httpsCallable()`; appointment reads use cursor-paginated bounded batches |
| `lib/data/repositories/document_repository.dart` | Scoped storage paths, `contentType` metadata on uploads |
| `lib/data/repositories/notification_repository.dart` | Client-side notification creation stubbed out (now server-owned) |
| `lib/data/models/user_model.dart` | Added `themeMode` field, explicit `hasPermission` now returns false for null permissions |
| `lib/providers/auth_provider.dart` | `updateLanguage()`, `updateThemeMode()`, pre-signout state clearing with rollback |
| `lib/services/auth_service.dart` | `updateUserLanguage()`, `updateUserThemeMode()` Firestore helpers |
| `lib/services/fcm_service.dart` | Removed dual `users` collection token writes, removed per-user/role/department topic subscriptions |
| `lib/services/local_notification_service.dart` | Android channel registration aligned with backend FCM channel ID |
| `lib/screens/admin/dashboard/admin_dashboard_screen.dart` | Permission-gated KPI queries, `_countSafely()` wrapper |
| `lib/screens/admin/reports/reports_screen.dart` | Updated to work with server-side appointment lifecycle |
| `lib/screens/super_admin/*` | UI refinements, Load More governance lists, and audit-log pagination handling |
| `firestore.indexes.json` | Composite indexes for appointment pagination, slot availability checks, audit queries, and scheduled notification scans |
| `storage.rules` | [NEW] Firebase Storage security rules |
| `lib/core/widgets/role_english_ltr_scope.dart` | [NEW] LTR text scope widget for role/status labels in RTL layouts |
| `pubspec.yaml` | Dependency updates |
| `lib/screens/onboarding/onboarding_screen.dart` | Full rewrite: premium gradient backgrounds, `CustomPainter` illustrations, `PageView` navigation, animated indicators |
| `lib/l10n/app_en.arb` | Expanded onboarding descriptions to detailed 2-sentence copy |
| `lib/l10n/app_ar.arb` | Expanded onboarding descriptions (Arabic) |
| `lib/l10n/app_ku.arb` | Expanded onboarding descriptions (Kurdish) |

</details>

<details>
<summary><b>v2.3.0</b> — May 2, 2026</summary>

#### 📊 Professional Excel Report Export (CSV → XLSX Migration)
- **Syncfusion XlsIO Integration** — Replaced legacy CSV exports with professional, styled `.xlsx` documents using `syncfusion_flutter_xlsio`.
- **Branded Report Design** — All 4 report types (Appointments, Doctors, Users, Departments) now feature:
  - Merged title row with branded blue (#2196F3) styling
  - Date-range sub-header
  - Bold white-on-blue header row with thin borders
  - Alternating white/light-gray row striping for readability
  - Footer row with total record count
- **Cross-Platform File Handling** — Implemented conditional export pattern (`save_file.dart`) for platform-safe file operations:
  - **Web**: Uses `package:web` + `dart:js_interop` for native browser Blob downloads
  - **Mobile/Desktop**: Uses `path_provider` + `share_plus` for temp file save + system share sheet
- **Revenue → Departments** — Renamed Revenue Report to Departments Report with department-specific data (name, doctor count, appointment count, status).

#### 🔥 Firebase Messaging Web Fix
- **Service Worker Registration** — Added `firebase-messaging-sw.js` to resolve `failed-service-worker-registration` errors on web. Firebase Cloud Messaging now registers correctly in the browser.

#### 🎨 App Branding Updates
- **Custom App Icons** — Updated launcher icons for Android (all density buckets) and iOS (all sizes) with new branded design.
- **Web Assets** — Updated `favicon.png`, PWA icons (`Icon-192`, `Icon-512`, maskable variants), and `manifest.json` with updated app name and branding.

#### 🛠 Dependencies
- **Added**: `syncfusion_flutter_xlsio`, `web` (for JS interop), `share_plus`, `path_provider`

#### 📁 Files Changed

| File | Key Changes |
|:---|:---|
| `lib/screens/admin/reports/reports_screen.dart` | Full rewrite: CSV → XLSX with Syncfusion XlsIO, styled headers, alternating rows, footers |
| `lib/utils/save_file.dart` | [NEW] Conditional export router (web vs IO) |
| `lib/utils/save_file_web.dart` | [NEW] Web Blob download implementation |
| `lib/utils/save_file_io.dart` | [NEW] Mobile/Desktop save + share implementation |
| `lib/utils/save_file_stub.dart` | [NEW] Stub fallback for unsupported platforms |
| `lib/main.dart` | Web-safe Crashlytics guards |
| `web/firebase-messaging-sw.js` | [NEW] Firebase Cloud Messaging service worker |
| `web/manifest.json` | Updated app name and branding |
| `web/favicon.png` | Updated favicon |
| `web/icons/` | Updated PWA icons (192, 512, maskable variants) |
| `android/app/src/main/res/mipmap-*/ic_launcher.png` | Updated Android launcher icons |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | Updated iOS app icons (all sizes) |
| `pubspec.yaml` | Added syncfusion_flutter_xlsio, web, share_plus, path_provider |

</details>

<details>
<summary><b>v2.2.0</b> — April 29, 2026</summary>

#### 🔐 Authentication & Provider Controls
- **Provider-aware password change** — `Change Password` is now enabled only when `password` provider is linked.
- **Mandatory Google-link gate hardening** — Removed stale session bypass and now gate from real provider state only.
- **Google unlink (self, role-gated)** — Added self-unlink capability for signed-in `admin` and `superAdmin` accounts.
- **Google unlink (admin on target user)** — Added User Management action and backend callable to unlink Google for managed non-admin users.

#### 📧 Password Reset & Account Reliability
- **Forgot password from profile** — Added Forgot Password entry in both patient and doctor profile account sections.
- **Context-aware forgot-password UX**:
  - login flow keeps **Back to Login**
  - profile flow uses neutral completion action (no login redirect wording)
- **Google-only account notice** — Forgot password clearly explains that reset works only for accounts with `password` provider.
- **Reset flow stability** — Sending password reset email no longer mutates authenticated app state.

#### ☁️ Cloud Functions Added
- `unlinkGoogleProviderByAdmin`

#### 📁 Files Changed

| File | Key Changes |
|:---|:---|
| `functions/src/index.ts` | Added `unlinkGoogleProviderByAdmin` with permission/role/provider guardrails |
| `functions/lib/index.js` | Compiled output sync |
| `functions/lib/index.js.map` | Compiled source map sync |
| `lib/services/auth_service.dart` | Added `isPasswordLinked`, unlink logic, provider-guarded password change, best-effort auth-email sync trigger |
| `lib/providers/auth_provider.dart` | Added `isPasswordLinked`, role-gated `unlinkGoogle`, reset-email state stabilization |
| `lib/services/user_functions_service.dart` | Added callable wrapper for admin-side unlink |
| `lib/screens/shared/change_password_screen.dart` | Provider-aware password UI behavior |
| `lib/screens/patient/profile/edit_profile_screen.dart` | Added admin/super-admin self unlink action |
| `lib/screens/admin/users/user_management_screen.dart` | Added `Unlink Google` in popup and detail bottom sheet |
| `lib/screens/auth/forgot_password_screen.dart` | Added profile/login mode support, initial email, Google-only notice, local loading |
| `lib/screens/patient/profile/profile_screen.dart` | Added profile-level Forgot Password entry |
| `lib/screens/doctor/profile/doctor_profile_screen.dart` | Added profile-level Forgot Password entry |
| `lib/main.dart` | Removed stale `_googleLinked` bypass flag |

</details>

<details>
<summary><b>v2.1.0</b> — April 28, 2026</summary>

#### 🛡 User Management & Super Admin Edit Rules
- **Super Admin can edit Super Admin profiles** — Updated UI and backend enforcement so only `superAdmin` can edit `superAdmin` accounts.
- **Edit-only protection for Super Admin rows** — In User Management, `superAdmin` targets expose **Edit** only (no deactivate/role-change destructive actions).
- **Role-change safety** — Role options in user actions/forms now exclude `admin`, `doctor`, and `superAdmin` where not allowed.
- **Server-side enforcement** — `updateUserProfileByAdmin` now allows super-admin target updates only when caller is `superAdmin`.

#### 🆔 UID UX Improvements
- **UID copy support** — Added quick UID copy action for super admin in User Management list rows.
- **Role-based UID visibility**:
  - `superAdmin`: sees UID in list + copy button.
  - `admin`: list UID hidden; UID remains available in edit dialog.
- **Edit form normalization** — Replaced manual Student/Staff ID inputs with read-only **User UID** behavior and server-safe mapping.

#### 👤 Profile Experience Refinements
- **Admin/Super Admin profile simplification** — Removed patient-only sections for admin-like roles (language/notifications/medical docs where not applicable).
- **Super Admin profile styling** — Added super-admin accent treatment and slot badge indicators (`PRIMARY` / `BACKUP`).
- **Admin quick entry restored** — Profile keeps direct access to Admin Dashboard for admin-like roles.

#### 🧭 Super Admin Navigation & Governance UX
- **Bottom nav streamlined** — Removed `Permissions` item from Super Admin bottom navigation; now: Dashboard, Admins, Audit Logs, Profile.
- **Quick Actions removed from Super Admin Dashboard** — Cleaner dashboard flow with governance focused sections.
- **Admin Governance dialog redesign** — Modernized create admin, reset password, assign slot, and rotate slot dialogs with consistent validation and submit/loading states.
- **UID/email resolution in governance flows** — Assign/Rotate slot inputs accept either UID or email and resolve to Firestore user doc IDs.

#### 📜 Audit Logs Filtering Upgrade
- **Actor/Target filters accept UID or email** — Improved discoverability when UIDs are not easy to find.
- **Active filter chips styled for dark mode** — Fixed readability (text/icon contrast) in dark theme.

#### 🎨 Dark Mode Readability Fixes
- **Admin Governance preset chips (`Full`, `Ops`, `Read-Only`)** — Improved dark-mode contrast (label/background/border/disabled state).
- **Chip/divider spacing fix** — Added vertical spacing so preset chips no longer touch divider lines.

#### 🧱 Runtime & Auth Reliability
- **Crashlytics web-safe guards** — Prevented web assertion crashes by disabling/guarding Crashlytics hooks on web and wrapping reporting calls.
- **Hero tag collision fix** — Unique FAB hero tags for `AdminControlScreen` instances inside `IndexedStack`.
- **Sign-out hardening** — Improved sign-out reliability with verification retries and better user feedback on failure.
- **Stale auth load guard** — Prevented outdated async auth loads from overriding current auth state after account switches/sign-out.

#### 📁 Files Changed

| File | Key Changes |
|:---|:---|
| `functions/src/index.ts` | Super-admin-only edit enforcement for super-admin profile updates |
| `functions/lib/index.js` | Compiled output sync |
| `functions/lib/index.js.map` | Compiled source map sync |
| `lib/main.dart` | Web-safe Crashlytics guards, non-fatal reporting helper, logout error feedback |
| `lib/providers/auth_provider.dart` | Stale auth load guard, sign-out error propagation improvements |
| `lib/providers/notification_provider.dart` | Web-safe Crashlytics wrapper |
| `lib/services/fcm_service.dart` | Web-safe Crashlytics wrapper |
| `lib/services/local_notification_service.dart` | Web-safe Crashlytics wrapper |
| `lib/services/auth_service.dart` | Deterministic sign-out verification/retry flow |
| `lib/screens/auth/link_google_screen.dart` | Safe logout error handling |
| `lib/screens/doctor/profile/doctor_profile_screen.dart` | Safe logout error handling |
| `lib/screens/patient/profile/profile_screen.dart` | Admin/super-admin profile simplification + super-admin visual enhancements |
| `lib/screens/admin/users/user_management_screen.dart` | Super-admin edit rules, UID visibility/copy behavior |
| `lib/screens/admin/users/user_form_dialog.dart` | Role-safe edit form, UID-only identity handling, super-admin edit behavior |
| `lib/screens/super_admin/super_admin_dashboard_screen.dart` | Removed Quick Actions section |
| `lib/screens/super_admin/super_admin_shell.dart` | Removed Permissions bottom-tab and remapped tab indexes |
| `lib/screens/super_admin/admin_control_screen.dart` | Dialog redesign, UID/email resolution, dark-mode chip contrast + spacing, unique FAB heroTag |
| `lib/screens/super_admin/audit_log_screen.dart` | UID/email filter resolution and dark-mode filter chip contrast |

</details>

<details>
<summary><b>v2.0.0</b> — April 2026</summary>

#### 🛡 Super Admin + Admin RBAC (Phases 0–8)
- Added new `superAdmin` role end-to-end (model, routing, UI, backend guards, rules)
- Added strict two-slot governance model (`primary` + `backup`) with transactional enforcement
- Added dedicated Super Admin shell and governance screens (Admins, Permissions, Slots, Audit Logs)
- Added admin permission model + presets and permission-driven admin UI gates
- Added comprehensive governance callables:
  - admin account lifecycle (create/changeRole/activate/reset/delete)
  - force sign-out
  - set admin permissions
  - assign/rotate super admin slots
  - audit log listing
- Hardened Firestore rules to block client-side privilege escalation fields
- Added `admin_audit_logs` collection model + UI query surface
- Added bootstrap/migration runbook for secure first Super Admin setup

#### 🧩 Reliability & Web Fixes
- Improved auth/profile mismatch handling (prevents silent fallback role routing)
- Improved governance callable error mapping to readable client errors
- Fixed Super Admin slot layout overflow in web/mobile card actions
- Fixed duplicate Hero tag conflicts in governance screen
- Guarded non-web Google Sign-In initialization path to avoid web client-id assertion at startup

</details>

<details>
<summary><b>v1.10.0</b> — April 2026</summary>

#### ⚡ Scalability & Performance Audit (20k–50k Concurrent Users)
A comprehensive code audit identified and resolved 13 scalability issues to ensure the app performs smoothly at scale (20,000–50,000 concurrent users).

##### 🔴 Critical Fixes
- **Bounded Firestore Queries** — Added `.limit()` to every unbounded query across the entire codebase. Previously, methods like `getUpcomingAppointments()`, `getPastAppointments()`, and `getAllDoctorAppointments()` would download entire document collections (potentially 500k+ docs at scale). All queries now have appropriate limits (500–1000 docs per method).
- **N+1 Query Elimination** — Replaced sequential `for`-loop photo fetching with `Future.wait()` for parallel execution. Loading 10 doctor photos now takes ~200ms instead of ~3,000ms (one network round-trip vs. ten sequential ones).
- **Admin User Stream Limit** — Added `.limit(200)` with **"Load More" pagination** to the admin User Management screen. Starts with 200 users, each tap loads 200 more — the admin can browse all users without loading 50k at once.
- **Notification Query Optimization** — Replaced `getUnreadCount()` (which downloaded all unread documents) with Firestore's `.count()` aggregation — zero document downloads, server-side counting.

##### 🟡 Moderate Fixes
- **8 Composite Firestore Indexes** — Defined composite indexes for the most common query patterns (`doctorId + appointmentDate`, `patientId + appointmentDate`, `userId + createdAt`, `userId + isRead`, etc.) to enable efficient server-side filtering instead of client-side in-memory filtering.
- **Batch Operation Chunking** — All batch write operations (`markAllAsRead`, `deleteAllNotifications`, `deleteAllUserAppointments`, `deleteFutureDailySummaries`) now chunk into groups of 500 to respect Firestore's batch limit. Previously, batches with >500 operations would fail silently.
- **Booking Screen Query Limit** — Added `.limit(500)` to the booking screen's appointment fetch, preventing download of a doctor's entire appointment history on every calendar date tap.
- **Doctor Search Caching** — `searchDoctors()` now caches the doctor list in memory and filters locally, instead of re-fetching the entire `doctors` collection on every keystroke.
- **Analytics & Reports Pagination** — Reports and analytics now use **cursor-based auto-pagination** (fetching in 5,000-doc batches using `startAfterDocument`) instead of hard limits. The admin clicks "Generate" and gets a **complete** CSV export or accurate stats, regardless of how many documents exist. Each individual Firestore request stays bounded at 5,000 docs to stay safe.

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
| `lib/screens/admin/users/user_management_screen.dart` | "Load More" pagination (200 per page) |
| `lib/screens/patient/booking/booking_screen.dart` | `.limit(500)` on booked slots query |
| `lib/screens/admin/analytics/appointment_analytics_screen.dart` | Cursor-based auto-pagination (5k batches) |
| `lib/screens/admin/reports/reports_screen.dart` | `_paginatedFetch()` helper, auto-pagination on all 3 report generators |
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
