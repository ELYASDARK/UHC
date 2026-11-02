import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/main.dart' as app;
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/screens/admin/dashboard/admin_dashboard_screen.dart';
import 'package:uhc/screens/admin/analytics/appointment_analytics_screen.dart';
import 'package:uhc/services/admin_statistics_service.dart';
import 'package:uhc/services/firebase_callable.dart';
import 'package:uhc/core/utils/app_messages.dart';

// Debug-only controls; credentials exist only in the host's process memory.
void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError('QA requires debug mode and isolated demo Firebase.');
  }
  enableFlutterDriverExtension();
  final statistics = _ControlledStatistics();
  developer.registerExtension('ext.uhc.fourFixes', (_, parameters) async {
    try {
      final context = app.navigatorKey.currentContext!;
      final navigator = app.navigatorKey.currentState!;
      switch (parameters['action']) {
        case 'guardProbe':
          try {
            await invokeFirebaseCallable(FirebaseFunctions.instance,
                'deleteUserAccount', {'targetUid': 'qa-four-locked-target'},
                timeout: const Duration(seconds: 45));
            throw StateError('Guard unexpectedly allowed deletion');
          } on FirebaseFunctionsException catch (error) {
            AppMessages.show(
                context,
                SnackBar(
                    content: Text(AppMessages.error(context, error)),
                    duration: const Duration(seconds: 30)));
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'code': error.code,
              'reason': error.details is Map ? error.details['reason'] : null
            }));
          }
        case 'clinicalProbe':
          final results = <String, String>{};
          for (final collection in ['appointments', 'medical_documents']) {
            try {
              await FirebaseFirestore.instance
                  .collection(collection)
                  .limit(1)
                  .get();
              results[collection] = 'allowed';
            } on FirebaseException catch (error) {
              results[collection] = error.code;
            }
          }
          return developer.ServiceExtensionResponse.result(jsonEncode(results));
        case 'probe':
          final started = Stopwatch()..start();
          try {
            final result =
                await statistics.analytics(parameters['period'] ?? 'dashboard');
            return developer.ServiceExtensionResponse.result(jsonEncode(
                {'result': result, 'ms': started.elapsedMilliseconds}));
          } catch (error) {
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'error': error is FirebaseFunctionsException
                  ? error.code
                  : error.runtimeType.toString(),
              'ms': started.elapsedMilliseconds
            }));
          }
        case 'signIn':
          final success = await context.read<AuthProvider>().signInWithEmail(
              email: parameters['email']!, password: parameters['password']!);
          if (!success) throw StateError('Synthetic sign-in failed');
        case 'configure':
          statistics.mode = parameters['mode'] ?? 'normal';
          statistics.delay = int.parse(parameters['delayMs'] ?? '0');
        case 'open':
          navigator.push(MaterialPageRoute(
              builder: (_) => parameters['screen'] == 'analytics'
                  ? AppointmentAnalyticsScreen(statistics: statistics)
                  : AdminDashboardScreen(statistics: statistics)));
        case 'metrics':
          return developer.ServiceExtensionResponse.result(
              jsonEncode(statistics.calls));
        case 'back':
          navigator.pop();
      }
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    } catch (_) {
      return developer.ServiceExtensionResponse.error(
          -32000, 'Synthetic QA action failed');
    }
  });
  app.main();
}

class _ControlledStatistics extends AdminStatisticsService {
  String mode = 'normal';
  int delay = 0;
  final calls = <String, int>{};
  @override
  Future<int> users() {
    calls.update('users', (v) => v + 1, ifAbsent: () => 1);
    return super.users();
  }

  @override
  Future<int> doctors() {
    calls.update('doctors', (v) => v + 1, ifAbsent: () => 1);
    return super.doctors();
  }

  @override
  Future<Map<String, dynamic>> analytics(String period) async {
    calls.update(period, (v) => v + 1, ifAbsent: () => 1);
    final currentMode = mode;
    final currentDelay = delay;
    if (currentMode == 'race') {
      // Deliberately finish older periods after the last selected empty week.
      await Future<void>.delayed(Duration(
          milliseconds: period == 'week'
              ? 2000
              : period == 'year'
                  ? 6000
                  : 8000));
      final total = period == 'week' ? 0 : 5000;
      return {
        'total': total,
        'truncated': total == 5000,
        'statuses': total == 0 ? <String, int>{} : {'completed': total},
        'departments': <String, int>{},
        'days': <String, int>{}
      };
    }
    if (currentDelay > 0) {
      await Future<void>.delayed(Duration(milliseconds: currentDelay));
    }
    if (currentMode == 'fail') throw StateError('Controlled analytics failure');
    return super.analytics(period);
  }
}
