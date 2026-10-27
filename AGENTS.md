# Repository Guidelines

## Project structure and module organization

UHC is a Flutter healthcare appointment app backed by Firebase. `lib/screens/` contains patient, doctor, admin, and super-admin interfaces. Keep state in `lib/providers/`, data models and repositories in `lib/data/`, integrations in `lib/services/`, and shared UI in `lib/core/`.

`functions/src/` contains TypeScript Cloud Functions; `functions/lib/` is compiled output. Flutter tests live in `test/`, backend tests in `functions/test/`, and driver scenarios in `test_driver/`. Assets belong in `assets/`; English, Arabic, and Kurdish localization resources live in `lib/l10n/`. See `docs/` for Firebase setup and backend references.

## Build, test, and development commands

Run from the repository root:

- `flutter pub get` and `npm --prefix functions ci`: install dependencies.
- `flutter run`: launch the app using configured Firebase services.
- `flutter analyze`: run the Dart analyzer and Flutter lints.
- `dart format lib test`: format Dart source and tests.
- `flutter test`: run Flutter unit and widget tests.
- `npm --prefix functions run build`: compile TypeScript with strict checks.
- `npm --prefix functions test`: compile and run backend unit tests.
- `npm --prefix functions run test:emulator`: run Firestore integration tests; requires Java 21 and the emulator JAR.
- `flutter build apk --debug`: compile an Android debug APK.

For isolated local development, follow `docs/FIREBASE_SETUP.md`, then run `flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true`.

## Coding style and naming conventions

Use two-space Dart indentation, `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Follow `analysis_options.yaml` and `flutter_lints`. Match existing TypeScript style, typically four-space indentation and single quotes. Edit localization ARB resources and run `flutter gen-l10n`; avoid editing generated output.

## Testing guidelines

Use `flutter_test` with `*_test.dart` files and Node's built-in test/assert APIs with `*.test.js` files. Add focused regression coverage for changed behavior, especially booking concurrency, authorization, and assistant quotas. No numeric coverage threshold is configured. CI runs Flutter analysis and tests; run relevant backend checks locally. Emulator integration tests reset only `demo-uhc-test`.

## Dart MCP and Android validation

Always discover and use the available Dart MCP tools for relevant Flutter/Dart development, analysis, testing, and runtime inspection. Android skills are available: consult and apply the relevant skills for Android work and validation, without limiting this guidance to particular skill names.

An Android emulator is installed on the user's PC. For Android UI changes, discover the installed emulators and launch a suitable one if none is running, then test the affected flows interactively. An empty connected-device list does not mean no emulator is installed. Use the project's isolated Firebase emulator setup and synthetic test data for checks that write data. Report the actual emulator, tools, checks, and results used. If Dart MCP or emulator testing is unavailable, explain the specific blocker and any fallback; do not present a build or widget test as completed device validation.

For every feature or bug fix exercised on the Android emulator, capture screenshots of the relevant verified states. Include before/after evidence when reproducing a visual bug, and a short recording or sequence for gestures and transitions that a still image cannot prove. Run the emulator headlessly unless the user requests a visible window. Save evidence locally under `build/qa/<date>-<task>/` with descriptive filenames and an `INDEX.md` mapping each issue to its screenshots, steps, expected result, actual result, device/API, theme and language. Use synthetic data in captures. Include the absolute evidence-folder and index paths in the final report and any authorized handoff so the user and reviewing thread can find them. Screenshots supplement assertions and functional tests; they do not prove backend correctness. If capture is blocked, record the blocker instead of marking the check passed And tell the user is blocked because of what we pass in it.

## Local reports, plans and sensitive information

- Save all agent-generated working documents in `docs/local-reports/`: reports, plans, timing notes, QA and QR testing reports, test results, bug investigation notes, fix summaries, rollout notes and security findings. These documents must remain local and ignored by Git. Never stage, commit, push, force-add or upload them to GitHub. Verify their ignore status before finishing a task.
- Keep screenshots, recordings, diagnostic logs and other test evidence in the already ignored `build/qa/<date>-<task>/` folder. Use synthetic accounts, patient data and QR payloads. Redact sensitive information before saving or sharing evidence. A task's evidence index may remain beside its captures.
- Never include passwords, private keys, service-account credentials, signing secrets, access/refresh tokens, real patient data or usable authentication/check-in QR payloads in reports, plans, logs, screenshots, fixtures, commits or chat output. Ignored folders are not secure secret storage. Keep privileged secrets out of client code, bundled assets and release APKs; use the project's approved secret storage and server-side access controls.
- If investigation reveals an exposed secret or sensitive record, describe the issue using redacted details and its location, without copying the value. Fix the exposure within the authorized scope and identify any required credential revocation or rotation. Do not claim that deleting a local copy removes it from Git history, published builds or prior uploads.
- Keep maintained setup and reference documentation in `docs/`. Keep application source changes and automated test code in their normal source folders, such as `lib/`, `functions/src/`, `test/` and `functions/test/`. Only the generated reports, results and evidence belong in the ignored folders. Source changes still require the user's authorization before committing or pushing, and must never contain secrets or real patient data.

## Commit and pull request guidelines

Use descriptive imperative commit subjects, such as `Fix booking concurrency and patient navigation`. PRs should explain the problem, resulting behavior, and checks performed; link relevant issues and include screenshots for UI changes.

## Security and agent instructions

Keep credentials and patient data out of commits and fixtures. Preserve server-side permission checks and transactional slot reservations. Keep agent changes local unless explicitly asked to commit, push, open a PR, or deploy. Answer in English unless another language is requested.
