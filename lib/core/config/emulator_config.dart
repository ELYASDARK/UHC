import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

/// Configuration and safety boundary for running against local Firebase Emulators.
///
/// STRICT SECURITY INVARIANTS:
/// 1. Only connects when `--dart-define=USE_FIREBASE_EMULATOR=true` is explicitly provided.
/// 2. Strictly REJECTS release mode builds (`kReleaseMode == true`).
/// 3. Strictly connects ONLY to the agreed demo project: `demo-uhc-test`.
/// 4. Rejects non-loopback hosts (only localhost, 127.0.0.1, ::1, or Android bridge 10.0.2.2 permitted).
/// 5. Supplies synthetic [FirebaseOptions] for `demo-uhc-test` BEFORE Firebase.initializeApp().
/// 6. Awaits all emulator connections (including `useAuthEmulator`).
/// 7. Prevents any connection to live project `uhca-20800` or production Firebase services.
class EmulatorConfig {
  static const bool isEmulatorEnabled = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
    defaultValue: false,
  );

  static const String emulatorHostOverride = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '',
  );

  /// The exact, agreed demo project identifier.
  static const String demoProjectId = 'demo-uhc-test';

  /// Synthetic options used exclusively for local demo emulator testing.
  /// Never touches live Google or Firebase backends.
  static const FirebaseOptions syntheticDemoOptions = FirebaseOptions(
    apiKey: 'fake-emulator-api-key-demo-only',
    appId: '1:000000000000:web:demo-uhc-test',
    messagingSenderId: '000000000000',
    projectId: demoProjectId,
    authDomain: '$demoProjectId.firebaseapp.com',
    storageBucket: '$demoProjectId.appspot.com',
  );

  /// Set of permitted loopback hosts and bridges.
  static const Set<String> allowedHosts = {
    'localhost',
    '127.0.0.1',
    '::1',
    '10.0.2.2',
  };

  /// Returns true if the host is a permitted local loopback or emulator bridge.
  static bool isAllowedHost(String host) {
    final normalized = host.trim().toLowerCase();
    return allowedHosts.contains(normalized);
  }

  /// Returns the validated local host for the current runtime platform.
  static String get loopbackHost {
    if (emulatorHostOverride.isNotEmpty) {
      final override = emulatorHostOverride.trim();
      if (!isAllowedHost(override)) {
        throw StateError(
          'Disallowed emulator host "$override". '
          'Only loopback (localhost, 127.0.0.1, ::1) or Android emulator host bridge (10.0.2.2) are permitted.',
        );
      }
      return override;
    }

    // Android emulator routes host machine's localhost through 10.0.2.2
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return '127.0.0.1';
  }

  /// Resolves the [FirebaseOptions] to use before calling `Firebase.initializeApp()`.
  ///
  /// When [USE_FIREBASE_EMULATOR] is true, returns synthetic options for [demoProjectId]
  /// and strictly fails if in release mode.
  /// When false, returns [defaultOptions] (production options for `uhca-20800`).
  static FirebaseOptions resolveFirebaseOptions({
    FirebaseOptions? defaultOptions,
    bool? isEmulatorOptIn,
    bool? isRelease,
  }) {
    final optedIn = isEmulatorOptIn ?? isEmulatorEnabled;
    final release = isRelease ?? kReleaseMode;

    if (optedIn) {
      if (release) {
        throw StateError(
          'Refusing to run emulators in release mode: USE_FIREBASE_EMULATOR is strictly prohibited in production/release builds.',
        );
      }
      return syntheticDemoOptions;
    }

    return defaultOptions ?? DefaultFirebaseOptions.currentPlatform;
  }

  /// Configures Firebase SDKs to connect to local emulators if opt-in is provided.
  /// Fails closed if project ID does not match [demoProjectId] or if release mode.
  static Future<void> configureEmulatorsIfOptedIn() async {
    if (!isEmulatorEnabled) {
      return;
    }

    if (kReleaseMode) {
      throw StateError(
        'Refusing to configure emulators in release mode: USE_FIREBASE_EMULATOR is strictly prohibited in production/release builds.',
      );
    }

    final projectId = Firebase.app().options.projectId;
    if (projectId != demoProjectId) {
      throw StateError(
        'Refusing to connect emulators: Project ID "$projectId" does not match required demo project "$demoProjectId". '
        'Mismatched or live configurations (e.g. uhca-20800) are strictly rejected to prevent accidental production connection.',
      );
    }

    final host = loopbackHost;
    if (!isAllowedHost(host)) {
      throw StateError('Refusing to connect emulators: Disallowed emulator host "$host".');
    }

    debugPrint('[EMULATOR] Connecting to Firebase emulators on $host for demo project $projectId');

    try {
      // NOTE: useAuthEmulator MUST be awaited
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
      FirebaseStorage.instance.useStorageEmulator(host, 9199);
      debugPrint('[EMULATOR] All Firebase emulators configured successfully.');
    } catch (e) {
      debugPrint('[EMULATOR] Error configuring emulators: $e');
      rethrow;
    }
  }
}
