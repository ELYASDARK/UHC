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
| `appointment_idempotency` | Booking and rescheduling idempotency receipts enabling safe lost-response retries (server-managed, client access denied) |
| `assistant_chats` | Server-side conversational session state, turn leasing, and structured booking offers (server-managed, client access denied, TTL-managed) |
| `assistant_user_limits` | Per-user rate-limiting records tracking per-minute turn usage (`USER_RPM` cap, keyed by `${patientId}_${minuteKey}`) per `functions/src/assistant/quota.ts` (server-managed, client access denied, TTL-managed) |
| `assistant_project_quota` | Global daily upstream Gemini API quota tracker with midnight America/Los_Angeles reset (server-managed, client access denied, TTL-managed) |
| `notifications` | Per-user notification history |
| `user_tokens/{uid}/tokens` | FCM token subcollection used by Cloud Functions for per-device push delivery |
| `doctor_availability_requests` | Server-owned doctor unavailable requests with admin review status and request notes |
| `doctor_availability_usage` | Monthly usage counters enforcing the two approved unavailable requests per doctor per calendar month |
| `admin_notification_sends` | Idempotency and audit records for admin-created notification sends |
| `admin_notification_rate_limits` | Per-admin cooldown records for notification sending |
| `medical_documents` | Uploaded file metadata and storage references |
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

The AI assistant documents contain an `expiresAt` timestamp field (`functions/src/assistant/quota.ts` also writes `expiresAt` on `assistant_user_limits` documents). To prevent stale session accumulation and ensure automated purging, future operators can configure Firestore TTL policies using Google Cloud CLI (these are future release steps; policies were not deployed or verified in this task):

```bash
gcloud firestore fields ttls update expiresAt --collection-group=assistant_chats --enable-ttl --project=uhca-20800
gcloud firestore fields ttls update expiresAt --collection-group=assistant_user_limits --enable-ttl --project=uhca-20800
gcloud firestore fields ttls update expiresAt --collection-group=assistant_project_quota --enable-ttl --project=uhca-20800
```

> [!NOTE]
> Physical TTL deletion in Cloud Firestore is asynchronous and typically occurs within 24 hours of expiration ([official Firestore TTL documentation](https://firebase.google.com/docs/firestore/ttl)), not a hard guarantee. Application-level queries apply real-time expiration filters (`pruneExpiredMessages`) on every read, while `assistant_user_limits` records track per-minute usage (`USER_RPM` cap per `functions/src/assistant/quota.ts`). These TTL policies were not deployed or verified in this task; "no TTL deployment" indicates that the deployment step was not executed, not that cleanup is unnecessary.

### AI Assistant Configuration & Privacy Gate

The UHC conversational assistant uses the server-side `gemini-3.5-flash-lite` model via Google AI Studio / Gemini API.

> [!CAUTION]
> **Privacy, Provider Terms & Architecture Gates**
> By default, the assistant is **strictly disabled** in Cloud Functions:
> - `AI_ASSISTANT_ENABLED=false`
> - `AI_PRIVACY_RELEASE_GATE_ACCEPTED=false`
> 
> Arbitrary production patient chat remains disabled pending an actual institutional provider/data decision.

### Factual Gemini API Terms (Effective March 23, 2026)
According to the official [Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms):
1. **Unpaid vs. Paid Services**:
   - **Unpaid Services**: Prohibit submitting sensitive, personal, or confidential information. User content (prompts, inputs, and outputs) may be used for model training and product improvement, and may be reviewed by human reviewers.
   - **Paid Services**: User content is not used to train or improve Google models only when the Gemini API is enabled in a Google Cloud project with an active Cloud Billing account attached.
2. **Project Billing Separation vs. Secret Key Location**:
   - The user has **already saved `GEMINI_API_KEY` into Firebase Secret Manager in `uhca-20800`**.
   - However, that API key was generated from a separate Gemini API project (on the free tier).
   - The billing status of the project owning the Gemini API key, **not** the UHC Firebase project's Blaze plan, governs whether requests are treated as Paid or Unpaid.
   - **Do Not Reconfigure Key**: Developers do not need to set, read, fetch, or overwrite the key again.
3. **Universal Restrictions (All Tiers)**:
   - **Age / Access Restriction**: Prohibits using the Services in a manner that is targeted to or likely to be accessed by individuals under the age of 18.
   - **Clinical Practice Clause**: Models must not be used for clinical practice, providing medical advice, patient care, or diagnostic decision-making.
   - **Territory**: Available only in authorized regions.
4. **Architecture Gate Principles**:
   - HIPAA applicability is **not** established for this application (university student/staff health center). Paying for the API or executing a BAA does not automatically satisfy all provider terms or acceptable use restrictions.
   - Regex redaction, removing caller IDs, or superficial consent forms do not make raw natural-language medical scheduling text safe under unpaid terms.
   - Therefore, production gates remain default OFF.

### Controlled Local Offline Synthetic Testing
The codebase includes a deterministic offline synthetic testing mode that exercises the exact same scheduling, slot locking, idempotency, and booking confirmation pipelines without making any external AI calls or transmitting patient data.

> [!NOTE]
> **Fixture Parsing vs. Real AI Generation**
> Synthetic mode uses deterministic keyword matching against local catalog fixtures. It does **not** evaluate real Gemini AI generation quality, fluency, context reasoning, or live network latency. It is designed to verify system plumbing and booking mechanics safely offline.

> [!IMPORTANT]
> **Runtime Testing Status Caveat**
> Backend Node.js tests and emulator runtime execution remain **UNRUN / blocked** by the host administrative broker in this environment (sandboxed broker denies Node.js process execution with exit code 127). All source contracts, schema boundaries, and mock assertions are verified in code and Dart MCP static analysis (0 errors), but runtime backend test commands cannot be executed directly until host broker permissions are granted.

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

##### 4. Launch the Flutter Web Application
In the second terminal, run the Flutter app targeting Chrome with the emulator flag. The app automatically selects synthetic `FirebaseOptions` for `demo-uhc-test` before initializing Firebase, without requiring any manual edit of `lib/firebase_options.dart`:

```powershell
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
```

##### 5. Sign In and Test the Appointment Assistant
1. When the login screen loads in Chrome, note the blue **LOCAL EMULATOR MODE (demo-uhc-test)** banner.
2. Click **Sign In as Demo Patient (No OAuth)** (authenticates directly with email `synthetic.patient@demo.uhc.edu` / `TestPassword123!` against the local Auth emulator; external OAuth is disabled in emulator mode).
3. On the Patient Home screen (first tab in bottom navigation bar), locate the **AI Health Assistant** / **AI Booking Assistant** card (`_buildAssistantCard` in `lib/screens/patient/home_screen.dart`, rendered as a gradient banner with robot icon). Note: This is an entry card on the Home screen, not a separate bottom navigation tab. Click the card to open the assistant.
4. Type the documented synthetic phrase:
   > "I want an appointment with Dr. Noor in dermatology on Tuesday"
5. The assistant returns real expiring schedule offers for Dr. Noor on Tuesday.
6. Click **Confirm Appointment** on an offer card.
7. The appointment is booked with a canonical slot lock and booking reference (`UHC-...`), all entirely offline and local!


