# Super Admin Governance — Bootstrap & Migration Runbook

> **Version:** 1.0  
> **Last Updated:** 2026-04-25  
> **Audience:** Project owner / DevOps

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Deploy Backend (Cloud Functions + Rules + Indexes)](#2-deploy-backend)
3. [Bootstrap the First Super Admin](#3-bootstrap-first-super-admin)
4. [Verify the Governance System](#4-verify-governance-system)
5. [Ongoing Operations](#5-ongoing-operations)
6. [Rollback Procedure](#6-rollback-procedure)
7. [Security Checklist](#7-security-checklist)

---

## 1. Prerequisites

| Requirement | Details |
|---|---|
| **Firebase CLI** | `npm install -g firebase-tools` (v13+) |
| **Node.js** | v22+ (matches `runtime` in `firebase.json`) |
| **Authenticated** | `firebase login` with project-owner Google account |
| **Project** | `firebase use uhca-20800` (or your project ID) |
| **Functions build** | `cd functions && npm install && npm run build` must pass |
| **Flutter SDK** | v3.x with `flutter pub get` passing |

---

## 2. Deploy Backend

Deploy all three components in order. Each can be deployed independently but the full deploy ensures consistency.

### 2a. Deploy Firestore Indexes

```bash
firebase deploy --only firestore:indexes
```

> **Note:** Index creation is async. New composite indexes can take 5–15 minutes to build.  
> Monitor status in the [Firebase Console → Firestore → Indexes](https://console.firebase.google.com).

**New indexes added in this migration:**

| Collection | Fields | Purpose |
|---|---|---|
| `admin_audit_logs` | `actorUid` ASC + `createdAt` DESC | Filter logs by actor |
| `admin_audit_logs` | `targetUid` ASC + `createdAt` DESC | Filter logs by target |
| `admin_audit_logs` | `action` ASC + `createdAt` DESC | Filter logs by action type |
| `users` | `role` ASC + `isActive` ASC | Dashboard admin status queries |
| `users` | `role` ASC + `superAdminType` ASC | Slot management queries |

### 2b. Deploy Firestore Security Rules

```bash
firebase deploy --only firestore:rules
```

**Key rule changes:**
- `users/{userId}` — owner writes blocked for `role`, `isActive`, `superAdminType`, `adminPermissions`
- `admin_audit_logs` — read: superAdmin only; write: denied (Cloud Functions only)
- `departments` — write requires `departments.manage` permission
- `doctors` — write requires `doctors.manage` permission

### 2c. Deploy Cloud Functions

```bash
firebase deploy --only functions
```

**New callable functions deployed:**

| Function | Access | Purpose |
|---|---|---|
| `createAdminAccount` | Super Admin only | Create admin users |
| `changeAdminRole` | Super Admin only | Promote/demote admin roles |
| `setAdminActiveStatus` | Super Admin only | Activate/deactivate admins |
| `resetAdminPassword` | Super Admin only | Reset admin passwords |
| `deleteAdminAccount` | Super Admin only | Delete admin accounts |
| `forceSignOutUser` | Super Admin only | Force user sign-out |
| `setAdminPermissions` | Super Admin only | Set admin RBAC permissions |
| `assignSuperAdminSlot` | Super Admin only | Assign primary/backup slot |
| `rotateSuperAdminSlot` | Super Admin only | Rotate slot holder |
| `listAdminAuditLogs` | Super Admin only | Query audit logs |

### 2d. Full Deploy (all at once)

```bash
firebase deploy
```

---

## 3. Bootstrap the First Super Admin

Since the governance system requires a Super Admin to create admins, and there are no Super Admins at first, you need to manually bootstrap the initial one.

### Step 1: Identify the Bootstrap User

Choose the Google account that will become the **Primary Super Admin**. This user must already exist in Firebase Auth (i.e., they've signed into the app at least once).

### Step 2: Get the User's UID

Find the UID from the [Firebase Console → Authentication → Users](https://console.firebase.google.com) tab, or run:

```bash
# If you know the email:
firebase auth:export users.json --format=json
# Then search for the email in users.json
```

### Step 3: Set Super Admin Fields in Firestore

Open the [Firebase Console → Firestore](https://console.firebase.google.com) and navigate to:

```
users/{USER_UID}
```

Update the following fields:

| Field | Value | Type |
|---|---|---|
| `role` | `superAdmin` | string |
| `superAdminType` | `primary` | string |
| `isActive` | `true` | boolean |
| `adminPermissions` | *(leave empty or delete)* | — |

> **Why manual?** Security rules block client-side `role` writes. Admin SDK (used by Cloud Functions) bypasses rules, but the callable functions themselves require an existing Super Admin to authorize the request — creating a chicken-and-egg problem. The Firestore console uses the Admin SDK internally, so this bypass is safe.

### Step 4: Verify the Bootstrap

1. **Sign out** of the app completely
2. **Sign back in** with the bootstrap account
3. You should see the **Super Admin shell** (5-tab layout: Dashboard, Admins, Permissions, Audit, Profile)
4. Navigate to **Admin Control → Slots tab** — the Primary slot should show as filled

### Step 5: Create the Backup Super Admin (Recommended)

From the Super Admin Dashboard:
1. Go to **Admin Control**
2. Tap the **FAB (+)** to create a new admin account
3. Once created, go to the **Slots** tab
4. Assign the new admin as the **Backup** Super Admin

> ⚠️ **Best Practice:** Always maintain both Primary and Backup slots filled. The dashboard will show a risk warning if any slot is empty.

---

## 4. Verify the Governance System

After bootstrap, run through this verification checklist:

### 4a. Super Admin Capabilities

- [ ] Can see Super Admin Dashboard with KPIs
- [ ] Can create admin accounts via Admin Control → FAB
- [ ] Can set admin permissions via Permissions tab
- [ ] Can assign/rotate Super Admin slots
- [ ] Can view audit logs
- [ ] Can force sign-out users
- [ ] Can activate/deactivate admin accounts

### 4b. Admin RBAC Verification

1. Create a test admin account with **Read Only** preset
2. Sign in as that admin
3. Verify:
   - [ ] Cannot see FAB on Doctor Management screen
   - [ ] Cannot see FAB on Department Management screen
   - [ ] Cannot see FAB on User Management screen
   - [ ] Cannot click Generate Report on Reports screen
   - [ ] Can still browse and view data (read-only)

4. Change the test admin to **Full Access** preset
5. Verify:
   - [ ] Can see all FABs and mutation actions
   - [ ] Can add/edit/delete doctors, departments, users

### 4c. Audit Trail

1. Perform several governance actions (create admin, change role, etc.)
2. Navigate to **Audit Logs** screen
3. Verify:
   - [ ] All actions appear with correct actor/target
   - [ ] Filters (action type, target UID, actor UID, date range) work
   - [ ] Timestamps are displayed correctly

---

## 5. Ongoing Operations

### Adding a New Admin

1. Sign in as Super Admin
2. Go to **Admin Control** → tap **FAB (+)**
3. Enter email, name, and initial password
4. The new admin is created with the **Read Only** preset by default
5. Navigate to **Permissions** tab to customize their permissions

### Rotating a Super Admin Slot

1. Go to **Admin Control → Slots** tab
2. Identify the slot to rotate (Primary or Backup)
3. Provide the replacement user's UID
4. The old holder is demoted to `admin`, the new holder is promoted to `superAdmin`

### Deactivating an Admin

1. Go to **Admin Control → Admins** tab
2. Tap the admin's card → select **Deactivate**
3. The admin can no longer sign in (enforced at auth level)

### Viewing Governance Audit

1. Go to **Audit Logs** screen
2. Use the filter bar (action type, target, actor, date range)
3. All governance actions are permanently logged and immutable

---

## 6. Rollback Procedure

If issues arise after deployment:

### Quick Rollback (Rules Only)

```bash
# Revert to previous rules
git checkout HEAD~1 -- firestore.rules
firebase deploy --only firestore:rules
```

### Function Rollback

```bash
# Revert functions
git checkout HEAD~1 -- functions/src/index.ts
cd functions && npm run build
firebase deploy --only functions
```

### Full Rollback

```bash
git checkout HEAD~1 -- firestore.rules firestore.indexes.json functions/
cd functions && npm run build
firebase deploy
```

> ⚠️ **Index rollback:** Removing indexes from `firestore.indexes.json` and redeploying will delete them. This is safe but may cause queries to fail if the indexes are still needed by other code paths.

---

## 7. Security Checklist

Before considering the deployment production-ready, verify:

- [ ] **No direct client writes to sensitive fields** — `role`, `isActive`, `superAdminType`, `adminPermissions` are blocked by Firestore rules
- [ ] **All governance callables require Super Admin** — verified via `requireSuperAdmin()` guard
- [ ] **Audit logs are immutable** — `allow write: if false` in rules; only Cloud Functions (Admin SDK) can write
- [ ] **Max 2 Super Admin slots** — enforced transactionally in `assignSuperAdminSlot`
- [ ] **Slot rotation is atomic** — `rotateSuperAdminSlot` uses Firestore transactions
- [ ] **Admin can only manage non-admin users** — enforced in both UI (`canManageTarget`) and backend (`requirePermission`)
- [ ] **Permission presets differentiated** — `operations` preset blocks `reports.export` and `notifications.send`
- [ ] **Self-registration restricted** — `createUserAccount` only allows `student`/`staff` roles
- [ ] **Firebase Auth tokens** — consider setting custom claims for role in a future iteration for server-side token validation

---

## Architecture Reference

```
┌─────────────────────────────────────────────┐
│                  Flutter App                 │
│                                             │
│  ┌─────────┐  ┌──────────┐  ┌────────────┐ │
│  │ Patient  │  │  Admin   │  │Super Admin │ │
│  │  Shell   │  │  Shell   │  │   Shell    │ │
│  └─────────┘  └──────────┘  └────────────┘ │
│       │            │              │         │
│       │     ┌──────┴──────┐       │         │
│       │     │ AuthProvider │       │         │
│       │     │ hasPermission│       │         │
│       │     └──────┬──────┘       │         │
│       │            │              │         │
│       └────────────┴──────────────┘         │
│                    │                         │
│     ┌──────────────┴──────────────┐         │
│     │  AdminGovernanceService     │         │
│     │  (Cloud Function callables) │         │
│     └──────────────┬──────────────┘         │
└────────────────────┼────────────────────────┘
                     │ HTTPS
┌────────────────────┼────────────────────────┐
│           Cloud Functions (Gen2)             │
│                    │                         │
│  ┌─────────────────┴──────────────────────┐ │
│  │  Guards: requireAuth, requireSuperAdmin │ │
│  │  requirePermission, writeAuditLog       │ │
│  └─────────────────┬──────────────────────┘ │
│                    │ Admin SDK               │
│           ┌────────┴────────┐                │
│           │   Firestore     │                │
│           │  ┌───────────┐  │                │
│           │  │   users   │  │                │
│           │  │  doctors  │  │                │
│           │  │audit_logs │  │                │
│           │  └───────────┘  │                │
│           └─────────────────┘                │
└──────────────────────────────────────────────┘
```

---

## Permissions Reference

| Permission Key | Description | Full Access | Read Only | Operations |
|---|---|:---:|:---:|:---:|
| `doctors.view` | View doctor list | ✅ | ✅ | ✅ |
| `doctors.manage` | Add/edit/delete doctors | ✅ | ❌ | ✅ |
| `departments.view` | View departments | ✅ | ✅ | ✅ |
| `departments.manage` | Add/edit/delete departments | ✅ | ❌ | ✅ |
| `users.view` | View user list | ✅ | ✅ | ✅ |
| `users.manageNonAdmin` | Add/edit/delete non-admin users | ✅ | ❌ | ✅ |
| `appointments.view` | View all appointments | ✅ | ✅ | ✅ |
| `analytics.view` | View analytics dashboard | ✅ | ✅ | ✅ |
| `reports.view` | View reports page | ✅ | ✅ | ✅ |
| `reports.export` | Generate/export reports | ✅ | ❌ | ❌ |
| `notifications.view` | View notifications | ✅ | ✅ | ✅ |
| `notifications.send` | Send topic notifications | ✅ | ❌ | ❌ |

> **Super Admin** automatically bypasses all permission checks via `hasPermission()`.
