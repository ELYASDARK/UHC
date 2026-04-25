# Super Admin + Admin RBAC Implementation - Task Tracker

## Phase 0 - Data Model & Enum Foundation ✅ (Approved)
- [x] Update `UserRole` enum to add `superAdmin`
- [x] Extend `UserModel` with `isSuperAdmin`, `superAdminType`, `adminPermissions`
- [x] Add `isAdminOrSuperAdmin` convenience getter
- [x] Add `hasPermission(key)` method with superAdmin bypass
- [x] Update `displayRole` for Super Admin
- [x] Backward-compatible defaults in `fromFirestore`
- [x] Create `AdminPermissions` model (with presets: fullAccess, readOnly, operations)
- [x] Create `AdminAuditLog` model (with AuditAction enum)
- [x] Update `copyWith` and `toFirestore` for new fields
- [x] Fix `_getRoleColor` switch in `user_management_screen.dart`
- [x] Exclude `superAdmin` from filter/role-change UIs
- [x] Exclude `superAdmin` from user form dialog role dropdown
- [x] Update `profile_screen.dart` admin check to `isAdminOrSuperAdmin`
- [x] Make super admin rows view-only in user management

## Phase 1 - Cloud Functions Security Layer ✅ (Approved)
- [x] Shared guards: `requireAuth`, `getCallerUserDoc`, `requireSuperAdmin`, `requirePermission` (with superAdmin bypass), `writeAdminAuditLog`
- [x] Update 6 existing function guards → `isAdminOrSuperAdmin`
- [x] Integrate guards into existing functions (createDoctorAccount uses `requirePermission`)
- [x] `createAdminAccount` - Super Admin only
- [x] `changeAdminRole` - Super Admin only
- [x] `setAdminActiveStatus` - Super Admin only, admin targets only
- [x] `resetAdminPassword` - Super Admin only, admin targets only
- [x] `deleteAdminAccount` - Super Admin only, admin targets only
- [x] `forceSignOutUser` - Super Admin only
- [x] `setAdminPermissions` - Super Admin only
- [x] `assignSuperAdminSlot` - transactional, max-2 + slot-switch guard
- [x] `rotateSuperAdminSlot` - transactional, blocks dual-slot replacement
- [x] `listAdminAuditLogs` - Super Admin only, filterable
- [x] `createUserAccount` restricted to student/staff only
- [x] Dart-side `AdminGovernanceService` with all methods
- **Non-blocking notes for later hardening:**
  - `forceSignOutUser` accepts any target user (not limited to admin)
  - `changeAdminRole` allows non-admin transitions (e.g., student→staff)

## Phase 2 - Firestore Rules Hardening ✅
- [x] Restrict `users/{userId}` owner writes (block `role`, `isActive`, etc.)
- [x] Add `admin_audit_logs` rules
- [x] Preserve doctor/patient self-service flows
- [x] **Review Fix 1** (High): Migrate admin UI direct writes → Cloud Functions (`_toggleUserStatus`, `_changeUserRole`, form dialog `role` field)
- [x] **Review Fix 2** (Medium): Enforce actor-role UI gating (admins: non-admin targets only, superAdmins: non-superAdmin)
- [x] **Review Fix 3** (Medium): Apply `requirePermission` to `updateDoctorEmail`, `deleteDoctorAccount`, `resetDoctorPassword`, `sendTopicNotification`
- [x] **Review Fix 4** (Medium): Add composite indexes for `admin_audit_logs` (targetUid+createdAt, action+createdAt)
- [x] **Review Fix 5** (Low): Differentiate operations preset (disable `reportsExport`, `notificationsSend`)
- [x] **Open Q1**: Fix self-registration — allow owner create with `role == 'student'` only

## Phase 3 - Super Admin Shell & Routing ✅
- [x] Update `AppNavigator` routing for `superAdmin` role
- [x] Create `SuperAdminShell` with `IndexedStack` (5 tabs: Dashboard, Admins, Permissions, Audit, Profile)

## Phase 4 - Super Admin Feature Screens ✅
- [x] Dashboard screen (reuses existing `AdminDashboardScreen`)
- [x] Admin Control screen (3 tabs: Admins list, Permissions matrix, Slot management)
- [x] Audit Logs screen (filterable, color-coded, pull-to-refresh)
- [x] Permissions surfaced as a top-level shell tab (routes to `AdminControlScreen(initialTab: 1)`)
- [x] Profile screen (reuses shared `ProfileScreen`)

## Phase 5 - Refactor Existing Admin Screens to RBAC + Functions ✅
- [x] Admin Dashboard: gate quick-action cards by `hasPermission()` (doctors.view, users.view, analytics.view, reports.view, departments.view)
- [x] Doctor Management: gate FAB (`Add Doctor`), popup edit/toggle/delete, bottom sheet edit/toggle buttons behind `doctors.manage`
- [x] Department Management: gate FAB (`Add Department`), popup edit/toggle/delete behind `departments.manage`
- [x] User Management: gate FAB (`Add User`), popup edit/toggle/role behind `users.manageNonAdmin`
- [x] Reports Screen: gate Generate Report button behind `reports.export`
- [x] Super Admin Dashboard: governance KPIs (admin counts, slot health, risk, audit)
- [x] Admin Control: view-only mode for non-SuperAdmin, initialTab routing
- [x] Fix unnecessary cast warning in admin_control_screen.dart
- [x] All screens use `hasPermission()` which auto-bypasses for superAdmin role

## Phase 6 - Localization (English only) ✅
- [x] Add ~100 governance/RBAC strings to `app_en.arb`
- [x] Strings cover: Super Admin dashboard, admin control, audit logs, permissions, slots, RBAC gating messages, CRUD labels
- [x] `flutter gen-l10n` passes (88 untranslated in ar/ku — expected, English-only scope)
- [x] Parameterized string: `inactiveAdminWarning` with `{count}` placeholder

## Phase 7 - Firestore Indexes ✅
- [x] Verified existing 3 audit log indexes (actorUid, targetUid, action × createdAt)
- [x] Added `users` composite: `role` + `isActive` (dashboard admin status queries)
- [x] Added `users` composite: `role` + `superAdminType` (slot management queries)
- [x] All 13 total indexes declared in `firestore.indexes.json`

## Phase 8 - Bootstrap & Migration Runbook ✅
- [x] Created `docs/SUPER_ADMIN_BOOTSTRAP_RUNBOOK.md`
- [x] Sections: Prerequisites, Deploy Backend, Bootstrap First Super Admin, Verification Checklist, Ongoing Operations, Rollback Procedure, Security Checklist
- [x] Architecture diagram and full Permissions Reference table
- [x] Step-by-step Firestore Console instructions for chicken-and-egg bootstrap
