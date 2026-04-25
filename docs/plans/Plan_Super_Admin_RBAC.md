# Super Admin + Admin RBAC Implementation Plan (UHC)

## Confirmed Product Decisions

- New role key in DB/API: `superAdmin`
- Super Admin availability: Web + Mobile (same app style)
- Super Admin model: exactly 2 accounts, strictly enforced (`primary` + `backup`)
- Existing admins stay admins; promotion to Super Admin is manual and explicit
- First Super Admin bootstrap: manual Firestore update
- Super Admin powers: full existing Admin powers + full admin-governance powers
- Admin-to-admin policy: Admin can view admins but cannot edit admins
- Admin governance actions required:
  - create admin
  - promote/demote admin role
  - activate/deactivate admin
  - reset admin password
  - delete admin
  - force sign-out (revoke sessions)
  - audit log visibility
- Security direction: move all sensitive admin operations to Cloud Functions
- Localization scope for this feature: English only now

---

## Current State Summary (from codebase review)

1. Roles currently supported in app model: `student`, `staff`, `doctor`, `admin` (`lib/data/models/user_model.dart`).
2. Routing currently has only one special shell: doctor. All non-doctor users use `MainShell` (`lib/main.dart`).
3. Admin entry is currently inside profile for users where `user.isAdmin == true` (`lib/screens/patient/profile/profile_screen.dart`).
4. Multiple admin-sensitive operations are currently done directly from client Firestore writes, including role/status updates in user management (`lib/screens/admin/users/user_management_screen.dart`).
5. Firestore rules currently allow owner write on full `users/{userId}` document, which is a privilege-escalation risk for `role` and other sensitive fields (`firestore.rules`).
6. Existing callable functions validate only `role == 'admin'` and do not include `superAdmin` yet (`functions/src/index.ts`).

---

## Target Architecture

### 1) Roles and hierarchy

- Keep existing roles: `student`, `staff`, `doctor`, `admin`
- Add new role: `superAdmin`
- Governance hierarchy:
  - `superAdmin`: can manage admins and perform all admin operations
  - `admin`: operational management only, no admin-governance edits

### 2) Super Admin strict two-account model

- Add `superAdminType` in user document for super admins only:
  - `primary`
  - `backup`
- Hard constraints enforced server-side in transactions:
  - max 2 users with role `superAdmin`
  - exactly one `primary`
  - exactly one `backup`
  - no API path that leaves system in invalid state

### 3) Admin RBAC (permissions)

- Add granular admin permissions object (stored under user document):
  - `users.view`, `users.manageNonAdmin`
  - `doctors.view`, `doctors.manage`
  - `departments.view`, `departments.manage`
  - `analytics.view`
  - `reports.view`, `reports.export`
  - `notifications.send`
- Super Admin bypasses admin permission checks (full access).
- Admin UI becomes permission-driven (what can be seen and changed).

### 4) Trust boundary

- Sensitive operations must be callable functions only.
- Client-side direct writes for sensitive fields/actions are removed.
- Firestore rules block privilege mutation by normal client updates.

---

## Implementation Phases

## Phase 0 - Data model and enum foundation

### App model updates

1. Update `UserRole` enum:
   - add `superAdmin`
2. Extend `UserModel`:
   - `bool get isSuperAdmin`
   - update `displayRole` for Super Admin
   - optional fields: `superAdminType`, `adminPermissions`
3. Backward compatibility:
   - safe defaults for missing fields in `fromFirestore`

### Suggested files

- `lib/data/models/user_model.dart`
- `lib/data/models/` (new permission/audit models if needed)

---

## Phase 1 - Cloud Functions security layer (primary backend work)

### Add shared guards in `functions/src/index.ts`

1. `requireAuth(context)`
2. `getCallerUserDoc(uid)`
3. `requireSuperAdmin(callerDoc)`
4. `requirePermission(...)` (with `superAdmin` bypass)
5. `writeAdminAuditLog(...)`

### New/updated callable functions

1. Admin governance (Super Admin only)
   - `createAdminAccount`
   - `changeAdminRole`
   - `setAdminActiveStatus`
   - `resetAdminPassword`
   - `deleteAdminAccount`
   - `forceSignOutUser` (session revocation)
   - `setAdminPermissions`
   - `listAdminAuditLogs`

2. Super Admin slot management (strict two)
   - `assignSuperAdminSlot(targetUid, slotType)` where `slotType in {primary, backup}`
     - MUST run inside Firestore `runTransaction(...)` (no plain `set()`/`update()` path)
     - transaction reads current super-admin documents + slot occupancy, validates constraints, then writes atomically
     - prevents race conditions where concurrent requests could create duplicate `primary` or duplicate `backup`
   - `rotateSuperAdminSlot(slotType, replacementUid)` (single transaction)

3. Existing function updates
   - update all admin-only guards to allow Super Admin where appropriate
   - keep governance functions as Super Admin-only

### Audit log schema

Create `admin_audit_logs/{logId}` with:

- `actorUid`, `actorRole`
- `targetUid`, `targetRoleBefore`, `targetRoleAfter`
- `action` (e.g. `admin.create`, `admin.demote`, `admin.forceSignOut`)
- `before` / `after` snapshots (sensitive fields only)
- `metadata` (reason, source screen)
- `createdAt`

---

## Phase 2 - Firestore rules hardening

### Required rule changes

1. `users/{userId}`
   - owner can update profile-safe fields only
   - owner cannot update `role`, `isActive`, `superAdminType`, `adminPermissions`
   - admin-governance mutations happen only through Cloud Functions (Admin SDK bypass)

2. `departments`, admin-sensitive collections
   - block sensitive client writes where moved to functions

3. `admin_audit_logs`
   - read: Super Admin (and optional admin with read permission if implemented)
   - write: deny from client

4. Keep doctor and patient flows working by preserving allowed self-service fields.

---

## Phase 3 - Super Admin shell and routing

### Routing

Update app navigator:

- if `role == superAdmin` -> `SuperAdminShell`
- else if `role == doctor` -> existing `DoctorShell`
- else -> existing `MainShell`

### New shell (same visual style as current app)

Create `lib/screens/super_admin/super_admin_shell.dart` with `IndexedStack`, same token style (`AppColors`, typography, spacing, cards) as existing shells.

### Proposed tabs

1. Dashboard
2. Admin Control
3. Permissions
4. Audit Logs
5. Profile

Notes:

- Keep design language aligned with current admin/doctor screens (no style redesign).
- Support responsive behavior for web and mobile.

---

## Phase 4 - Super Admin feature screens

### 1) Super Admin Dashboard

- KPIs: total admins, active admins, super-admin slot health (`primary`/`backup`), pending risk warnings
- Quick actions linking to Admin Control and Permission pages

### 2) Admin Control screen

- List all admin + super admin accounts
- Admin users can only view this list (no edit actions)
- Super Admin can:
  - create admin
  - change role
  - activate/deactivate
  - reset password
  - delete admin
  - force sign-out

### 3) Permission matrix screen

- Per-admin toggles for each permission module
- Preset templates (optional): `ReadOnlyAdmin`, `OperationsAdmin`, `FullAdmin`

### 4) Audit logs screen

- Filter by actor, target, action, date range
- Human-readable event cards using current app card style

### 5) Profile screen

- Reuse shared profile/settings patterns with role-specific options

---

## Phase 5 - Refactor existing admin screens to RBAC + functions

### User management

1. Replace direct writes for:
   - role change
   - activation toggle
2. Respect admin policy:
   - admin can view admin rows but no admin edits
   - superAdmin can edit admin rows

### Doctor and department management

1. Move sensitive write operations to callable functions
2. Gate actions by permissions (`doctors.manage`, `departments.manage`)
3. Keep list/read access under `view` permissions

### Reports/analytics/notifications

1. Gate visibility and actions by permission map
2. Keep superAdmin full access regardless of map

---

## Phase 6 - Localization strategy (English only now)

1. Add new strings only in `lib/l10n/app_en.arb`
2. Use English fallback for AR/KU for this phase
3. Keep key naming ready for later translation expansion

---

## Phase 7 - Firestore indexes

Add indexes for new governance queries:

1. `users`: `role + isActive`
2. `users`: `role + superAdminType`
3. `admin_audit_logs`: `actorUid + createdAt`
4. `admin_audit_logs`: `targetUid + createdAt`
5. `admin_audit_logs`: `action + createdAt`
6. `admin_audit_logs`: `createdAt` uses Firestore single-field indexing by default

---

## Phase 8 - Bootstrap and migration runbook

1. Manual bootstrap first Super Admin:
   - set `role: superAdmin`
   - set `superAdminType: primary`
2. Deploy backend functions + rules
3. App deploy with Super Admin shell
4. Use Super Admin UI to create/assign backup slot
5. Keep existing admins as admins
6. Assign admin permissions progressively

---

## Test Plan

### A) Security tests (must pass)

1. Student/staff/doctor cannot self-promote to admin/superAdmin
2. Admin cannot edit admin role/status/password/delete
3. Only Super Admin can run governance functions
4. Super Admin slot constraints always enforced (primary + backup only)

### B) Functional tests

1. Super Admin can perform every required admin-governance action
2. Admin has view-only admin section
3. Permission toggles immediately affect screen/action visibility
4. Audit logs are created for all governance actions

### C) UX tests

1. New screens match existing app style tokens/components
2. Web and mobile responsive behavior verified
3. Existing doctor/patient/admin flows remain stable

---

## Delivery Sequence (recommended)

1. Backend guards + governance functions + audit logs
2. Firestore rules hardening
3. Model/routing updates
4. Super Admin shell + core screens
5. Existing admin screen migration to functions + RBAC
6. Indexes + QA + rollout

---

## Acceptance Criteria

1. `superAdmin` role exists end-to-end (model, routing, backend, rules).
2. Exactly two Super Admin slots are enforced (`primary`, `backup`).
3. Super Admin can fully govern admin accounts.
4. Admin users can view admin accounts but cannot modify them.
5. Sensitive admin operations are callable-function based (not direct client writes).
6. All admin-governance actions are auditable.
7. UI remains visually consistent with current UHC style on web and mobile.
