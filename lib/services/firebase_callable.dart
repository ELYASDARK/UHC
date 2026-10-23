import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../core/config/emulator_config.dart';
import 'emulator_callable_client.dart';

Future<dynamic> invokeFirebaseCallable(
  FirebaseFunctions functions,
  String functionName,
  Map<String, dynamic> parameters, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (EmulatorConfig.isEmulatorEnabled &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android) {
    // The Android callable SDK requests an un-emulated Instance ID token.
    return EmulatorCallableClient(
      projectId: functions.app.options.projectId,
      host: EmulatorConfig.loopbackHost,
      enabled: EmulatorConfig.isEmulatorEnabled,
      isRelease: kReleaseMode,
      getIdToken: () async => FirebaseAuth.instanceFor(app: functions.app)
          .currentUser
          ?.getIdToken(),
    ).call(functionName, parameters, timeout: timeout);
  }

  final result = await functions
      .httpsCallable(functionName,
          options: HttpsCallableOptions(timeout: timeout))
      .call<dynamic>(parameters);
  return result.data;
}
