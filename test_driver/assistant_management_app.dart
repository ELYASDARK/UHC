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
import 'package:uhc/screens/admin/doctors/doctor_management_screen.dart';
import 'package:uhc/screens/admin/users/user_management_screen.dart';
import 'package:uhc/screens/admin/departments/department_management_screen.dart';
import 'package:uhc/screens/patient/assistant/assistant_chat_screen.dart';
import 'package:uhc/providers/assistant_chat_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/providers/theme_provider.dart';

// Debug-only controls; credentials exist only in the host's process memory.
void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError('QA requires debug mode and isolated demo Firebase.');
  }
  enableFlutterDriverExtension();
  final statistics = _ControlledStatistics();
  AssistantChatProvider? chat;
  var textScale = 1.0;
  double? bottomInset;
  developer.registerExtension('ext.uhc.fourFixes', (_, parameters) async {
    try {
      final context = app.navigatorKey.currentContext!;
      final navigator = app.navigatorKey.currentState!;
      switch (parameters['action']) {
        case 'environment':
          textScale = double.parse(parameters['textScale'] ?? '1');
          bottomInset = parameters['bottomInset'] == null
              ? null
              : double.parse(parameters['bottomInset']!);
          await context
              .read<LocaleProvider>()
              .setLocaleByCode(parameters['locale'] ?? 'en');
          await context.read<ThemeProvider>().setThemeMode(
              parameters['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light);
        case 'focusReply':
          await _focusReply(chat!.messages.last.text);
        case 'scrollEnd':
          void scroll(Element element) {
            if (element is StatefulElement &&
                element.state is ScrollableState &&
                ModalRoute.of(element)?.isCurrent == true) {
              final state = element.state as ScrollableState;
              if (state.position.hasContentDimensions) {
                state.position.jumpTo(state.position.maxScrollExtent);
              }
            }
            element.visitChildren(scroll);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(scroll);
        case 'chatSend':
          final ok = await chat!.sendMessage(parameters['text']!,
              localeCode: context.read<LocaleProvider>().locale.languageCode);
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'ok': ok,
            'status': chat!.currentStatus.name,
            'failure': chat!.failureKind?.name,
            'messages': chat!.messages
                .map((m) => {
                      'role': m.isPatient ? 'patient' : 'assistant',
                      'text': m.text
                    })
                .toList()
          }));
        case 'chatClear':
          await chat!.clearChat();
        case 'chatHistory':
          await chat!.refreshHistory();
          return developer.ServiceExtensionResponse.result(
              jsonEncode({'count': chat!.messages.length}));
        case 'geometry':
          final boxes = <Map<String, dynamic>>[];
          void visit(Element element) {
            final type = element.widget.runtimeType.toString();
            if (type == 'Text' ||
                type.startsWith('FloatingActionButton') ||
                type.startsWith('PopupMenuButton')) {
              final box = element.findRenderObject();
              if (box is RenderBox && box.hasSize && box.attached) {
                final offset = box.localToGlobal(Offset.zero);
                boxes.add({
                  'type': type,
                  if (element.widget is Text)
                    'text': (element.widget as Text).data,
                  if (element.widget is Text)
                    'direction':
                        (element.widget as Text).textDirection.toString(),
                  'x': offset.dx,
                  'y': offset.dy,
                  'width': box.size.width,
                  'height': box.size.height
                });
              }
            }
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          return developer.ServiceExtensionResponse.result(
              jsonEncode({'boxes': boxes}));
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
            final result = await AdminStatisticsService()
                .analytics(parameters['period'] ?? 'dashboard');
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
          final screen = parameters['screen'];
          if (screen == 'assistant') {
            chat?.dispose();
            chat = AssistantChatProvider(
                patientId: context.read<AuthProvider>().currentUser?.id);
          }
          navigator.push(MaterialPageRoute(builder: (routeContext) {
            final child = switch (screen) {
              'analytics' => AppointmentAnalyticsScreen(statistics: statistics),
              'doctors' => const DoctorManagementScreen(),
              'users' => const UserManagementScreen(),
              'departments' => const DepartmentManagementScreen(),
              'assistant' => AssistantChatScreen(provider: chat),
              _ => AdminDashboardScreen(statistics: statistics),
            };
            final media = MediaQuery.of(routeContext);
            return MediaQuery(
                data: media.copyWith(
                    textScaler: TextScaler.linear(textScale),
                    padding: media.padding
                        .copyWith(bottom: bottomInset ?? media.padding.bottom)),
                child: child);
          }));
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

Future<void> _focusReply(String reply) async {
  await WidgetsBinding.instance.endOfFrame;
  Element? target;
  void visit(Element element) {
    if (element.widget is Text &&
        (element.widget as Text).data == reply &&
        ModalRoute.of(element)?.isCurrent == true) {
      target = element;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  if (target == null) throw StateError('Latest reply is not built');
  await Scrollable.ensureVisible(target!,
      alignment: .22, duration: const Duration(milliseconds: 300));
}
