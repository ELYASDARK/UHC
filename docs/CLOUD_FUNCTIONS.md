# Cloud Functions reference

[Back to README](../README.md#cloud-functions) | [Firebase setup](FIREBASE_SETUP.md)

Source paths in this reference are relative to the repository root. For dependency installation and deployment commands, see [Cloud Functions setup](../README.md#cloud-functions-setup).

## Access rules

`functions/src/index.ts` exports the functions listed below. Implementations live in the corresponding domain modules.

- Protected callables require an authenticated, active account linked to Google. Registration and initial account setup have their own checks.
- A permission key in the Access column means an admin with that explicit key, or a Super Admin. These permissions do not grant access to doctor-only callables.
- An appointment admin is a Super Admin or an admin with `appointments.manage: true`. The current permissions UI keeps this key disabled, including in the Full preset.
- An assigned doctor must have an active doctor record whose ID matches the appointment's `doctorId`. A patient's access applies only to their own appointment.
- Auto means a Firestore trigger or scheduled job, not a client-callable endpoint.

## Appointment Lifecycle

| Function | Description | Access |
|:---|:---|:---|
| `createAppointment` | Creates a booking for the caller; validates selected doctor availability, verifies doctor weeklySchedule, and acquires its slot lock with transactional idempotency | Self (Patient) |
| `getDoctorDayAvailability` | Returns trusted doctor availability for a calendar date with start/end slots and conflict checking without exposing patient records | Authenticated user |
| `rescheduleAppointment` | Moves an active booking to a future time and updates slot locks atomically | Patient / assigned doctor / appointment admin |
| `cancelAppointment` | Cancels the appointment and releases its slot lock | Patient / assigned doctor / appointment admin |
| `updateAppointmentStatus` | Updates non-confirmation status; rejects `confirmed`, rejects reactivation to `pending` from non-pending, requires confirmed status before completion and pending status before no-show | Assigned doctor / appointment admin |
| `confirmAppointmentCheckIn` | Verifies the appointment QR code and confirmation window, then records check-in | Assigned doctor |
| `updateMedicalNotes` | Updates medical notes on an appointment | Assigned doctor / appointment admin |
| `incrementQrScanFailures` | Atomically increments the appointment's scan failure counter | Assigned doctor |
| `deleteAppointment` | Permanently deletes an appointment and releases its slot lock | Appointment admin |

## Doctor Management

| Function | Description | Access |
|:---|:---|:---|
| `createDoctorAccount` | Creates a doctor account in Auth + Firestore with the `doctor` role | `doctors.manage` |
| `updateDoctorEmail` | Updates a doctor's email in both Auth and Firestore | `doctors.manage` |
| `deleteDoctorAccount` | Deletes doctor and linked user records and attempts Auth deletion; does not cascade-delete appointment history | `doctors.manage` |
| `resetDoctorPassword` | Resets a doctor's password without requiring the old one | `doctors.manage` |
| `completeInitialPasswordChange` | Sets the caller's new password and clears the initial-change flag when required | Active doctor / student / staff, acting on self |
| `updateDoctorProfile` | Updates admin-safe doctor profile fields | `doctors.manage` |
| `setDoctorActiveStatus` | Activates/deactivates doctor records | `doctors.manage` |
| `updateDoctorSchedule` | Updates a doctor's weekly schedule | `doctors.manage` |
| `requestDoctorUnavailable` | Doctor submits an unavailable request with a note for admin review | Doctor |
| `setDoctorAvailability` | Doctor returns to available immediately; unavailable requires admin approval | Doctor |
| `setDoctorAvailabilityByAdmin` | Admin directly marks a doctor available/unavailable from Doctor Management | `doctors.manage` |
| `reviewDoctorAvailabilityRequest` | Approves or rejects an unavailable request; approval triggers appointment cancellation and patient notifications | `doctors.manage` |

## Department Management

| Function | Description | Access |
|:---|:---|:---|
| `createDepartment` | Creates a department with metadata and working hours | `departments.manage` |
| `updateDepartment` | Updates department details and working hours | `departments.manage` |
| `setDepartmentActiveStatus` | Activates/deactivates departments | `departments.manage` |
| `deleteDepartment` | Deletes a department record | `departments.manage` |

## User Management

| Function | Description | Access |
|:---|:---|:---|
| `createUserAccount` | Creates student/staff accounts in Auth + Firestore | `users.manageNonAdmin` |
| `bootstrapSelfUserDocument` | Creates the caller's student profile if absent; leaves an existing profile unchanged | Authenticated self |
| `syncGoogleLinkStatus` | Syncs the caller's linked Google email from Firebase Authentication | Active self with linked Google provider |
| `unlinkOwnGoogleProvider` | Removes the caller's Google link; requires password sign-in to remain available | Active self with Google and password providers |
| `setUserActiveStatus` | Activates/deactivates non-admin users | `users.manageNonAdmin` |
| `changeUserRoleByAdmin` | Changes non-admin user roles within allowed patient roles | `users.manageNonAdmin` |
| `unlinkGoogleProviderByAdmin` | Unlinks Google provider for managed users | `users.manageNonAdmin` |
| `updateUserProfileByAdmin` | Admin-safe profile updates without direct privilege writes | `users.manageNonAdmin` |
| `deleteUserAccount` | Deletes non-admin user accounts through server-side validation | `users.manageNonAdmin` |

## Notifications

| Function | Description | Access |
|:---|:---|:---|
| `onNotificationCreated` | Firestore trigger that sends immediate FCM push and defers future scheduled notifications | Auto |
| `deliverScheduledNotifications` | Scheduled function that delivers due FCM notifications and makes local/in-app scheduled notifications visible every 5 minutes | Auto |
| `resyncUserNotificationSchedules` | Rebuilds future reminders and returns local scheduling instructions | Self; other users require Super Admin or an admin with `appointments.view`, `analytics.view`, or `reports.view` |
| `sendDoctorDailyReports` | Scheduled function that creates doctor daily summary notifications at each doctor's configured time | Auto |
| `searchAdminNotificationRecipients` | Searches valid notification recipients without broad client-side user listing | `notifications.send` |
| `previewAdminNotificationRecipients` | Counts recipients before sending an admin notification | `notifications.send` |
| `sendAdminNotification` | Creates audited in-app notifications for selected patient/doctor audiences | `notifications.send` |
| `sendTopicNotification` | Disabled legacy topic sender; directs admins to audited in-app notifications | `notifications.send` |

## Super Admin Governance

| Function | Description | Access |
|:---|:---|:---|
| `createAdminAccount` | Creates admin account with default permission map | Super Admin |
| `changeAdminRole` | Promotes/demotes admin role (excluding superAdmin assignment) | Super Admin |
| `setAdminActiveStatus` | Activates/deactivates admin accounts | Super Admin |
| `resetAdminPassword` | Resets an admin password (8-character minimum enforced) | Super Admin |
| `deleteAdminAccount` | Deletes Auth and user records; Auth errors stop cleanup unless the account is already absent. Profile-photo cleanup is best effort | Super Admin |
| `forceSignOutUser` | Revokes user refresh tokens and clears FCM tokens; does not deactivate the account | Super Admin |
| `setAdminPermissions` | Updates granular admin permission map | Super Admin |
| `assignSuperAdminSlot` | Assigns `primary`/`backup` super admin slot with transaction checks | Super Admin |
| `rotateSuperAdminSlot` | Rotates slot holder atomically (demote + promote) | Super Admin |
| `listAdminAuditLogs` | Returns filtered governance audit logs | Super Admin |

## Medical documents and analytics

| Function | Description | Access |
|:---|:---|:---|
| `uploadMedicalDocument` | Creates a document or stages replacement bytes; enforces upload budgets | Authorized caller for the target document/patient |
| `readMedicalDocument` | HTTP GET with a Firebase bearer token; checks current access and returns bytes with no-store headers | Owner, doctor with current patient access, Super Admin, or admin with `reports.view` / `appointments.view`; legacy patient-only files remain owner-only |
| `deleteMedicalDocument` | Removes document metadata after transactional authorization | Document author with current access to the target patient |
| `replaceMedicalDocument` | Begins, finishes, or cancels an authorized replacement | Document author with current access to the target patient |
| `queueMedicalDocumentCleanup` | Queues cleanup when document references change | Auto: Firestore trigger |
| `cleanDocumentReplacements` | Processes bounded replacement cleanup | Auto: hourly job |
| `getAppointmentAnalytics` | Returns dashboard counts or paged aggregate analytics without raw clinical records | Super Admin or admin with `analytics.view`, `appointments.view`, or `reports.view` |

Medical-file operations live in `medicalFiles.ts` and `documentReplacement.ts`. Direct client Storage access to medical-file paths is denied; profile photos use separate rules.

## AI Appointment Assistant

| Function | Description | Access |
|:---|:---|:---|
| `sendAssistantMessage` | Interprets patient scheduling requests in English, Arabic, and Kurdish Sorani using `gemini-3.5-flash-lite`, matches real doctor schedules in Baghdad time, returns expiring selectable offers (10-minute expiry), and saves bounded history | Active `student`, `staff`, or regular `admin` with Google link |
| `getAssistantHistory` | Returns the patient's saved conversation history and revalidates active offer availability against real doctor schedules without calling Gemini; resumes prior search preferences if offers have expired | Active `student`, `staff`, or regular `admin` with Google link |
| `clearAssistantHistory` | Clears conversation history and active offers immediately; increments revision and changes generation ID to prevent in-flight completions from resurrecting chat | Active `student`, `staff`, or regular `admin` with Google link |
| `confirmAssistantAppointment` | Explicitly confirms and books an assistant offer (`confirmed: true` required) through canonical appointment creation with slot locking and transaction idempotency | Active `student`, `staff`, or regular `admin` with Google link |

Doctors and Super Admins are excluded from all four assistant endpoints, including confirmation retries. This restriction does not change their separate appointment-management permissions.

### Callable API Contracts

#### 1. `sendAssistantMessage`
- **Request Data**:
  ```typescript
  interface SendAssistantMessageData {
      message: string;             // Patient's natural language message (1-500 chars)
      locale?: string;             // Client locale: 'en' | 'ar' | 'ckb' | 'ku' (normalized to 'en' | 'ar' | 'ckb', default: 'en')
      clientRequestId?: string;    // Client UUID for turn deduplication and idempotency (<= 128 chars)
  }
  ```
- **Response Result**:
  ```typescript
  interface SendAssistantMessageResult {
      success: boolean;            // RPC status flag
      status: 'ready' | 'clarify' | 'out_of_scope' | 'throttled' | 'daily_limit' | 'unavailable' | 'disabled' | 'cancelled';
      reasonCode: string;          // Programmatic reason (e.g. 'offers_available', 'unknown_department', 'missing_date', 'catalog_overflow')
      message: string;             // Server-controlled localized message (never arbitrary model prose)
      replyLanguage: 'en' | 'ar' | 'ckb';
      offers: AssistantOffer[];    // Up to 6 real expiring offers from doctor weekly schedules
      revision: number;            // Current chat revision number
      resetAt?: string | null;     // ISO UTC timestamp when daily quota resets (Pacific Midnight)
  }
  ```

#### 2. `getAssistantHistory`
- **Request Data**: `{}` (empty object)
- **Response Result**:
  ```typescript
  interface GetAssistantHistoryResult {
      success: boolean;
      messages: AssistantChatMessage[]; // Bounded history (<= 20 messages, retained <= 7 days)
      offers: AssistantOffer[];         // Refreshed active offers (marked isAvailable: false if expired/taken)
      revision: number;                 // Monotonically increasing revision counter
      resetAt?: string | null;          // Pacific midnight ISO string if project daily quota is exhausted
      status?: AssistantMessageStatus | null; // Restored status (e.g. 'daily_limit')
      reasonCode?: string | null;       // Restored reason code (e.g. 'upstream_daily_limit_reached')
  }
  ```

#### 3. `clearAssistantHistory`
- **Request Data**: `{}` (empty object)
- **Response Result**:
  ```typescript
  interface ClearAssistantHistoryResult {
      success: boolean;
      message: string;
  }
  ```

#### 4. `confirmAssistantAppointment`
- **Request Data**:
  ```typescript
  interface ConfirmAssistantAppointmentData {
      offerId: string;             // Offer UUID from chat document (<= 128 chars)
      confirmed: boolean;          // MUST be explicitly true (rejects false, null, or undefined)
      notes?: string;              // Optional patient booking notes (<= 1000 chars)
  }
  ```
- **Response Result**:
  ```typescript
  interface ConfirmAssistantAppointmentResult {
      success: boolean;
      appointmentId: string;       // Created or existing appointment document ID
      bookingReference: string;    // 8-character uppercase booking reference
      qrCode: string;              // QR check-in token
      isExisting?: boolean;        // Present and true if recovered via idempotency (lost-response retry)
  }
  ```

#### 5. `getDoctorDayAvailability`
- **Request Data**:
  ```typescript
  interface GetDoctorDayAvailabilityData {
      doctorId: string;            // Target doctor document ID (<= 128 chars)
      date: string;                // Target calendar date in YYYY-MM-DD format
  }
  ```
- **Response Result**:
  ```typescript
  interface GetDoctorDayAvailabilityResult {
      success: boolean;
      doctorId: string;
      appointmentDate: string;     // YYYY-MM-DD
      doctorName: string;          // Trusted doctor name
      department: string;          // Trusted department key
      slots: Array<{
          timeSlot: string;        // 'HH:MM - HH:MM' or 'HH:MM'
          startTime: string;       // 'HH:MM'
          endTime: string;         // 'HH:MM'
          isAvailable: boolean;    // true if slot is within working hours, in future, and free of overlap/locks
      }>;
  }
  ```

### Unified Booking Architecture, Day Coordination & Slot Locking
1. **Single Source of Truth (`createAppointmentCore`)**:
   - Both ordinary booking (`createAppointment`) and AI assistant confirmation (`confirmAssistantAppointment`) execute through the unified `createAppointmentCore` transaction.
   - For assistant confirmation, the idempotency key is derived deterministically from `sha256(patientId:offerId)`.
   - **Receipt Check First**: The transaction inspects `appointment_idempotency` before running any date or availability checks. This guarantees that network retries after offer consumption or session expiration return the original committed booking receipt idempotently.
   - **Active Department & Doctor Verification**: The transaction verifies that the doctor's department is actively registered and `isActive: true` inside the transaction before any writes.
   - **Atomic Offer Consumption**: The confirmed offer is removed from the active `offers` array, its ID is removed from messages' `offerIds`, and the session revision is advanced (`revision + 1`).

2. **Day Coordination Record (`appointment_day_coordination`)**:
   - Serializes concurrent booking attempts for the same doctor and date using `appointment_day_coordination/{doctorId}_{dateKey}`.
   - Prevents race conditions between appointments with different start times that overlap in duration (e.g. 09:00-10:00 vs 09:30-10:00).
   - Direct client read and write access is strictly denied in `firestore.rules` (`allow read, write: if false;`).

3. **Schedule Duration Resolution vs Legacy Start-Only Entries**:
   - For new bookings, slot ranges are parsed and validated against the doctor's weekly schedule.
   - For legacy start-only records (e.g. `09:00`), `doesAppointmentOverlapSlot` resolves the actual duration from the doctor's schedule on that day instead of assuming a default 30 minutes.

4. **Slot Lock Release Safety**:
   - When rescheduling or cancelling, only the slot lock owned by the specific appointment (`appointmentId`) is released. Other concurrent locks are never clobbered or released.

5. **Post-Commit Notification Strategy**:
   - Post-commit notification failures log structured error events without patient identifiers.
   - The booking receipt is returned reliably to the caller even if the notification gateway fails, and `notificationDeliveryError: true` is set on the appointment document.

### Required Firestore Composite Indexes
The following indexes must be deployed via `firestore.indexes.json`:
1. `appointments`:
   - `doctorId` ASC + `appointmentDate` ASC (Collection scope; supports bounded date range queries)
2. `appointment_slot_locks`:
   - `doctorId` ASC + `appointmentDateKey` ASC (Collection scope; supports date lock lookups)

### Assistant configuration and retention

The server selects `gemini-3.5-flash-lite`; clients cannot select the model. Live generation requires both `AI_ASSISTANT_ENABLED=true` and `AI_PRIVACY_RELEASE_GATE_ACCEPTED=true`, plus the `GEMINI_API_KEY` Secret Manager binding. Unset flags disable live generation. These defaults do not describe the current deployed environment.

`getAssistantHistory` uses the same readiness gate and secret binding as sends, but does not call Gemini or consume generation quota. Message language detection is independent of the interface locale, which supplies a fallback.

Free-text messages are not automatically redacted. Review provider terms and the intended data use before enabling live generation. See [assistant configuration and local testing](FIREBASE_SETUP.md#ai-assistant-configuration--privacy-gate) for setup and [Firestore TTL](FIREBASE_SETUP.md#firestore-ttl-time-to-live-policies) for physical cleanup. Logical expiry does not prove that expired documents have been deleted.

Offline synthetic mode requires the isolated `demo-uhc-test` emulator configuration. It tests scheduling and booking behavior without contacting Gemini; it does not establish live AI quality or latency.

## Check-in behavior

`confirmAppointmentCheckIn` validates the QR value and the window from 5 minutes before to 10 minutes after the appointment. Appointment times are interpreted in Baghdad time by the backend helper.

After five failed scans, the doctor UI offers manual verification of patient and booking details within the check-in window. It submits the appointment's QR value through `confirmAppointmentCheckIn`, using the same authorized transaction as camera scanning. Direct confirmation through `updateAppointmentStatus` remains rejected. The failed-scan threshold is a UI eligibility rule, not a server-enforced scan counter.

## Rules and troubleshooting

Firestore rules block direct client writes to appointment records and privileged user fields such as `role`, `isActive`, `superAdminType`, and `adminPermissions`. Storage rules constrain upload paths, content types, and file sizes.

Protected operations using `getCallerUserDoc()` also require a linked Google provider in Firebase Authentication. If an operation returns `failed-precondition` with "Link your Google account before accessing UHC services.", link Google in the app and retry. Signing in with email/password alone does not satisfy this check.

For `permission-denied`, confirm the caller, target relationship, active status, and exact permission key. For `already-exists` during booking, refresh the available slots before selecting another time. Changing permissions does not remove status or confirmation-window restrictions.
