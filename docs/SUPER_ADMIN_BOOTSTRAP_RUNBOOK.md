# Super Admin Governance Bootstrap Runbook

> Version: 2.0  
> Last Updated: 2026-06-03  
> Audience: project owner, Firebase owner, deployment operator

This runbook explains how to connect and bootstrap the current Super Admin governance system. It matches the current implementation in:

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
| `superAdmin` | Governance owner with full access |

The Super Admin system uses a strict two-slot model:

| Slot | Field value | Purpose |
|---|---|---|
| Primary | `superAdminType: "primary"` | Main governance owner |
| Backup | `superAdminType: "backup"` | Recovery/governance backup |

Important current rules:

- There should be one primary and one backup Super Admin.
- Super Admin bypasses granular admin permissions in the app and backend.
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
| Firebase CLI | `npm install -g firebase-tools` |
| Node.js | Node.js 22, matching `firebase.json` |
| Flutter SDK | Flutter 3.x with `flutter pub get` passing |
| Firebase login | `firebase login` with a project-owner Google account |
| Firebase project | Select with `firebase use --add` or `firebase use <project-id>` |
| Functions dependencies | `cd functions && npm install` |
| Functions build | `cd functions && npm run build` must pass |
| Google-linked bootstrap user | The first Super Admin must be able to link/sign in with Google |

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
- `web/firebase-messaging-sw.js`

---

## 3. Deploy Firebase Backend

Build Functions first:

```bash
cd functions
npm install
npm run build
cd ..
```

Deploy Firestore rules, indexes, Storage rules, and Functions:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

Optional dry run before a real deploy:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage,functions --dry-run
```

Current governance callable functions:

| Function | Access | Purpose |
|---|---|---|
| `createAdminAccount` | Super Admin only | Create admin Auth/user records |
| `changeAdminRole` | Super Admin only | Change non-super-admin user role to `admin`, `student`, or `staff` |
| `setAdminActiveStatus` | Super Admin only | Activate/deactivate admin accounts |
| `resetAdminPassword` | Super Admin only | Reset admin password, minimum 8 characters |
| `deleteAdminAccount` | Super Admin only | Delete admin Auth/user records |
| `forceSignOutUser` | Super Admin only | Revoke sessions and clear FCM tokens |
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

Choose the person who will become the Primary Super Admin.

The account must have:

- A Firebase Authentication user.
- A matching Firestore document at `users/{uid}`.
- `isActive: true`.
- A linked Google account.

The linked Google account matters because `getCallerUserDoc()` checks Firebase Auth provider data and requires `google.com` before allowing UHC Cloud Function access.

### Step 2: Create or Prepare the User

Recommended path:

1. Open the app.
2. Create/sign in with the bootstrap account.
3. Link Google from the app if the account was created with email/password.
4. Confirm the user appears in Firebase Console -> Authentication -> Users.
5. Confirm the Firestore document exists at `users/{uid}`.

If the Firestore user document does not exist, create it manually with these minimum fields:

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
| `requiresInitialPasswordChange` | `false` | boolean |
| `notificationSettings` | `{ email: true, push: true, sms: false }` | map |

### Step 3: Get the User UID

Find the UID in:

- Firebase Console -> Authentication -> Users
- or Firestore document ID under `users/{uid}`

### Step 4: Promote the User in Firestore

Open Firebase Console -> Firestore -> `users/{uid}` and set:

| Field | Value | Type |
|---|---|---|
| `role` | `superAdmin` | string |
| `superAdminType` | `primary` | string |
| `isActive` | `true` | boolean |
| `googleEmail` | the linked Google email | string |
| `requiresInitialPasswordChange` | `false` | boolean |
| `updatedAt` | current timestamp | timestamp |

Remove `adminPermissions` from this Super Admin document if it exists. Super Admin bypasses permissions, so this map is not needed.

### Step 5: Verify Login

1. Fully sign out of the app.
2. Sign in again as the bootstrap account.
3. If prompted to link Google, complete the Google link flow.
4. Confirm the app opens the Super Admin shell.
5. Confirm the main tabs are Dashboard, Admins, Audit Logs, and Profile.
6. Open Admins -> Slots and confirm the Primary slot is filled.

---

## 5. Create the Backup Super Admin

Always create a backup Super Admin after the primary account is working.

Recommended path from the app:

1. Sign in as the Primary Super Admin.
2. Open Admins.
3. Tap the add-admin button.
4. Create a new admin with an email, name, and password of at least 8 characters.
5. Ask the backup owner to sign in and link Google.
6. Open Admins -> Slots.
7. Assign the Backup slot using the backup user's UID or email.

Alternative path:

1. Prepare an existing active user/admin with a linked Google account.
2. Open Admins -> Slots.
3. Assign the Backup slot using UID or email.

The slot assignment function promotes the target to `role: "superAdmin"` and sets `superAdminType: "backup"`.

---

## 6. Verify the System

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
- [ ] Super Admin cannot accidentally delete or demote another Super Admin from normal admin row actions.

### Admin RBAC Verification

Create a test admin. By default, it should receive the read-only preset:

- [ ] `users.view: true`
- [ ] `doctors.view: true`
- [ ] `departments.view: true`
- [ ] `analytics.view: true`
- [ ] `reports.view: true`
- [ ] manage/export/send permissions disabled

Sign in as the test admin and verify:

- [ ] Can view allowed screens.
- [ ] Cannot create/edit/delete doctors without `doctors.manage`.
- [ ] Cannot create/edit/delete departments without `departments.manage`.
- [ ] Cannot create/edit/delete users without `users.manageNonAdmin`.
- [ ] Cannot export reports without `reports.export`.
- [ ] Cannot send admin notifications without `notifications.send`.

Then apply the Full Access preset and verify those operations become available.

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
6. Open Permissions to apply Operations or Full Access if needed.

### Change Admin Permissions

1. Open Admins -> Permissions.
2. Select the admin.
3. Toggle individual permissions or apply a preset.
4. Save changes.

The backend sanitizes the permission payload and rejects unknown permission keys.

### Deactivate an Admin

1. Open Admins.
2. Use the admin row menu.
3. Choose Deactivate.

The backend sets `isActive: false`, revokes sessions, and clears FCM tokens.

### Force Sign-Out

1. Open Admins.
2. Use the admin row menu.
3. Choose Force Sign-Out.

This revokes refresh tokens and clears FCM tokens. The user may need to reopen or refresh the app before the local session fully reflects the server-side revocation.

### Rotate a Super Admin Slot

1. Prepare the replacement user/admin.
2. Make sure the replacement account is active and Google-linked.
3. Open Admins -> Slots.
4. Choose Rotate on Primary or Backup.
5. Enter the replacement UID or email.

Rotation demotes the old slot holder to `admin`, removes `superAdminType`, and promotes the replacement to `superAdmin`.

### Assign an Empty Super Admin Slot

1. Open Admins -> Slots.
2. Choose Assign for the empty slot.
3. Enter the target UID or email.

Use Assign only for an empty slot. Use Rotate when the slot already has a holder.

---

## 8. Troubleshooting

### "Link your Google account before accessing UHC services."

Cause:

- The caller's Firebase Auth user does not have a `google.com` provider.

Fix:

1. Sign in to the app.
2. Link Google from the account/profile flow.
3. Confirm Firebase Console -> Authentication -> Users shows Google as a provider.
4. Confirm `users/{uid}.googleEmail` is set.

### "Only Super Admins can perform this action."

Cause:

- `users/{callerUid}.role` is not `superAdmin`, or the wrong Firebase project is selected.

Fix:

1. Confirm `.firebaserc` points to the intended project.
2. Confirm `lib/firebase_options.dart` points to the intended project.
3. Confirm the signed-in user's Firestore document has `role: "superAdmin"`.

### "The primary/backup slot is already occupied."

Cause:

- You used Assign on a filled slot.

Fix:

- Use Rotate instead.

### "Replacement already holds a Super Admin slot."

Cause:

- The replacement user is already primary or backup.

Fix:

- Choose a non-Super-Admin replacement, or manually repair slots in Firebase Console if the system is already inconsistent.

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
- [ ] Both Super Admin accounts are active and Google-linked.
- [ ] No service account JSON/private key is included in the CD/source handoff.
- [ ] No real Firebase Auth user export, Firestore export, Storage export, or patient data is included unless authorized.

---

## 10. Permissions Reference

Super Admin bypasses all permission checks. Admin accounts require explicit permission values.

| Permission key | Description | Read Only | Operations | Full Access |
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

Current UI note:

- `appointments.view` and `appointments.manage` remain in the backend permission schema.
- The Super Admin permissions UI hides appointment permissions for now and sends both as `false`.
- Appointment reads for admin workflows are currently covered by permissions such as `analytics.view` and `reports.view` in Firestore rules.

