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
| `appointment_slot_locks` | Transactional slot lock documents preventing double-booking (server-managed, client access denied) |
| `appointment_day_coordination` | Transactional day coordination documents serializing booking and rescheduling across overlapping/differently-sized slot ranges (server-managed, client access denied) |
| `appointment_idempotency` | Booking and assistant-confirmation idempotency receipts enabling safe lost-response retries (server-managed, client access denied) |
| `assistant_chats` | Server-side conversational session state, turn leasing, and structured booking offers (server-managed, client access denied, contains an expiry timestamp) |
| `assistant_user_limits` | Per-user rate-limiting records tracking per-minute turn usage (`USER_RPM` cap, keyed by `${patientId}_${minuteKey}`) per `functions/src/assistant/quota.ts` (server-managed, client access denied, contains an expiry timestamp) |
| `assistant_project_quota` | Project-wide minute and daily Gemini request counters, with daily reset at midnight America/Los_Angeles (server-managed, client access denied, contains an expiry timestamp) |
| `notifications` | Per-user notification history |
| `user_tokens/{uid}/tokens` | FCM token subcollection used by Cloud Functions for per-device push delivery |
| `doctor_availability_requests` | Server-owned doctor unavailable requests with admin review status and request notes |
| `doctor_availability_usage` | Monthly usage counters enforcing the two approved unavailable requests per doctor per calendar month |
| `admin_notification_sends` | Idempotency and audit records for admin-created notification sends |
| `admin_notification_rate_limits` | Per-admin cooldown records for notification sending |
| `medical_documents` | Uploaded file metadata and storage references |
| `medical_document_replacements` | Replacement state, file ownership, and cleanup progress; not disposable test data |
| `medical_upload_transfer_admissions` | Idempotent byte-transfer admission records |
| `medical_upload_budgets` | Per-user and project upload budgets |
| `appointment_analytics_jobs` | Server-managed paged analytics jobs and expiry |
| `appointment_analytics_admissions` | Per-caller analytics job admission control |
| `maintenance` | Server maintenance and migration progress |
| `doctor_patient_access/{doctorUid}/patients` | Patient access-grant subcollection for scoped doctor access |
| `admin_audit_logs` | Governance audit trail; client writes are denied by Firestore rules |

## Composite Indexes

The repository includes `firestore.indexes.json` defining all required compound queries. The critical indexes for appointment coordination and booking validation include:

- **`appointments`**:
  - `doctorId` (ASC) + `appointmentDate` (ASC)
  - `doctorId` (ASC) + `appointmentDate` (DESC) + `__name__` (DESC)
  - `patientId` (ASC) + `status` (ASC) + `appointmentDate` (ASC)
  - `patientId` (ASC) + `appointmentDate` (DESC)
  - `doctorId` (ASC) + `status` (ASC) + `appointmentDate` (ASC)
  - `doctorId` (ASC) + `timeSlot` (ASC) + `appointmentDate` (ASC)
  - `status` (ASC) + `appointmentDate` (DESC)
- **`appointment_slot_locks`**:
  - `doctorId` (ASC) + `appointmentDateKey` (ASC)

Deploy indexes using the Firebase CLI:

```bash
firebase deploy --only firestore:indexes
```

## Firestore TTL (Time-To-Live) Policies

Assistant chats and rate-limit records contain `expiresAt` timestamps. Those fields alone do not enable automatic deletion. Inspect the target project's TTL configuration before relying on physical cleanup; application-level history expiry and quota windows are enforced separately.

An authorized operator can configure TTL for each appropriate collection group, for example:

```bash
gcloud firestore fields ttls update expiresAt --collection-group=assistant_chats --enable-ttl --project=<your-firebase-project-id>
```

Review `assistant_user_limits` and `assistant_project_quota` similarly. TTL deletion is asynchronous; see the [Firestore TTL documentation](https://firebase.google.com/docs/firestore/ttl). Do not apply a blanket deletion policy to booking receipts, slot coordination, medical replacement records, or audit logs: these can support retries, ownership checks, and cleanup.

### AI Assistant Configuration & Privacy Gate

Live generation requires `AI_ASSISTANT_ENABLED=true`, `AI_PRIVACY_RELEASE_GATE_ACCEPTED=true`, and the server-side `GEMINI_API_KEY` Secret Manager binding. Unset flags default to disabled; inspect the target environment separately rather than assuming a deployment has these defaults.

The model is selected on the server as `gemini-3.5-flash-lite`. Free-text scheduling messages and bounded conversation context are sent to Gemini without automatic redaction. Before enabling live use, the project owner must review the [Gemini API terms](https://ai.google.dev/gemini-api/terms), the billing status of the project that owns the API key, and the institution's data requirements. The Firebase project's Blaze plan alone does not establish the Gemini project's billing status.

Provision the secret through the approved server-side secret workflow. Never put its value in Flutter code, documentation, fixtures, or command output. Preserve existing secret configuration during local testing.

### Controlled Local Offline Synthetic Testing
The codebase includes a deterministic offline synthetic testing mode that exercises the exact same scheduling, slot locking, idempotency, and booking confirmation pipelines without making any external AI calls or transmitting patient data.

> [!NOTE]
> **Fixture Parsing vs. Real AI Generation**
> Synthetic mode uses deterministic keyword matching against local catalog fixtures. It does **not** evaluate real Gemini AI generation quality, fluency, context reasoning, or live network latency. It is designed to verify system plumbing and booking mechanics safely offline.

#### Exact Runnable PowerShell Steps for Local Testing

Follow these steps in Windows PowerShell to test the assistant locally:

##### 1. Prepare Dummy Local Secret & Build Functions
Firebase Functions emulator requires the declared secret `GEMINI_API_KEY` to be present locally. To prevent the emulator from attempting to look up Secret Manager on Google Cloud, ensure the dummy local secret fixture exists.

> [!CAUTION]
> **Secret Preservation Rule**: Test path with literal path. If an existing `.secret.local` is present, stop and do **not** read, print, overwrite, or delete it. To preserve existing secrets in an unpolluted clean room, run in a fresh isolated checkout.

```powershell
cd functions

# Test literal path; never read, print, overwrite, or delete existing secret
if (Test-Path -LiteralPath ".secret.local") {
    throw ".secret.local already exists. To preserve existing secrets in an unpolluted clean room, run in a fresh isolated checkout."
} else {
    Write-Host "Creating dummy .secret.local fixture from template..."
    Copy-Item -LiteralPath ".secret.local.example" -Destination ".secret.local"
}

# Compile TypeScript functions; stop immediately if build fails
npm run build
if ($LASTEXITCODE -ne 0) {
    throw "npm run build failed with exit code $LASTEXITCODE. Stopping before startup."
}

cd ..
```

##### 2. Start Local Firebase Emulators on Agreed Demo Project
In a dedicated PowerShell terminal (Terminal 1), configure the complete set of required fail-closed environment variables (clearing any inherited production configuration) and start the emulators using the isolated `firebase.emulator.json` configuration on `demo-uhc-test`:

```powershell
# Set strict demo environment variables in Terminal 1
$env:GCLOUD_PROJECT = "demo-uhc-test"
$env:GOOGLE_CLOUD_PROJECT = "demo-uhc-test"
$env:FIREBASE_CONFIG = '{"projectId":"demo-uhc-test"}'
$env:AI_OFFLINE_SYNTHETIC_TESTING = "true"
$env:AI_ASSISTANT_ENABLED = "false"
$env:AI_PRIVACY_RELEASE_GATE_ACCEPTED = "false"
$env:FUNCTIONS_EMULATOR = "true"
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"

# Start Auth (9099), Firestore (8080), Functions (5001), and Storage (9199) loopback emulators
firebase emulators:start --config firebase.emulator.json --only "auth,firestore,functions,storage" --project demo-uhc-test
```

##### 3. Seed Fake Patient & Doctor Catalogs via CLI
In a second PowerShell terminal (Terminal 2), configure the same strict demo environment variables and run the explicitly gated seed script (`npm run seed:emulator`, which builds and runs `seedCli.js`). This populates local Auth emulator user `synthetic-patient-1` (with email `synthetic.patient@demo.uhc.edu`, password `TestPassword123!`, and linked Google provider metadata), patient Firestore profile, and doctor weekly schedule fixtures:

```powershell
cd functions

# Set strict demo environment variables in Terminal 2
$env:GCLOUD_PROJECT = "demo-uhc-test"
$env:GOOGLE_CLOUD_PROJECT = "demo-uhc-test"
$env:FIREBASE_CONFIG = '{"projectId":"demo-uhc-test"}'
$env:AI_OFFLINE_SYNTHETIC_TESTING = "true"
$env:AI_ASSISTANT_ENABLED = "false"
$env:AI_PRIVACY_RELEASE_GATE_ACCEPTED = "false"
$env:FUNCTIONS_EMULATOR = "true"
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"

npm run seed:emulator
if ($LASTEXITCODE -ne 0) {
    throw "npm run seed:emulator failed with exit code $LASTEXITCODE. Stopping."
}
cd ..
```

##### 4. Launch the Flutter Application
In the second terminal, run the Flutter app targeting Chrome with the emulator flag. The app automatically selects synthetic `FirebaseOptions` for `demo-uhc-test` before initializing Firebase, without requiring any manual edit of `lib/firebase_options.dart`:

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
```

For Android, select an emulator from `flutter devices` and launch the debug app:

```powershell
flutter run -d emulator-5554 --debug --dart-define=USE_FIREBASE_EMULATOR=true
```

The demo API key is `fake-emulator-api-key-demo-only`. It is a placeholder,
not a credential for a live Firebase project. Keep it unchanged. Android's
native callable SDK requests an Instance ID token even when Functions points
at an emulator, which rejects this synthetic key. In explicitly opted-in Android
emulator mode, appointment operations, the assistant, and notification resync use the
[callable HTTP protocol](https://firebase.google.com/docs/functions/callable-reference)
through `lib/services/firebase_callable.dart`. Requests carry the local Auth
emulator ID token to the validated local `demo-uhc-test` Functions endpoint;
they do not need an API key or Instance ID token. Other configurations use the
Firebase callable SDK. The debug manifest permits the local HTTP connection and
lets Dart initialize the demo Firebase app before native services can initialize
the bundled live configuration.

Functions runtime code imports `Timestamp` and `FieldValue` directly from
`firebase-admin/firestore`. The Functions emulator binds the legacy
`admin.firestore` function and can omit its static members; accessing them through
that namespace caused history and notification requests to fail with `INTERNAL`.

The admin schedule callable also uses this transport in Android emulator mode.
To exercise schedule saving through the actual local Functions runtime, start
the Auth, Firestore and Functions emulators on the ports above, then run:

```powershell
$env:GCLOUD_PROJECT = 'demo-uhc-test'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
npm --prefix functions run test:callable-emulator
```

This test refuses other project/host configurations. It creates and removes
its own synthetic users/doctor, verifies schedule persistence and unchanged
profile fields, and rejects student and unauthorized-admin writes.

For UI automation with Dart MCP's `flutter_driver_command`, use the debug test
entry point instead:

```powershell
flutter run -d emulator-5554 --debug --target=test_driver/assistant_booking_app.dart --dart-define=USE_FIREBASE_EMULATOR=true --print-dtd
```

Connect Dart MCP to the printed Dart Tooling Daemon URI. The entry point enables
the Flutter driver extension and starts the same application. It refuses to start
unless both debug mode and `USE_FIREBASE_EMULATOR=true` are active. Release builds
use the normal `lib/main.dart` entry point.

##### 5. Sign In and Test the Appointment Assistant
1. When the login screen loads, note the blue **LOCAL EMULATOR MODE (demo-uhc-test)** banner.
2. Click **Sign In as Demo Patient (No OAuth)** (authenticates directly with email `synthetic.patient@demo.uhc.edu` / `TestPassword123!` against the local Auth emulator; external OAuth is disabled in emulator mode).
3. On the Patient Home screen (first tab in bottom navigation bar), locate the **AI Health Assistant** / **AI Booking Assistant** card (`_buildAssistantCard` in `lib/screens/patient/home/home_screen.dart`, rendered as a gradient banner with robot icon). Note: This is an entry card on the Home screen, not a separate bottom navigation tab. Click the card to open the assistant.
4. Type the documented synthetic phrase:
   > "I want an appointment with Dr. Noor in dermatology on Tuesday"
5. The assistant returns real expiring schedule offers for Dr. Noor on Tuesday.
6. Click **Book This Slot**, review the confirmation sheet, then click **Confirm Appointment**.
7. Verify the **Booking Confirmed!** receipt, QR code, and booking reference. The appointment and canonical slot lock are saved in the local Firestore emulator.


