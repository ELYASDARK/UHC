# AGENTS.md — UHC (University Health Center)

## Project Overview

Flutter/Dart healthcare appointment booking app with Firebase backend.
Dart SDK ^3.5.0, Provider (ChangeNotifier) state management, Firestore + Auth + Cloud Functions (TypeScript/Node.js 22).
Localization: English, Arabic, Kurdish via ARB files. No code generation (no freezed/json_serializable).

## Build / Run / Test

```bash
flutter pub get                          # Install dependencies
flutter gen-l10n                         # Generate l10n (MUST run before analyze/build)
flutter analyze                          # Static analysis
flutter test                             # Run all tests
flutter test test/widget_test.dart       # Run single test file
flutter test --name "test name here"     # Run single test by name
dart format .                            # Format code
dart format --set-exit-if-changed .      # Format check (CI)
flutter run                              # Debug run
flutter build apk --release              # Release APK

# Cloud Functions (from functions/ directory)
npm install && npm run build             # Install + compile TS
npm run serve                            # Local emulator
```

**CI** (`.github/workflows/dart.yml`): `pub get` -> `gen-l10n` -> `analyze` -> `test` on push/PR to `main`.

## Project Structure

```
lib/
  main.dart                 # Entry point, 7 ChangeNotifierProviders, AppNavigator state machine
  firebase_options.dart     # Auto-generated — NEVER edit
  core/
    constants/              # AppColors, AppStrings, AppAssets (private constructor utility classes)
    theme/                  # AppTheme — Material 3 light/dark (Poppins headings, Roboto body)
    utils/                  # Locale utilities, dynamic content translation maps
    widgets/                # PrimaryButton, CustomTextField, GlassmorphicCard, skeletons
  data/
    models/                 # 5 models: User, Appointment, Doctor, Department, Notification
    repositories/           # Firestore CRUD — one per collection
  providers/                # 7 ChangeNotifiers: auth, theme, locale, appointment, notification, doctor, doctor_appointment
  services/                 # Firebase SDK wrappers (AuthService, FCMService, etc.)
  screens/                  # Screens grouped by feature (auth/, home/, booking/, doctor/, admin/)
  l10n/                     # ARB files (app_en.arb, app_ar.arb, app_ku.arb) + generated
functions/src/index.ts      # 5 admin-only callable Cloud Functions (Gen2)
firestore.rules             # Security rules with role-based access
```

## Code Style

### Formatting
- `dart format` default settings. **Trailing commas** everywhere. **Single quotes** only.

### Imports (3 groups, no blank lines between)
1. `dart:` core libraries
2. `package:` dependencies
3. Relative project imports (`'../services/...'`) — never `package:uhc/...`

### Naming

| Element            | Convention                            | Example                              |
|--------------------|---------------------------------------|--------------------------------------|
| Files              | `snake_case`                          | `auth_provider.dart`                 |
| Classes            | `PascalCase`                          | `AuthProvider`, `AppointmentModel`   |
| Enums              | `PascalCase` name, `camelCase` values | `enum UserRole { student, doctor }`  |
| Variables/fields   | `camelCase`, explicit types preferred | `final String id;`                   |
| Private members    | `_` prefix                            | `_authService`, `_handleError()`     |
| Constants          | `static const camelCase`              | `static const Color primary = ...`   |
| Widget builders    | `_build` prefix                       | `_buildHeader()`                     |
| Constants classes  | Private constructor                   | `class AppColors { AppColors._(); }` |

### Types
- Explicit type annotations on fields and method signatures. `final` without type OK for obvious locals.
- Always annotate return types. Nullable: `String?`, fallbacks with `??`.
- `const` constructors on StatelessWidgets. `const` children wherever possible.

## Key Patterns

### Screen Lifecycle
- `StatefulWidget`. Load data in `initState` via `addPostFrameCallback`.
- **Always check `mounted`** before `setState` after any `await`.
- **Always dispose** controllers/subscriptions. `super.dispose()` last.
- Dark mode: `final isDark = Theme.of(context).brightness == Brightness.dark;`
- Break large `build()` into `_buildXxx()` methods.

### Navigation
- No router package. `AppNavigator` state machine: splash -> onboarding -> auth -> role shell.
- `UserRole.doctor` -> `DoctorShell`, others -> `MainShell`. Both use `IndexedStack`.
- Screens receive navigation callbacks (`VoidCallback?`) — no direct `Navigator.push` from children.

### Provider Pattern
```dart
class XxxProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  // public getters, no public setters

  Future<bool> doAction() async {
    _isLoading = true; _error = null; notifyListeners();
    try {
      // await service call
      return true;
    } catch (e) {
      _error = e.toString(); return false;
    } finally {
      _isLoading = false; notifyListeners();
    }
  }
}
```
Providers are independent — no cross-provider injection.

### Data Models
All `final` fields. `factory fromFirestore(DocumentSnapshot)` with `??` fallbacks, `toFirestore()`, `copyWith(...)`. Enums at top of file.

### Firestore Repositories
- Single-field `.where()` + in-memory filtering (avoids composite indexes).
- Create: `.add()` then `.update({'id': docRef.id})`.
- Error: `catch (e) { debugPrint(...); return []; }`.

### Error Handling

| Layer        | Pattern                                                          |
|--------------|------------------------------------------------------------------|
| Services     | Catch `FirebaseAuthException`, map to user strings, rethrow      |
| Providers    | `catch (e)` -> set `_error` -> `notifyListeners()` -> return `false` |
| Repositories | `catch (e)` -> `debugPrint(...)` -> return `[]` or `null`        |
| Screens      | Check `isLoading`/`error` inline, show `SnackBar` on failure     |

### Localization
- Strings in ARB files (`lib/l10n/`). Access: `AppLocalizations.of(context)!.key`.
- Run `flutter gen-l10n` after any ARB change.

### Cloud Functions (TypeScript)
- Admin-only: verify `context.auth` + Firestore role check.
- Gen2 `onCall`, typed `CallableRequest<T>`, throw `HttpsError`.
- Strict TS: `noImplicitReturns`, `noUnusedLocals`, `strict`.

## Never Edit Manually

- `lib/firebase_options.dart` — generated by FlutterFire CLI
- `lib/l10n/app_localizations*.dart` — generated by `flutter gen-l10n`
