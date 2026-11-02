import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/main.dart' as app;
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/providers/theme_provider.dart';
import 'package:uhc/screens/admin/analytics/appointment_analytics_screen.dart';
import 'package:uhc/services/admin_statistics_service.dart';

// Debug-only access to the real analytics screen and demo callable service.
// The host supplies a random synthetic-account password in memory only.
void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError('Analytics QA requires debug mode and demo emulators.');
  }
  enableFlutterDriverExtension();
  final statistics = _ObservedStatistics();
  developer.registerExtension('ext.uhc.analyticsHeader', (_, parameters) async {
    try {
      final context = app.navigatorKey.currentContext!;
      final auth = context.read<AuthProvider>();
      switch (parameters['action']) {
        case 'signOut':
          await auth.signOut();
        case 'signIn':
          if (!parameters['email']!.endsWith('@example.test')) {
            throw StateError('Synthetic account required');
          }
          final ok = await auth.signInWithEmail(
              email: parameters['email']!, password: parameters['password']!);
          if (!ok) throw StateError('Synthetic sign-in failed');
        case 'environment':
          await context.read<LocaleProvider>().setLocaleByCode('en');
          await context.read<ThemeProvider>().setThemeMode(
              parameters['theme'] == 'light'
                  ? ThemeMode.light
                  : ThemeMode.dark);
        case 'open':
          if (!(auth.user?.id.startsWith('qa-analytics-header-') ?? false)) {
            throw StateError('Synthetic analytics account required');
          }
          final scale = double.parse(parameters['scale'] ?? '1');
          app.navigatorKey.currentState!.push(MaterialPageRoute<void>(
              builder: (routeContext) => MediaQuery(
                  data: MediaQuery.of(routeContext)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: AppointmentAnalyticsScreen(statistics: statistics))));
        case 'back':
          app.navigatorKey.currentState!.pop();
        case 'state':
          final texts = <Map<String, dynamic>>[];
          void visit(Element element, bool analytics) {
            final inside =
                analytics || element.widget is AppointmentAnalyticsScreen;
            if (inside && element.widget is Text) {
              final text = (element.widget as Text).data;
              final box = element.findRenderObject();
              if (text != null && box is RenderBox && box.hasSize) {
                final position = box.localToGlobal(Offset.zero);
                texts.add({
                  'text': text,
                  'direction': Directionality.of(element).name,
                  'x': position.dx,
                  'y': position.dy,
                  'width': box.size.width,
                  'height': box.size.height,
                });
              }
            }
            element.visitChildren((child) => visit(child, inside));
          }
          WidgetsBinding.instance.rootElement!
              .visitChildren((element) => visit(element, false));
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'authenticated': auth.isAuthenticated,
            'locale': context.read<LocaleProvider>().locale.languageCode,
            'calls': statistics.calls,
            'snapshots': statistics.snapshots,
            'errors': statistics.errors,
            'texts': texts,
          }));
      }
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    } catch (_) {
      return developer.ServiceExtensionResponse.error(
          -32000, 'Synthetic analytics QA action failed');
    }
  });
  app.main();
}

class _ObservedStatistics extends AdminStatisticsService {
  final calls = <String, int>{};
  final snapshots = <String, Map<String, dynamic>>{};
  final errors = <String, String>{};

  @override
  Future<Map<String, dynamic>> analytics(String period) async {
    calls.update(period, (count) => count + 1, ifAbsent: () => 1);
    try {
      final result = await super.analytics(period);
      snapshots[period] = {'asOf': result['asOf'], 'total': result['total']};
      errors.remove(period);
      return result;
    } catch (error) {
      errors[period] = error is FirebaseFunctionsException
          ? error.code
          : error.runtimeType.toString();
      rethrow;
    }
  }
}
