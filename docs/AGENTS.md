# Repository Guidelines

## Project Structure & Module Organization
- `lib/` contains the Flutter app code: `core/` (theme, constants, shared widgets), `data/` (models/repositories), `providers/`, `services/`, `screens/`, and `l10n/`.
- `functions/` contains Firebase Cloud Functions (TypeScript entrypoint at `functions/src/index.ts`).
- `test/` contains Flutter tests (`widget_test.dart` today; add new tests here).
- `assets/` stores images, animations, and icons declared in `pubspec.yaml`.
- Platform folders (`android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`) hold build-specific configs.
- `docs/` is for implementation plans and supporting documentation.

## Build, Test, and Development Commands
- `flutter pub get` installs Dart/Flutter dependencies.
- `flutter gen-l10n` regenerates localization classes from `lib/l10n/*.arb`.
- `flutter run` launches the app locally.
- `flutter analyze` runs static analysis using `flutter_lints`.
- `flutter test` runs the test suite.
- `flutter build apk --release` (or `appbundle`, `ios`, `web`) builds production artifacts.
- `cd functions && npm install` installs Functions dependencies.
- `cd functions && npm run build|serve|deploy` compiles, emulates, or deploys Cloud Functions.

## Coding Style & Naming Conventions
- Follow `analysis_options.yaml` (`include: package:flutter_lints/flutter.yaml`).
- Use standard Dart formatting: 2-space indentation and `dart format .` before PRs.
- Naming: files `snake_case.dart`, classes/enums `PascalCase`, methods/variables `camelCase`.
- Keep role-specific UI under `lib/screens/patient`, `lib/screens/doctor`, and `lib/screens/admin`.

## Testing Guidelines
- Use `flutter_test` with files named `*_test.dart` in `test/`.
- Prefer widget tests for UI flows and provider/service tests for business logic.
- No coverage threshold is currently enforced; add regression tests for changed behavior.
- CI (`.github/workflows/dart.yml`) runs `flutter gen-l10n`, `flutter analyze`, and `flutter test` on PRs to `main`.

## Commit & Pull Request Guidelines
- Git history mostly follows Conventional Commits (`feat:`, `chore:`, `docs:`); keep using that style.
- Write concise, imperative commit subjects (example: `feat: add doctor schedule validation`).
- PRs should include: change summary, linked issue/plan, and local verification steps run.
- For UI updates, attach screenshots from `screenshots/` or new captures.

## Security & Configuration Tips
- Firebase settings live in `firebase.json`, `firestore.rules`, and platform config files.
- Do not commit service-account credentials or other private keys.
- When changing access patterns, update `firestore.rules` and `firestore.indexes.json` together.
