import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/main.dart' as app;
import 'package:uhc/providers/appointment_provider.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/screens/patient/appointments/my_appointments_screen.dart';

// Debug-only response gate: queries are real authenticated demo Firestore reads.
// The second-page response is held beyond the production timeout until released.
void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError(
        'History QA requires debug mode and isolated demo Firebase.');
  }
  enableFlutterDriverExtension();
  AppointmentProvider? history;
  _HistoryGate? repository;
  developer.registerExtension('ext.uhc.historyRetry', (_, parameters) async {
    try {
      final context = app.navigatorKey.currentContext!;
      switch (parameters['action']) {
        case 'signOut':
          await context.read<AuthProvider>().signOut();
        case 'signIn':
          final ok = await context.read<AuthProvider>().signInWithEmail(
              email: parameters['email']!, password: parameters['password']!);
          if (!ok) throw StateError('Synthetic sign-in failed');
        case 'openHistory':
          final auth = context.read<AuthProvider>();
          if (!(auth.user?.id.startsWith('qa-history-') ?? false)) {
            throw StateError('Synthetic history account required');
          }
          repository = _HistoryGate();
          app.navigatorKey.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => ChangeNotifierProvider<AppointmentProvider>(
                  create: (_) => history = AppointmentProvider(
                      sessionUserId: auth.user!.id,
                      sessionScope: auth.cacheSessionKey,
                      appointmentRepository: repository),
                  child: const MyAppointmentsScreen(initialTabIndex: 0))));
        case 'release':
          repository!.release.complete();
        case 'refresh':
          unawaited(history!.loadPastAppointments(
              context.read<AuthProvider>().user!.id,
              forceRefresh: true));
        case 'state':
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'authenticated': context.read<AuthProvider>().isAuthenticated,
            'loaded': history?.hasLoadedHistory ?? false,
            'loading': history?.isLoadingHistory ?? false,
            'error': history?.historyError != null,
            'more': history?.hasMoreHistory ?? false,
            'ids': history?.pastAppointments.map((a) => a.id).toList() ?? [],
            'cursors': repository?.cursors ?? [],
            'responseHeld': repository?.held ?? false,
          }));
      }
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    } catch (_) {
      return developer.ServiceExtensionResponse.error(
          -32000, 'Synthetic history QA action failed');
    }
  });
  app.main();
}

class _HistoryGate extends AppointmentRepository {
  final release = Completer<void>();
  final cursors = <String?>[];
  var held = false;
  var _holdNextAppend = true;

  @override
  Future<AppointmentHistoryPage> getPastAppointmentsPage(String userId,
      {String? email, AppointmentHistoryPage? after, int pageSize = 30}) async {
    cursors.add(after?.cursor?.id);
    final page = await super.getPastAppointmentsPage(userId,
        email: email, after: after, pageSize: pageSize);
    if (_holdNextAppend && after != null) {
      _holdNextAppend = false;
      held = true;
      await release.future;
      held = false;
    }
    return page;
  }
}
