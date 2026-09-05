# Super Admin Governance Bootstrap Runbook

> Version: 2.2
>
> Reviewed against the source: 2026-09-05
>
> Audience: project owner, Firebase owner, deployment operator

[Back to README](../README.md#super-admin-bootstrap) | [Firebase setup](FIREBASE_SETUP.md) | [Cloud Functions reference](CLOUD_FUNCTIONS.md)

Run commands from the repository root unless a step changes directory. Source paths below are relative to that root. This guide covers initial setup, backup access, and ongoing governance, based on:

- `functions/src/admin.ts`
- `functions/src/shared/auth.ts`
- `lib/screens/super_admin/super_admin_shell.dart`
- `lib/screens/super_admin/admin_control_screen.dart`
- `firestore.rules`

---

## Table of Contents

1. [Current Governance Model](#1-current-governance-model)
2. [Prerequisites](#2-prerequisites)
3. [Deploy Firebase Backend](#3-deploy-firebase-backend)
4. [Bootstrap the First Super Admin](#4-bootstrap-the-first-super-admin)
5. [Create the Backup Super Admin](#5-create-the-backup-super-admin)
6. [Verify the System](#6-verify-the-system)
7. [Ongoing Operations](#7-ongoing-operations)
8. [Troubleshooting](#8-troubleshooting)
9. [Security Checklist](#9-security-checklist)
10. [Permissions Reference](#10-permissions-reference)

---

## 1. Current Governance Model

The app supports these user roles:

| Role | Purpose |
|---|---|
| `student` | Patient account |
| `staff` | Staff patient account |
| `doctor` | Doctor dashboard account |
| `admin` | Operational admin with granular permissions |
| `superAdmin` | Governance owner; bypasses granular admin permissions |

The Super Admin system has two named slots:

| Slot | Field value | Purpose |
|---|---|---|
| Primary | `superAdminType: "primary"` | Main governance owner |
| Backup | `superAdminType: "backup"` | Recovery/governance backup |

Governance rules:

- Keep one primary and one backup Super Admin. Normal slot operations check occupancy; manual Firebase Console edits bypass those checks.
- Super Admin bypasses the granular admin permission map. Authentication, active-account, Google-linking, and operation-specific checks still apply.
- Normal admins require explicit `adminPermissions`.
- New admins created from Super Admin governance start with the read-only permission preset.
- Governance actions are performed through Cloud Functions, not direct client writes.
- Firestore blocks direct client writes to `role`, `isActive`, `superAdminType`, and `adminPermissions`.
- Governance Cloud Functions require an active Super Admin caller.
- Governance Cloud Functions also require the caller's Firebase Auth account to have a linked Google provider.

The current Super Admin shell has 4 main tabs:

| Main tab | Purpose |
|---|---|
| Dashboard | Governance KPIs and slot health |
| Admins | Admin Control panel |
| Audit Logs | Governance audit trail |
| Profile | Super Admin profile/settings |

Inside the Admin Control panel, there are 3 tabs:

| Admin Control tab | Purpose |
|---|---|
| Admins | Create admins, activate/deactivate, change role, reset password, delete, force sign-out |
| Permissions | Edit admin permission maps and apply presets |
| Slots | Assign or rotate primary/backup Super Admin slots |

---

## 2. Prerequisites

| Requirement | Details |
|---|---|
| Firebase CLI | `npm install -g firebase-tools@15.19.0`, matching the setup guide |
| Node.js | Node.js 22, matching `firebase.json` |
| Flutter SDK | Meet the [locked Flutter and Dart requirements](../README.md#prerequisites), then run `flutter pub get` |
| Firebase login | `firebase login` with an account authorized to deploy to the target Firebase project |
| Firebase project | Select with `firebase use --add` or `firebase use <project-id>` |
| Functions dependencies | From the root, `npm --prefix functions ci` |
| Functions build | From the root, `npm --prefix functions run build` must pass |
| FlutterFire CLI and Firebase services | Complete [Firebase setup](FIREBASE_SETUP.md), including authentication providers and billing for Functions |
| Google-linked bootstrap user | An active app account with a linked Google provider; this is separate from the CLI deployment account |

If the app is being handed to a new owner, connect the repo to the new Firebase project first:

```bash
firebase login
firebase use --add
flutterfire configure --project=<firebase-project-id> --platforms=android,ios,web --out=lib/firebase_options.dart
```

Then confirm these files point to the new Firebase project:

- `.firebaserc`
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `ios/Runner/Info.plist` (Google OAuth client ID and callback URL scheme)
- `web/firebase-messaging-sw.js`

Complete the [platform configuration checks](FIREBASE_SETUP.md#platform-configuration), including Android signing fingerprints and iOS sign-in configuration, before testing the bootstrap account.

---

## 3. Deploy Firebase Backend

Build Functions first:

```bash
npm --prefix functions ci
npm --prefix functions run build
```

Optionally validate before deploying:

```bash
firebase deploy --only 'firestore:rules,firestore:indexes,storage,functions' --dry-run
```

The dry run does not deploy resources, but it may enable required APIs on the selected project.

Then deploy Firestore rules, indexes, Storage rules, and Functions:

```bash
firebase deploy --only 'firestore:rules,firestore:indexes,storage,functions'
```

Current governance callable functions:

| Function | Access | Purpose |
|---|---|---|
| `createAdminAccount` | Super Admin only | Create admin Auth/user records |
| `changeAdminRole` | Super Admin only | Change non-super-admin user role to `admin`, `student`, or `staff` |
| `setAdminActiveStatus` | Super Admin only | Activate/deactivate admin accounts |
| `resetAdminPassword` | Super Admin only | Reset admin password, minimum 8 characters |
| `deleteAdminAccount` | Super Admin only | Delete the Auth account and user record; attempts profile-photo cleanup |
| `forceSignOutUser` | Super Admin only | Revoke refresh tokens and clear FCM tokens |
| `setAdminPermissions` | Super Admin only | Replace an admin permission map |
| `assignSuperAdminSlot` | Super Admin only | Assign an empty primary/backup slot |
| `rotateSuperAdminSlot` | Super Admin only | Replace an existing primary/backup slot holder |
| `listAdminAuditLogs` | Super Admin only | Query governance audit logs |

Current governance-related indexes:

| Collection | Fields | Purpose |
|---|---|---|
| `admin_audit_logs` | `actorUid` ASC, `createdAt` DESC | Filter audit logs by actor |
| `admin_audit_logs` | `targetUid` ASC, `createdAt` DESC | Filter audit logs by target |
| `admin_audit_logs` | `action` ASC, `createdAt` DESC | Filter audit logs by action |
| `users` | `role` ASC, `isActive` ASC | Admin status queries |
| `users` | `role` ASC, `superAdminType` ASC | Super Admin slot queries |

Index creation can take several minutes. Check Firebase Console -> Firestore -> Indexes if queries fail immediately after deploy.

---

## 4. Bootstrap the First Super Admin

At the very beginning there is no Super Admin, so the first account must be promoted manually in Firebase Console.

### Step 1: Choose the Bootstrap Account

Choose the person who will become the Primary Super Admin. Use a dedicated owner account or an existing student, staff, or admin account. Slot assignment changes the user role; it does not migrate a doctor record or its appointments.

The account must have:

- A Firebase Authentication user.
- A matching Firestore document at `users/{uid}`.
- `isActive: true`.
- A linked Google account.

The linked Google account matters because `getCallerUserDoc()` checks Firebase Auth provider data and requires `google.com` before allowing UHC Cloud Function access.

### Step 2: Create or Prepare the User

Recommended path:

1. Open the app.
2. Register with email/password, or sign in to an existing active UHC account. A new Google-only sign-in does not create a UHC profile.
3. Complete any initial password change, then link Google from that account.
4. Confirm the user appears in Firebase Console -> Authentication -> Users.
5. Confirm the Firestore document exists at `users/{uid}`.

If app sign-in has not created the profile, first check the `bootstrapSelfUserDocument` deployment and error. For manual recovery, create `users/{uid}` in Firebase Console using the baseline below. Use the Firebase Authentication UID as the document ID; do not overwrite an existing profile.

| Field | Value | Type |
|---|---|---|
| `email` | bootstrap email | string |
| `fullName` | owner/admin name | string |
| `role` | `student` temporarily | string |
| `isActive` | `true` | boolean |
| `googleEmail` | linked Google email, if already linked | string or null |
| `createdAt` | current timestamp | timestamp |
| `updatedAt` | current timestamp | timestamp |
| `language` | `en` | string |
| `themeMode` | `system` | string |
| `requiresInitialPasswordChange` | `false` after any required initial password change | boolean |
| `notificationSettings` | `{ email: true, push: true, sms: false }` | map |

### Step 3: Get the User UID

Find the UID in:

- Firebase Console -> Authentication -> Users
- or Firestore document ID under `users/{uid}`

### Step 4: Promote the User in Firestore

Before manual promotion, inspect all `users` documents with `role: "superAdmin"`. If a primary already exists, use the normal slot workflow instead of creating a second primary. Otherwise, open `users/{uid}` in Firebase Console and set:

| Field | Value | Type |
|---|---|---|
| `role` | `superAdmin` | string |
| `superAdminType` | `primary` | string |
| `isActive` | `true` | boolean |
| `googleEmail` | the linked Google email | string |
| `requiresInitialPasswordChange` | `false` after any required initial password change | boolean |
| `updatedAt` | current timestamp | timestamp |

The `adminPermissions` map is not needed while the account is Super Admin. If you remove it, assign an explicit preset if the account later becomes an admin. Manual Console edits do not create app governance audit entries; record the bootstrap UID, project, and date in your handoff notes.

### Step 5: Verify Login

1. Fully sign out of the app.
2. Sign in again as the bootstrap account.
3. If prompted to link Google, complete the Google link flow.
4. Confirm the app opens the Super Admin shell.
5. Confirm the main tabs are Dashboard, Admins, Audit Logs, and Profile.
6. Open Admins -> Slots and confirm the Primary slot contains the expected UID.
7. Open Audit Logs or create a test admin to verify backend governance access. Seeing the shell alone does not prove the caller passes the backend checks.

---

## 5. Create the Backup Super Admin

Always create a backup Super Admin after the primary account is working.

Recommended path from the app:

1. Sign in as the Primary Super Admin.
2. Open Admins.
3. Tap the add-admin button.
4. Create a new admin with an email, name, and password of at least 8 characters.
5. Have the backup owner sign in, link Google, and confirm the account is active before assigning the slot.
6. Open Admins -> Slots.
7. Assign the Backup slot using the backup user's UID or email.
8. Have the backup owner sign in separately and open Audit Logs to verify backend access.

Alternative path:

1. Prepare an existing active user/admin with a linked Google account.
2. Open Admins -> Slots.
3. Assign the Backup slot using UID or email.

The slot assignment function promotes the target to `role: "superAdmin"` and sets `superAdminType: "backup"`. It does not activate the target or check its linked Google provider. Verify both beforehand, then have the backup owner sign out, sign in again, and confirm governance access.

---

## 6. Verify the System

Use test accounts and test data for account creation, password resets, and permission checks. Verify slot changes during the planned backup setup or replacement.

### Super Admin Verification

- [ ] Super Admin Dashboard loads.
- [ ] Admins tab loads the Admin Control panel.
- [ ] Admin Control has Admins, Permissions, and Slots tabs.
- [ ] Primary slot appears as filled.
- [ ] Backup slot appears as filled after setup.
- [ ] Audit Logs tab loads.
- [ ] Super Admin can create an admin account.
- [ ] Super Admin can set admin permissions.
- [ ] Super Admin can force sign-out a test user.
- [ ] Normal admin row actions reject deleting or changing the role of a Super Admin.

### Admin RBAC Verification

Create a test admin. By default, it should receive the read-only preset:

- [ ] `users.view: true`
- [ ] `doctors.view: true`
- [ ] `departments.view: true`
- [ ] `analytics.view: true`
- [ ] `reports.view: true`
- [ ] manage/export/send permissions disabled

Sign in as the test admin, link Google, and verify:

- [ ] Can view allowed screens.
- [ ] Cannot create/edit/delete doctors without `doctors.manage`.
- [ ] Cannot create/edit/delete departments without `departments.manage`.
- [ ] Cannot create/edit/delete users without `users.manageNonAdmin`.
- [ ] Cannot export reports without `reports.export`.
- [ ] Cannot send admin notifications without `notifications.send`.

Then apply the Full preset and verify those operations become available. The Off preset disables all granular admin permissions; it does not deactivate the account.

### Audit Verification

Perform several governance actions:

- Create admin.
- Update permissions.
- Reset password.
- Force sign-out.
- Assign or rotate slot.

Then open Audit Logs and verify:

- [ ] Actions appear with actor UID/name.
- [ ] Target UID/name appears.
- [ ] Action type is correct.
- [ ] Created timestamp is correct.
- [ ] Filters for actor, target, action, and date work.

---

## 7. Ongoing Operations

### Add a New Admin

1. Sign in as Super Admin.
2. Open Admins.
3. Tap the add-admin button.
4. Enter email, full name, optional profile details, and password.
5. The admin starts with read-only permissions.
6. Have the admin sign in and link Google.
7. Open Permissions to apply Ops or Full if needed.

Creating an admin installs the Read-Only preset. Promoting an existing user with Change Role does not initialize permissions; apply an explicit preset after promotion. A missing permission map now displays no access, matching the backend. Verify the saved values after applying a preset.

### Change Admin Permissions

1. Open Admins -> Permissions.
2. Select the admin.
3. Toggle individual permissions or choose Full, Ops, Read-Only, or Off.
4. Each toggle or preset saves immediately. Wait for success, then reopen the permissions dialog to confirm the saved values; there is no separate Save button.

The backend requires every known permission key with a boolean value and rejects unknown keys. The UI sends the complete map.

### Deactivate an Admin

1. Open Admins.
2. Use the admin row menu.
3. Choose Deactivate.

The backend sets `isActive: false`, revokes sessions, and clears FCM tokens.

### Force Sign-Out

1. Open Admins.
2. Use the admin row menu.
3. Choose Force Sign-Out.

This revokes refresh tokens and clears FCM tokens. It does not deactivate the account, unlink Google, or guarantee that an already open screen closes immediately. Use Deactivate when an admin must lose backend access.

If the Auth user is already missing, the callable still clears the stored FCM tokens and returns "Auth user not found; local tokens were cleared." Verify the target account state before treating that result as a session-revocation test.

### Rotate a Super Admin Slot

1. Prepare the replacement user/admin.
2. Make sure the replacement account is active and Google-linked.
3. Open Admins -> Slots.
4. Choose Rotate on Primary or Backup.
5. Enter the replacement UID or email.
6. Have the replacement sign in and open Audit Logs. Confirm the slot UID, the former holder's admin role, and both rotation audit entries.

Rotation changes both roles in one transaction: the old holder becomes `admin` without `superAdminType`, and the replacement becomes `superAdmin` in the selected slot.

Rotation preserves the old holder's existing `adminPermissions` and does not revoke sessions or clear FCM tokens. Review that account's permissions afterward, or deactivate it if access should end. If the old holder has no permission map, assign an explicit preset before expecting admin operations to work.

The replacement's active status and Google provider are not checked by the rotation function. Confirm them before rotating. When replacing your own slot, perform the change from the other working Super Admin account so you retain access to finish verification.

### Reset a password or delete an admin

Password reset targets `admin` accounts only. It updates the Auth password without setting `requiresInitialPasswordChange`. Arrange for the owner to change a temporary password after signing in; the admin creation and reset callables do not enforce that step.

Admin deletion removes the Auth account before removing `users/{uid}`. If Auth deletion fails, the callable reports an error and leaves the profile and photos untouched. An already absent Auth account is treated as deleted, allowing profile cleanup to continue. Profile-photo cleanup remains best effort.

Confirm the UID is absent from Authentication and Firestore after deletion. If a later step fails after Auth deletion, inspect the remaining profile before retrying; the operation spans separate services.

### Assign an Empty Super Admin Slot

1. Open Admins -> Slots.
2. Choose Assign for the empty slot.
3. Enter the target UID or email.

Use Assign for an empty slot and Rotate for an occupied slot. Confirm the target is active, Google-linked, and able to sign in before either operation.

---

## 8. Troubleshooting

### A governance action failed or timed out

Check the target account or slot before retrying. Several operations write account changes before writing their audit entry. A failed response can therefore follow a completed change, and slot rotation can leave only one of its two audit entries.

Compare the current role, slot UID, permission map, and Auth account with the intended result. Check Functions logs for the failed step. Retry only the missing operation; do not repeat a slot rotation or recreate an account solely because the UI reported an error.

### Primary or backup access is lost

If one Super Admin still works, sign in with that account and use Rotate to replace the inaccessible holder. Verify the replacement's active status and Google link first, then verify its governance access before ending the working session.

If neither holder can sign in, an authorized Firebase project owner must recover access through Firebase Authentication and inspect the matching `users/{uid}` profile. Check Auth account availability, linked providers, `isActive`, `role`, and `superAdminType`. The app has no recovery callable that bypasses these checks. Restore an existing holder when possible; do not repeat first-time bootstrap and create duplicate slots. Record manual repairs, then verify both slots and both owners' backend access.

### "Link your Google account before accessing UHC services."

Cause:

- The caller's Firebase Auth user does not have a `google.com` provider.

Fix:

1. Sign in to the app.
2. Link Google from the account/profile flow.
3. Confirm Firebase Console -> Authentication -> Users shows Google as a provider.
4. Confirm the app syncs `users/{uid}.googleEmail`. Editing this field manually does not link a Google provider in Firebase Authentication.

### "Only Super Admins can perform this action."

Cause:

- `users/{callerUid}.role` is not `superAdmin`, or the wrong Firebase project is selected.

Fix:

1. Confirm `.firebaserc` points to the intended project.
2. Confirm `lib/firebase_options.dart` points to the intended project.
3. Confirm the signed-in user's Firestore document has `role: "superAdmin"`.

### Slot already occupied

Cause:

- You used Assign on a filled slot.

Fix:

- Use Rotate instead.

The error identifies the occupied slot, for example: "The primary slot is already occupied. Use rotateSuperAdminSlot to replace."

### "Replacement already holds a Super Admin slot."

Cause:

- The replacement user is already primary or backup.

Fix:

- Choose a replacement who does not already hold either slot. Do not manually demote a working slot holder just to swap slots.

### Admin can view UI but actions fail

Cause:

- Missing explicit permission in `adminPermissions`, or the admin is not Google-linked.

Fix:

1. Open Super Admin -> Admins -> Permissions.
2. Confirm the required permission is true.
3. Confirm the admin is active and Google-linked.

---

## 9. Security Checklist

Before production handoff, verify:

- [ ] `.firebaserc` points to the intended Firebase project.
- [ ] `lib/firebase_options.dart`, `google-services.json`, and `GoogleService-Info.plist` point to the intended Firebase project.
- [ ] iOS OAuth IDs, Android signing fingerprints, and Web messaging configuration match the intended project.
- [ ] Firestore rules are deployed.
- [ ] Storage rules are deployed.
- [ ] Firestore indexes are deployed and built.
- [ ] Functions build and deploy successfully.
- [ ] Direct client writes to `role`, `isActive`, `superAdminType`, and `adminPermissions` are blocked.
- [ ] `admin_audit_logs` read is Super Admin only.
- [ ] `admin_audit_logs` write is denied to clients.
- [ ] Governance functions require `requireSuperAdmin()`.
- [ ] Admin permission functions reject unknown permission keys.
- [ ] Primary Super Admin slot is filled.
- [ ] Backup Super Admin slot is filled.
- [ ] Both Super Admin accounts are active and Google-linked, and each owner has separately verified backend governance access.
- [ ] No service account JSON/private key is included in the source or release handoff.
- [ ] No real Firebase Auth user export, Firestore export, Storage export, or patient data is included unless authorized.

---

## 10. Permissions Reference

Super Admin bypasses the granular admin permission map, while caller and operation-specific checks still apply. Admin accounts require explicit permission values.

| Permission key | Description | Read-Only | Ops | Full |
|---|---|:---:|:---:|:---:|
| `users.view` | View user list and details | yes | yes | yes |
| `users.manageNonAdmin` | Create/edit/activate/deactivate non-admin users | no | yes | yes |
| `doctors.view` | View doctor profiles and schedules | yes | yes | yes |
| `doctors.manage` | Create/edit/delete doctor accounts and schedules | no | yes | yes |
| `departments.view` | View departments | yes | yes | yes |
| `departments.manage` | Create/edit/delete departments | no | yes | yes |
| `appointments.view` | Backend appointment-read permission | no | no | no |
| `appointments.manage` | Backend appointment-mutation permission | no | no | no |
| `analytics.view` | View analytics/dashboard data | yes | yes | yes |
| `reports.view` | View reports screen/data | yes | yes | yes |
| `reports.export` | Export reports | no | no | yes |
| `notifications.send` | Send admin notifications | no | no | yes |

The Off preset sets every key to `false`. The other preset values are listed above.

UI behavior:

- `appointments.view` and `appointments.manage` remain in the backend permission schema.
- The Super Admin permissions UI hides appointment permissions for now and sends both as `false`.
- Appointment reads for admin workflows are currently covered by permissions such as `analytics.view` and `reports.view` in Firestore rules.
