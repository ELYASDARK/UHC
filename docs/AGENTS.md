# AGENTS.md — UHC (University Health Center)

## Project Overview

Flutter/Dart healthcare app (appointment booking & reminders) with a Firebase backend.
Multi-platform: Android, iOS, macOS, Web, Windows. Firebase project ID: `uhca-20800`.

**Tech stack:** Flutter 3.x (Dart SDK ^3.5.0), Provider for state management,
Firestore + Firebase Auth + Cloud Functions (TypeScript on Node.js 22), ARB-based
localization (English, Arabic, Kurdish).

---

## Build / Run / Test Commands

### Flutter (frontend)

```bash
# Install dependencies
flutter pub get

# Generate localization files (MUST run before analyze or build)
flutter gen-l10n

# Static analysis (linter)
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Run a single test by name
flutter test --name "App should build without errors"

# Run tests with coverage
flutter test --coverage

# Build (debug)
flutter run

# Build (release APK)
flutter build apk --release

# Build (web)
flutter build web

# Format code (standard dart formatter)
dart format .

# Format check (dry run)
dart format --set-exit-if-changed .
```

### Cloud Functions (backend — run from `functions/` directory)

```bash
# Install dependencies
npm install

# Build (compile TypeScript)
npm run build        # runs: tsc

# Start local emulator
npm run serve        # runs: build + firebase emulators:start --only functions

# Deploy to Firebase
npm run deploy       # runs: firebase deploy --only functions

# View logs
npm run logs         # runs: firebase functions:log
```

### Firebase

```bash
# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Firestore indexes
firebase deploy --only firestore:indexes

# Deploy everything
firebase deploy
```

---

## Project Structure

```
lib/
  main.dart                 # Entry point, MultiProvider setup, AppNavigator state machine
  firebase_options.dart     # Auto-generated — do NOT edit manually
  core/
    constants/              # AppColors, AppStrings, AppAssets (private constructor utility classes)
    theme/                  # AppTheme — Material 3 light/dark themes (Poppins + Roboto)
    utils/                  # Locale utilities, dynamic content translation helpers
    widgets/                # Reusable widgets (buttons, cards, text fields, skeletons)
  data/
    models/                 # Immutable data models with fromFirestore/toFirestore/copyWith
    repositories/           # Firestore CRUD — one repository per collection
  providers/                # ChangeNotifier classes — one per domain area
  services/                 # Firebase SDK wrappers (Auth, FCM, Cloud Functions calls)
  screens/                  # UI screens grouped by feature area
  l10n/                     # ARB localization files (en, ar, ku) + generated files
functions/
  src/index.ts              # All Cloud Functions (5 admin-only callable functions)
firestore.rules             # Firestore security rules with role-based access
```

---

## Code Style Guidelines

### Formatting

- Use `dart format` with default settings (no custom line length).
- Always use **trailing commas** on multi-line argument/parameter lists.
- Use **single quotes** (`'...'`) for all strings. Never double quotes.

### Imports

Order imports in three groups (no blank lines between groups):
1. `dart:` core libraries (`dart:ui`, `dart:async`, `dart:convert`, etc.)
2. `package:` dependencies (`package:flutter/material.dart`, `package:provider/...`, etc.)
3. Relative project imports (`'../services/auth_service.dart'`, `'../../core/constants/...'`)

Always use **relative paths** for project-internal imports. Never `package:uhc/...`.

### Naming Conventions

| Element              | Convention    | Example                                    |
|----------------------|---------------|--------------------------------------------|
| Files                | `snake_case`  | `auth_provider.dart`, `appointment_model.dart` |
| Classes              | `PascalCase`  | `AuthProvider`, `AppointmentModel`         |
| Enums                | `PascalCase` name, `camelCase` values | `enum UserRole { student, staff, doctor, admin }` |
| Variables / fields   | `camelCase`   | `final String id;`, `bool _isLoading`      |
| Private members      | `_` prefix    | `_authService`, `_handleAuthException()`   |
| Constants            | `camelCase` static const | `static const Color primary = ...`  |
| Widget builders      | `_build` prefix | `_buildHeader()`, `_buildQuickActions()`  |

### Types

- Prefer **explicit type annotations** on class fields and method signatures.
- `final` without type is acceptable for locals when the type is obvious from the RHS.
- Always annotate return types on methods: `Future<bool>`, `Future<void>`, `List<T>`.
- Use full null safety: `String?` for nullable, `??` for fallback defaults.

### Const Usage

- Use `const` constructors on all StatelessWidgets and wherever applicable.
- Mark child widgets `const` when possible: `const SizedBox(height: 16)`, `const Icon(...)`.
- Utility/constants classes use a private constructor: `AppColors._()`.

### Widget Patterns

- Screens are typically `StatefulWidget` with data loading in `initState` + `addPostFrameCallback`.
- Break large `build()` methods into private `_buildXxx()` helper methods.
- Pass navigation actions as constructor callbacks (`VoidCallback?`, `Function(T)`) — no router library.
- Use `context.watch<Provider>()` or `Consumer<Provider>()` for reactive UI.
- Check dark mode via `Theme.of(context).brightness == Brightness.dark`.

### State Management (Provider)

All providers follow this pattern:
- Extend `ChangeNotifier` with private state fields + public getters.
- Expose `isLoading` and `error` state for every async operation.
- Call `notifyListeners()` after every state mutation.
- Use `try/catch/finally` — set `_isLoading = false` in `finally`.
- Return `bool` from mutating methods to indicate success/failure.
- Providers are independent (no cross-provider injection).

### Data Models

Every model must have:
- All `final` fields (immutable).
- `factory ModelName.fromFirestore(DocumentSnapshot doc)` with null-safe fallbacks.
- `Map<String, dynamic> toFirestore()` method.
- `copyWith(...)` method with all optional named parameters.
- Enums defined at the top of the model file.

### Error Handling

- **Services:** Catch `FirebaseAuthException`, map codes to user-friendly strings, rethrow.
- **Providers:** Catch generic `catch (e)`, set `_error = e.toString()`, `notifyListeners()`.
- **Repositories:** Catch `catch (e)`, `debugPrint('Error ...: $e')`, return empty list or `null`.
- **Screens:** Show loading/error states inline based on provider state.
- Report non-fatal errors via `FirebaseCrashlytics.instance.recordError(e, stack)`.

### Comments

- `///` doc comments on every class and public method.
- `//` inline comments for explanations and section dividers.
- No TODO comments in production code without a tracking reference.

### Localization

- User-facing strings go in ARB files (`lib/l10n/app_en.arb`, `app_ar.arb`, `app_ku.arb`).
- Access via `AppLocalizations.of(context)!.stringKey`.
- Dynamic content translations (department names, etc.) go in `localization_helper.dart`.
- Run `flutter gen-l10n` after modifying ARB files.

### Cloud Functions (TypeScript)

- All functions are admin-only — verify `context.auth` and check Firestore role.
- Use Gen2 `onCall` pattern with typed `CallableRequest<T>`.
- Define TypeScript interfaces for request data.
- Throw `HttpsError` with appropriate codes for client-facing errors.
- TypeScript strict mode is enabled (`noImplicitReturns`, `noUnusedLocals`, `strict`).

---

## CI Pipeline

GitHub Actions (`.github/workflows/dart.yml`) runs on push/PR to `main`:
1. `flutter pub get`
2. `flutter gen-l10n`
3. `flutter analyze`
4. `flutter test`

No Cloud Functions CI. No deployment automation in CI.
