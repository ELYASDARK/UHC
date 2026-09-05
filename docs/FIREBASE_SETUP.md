# Firebase configuration

[Back to README](../README.md#firebase-configuration) | [Cloud Functions reference](CLOUD_FUNCTIONS.md)

All file paths and commands in this guide are relative to the repository root. Complete the [prerequisites and dependency installation](../README.md#getting-started) before deploying. The checked-in configuration is for the original project; replacing only `firebase_options.dart` is not enough to transfer every platform.

## Required Services

Enable the following in your [Firebase Console](https://console.firebase.google.com):

- **Authentication**. Enable Email/Password and Google Sign-In providers
- **Cloud Firestore**. Create database in production mode
- **Firebase Storage**. Enable for file uploads
- **Cloud Messaging**. Enable for push notifications
- **Cloud Functions**. Upgrade project to Blaze plan (required for Node.js functions)
- **Cloud Scheduler**. Required by scheduled notification delivery (`deliverScheduledNotifications`, `sendDoctorDailyReports`)

## Connect to a New Firebase Project

Use this checklist when handing the app to another owner or connecting the codebase to a different Firebase project.

1. Create or open the target project in the [Firebase Console](https://console.firebase.google.com).
2. Enable the required Firebase services listed above.
3. Install the Firebase CLI and FlutterFire CLI if they are not already installed:

```bash
npm install -g firebase-tools@15.19.0
dart pub global activate flutterfire_cli
```

4. Sign in and connect this repository to the target Firebase project:

```bash
firebase login
firebase use --add
```

Choose the new Firebase project, then set an alias such as `default`. This updates `.firebaserc` so deploy commands use the new project instead of the previous project.

5. Register the app platforms in Firebase:

| Platform | Firebase app type | App identifier to register |
|:---|:---|:---|
| Android | Android app | `com.example.uhc` from `android/app/build.gradle.kts` |
| iOS | iOS app | `com.example.uhc` from `ios/Runner.xcodeproj/project.pbxproj` |
| Web | Web app | Any Firebase web app nickname |

If you change the Android package name or iOS bundle identifier for production, register the new identifiers in Firebase before downloading config files.

6. Regenerate Flutter Firebase configuration for the new project:

```bash
flutterfire configure --project=<your-firebase-project-id> --platforms=android,ios,web --out=lib/firebase_options.dart
```

Check that these files point to the selected project after configuration:

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

7. Update the [platform configuration](#platform-configuration), including iOS OAuth IDs, Android signing fingerprints, and [Web notifications](#web-notifications). Keep `web/firebase-messaging-sw.js` aligned with the generated Firebase web options.

8. From the repository root, build and deploy the backend:

```bash
npm --prefix functions run build
firebase deploy --only 'firestore:rules,firestore:indexes,storage'
firebase deploy --only functions
```

9. Create the first Super Admin using the [bootstrap runbook](SUPER_ADMIN_BOOTSTRAP_RUNBOOK.md), then run the [verification checklist](#verify-the-configured-project).

> Do not copy real user, doctor, appointment, medical document, FCM token, or audit-log data from the old Firebase project unless the new owner is authorized to receive that data.

## Platform Configuration

| Platform | Config File | Location | Instructions |
|:---|:---|:---|:---|
| Android | `google-services.json` | `android/app/` | Download from Firebase Console |
| iOS | `GoogleService-Info.plist` | `ios/Runner/` | Download from Firebase Console |
| iOS Google Sign-In | `GIDClientID` and Google callback URL scheme | `ios/Runner/Info.plist` | Replace the original project's values using `CLIENT_ID` and `REVERSED_CLIENT_ID` from the new Firebase iOS configuration |
| App initialization, including Web | Generated Firebase options | `lib/firebase_options.dart` | Generate with FlutterFire CLI; `lib/main.dart` selects the current platform |
| Web background messaging | Service worker configuration | `web/firebase-messaging-sw.js` | Keep its Firebase project values aligned with the generated web options |

For Android Google Sign-In, register the SHA-1 fingerprint of the signing certificate used by the build in Firebase, then refresh the Android configuration. For iOS, both the OAuth client ID and reversed callback scheme must match the new project. See [Firebase Google authentication](https://firebase.google.com/docs/auth/flutter/federated-auth) and the [official iOS plugin setup](https://pub.dev/packages/google_sign_in_ios).

The app also accepts an optional `GOOGLE_SERVER_CLIENT_ID` Dart define in `lib/services/auth_service.dart`. If your build supplies it, update it to the new project's server OAuth client ID.

UHC's Google Sign-In flow expects an existing active app profile. Create or sign in with email/password first and link Google from that account; a new Google-only login does not create a UHC profile.

## Authentication Email Deliverability (SMTP)

For custom password-reset email delivery, review the SMTP settings in:

- `Firebase Console → Authentication → Templates → SMTP settings`

Recommended:

- Use a real sender mailbox (for example: `no-reply@yourdomain.com`)
- Use your SMTP provider's real host/port/security values (not placeholders)
- Verify sender DNS with your provider (SPF, DKIM, DMARC)

Test delivery to the mail providers your users use. Configuring SMTP alone does not guarantee inbox placement.

## Android Configuration

The checked-in `android/app/src/main/AndroidManifest.xml` declares these permissions. Preserve them when changing the Android configuration:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

## iOS Configuration

The checked-in `ios/Runner/Info.plist` contains camera, photo-library, and background-mode entries. Keep these keys and the Google callback configuration when updating the runner:

```xml
<!-- Camera & Photo Library for Profile/Document Uploads -->
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to take profile photos, scan medical documents, and scan QR codes to confirm appointments.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photo library to upload profile photos and medical records.</string>

<!-- Notifications -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>
```

The Android and iOS runners also expose the `uhc/notification_settings` method channel so the shared notification settings screen can open the app's native notification settings page.

For iOS push delivery, enable Push Notifications and the required background modes in Xcode, upload an APNs authentication key to the target Firebase project, and verify APNs registration before testing FCM. Plist permissions alone do not complete this setup. Follow the [Firebase Flutter messaging setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).

## Web notifications

Generate or import Web Push credentials in the target Firebase project's Cloud Messaging settings. Firebase's Flutter guidance passes the public VAPID key to `getToken(vapidKey: ...)`. The current UHC helper in `lib/services/fcm_service.dart` calls `getToken()` without an explicit key, so configure that call for your project before relying on browser push. See [Firebase Web credential setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started#web).

Confirm that the deployed site serves `firebase-messaging-sw.js`, that browser notification permission is granted, and that a token is recorded for the signed-in user. `flutter build web` creates build output; this repository does not include a Firebase Hosting deployment configuration.

## Verify the configured project

- Sign in with a test email/password account, link Google, sign out, and sign in through Google again on each target platform.
- Create a department and doctor, then book and cancel a test appointment. Confirm the slot becomes available again.
- Test a permitted file upload and view it from the intended account.
- Test in-app alerts, foreground/background push, and mobile local reminders separately. Use a supported device or browser with notification permission granted.
- Verify primary and backup governance access using the [runbook checklist](SUPER_ADMIN_BOOTSTRAP_RUNBOOK.md#6-verify-the-system).

Use the project's actual results for handoff. The documentation review does not establish successful sign-in or push delivery on a newly configured project.

## Firestore Collections

| Collection | Description |
|:---|:---|
| `users` | User profiles, roles, preferences, language, and theme mode |
| `doctors` | Doctor profiles, specializations, and schedules |
| `departments` | Department names, icons, colors, and working hours |
| `appointments` | Booking records with status tracking, QR check-in, and scan failure counts |
| `appointment_slot_locks` | Transactional slot lock documents preventing double-booking (server-managed) |
| `notifications` | Per-user notification history |
| `user_tokens/{uid}/tokens` | FCM token subcollection used by Cloud Functions for per-device push delivery |
| `doctor_availability_requests` | Server-owned doctor unavailable requests with admin review status and request notes |
| `doctor_availability_usage` | Monthly usage counters enforcing the two approved unavailable requests per doctor per calendar month |
| `admin_notification_sends` | Idempotency and audit records for admin-created notification sends |
| `admin_notification_rate_limits` | Per-admin cooldown records for notification sending |
| `medical_documents` | Uploaded file metadata and storage references |
| `doctor_patient_access/{doctorUid}/patients` | Patient access-grant subcollection for scoped doctor access |
| `admin_audit_logs` | Governance audit trail; client writes are denied by Firestore rules |
