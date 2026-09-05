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
| `createAppointment` | Creates a booking for the caller; validates a selected doctor's availability and acquires its slot lock | Self |
| `rescheduleAppointment` | Moves an active booking to a future time and updates slot locks atomically | Patient / assigned doctor / appointment admin |
| `cancelAppointment` | Cancels the appointment and releases its slot lock | Patient / assigned doctor / appointment admin |
| `updateAppointmentStatus` | Updates non-confirmation status; rejects `confirmed`, requires confirmed status before completion and pending status before no-show | Assigned doctor / appointment admin |
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

## Check-in behavior

`confirmAppointmentCheckIn` validates the QR value and the window from 5 minutes before to 10 minutes after the appointment. Appointment times are interpreted in Baghdad time by the backend helper.

The doctor UI still exposes manual confirmation after five failed scans. That action calls `updateAppointmentStatus` with `confirmed`, which the backend rejects. It is not a working fallback in this checkout; use QR check-in. Resolving the mismatch requires an application change, not a permission adjustment.

## Rules and troubleshooting

Firestore rules block direct client writes to appointment records and privileged user fields such as `role`, `isActive`, `superAdminType`, and `adminPermissions`. Storage rules constrain upload paths, content types, and file sizes.

Protected operations using `getCallerUserDoc()` also require a linked Google provider in Firebase Authentication. If an operation returns `failed-precondition` with "Link your Google account before accessing UHC services.", link Google in the app and retry. Signing in with email/password alone does not satisfy this check.

For `permission-denied`, confirm the caller, target relationship, active status, and exact permission key. For `already-exists` during booking, refresh the available slots before selecting another time. Changing permissions does not remove status or confirmation-window restrictions.
