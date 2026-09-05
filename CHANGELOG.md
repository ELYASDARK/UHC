# Changelog

[Back to README](README.md#changelog)

These are historical release notes, not a fresh verification of old builds or test results. Later releases may replace earlier limits, dependencies, and behavior; use the [README](README.md#getting-started), [Firebase setup](docs/FIREBASE_SETUP.md), and [Cloud Functions reference](docs/CLOUD_FUNCTIONS.md) for the current configuration.

<details open>
<summary><b>Unreleased</b></summary>

### Admin governance fixes

- Admin deletion now returns an error and preserves the profile when Firebase Auth deletion fails. Cleanup still proceeds when the Auth account is already absent.
- Missing admin permission maps now default to no access in the client, matching backend permission checks.
- Added regression tests for Auth deletion failures, cleanup retries, and missing or partial permission maps. Run `npm --prefix functions test` and `flutter test`.

### Firebase Functions Modularization

- Domain Split. Refactored the large Firebase Functions entrypoint into focused modules for appointments, doctors, users, departments, doctor availability, notifications, admin governance, and shared helpers.
- Stable Public Surface. Kept `functions/src/index.ts` as the public Firebase export surface only; the 48 exports present at that refactor retained their names. The current export list is in the [Cloud Functions reference](docs/CLOUD_FUNCTIONS.md).
- Central Firebase Admin Initialization. Added a shared Firebase Admin module so `admin.initializeApp()`, Firestore, Auth, and Messaging handles are initialized once and reused safely.
- Validation recorded at the time. The original notes report checks with `npm --prefix functions run build`, Firebase emulator boot for `functions`, `firestore`, and `storage`, and `firebase deploy --only 'firestore:rules,firestore:indexes,storage,functions' --dry-run`.

### Notification Settings & Local Scheduling Follow-Up

- Native Settings Bridge. Added Android/iOS method-channel support for opening the app's notification settings page from the shared settings screen.
- Permission Refresh on Resume. Notification settings now refresh permission/device state when returning from system settings and resync token/schedule state.
- Local Reminder Cleanup. Local appointment reminder resync now cancels only appointment-reminder notifications instead of wiping unrelated local notifications.
- Doctor Local Daily Summary Resync. Mobile doctor daily summaries can be rescheduled from current doctor settings and weekly schedule.
- Visibility-Safe Reads. Notification list, unread count, mark-read, and delete flows filter scheduled/future notifications client-side when Firestore queries cannot rely solely on `isVisible`.
- Index Support. Added a composite notification index for user/type/scheduled reminder cleanup queries.

### Files Changed

| File | Key Changes |
|:---|:---|
| `functions/src/index.ts` | Reduced to public re-exports only |
| `functions/src/firebase.ts` | Centralized Firebase Admin initialization and shared SDK handles |
| `functions/src/*.ts` | Added domain modules for appointments, doctors, users, departments, availability, and admin governance |
| `functions/src/notifications/` | Added notification core, delivery, admin send, and scheduled modules |
| `functions/src/shared/` | Added reusable auth, audit, error, validation, profile photo, and appointment helper modules |
| `lib/screens/shared/notification_settings_screen.dart` | Added lifecycle refresh, native settings open flow, and settings rollback on save failure |
| `lib/services/notification_scheduling_coordinator.dart` | Added targeted local reminder cleanup and doctor daily summary local resync |
| `lib/services/local_notification_service.dart` | Added native notification settings bridge and idempotent initialization |
| `android/app/src/main/kotlin/com/example/uhc/MainActivity.kt` | Added Android notification settings method channel |
| `ios/Runner/AppDelegate.swift` | Added iOS notification settings method channel |
| `lib/data/repositories/notification_repository.dart` | Added visibility-safe notification filtering |
| `firestore.indexes.json` | Added notification cleanup composite index |

</details>

<details>
<summary><b>v2.4.0</b>, May 30, 2026</summary>

### UHC Notification System V2 (May 30, 2026)

- Notification Responsibilities. Firestore Alerts are the in-app source of truth; FCM handles real-time push notifications; Local reminders handle mobile-only offline schedules. Web never schedules local notifications.
- Multi-Device Token Support. Replaced single-token per user limits with subcollection-based hashed multi-device tracking (`user_tokens/{userId}/tokens/{tokenHash}`) with device and timezone metadata.
- No Duplicate Reminders. Prevented duplicate delivery of local alarms and FCM scheduled pushes for identical appointments by routing scheduling and cancellation flows through a new scheduling coordinator.
- Scheduling Coordinator Integration. Created `NotificationSchedulingCoordinator` which manages offline local scheduling state, clears old alarms, and synchronizes future reminders after login, logout, app reboots, settings change, cancellations, and reschedules.
- Settings UI Redesign. Redesigned the settings screen with 6 card-based sections mapping platforms, push switches, appointment timing reminders, delivery preferences, doctor summary timing, and announcements. Hides local-mode reminder widgets entirely on Web.
- Doctor Daily Summaries. Refactored summaries to compute fresh appointment counts server-side at the configured time (delivered via FCM). Mobile local modes schedule a generic open-app reminder instead of using stale local data.
- Alerts Count Visibility Guard. Future scheduled alerts are hidden (`isVisible: false`) from the in-app Alerts count until they are actually due and processed by the delivery worker.
- Logout Cleanup. Added cleanup of current device FCM tokens, topic subscriptions, and local alarms on user sign-out.
- Upgrade Package Compatibility. Upgraded `flutter_timezone` to `5.1.0` and `crypto` to `3.0.7` and addressed compilation errors and warnings reported during that update.

### Onboarding Redesign (May 27, 2026)

- Full onboarding rewrite. Replaced the legacy onboarding screen with per-slide gradient backgrounds, custom `CustomPainter` vector illustrations, animated transitions, and a bottom content area.
- Custom vector illustrations. Three programmatic illustrations (calendar with clock, notification bell with pulse rings, clipboard with heartbeat line) built entirely with `CustomPainter`. No external image assets required.
- Per-slide gradient themes. Each slide uses the app's own color palette: primary blue gradient (Appointments), secondary teal gradient (Reminders), warm amber-to-brown gradient (Health Records).
- Page transitions. `PageView` with swipe navigation, `AnimatedSwitcher` for title/description cross-fades, and `AnimatedContainer` pill indicators.
- Onboarding descriptions. Expanded all three onboarding descriptions from brief one-liners to detailed, 2-sentence explanations in English, Arabic, and Kurdish.
- Simplified visual effects. Removed heavy visual effects (frosted glass `BackdropFilter`, liquid `CustomPainter` indicators, floating bokeh particles) to match the app's other screens.
- Zero new dependencies. Uses only existing project packages: `google_fonts`, `flutter_animate`, and built-in Flutter painting APIs.

### Doctor Availability Approval & Booking Locks (May 27, 2026)

- Admin-approved unavailable workflow. Doctors now request unavailable status with a short note; only admins with `doctors.manage` can approve or reject the request.
- Monthly unavailable limit. Approved doctor unavailable requests are capped at 2 per calendar month using server-owned `doctor_availability_usage` counters.
- High-priority admin notifications. Doctor availability requests render as special notification cards with Approve/Reject actions, clear pending/approved/rejected status, and permission-gated controls.
- Real-time doctor dashboard sync. Doctor dashboard availability state listens to the doctor document, so admin approvals or manual admin availability changes update the switch without app refresh.
- Admin Doctor Management controls. Doctor cards now show both account status and availability badges, hide inactive doctors by default, expose an Inactive filter, and include `Make Available` / `Make Unavailable` in the three-dot menu.
- Patient booking protection. Patients cannot open/book unavailable doctors from the doctor browser, schedule page, or booking flow; `createAppointment` also rejects unavailable doctors server-side.
- Appointment cancellation on approval. When an unavailable request is approved, active future appointments for that doctor are cancelled, slot locks are released, and patients are notified to book another available time.
- Firestore rule hardening. `doctor_availability_requests` are readable only by the requesting doctor or doctor-managing admins, and client-side writes to sensitive doctor availability fields are blocked.

### Admin Notifications & Account Operations (May 27, 2026)

- Audited admin notifications. Added recipient search, preview, idempotency, cooldown, and audited send records for targeted patient/doctor notifications.
- Legacy topic send disabled. `sendTopicNotification` now blocks topic broadcast sends and points admins to audited in-app notification delivery.
- Initial password change flow. Admin-created doctor/student/staff accounts can be forced through `completeInitialPasswordChange` before normal use.
- Server-owned profile photo operations. Storage rules and helper functions now support permission-gated doctor/user profile photo uploads and cleanup.

### Stability Follow-Up (May 24, 2026)

- Scheduled reminder delivery. Added `deliverScheduledNotifications` so future notification documents are delivered when due instead of being skipped by the create trigger.
- Cursor-paginated appointment reads. Patient, doctor, admin, slot-availability, and doctor/patient history queries now page through bounded Firestore batches with server-side filters instead of applying hard `.limit(500/1000)` before in-memory filtering.
- Admin hard-delete slot release. `deleteAppointment` releases its `appointment_slot_locks` document before deleting the appointment so the same doctor/date/time does not stay blocked.
- Doctor status notification reliability. Confirmed, completed, and no-show status updates create patient notifications from trusted backend code.
- Super Admin list completeness. Admin/permission lists support Load More, and audit logs use backend `hasMore` pagination so filtered views do not silently hide older matches.
- Android notification channel alignment. Local Android channel setup now includes the backend FCM channel ID (`uhc_notifications`) to avoid fallback-channel behavior.
- Release metadata aligned. `pubspec.yaml` is now `2.4.0+24`; Android package ID and release signing remain intentionally unchanged until the final Play Store package, Firebase config, and keystore are chosen.

### Server-Side Appointment Lifecycle (Client → Cloud Functions Migration)

- All appointment mutations moved server-side. `createAppointment`, `rescheduleAppointment`, `cancelAppointment`, `updateAppointmentStatus`, `updateMedicalNotes`, `incrementQrScanFailures`, and `deleteAppointment` are now Cloud Functions callables with full server-side validation.
- Transactional Slot Locking. New `appointment_slot_locks` collection with atomic lock/release within Firestore transactions prevents double-booking race conditions. Each slot lock document is keyed by `{doctorId}_{date}_{timeSlot}`.
- Server-Side Notifications. Appointment confirmation, completion, and no-show notifications are now created by Cloud Functions instead of client-side writes, ensuring trusted notification delivery.

### Security Hardening

- Inactive account gateway. All Cloud Function callables now reject requests from inactive accounts (`isActive !== true`) at the entry point.
- Explicit permission enforcement. Legacy admins without an `adminPermissions` object are no longer granted implicit full access; explicit permission map is now required.
- Password validation. Admin and doctor password resets use the shared `MIN_PASSWORD_LENGTH` policy. Its current value is 8 characters.
- Session revocation consolidation. `forceSignOutUser` now also clears FCM tokens from `user_tokens` collection alongside refresh token revocation.
- Firebase Storage rules. Added `storage.rules` with:
  - Content-type validation (images for profiles, PDF/DOCX/images for medical docs)
  - File size limits (5 MB profile images, 20 MB medical documents)
  - Scoped medical document uploads (`self` scope for patients, appointment-scoped for doctors)
  - Doctor-patient access grants via `doctor_patient_access` subcollection checks
  - Permission-gated admin/superAdmin read access

### FCM Token & Topic Consolidation

- Removed dual token storage. FCM tokens are no longer written to the `users` collection; `user_tokens` is now the single source of truth for Cloud Functions push delivery.
- Removed per-user/role/department topic subscriptions. Private notifications are now delivered by token from Cloud Functions. Only the broadcast `announcements` topic subscription remains.

### User Preferences Sync

- Theme mode persistence. Added `themeMode` field to `UserModel` and Firestore `users` document, synced on change via `AuthProvider.updateThemeMode()`.
- Language preference persistence. Added `AuthProvider.updateLanguage()` to write the selected language code back to Firestore.

### Sign-Out Resilience

- Pre-signout state clearing. Local user state is cleared *before* `FirebaseAuth.signOut()` so role-scoped Firestore streams are disposed while permissions are still valid. On sign-out failure, state is rolled back with error feedback.

### Medical Documents Scoping

- Storage path scoping. Medical document uploads now include a `scope` segment (`self` for patient-uploaded, `{appointmentId}` for doctor-uploaded), aligning with the new Storage rules.
- Upload metadata. `contentType` metadata is now attached to Storage uploads for accurate content-type validation.

### Admin Dashboard Reliability

- Permission-safe KPI stats. Dashboard stat queries are now guarded by the admin's view permissions; stats return zero instead of throwing permission errors.
- Firestore exception tolerance. Wrapped aggregation queries in `_countSafely()` to prevent a single failed stat from crashing the dashboard.

### Files Changed

| File | Key Changes |
|:---|:---|
| `functions/src/index.ts` | Added settings normalization, `resyncUserNotificationSchedules` callable, `sendDoctorDailyReports` scheduled summary, and multi-device multicast delivery |
| `firestore.indexes.json` | Added composite indexes for notification queries and scheduled scans |
| `firestore.rules` | Configured user device tokens subcollection security rules |
| `lib/core/notifications/` | [NEW] Added device and user notification preferences models |
| `lib/services/notification_scheduling_coordinator.dart` | [NEW] Added notification scheduling coordinator to orchestrate local/FCM reminder sync |
| `lib/services/local_notification_service.dart` | Upgraded with timezone compatibility, web guards, stable reminder IDs, and fallback exact-alarm modes |
| `lib/services/fcm_service.dart` | Modified to register tokens under `user_tokens` subcollections and fixed timezone info extraction |
| `lib/screens/shared/notification_settings_screen.dart` | Complete settings screen redesign with status card, timing preferences, radio card delivery selectors, and web overrides |
| `lib/providers/appointment_provider.dart` | Integrated scheduling coordinator, removing direct/duplicate local alarms |
| `lib/providers/doctor_appointment_provider.dart` | Modified doctor daily summary local scheduling to align with coordinator and use generic fallback reminders |
| `lib/data/repositories/notification_repository.dart` | Updated notifications and unread streams to filter for visibility status |
| `pubspec.yaml` | Upgraded `flutter_timezone` to `5.1.0` and `crypto` to `3.0.7` |
| `lib/main.dart` | Integrated coordinator resync on user login or session restoration |
| `lib/data/models/user_model.dart` | Added `themeMode` field, explicit `hasPermission` now returns false for null permissions |
| `lib/services/auth_service.dart` | `updateUserLanguage()`, `updateUserThemeMode()` Firestore helpers |
| `lib/screens/onboarding/onboarding_screen.dart` | Full rewrite: gradient backgrounds, `CustomPainter` illustrations, `PageView` navigation, animated indicators |
| `lib/l10n/app_en.arb` | Expanded onboarding descriptions to detailed 2-sentence copy |
| `lib/l10n/app_ar.arb` | Expanded onboarding descriptions (Arabic) |
| `lib/l10n/app_ku.arb` | Expanded onboarding descriptions (Kurdish) |

</details>

<details>
<summary><b>v2.3.0</b>, May 2, 2026</summary>

### Excel Report Export (CSV → XLSX Migration)

- Syncfusion XlsIO Integration. Replaced legacy CSV exports with styled `.xlsx` documents using `syncfusion_flutter_xlsio`.
- Branded Report Design. All 4 report types (Appointments, Doctors, Users, Departments) now feature:
  - Merged title row with branded blue (#2196F3) styling
  - Date-range sub-header
  - Bold white-on-blue header row with thin borders
  - Alternating white/light-gray row striping for readability
  - Footer row with total record count
- Cross-Platform File Handling. Implemented conditional export pattern (`save_file.dart`) for platform-safe file operations:
  - **Web**: Uses `package:web` + `dart:js_interop` for native browser Blob downloads
  - **Mobile/Desktop**: Uses `path_provider` + `share_plus` for temp file save + system share sheet
- Revenue → Departments. Renamed Revenue Report to Departments Report with department-specific data (name, doctor count, appointment count, status).

### Firebase Messaging Web Fix

- Service Worker Registration. Added `firebase-messaging-sw.js` to resolve `failed-service-worker-registration` errors on web. Firebase Cloud Messaging now registers correctly in the browser.

### App Branding Updates

- Custom App Icons. Updated launcher icons for Android (all density buckets) and iOS (all sizes) with new branded design.
- Web Assets. Updated `favicon.png`, PWA icons (`Icon-192`, `Icon-512`, maskable variants), and `manifest.json` with updated app name and branding.

### Dependencies

- **Added**: `syncfusion_flutter_xlsio`, `web` (for JS interop), `share_plus`, `path_provider`

### Files Changed

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
<summary><b>v2.2.0</b>, April 29, 2026</summary>

### Authentication & Provider Controls

- Provider-aware password change. `Change Password` is now enabled only when `password` provider is linked.
- Mandatory Google-link gate hardening. Removed stale session bypass and now gate from real provider state only.
- Google unlink (self, role-gated). Added self-unlink capability for signed-in `admin` and `superAdmin` accounts.
- Google unlink (admin on target user). Added User Management action and backend callable to unlink Google for managed non-admin users.

### Password Reset & Account Reliability

- Forgot password from profile. Added Forgot Password entry in both patient and doctor profile account sections.
- **Context-aware forgot-password UX**:
  - login flow keeps **Back to Login**
  - profile flow uses neutral completion action (no login redirect wording)
- Google-only account notice. Forgot password clearly explains that reset works only for accounts with `password` provider.
- Reset flow stability. Sending password reset email no longer mutates authenticated app state.

### Cloud Functions Added

- `unlinkGoogleProviderByAdmin`

### Files Changed

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
<summary><b>v2.1.0</b>, April 28, 2026</summary>

### User Management & Super Admin Edit Rules

- Super Admin can edit Super Admin profiles. Updated UI and backend enforcement so only `superAdmin` can edit `superAdmin` accounts.
- Edit-only protection for Super Admin rows. In User Management, `superAdmin` targets expose **Edit** only (no deactivate/role-change destructive actions).
- Role-change safety. Role options in user actions/forms now exclude `admin`, `doctor`, and `superAdmin` where not allowed.
- Server-side enforcement. `updateUserProfileByAdmin` now allows super-admin target updates only when caller is `superAdmin`.

### UID UX Improvements

- UID copy support. Added quick UID copy action for super admin in User Management list rows.
- **Role-based UID visibility**:
  - `superAdmin`: sees UID in list + copy button.
  - `admin`: list UID hidden; UID remains available in edit dialog.
- Edit form normalization. Replaced manual Student/Staff ID inputs with read-only **User UID** behavior and server-safe mapping.

### Profile Experience Refinements

- Admin/Super Admin profile simplification. Removed patient-only sections for admin-like roles (language/notifications/medical docs where not applicable).
- Super Admin profile styling. Added super-admin accent treatment and slot badge indicators (`PRIMARY` / `BACKUP`).
- Admin quick entry restored. Profile keeps direct access to Admin Dashboard for admin-like roles.

### Super Admin Navigation & Governance UX

- Bottom nav streamlined. Removed `Permissions` item from Super Admin bottom navigation; now: Dashboard, Admins, Audit Logs, Profile.
- Quick Actions removed from Super Admin Dashboard. Cleaner dashboard flow with governance focused sections.
- Admin Governance dialog redesign. Modernized create admin, reset password, assign slot, and rotate slot dialogs with consistent validation and submit/loading states.
- UID/email resolution in governance flows. Assign/Rotate slot inputs accept either UID or email and resolve to Firestore user doc IDs.

### Audit Logs Filtering Upgrade

- Actor/Target filters accept UID or email. Improved discoverability when UIDs are not easy to find.
- Active filter chips styled for dark mode. Fixed readability (text/icon contrast) in dark theme.

### Dark Mode Readability Fixes

- Admin Governance preset chips (`Full`, `Ops`, `Read-Only`). Improved dark-mode contrast (label/background/border/disabled state).
- Chip/divider spacing fix. Added vertical spacing so preset chips no longer touch divider lines.

### Runtime & Auth Reliability

- Crashlytics web-safe guards. Prevented web assertion crashes by disabling/guarding Crashlytics hooks on web and wrapping reporting calls.
- Hero tag collision fix. Unique FAB hero tags for `AdminControlScreen` instances inside `IndexedStack`.
- Sign-out hardening. Improved sign-out reliability with verification retries and better user feedback on failure.
- Stale auth load guard. Prevented outdated async auth loads from overriding current auth state after account switches/sign-out.

### Files Changed

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
<summary><b>v2.0.0</b>, April 2026</summary>

### Super Admin + Admin RBAC (Phases 0–8)

- Added new `superAdmin` role end-to-end (model, routing, UI, backend guards, rules)
- Added strict two-slot governance model (`primary` + `backup`) with transactional enforcement
- Added dedicated Super Admin shell and governance screens (Admins, Permissions, Slots, Audit Logs)
- Added admin permission model + presets and permission-driven admin UI gates
- Added governance callables:
  - admin account lifecycle (create/changeRole/activate/reset/delete)
  - force sign-out
  - set admin permissions
  - assign/rotate super admin slots
  - audit log listing
- Hardened Firestore rules to block client-side privilege escalation fields
- Added `admin_audit_logs` collection model + UI query surface
- Added bootstrap/migration runbook for secure first Super Admin setup

### Reliability & Web Fixes

- Improved auth/profile mismatch handling (prevents silent fallback role routing)
- Improved governance callable error mapping to readable client errors
- Fixed Super Admin slot layout overflow in web/mobile card actions
- Fixed duplicate Hero tag conflicts in governance screen
- Guarded non-web Google Sign-In initialization path to avoid web client-id assertion at startup

</details>

<details>
<summary><b>v1.10.0</b>, April 2026</summary>

### Scalability & Performance Audit
The audit covered query limits, pagination, parallel fetching, and listener cleanup. The changes below describe that release; later entries document the move to cursor pagination. Concurrent-user capacity has not been established by a documented load test.

#### Critical Fixes

- Bounded Firestore Queries. Added limits to appointment and user queries reviewed during that audit. Previously, methods like `getUpcomingAppointments()`, `getPastAppointments()`, and `getAllDoctorAppointments()` would download entire document collections (potentially 500k+ docs at scale). The affected methods used limits of 500–1000 documents at that release; later releases introduced cursor pagination.
- Parallel photo fetching. Replaced sequential photo fetching with `Future.wait()`. Requests run concurrently rather than waiting for each preceding request; this does not combine them into a single network request.
- Admin User Stream Limit. Added `.limit(200)` with Load More pagination to the admin User Management screen. It starts with 200 users and loads another page on request, instead of loading the entire user list.
- Notification Query Optimization. Replaced `getUnreadCount()` (which downloaded all unread documents) with Firestore's `.count()` aggregation for server-side counting without downloading documents.

#### Moderate Fixes

- 8 Composite Firestore Indexes. Defined composite indexes for the most common query patterns (`doctorId + appointmentDate`, `patientId + appointmentDate`, `userId + createdAt`, `userId + isRead`, etc.) to enable efficient server-side filtering instead of client-side in-memory filtering.
- Batch Operation Chunking. All batch write operations (`markAllAsRead`, `deleteAllNotifications`, `deleteAllUserAppointments`, `deleteFutureDailySummaries`) now chunk into groups of 500 to respect Firestore's batch limit. Previously, batches with >500 operations would fail silently.
- Booking Screen Query Limit. Added `.limit(500)` to the booking screen's appointment fetch, preventing download of a doctor's entire appointment history on every calendar date tap.
- Doctor Search Caching. `searchDoctors()` now caches the doctor list in memory and filters locally, instead of re-fetching the entire `doctors` collection on every keystroke.
- Analytics & Reports Pagination. Reports and analytics adopted cursor-based pagination using `startAfterDocument`, with batches of up to 5,000 documents at this release. Successful exports could continue past the previous fixed result limit. Later releases changed report output from CSV to XLSX.

#### Minor Fixes

- FCM Token Refresh Leak. Fixed duplicate `onTokenRefresh` listeners by cancelling previous subscriptions before re-registering.
- Notification Tap Listener Leak. Fixed `onMessageTapped` listeners being registered multiple times upon re-initialization, causing duplicate navigation.
- Server-Side Daily Summary Filtering. `deleteFutureDailySummaries()` now uses a `where('type', isEqualTo: 'dailySummary')` server-side filter instead of downloading all user notifications.

#### Performance validation

Read counts, cost, and latency depend on the dataset, access patterns, devices, and network. Earlier numerical projections had no accompanying benchmark or cost model. Use these checks to measure the effects before making capacity or savings claims:

| Area | Change | Validation |
|:---|:---|:---|
| Firestore reads | Pagination and count queries avoid fetching whole collections for a page or count | Compare billed reads for the same dataset and user actions |
| Monthly cost | Read volume affects database cost; other services also contribute | Record traffic, reads, writes, storage, function usage, region, and billing rates |
| Appointment load time | Bounded pages reduce the records fetched for a page | Record first-page and subsequent-page latency with a fixed appointment dataset |
| Doctor photo fetching | Concurrent requests replace sequential waits | Compare the same doctor set and network conditions, with both cold and warm caches |

### Files Changed

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
<summary><b>v1.9.0</b>, March 2026</summary>

### Auto No-Show System

- Automated Status Updates. Pending appointments that have passed their scheduled time by 60 minutes (30-minute slot + 30-minute grace period) are automatically marked as "No Show" when the doctor opens their dashboard.
- System Attribution. Auto no-show updates are tagged with `statusUpdatedBy: 'system_auto'` to distinguish them from manual doctor actions.

### Profile Image Size Limits

- 25 MB Upload Limit. All profile image uploads (patient, doctor, and admin) now enforce a 25 MB file size limit with a clear error message, preventing excessive storage consumption.

### Google Authentication Hardening

- Account-Only Sign-In. Google Sign-In now only allows existing, admin-created accounts to log in. Signing in with a Google account that isn't already registered is blocked, preventing unauthorized account creation.
- Profile Photo Preservation. Signing in with a linked Google account no longer overwrites the user's custom profile image with the generic Google avatar.

### Doctor Appointment Display Fix

- Today's Appointments Visible. Fixed a date comparison bug where today's appointments were not showing in the doctor's "Upcoming" tab. Corrected the start-of-day boundary logic to include the current date.

### Document Screen Fixes

- Stream Caching. Fixed Firestore stream recreation during document uploads that caused performance issues and UI churn. The stream is now cached in widget state and only recreated when the user ID changes.
- Mounted Check. Added `mounted` guard before accessing context after async dialog operations to prevent "context used after dispose" errors.

### Files Changed

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
<summary><b>v1.8.0</b>, March 2026</summary>

### FCM Push Notification Infrastructure (BUGs 6–10)

- Server-Side FCM Sending. Added `onNotificationCreated` Cloud Function: a Firestore `onDocumentCreated` trigger that automatically sends FCM push notifications when a notification document is created. Looks up user FCM tokens from the `user_tokens` collection and sends via `admin.messaging().send()` with Android high-priority channel and iOS alert/badge/sound support. Automatically cleans up stale tokens on `invalid-registration-token` errors.
- Topic Broadcast Function. Added `sendTopicNotification` callable Cloud Function for admins to send push notifications to FCM topics (e.g. `announcements`, `department_*`).
- Patient FCM Token Registration. Fixed `main_shell.dart` to call `notificationProvider.initialize(userId)` instead of `loadNotifications()`, ensuring patient devices register their FCM token, subscribe to topics, and start notification listeners.
- FCMService Singleton. Refactored `FCMService` into a proper singleton with a factory constructor and `_initialized` guard, preventing duplicate notification handlers across `main.dart` and `NotificationProvider`.
- Platform Detection. Replaced hardcoded `'android'` platform string with dynamic `Platform.isIOS ? 'ios' : 'android'` detection in both initial token save and `onTokenRefresh` listener.
- Logout FCM Cleanup. `AuthProvider.signOut()` now calls `FCMService.removeTokenFromDatabase()` and `unsubscribeUserFromTopics()` before Firebase Auth sign-out, preventing stale token accumulation.

### Notification System Consolidation

- Unified Notification Settings. Removed individual push/email notification toggles from patient `ProfileScreen` and doctor `DoctorProfileScreen`. All notification preferences are now managed exclusively through the shared `NotificationSettingsScreen`.
- Real-Time Notification Streams. `NotificationProvider` now uses Firestore real-time streams (`streamNotifications`, `streamUnreadCount`) instead of one-time fetches, so the UI auto-updates when new notifications arrive.
- Doctor Daily Summary Settings. Consolidated daily summary toggle and time picker into `NotificationSettingsScreen`, visible only to doctors. Time selection uses `SharedPreferences` and syncs to the scheduling system.
- Dead Code Removal. Removed unused `showAppointmentConfirmed()` and `showAppointmentCancelled()` methods from `LocalNotificationService`.

### Appointment Reminder Timing Fix

- Exact Appointment Time. Reminders now use `exactAppointmentTime` (date + timeSlot combined) instead of `appointmentDate` (midnight), so 1-week, 24-hour, and 1-hour reminders fire relative to the actual appointment time, not midnight.
- Reschedule Reminders. Rescheduled appointments correctly rebuild the exact DateTime from the new date and time slot.

### Doctor Status Notifications to Patients

- Confirmation Notification. When a doctor confirms an appointment, the patient now receives a Firestore notification with the doctor's name, date, and time slot.
- No-Show Notification. When a doctor marks a patient as no-show, the patient receives a notification and old reminders are cleaned up.
- Completion Notification. When an appointment is completed, the patient receives a thank-you notification and old reminders are deleted.

### Doctor Profile Photo Editing

- Large Avatar Editor. Doctor edit profile screen now features a 120px tappable photo circle (matching patient profile style) with camera icon overlay and "Tap to change photo" text.
- Image Picker. Camera, gallery, and remove options via bottom sheet with themed icons.
- Firebase Storage Upload. Photo is uploaded on save and the URL is synced to both `doctors` and `users` Firestore collections.
- Read-Only Card Cleanup. Removed duplicate small avatar from the read-only card, replaced with an info icon to avoid visual clutter.

### UI Improvements

- Appointment Detail Layout. Fixed text overflow in the doctor appointment detail info rows by switching to `Expanded` flex layout instead of `Spacer` + `Flexible`.
- Patient Detail FittedBox. Patient info values now scale down using `FittedBox` instead of being truncated with `TextOverflow.ellipsis`.
- Home Screen Book Button. "Book Appointment Now" text is now wrapped in `Flexible` with `maxLines: 1` to prevent overflow on narrow screens or long translations.

### Files Changed

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
<summary><b>v1.7.0</b>, February 2026</summary>

### Doctor Daily Notifications

- Customizable Timing. Admins can now configure the exact time doctors receive their daily appointment summary directly from the Doctor Management panel.
- Working Days. Daily notifications follow the doctor's weekly schedule and skip days off.
- Accurate Pending Counts. Daily summaries count pending appointments separately from completed or cancelled appointments.

### QR Check-In System

- Time-Gated Verification. Doctors can use a built-in QR scanner to confirm patient attendance.
- Scan Attempt Monitoring. Added a manual-confirmation UI after repeated scan failures, with counts stored in Firestore. The current backend rejects that fallback; see [check-in behavior](docs/CLOUD_FUNCTIONS.md#check-in-behavior).
- Localized. Added QR UI messages in English, Arabic, and Kurdish.

</details>

<details>
<summary><b>v1.6.0</b>, February 2026</summary>

### Admin UI Refinements

- Standardized Detail Sheets. Users, Doctors, and Departments now share the same bottom sheet design
- Improved Consistency. "View Details" screens now feature consistent styling, layout, and action button placement
- Department Status. "Closed" days are now clearly marked in red with dimmed text in the details view

### Authentication Flow

- Enhanced Google Linking. Added "Sign Out" option to the mandatory link screen, preventing users from getting stuck
- Navigation Safety. Implemented `PopScope` to properly handle back navigation during the linking process
- Lint Fixes. Resolved `use_build_context_synchronously` issues in authentication flows

</details>

<details>
<summary><b>v1.5.0</b>, February 2026</summary>

### Doctor Screen Restyling

- Unified Design Language. All 8 doctor screens now match the patient/staff UI for a consistent cross-role experience
- Staggered Animations. Added `flutter_animate` fade-in and slide transitions to every doctor screen section (300→600ms stagger delays, `index * 100` per list item)
- Skeleton Loaders. Replaced bare `CircularProgressIndicator` with `CardSkeleton`, `AppointmentCardSkeleton`, and `SkeletonList` across dashboard, schedule, and patient detail screens
- Theme-Aware Colors. Replaced all hardcoded `Colors.white` backgrounds with `AppColors.surfaceLight` / `AppColors.surfaceDark` tokens for consistent light/dark mode support
- Typography Hierarchy. Enforced consistent font usage: `Poppins` for headings, `Plus Jakarta Sans` for subtitles, `Roboto` for body text, `Outfit` for avatar initials
- Shared Widgets. Adopted `GradientCard` for hero cards (dashboard greeting, patient profile header) instead of manual gradient containers
- Improved Empty States. Enlarged icons (80px), descriptive titles with `Poppins w600`, body text with `textAlign: center`, wrapped in scrollable containers for pull-to-refresh
- Loading Overlays. Appointment detail screen now uses a semi-transparent overlay during save operations instead of replacing content with a blank spinner
- Layout Standardization. Consistent 20px horizontal padding, 100px bottom clearance for nav bar, 16px border radius on all cards, and box shadows (`blur: 10, offset: (0,2)`) across all screens
- SafeArea & Scaffold. Schedule screen migrated from bare `SafeArea` + manual title to proper `Scaffold` + `AppBar`; Profile screen wrapped in `SafeArea`
- Nav Bar Tokens. Doctor shell nav bar light mode updated from `Colors.white` to `AppColors.surfaceLight` for token consistency

### Screens Updated

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
<summary><b>v1.4.0</b>, February 2026</summary>

### Department Working Hours

- Fixed persistent working hours. Custom times no longer reset after toggling days
- All 7 days saved with `start`, `end`, and `enabled` fields; backward-compatible
- Mon–Fri default to ON (08:00–20:00), Sat–Sun default to OFF for new departments
- Fixed oversized Switch widgets in the working hours section

### Doctor Schedule Improvements

- Doctor schedules now respect department `enabled` flags for closed days
- Time slot picker constrained to department working hours range
- Closed days auto-disabled in doctor schedule dialog
- Replaced hidden SnackBars with visible AlertDialogs for validation errors

### Color Picker Performance

- Cached color, hex, and gradient values to avoid per-frame recalculations
- Unified HSL mutations through `_setHSL()` → `_recomputeCache()` pipeline
- Hex field syncs on `onChangeEnd` only to avoid unnecessary rebuilds

### Expanded Icons

- 155+ department icons (up from ~85), organized into clear categories

### Technical

- Migrated deprecated `color.value` → `color.toARGB32()`
- Migrated `RadioListTile` to `RadioGroup` ancestor widget (Flutter 3.32+)
- Wrapped bare `if` statements per Dart lint rules

</details>

<details>
<summary><b>v1.3.0</b>, February 2026</summary>

### Performance

- Lazy-loaded navigation screens to defer work until the screen is needed. Verify startup frame timing with a device profile before reporting a numerical improvement.
- Deferred service initialization (notifications, FCM) after first frame
- Deferred data loading in HomeScreen to prevent UI blocking

### Booking Fixes

- Fixed critical double-booking bug: corrected field name mismatch in Firestore query
- Booked slots now appear grayed out with strikethrough styling
- Switched from real-time subscription to one-time fetch for booked appointments

</details>

<details>
<summary><b>v1.2.0</b>, February 2026</summary>

### Localization

- Full multi-language support: English, Arabic, Kurdish
- Localized doctor bios, cancellation dialogs, and rescheduling screens
- Custom Kurdish material localizations

### Departments

- Added Cardiology department with full integration across all screens

### Profile & UI

- Admin-only visibility for Developer Testing and Admin sections
- Consolidated account settings into Profile screen
- Consistent dialog sizing; enhanced FAB with text label

### Notifications

- Android 12+ exact alarm permission handling
- Cleaned up test notification code for production readiness

### Technical

- Deprecated API migrations (`withOpacity` → `withValues`, `value` → `initialValue`)
- Sample data seeder for admin testing
- Gradle plugin update + core library desugaring

</details>

<details>
<summary><b>v1.1.0</b>, January 2026</summary>

- Initial feature-complete release
- Firebase integration (Auth, Firestore, Storage, Cloud Messaging)
- Complete appointment booking workflow
- Admin dashboard with analytics
- Doctor management system

</details>
