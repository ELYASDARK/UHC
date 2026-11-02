import 'package:uhc/screens/super_admin/super_admin_dashboard_screen.dart';
import 'dart:ui' show FrameTiming;
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/repositories/department_repository.dart';
import 'package:uhc/core/widgets/session_stream_builder.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/main.dart' as app;
import 'package:uhc/providers/appointment_provider.dart';
import 'package:uhc/providers/doctor_appointment_provider.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/providers/theme_provider.dart';

// Normal navigation uses real UI. A fresh dashboard route is reserved for
// the labeled dashboard fault test under an already authenticated synthetic session.
void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError('QA requires debug mode and isolated demo Firebase.');
  }
  enableFlutterDriverExtension();
  final frames = <FrameTiming>[];
  WidgetsBinding.instance.addTimingsCallback((batch) {
    frames.addAll(batch);
    if (frames.length > 600) frames.removeRange(0, frames.length - 600);
  });
  AppointmentModel? mutationFixture;
  Map<String, dynamic>? mutationResult;
  developer.registerExtension('ext.uhc.loadingCache', (_, parameters) async {
    try {
      final context = app.navigatorKey.currentContext!;
      switch (parameters['action']) {
        case 'openDashboardForFaultTest':
          if (context.read<AuthProvider>().user?.role.name != 'superAdmin') {
            throw StateError(
                'An authenticated synthetic super-admin is required');
          }
          app.navigatorKey.currentState!.push(MaterialPageRoute<void>(
              builder: (_) => const SuperAdminDashboardScreen()));
        case 'invalidateDirectory':
          DepartmentRepository.invalidateCache();
        case 'frames':
          if (parameters['reset'] == 'true') frames.clear();
          double percentile(List<int> values, double p) {
            if (values.isEmpty) return 0;
            values.sort();
            return values[((values.length - 1) * p).round()] / 1000;
          }
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'samples': frames.length,
            'buildP90Ms': percentile(
                frames.map((f) => f.buildDuration.inMicroseconds).toList(), .9),
            'rasterP90Ms': percentile(
                frames.map((f) => f.rasterDuration.inMicroseconds).toList(),
                .9),
            'mode': kProfileMode ? 'profile' : 'debug',
            'notAnFpsClaim': true,
          }));
        case 'signIn':
          final ok = await context.read<AuthProvider>().signInWithEmail(
              email: parameters['email']!, password: parameters['password']!);
          if (!ok) throw StateError('Synthetic sign-in failed');
        case 'signOut':
          app.navigatorKey.currentState!.popUntil((route) => route.isFirst);
          await context.read<AuthProvider>().signOut();
        case 'environment':
          await context
              .read<LocaleProvider>()
              .setLocaleByCode(parameters['locale'] ?? 'en');
          await context.read<ThemeProvider>().setThemeMode(
              parameters['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light);
        case 'network':
          if (parameters['enabled'] == 'false') {
            await FirebaseFirestore.instance.disableNetwork();
          } else {
            await FirebaseFirestore.instance.enableNetwork();
          }
        case 'mutations':
          if (mutationResult != null) {
            return developer.ServiceExtensionResponse.result(
                jsonEncode(mutationResult));
          }
          final user = context.read<AuthProvider>().user!;
          if (!user.id.startsWith('qa-loading-')) {
            throw StateError('Synthetic account required');
          }
          final provider = context.read<AppointmentProvider>();
          final now = DateTime.now();
          final date = DateTime(now.year, now.month, now.day + 9);
          mutationFixture ??= AppointmentModel(
              id: '',
              patientId: user.id,
              patientName: user.fullName,
              patientEmail: user.email,
              doctorId: 'qa-loading-00',
              doctorName: 'Synthetic Doctor 00',
              department: 'generalMedicine',
              appointmentDate: date,
              timeSlot: '12:00 - 12:30',
              bookingReference: 'QA${now.microsecondsSinceEpoch}',
              createdAt: now,
              updatedAt: now);
          final bookings = await Future.wait([
            provider.bookAppointment(mutationFixture!),
            provider.bookAppointment(mutationFixture!),
          ]);
          if (bookings.any((booking) => booking == null)) {
            throw StateError('Booking did not succeed');
          }
          final id = bookings.first!.appointmentId;
          if (id != bookings.last!.appointmentId) {
            throw StateError('Duplicate appointment');
          }
          await provider.loadAppointments(user.id, email: user.email);
          final booked =
              provider.upcomingAppointments.any((apt) => apt.id == id);
          final rescheduled = await provider.rescheduleAppointment(
              appointmentId: id,
              newDate: date.add(const Duration(days: 1)),
              newTimeSlot: '13:00 - 13:30',
              doctorId: 'qa-loading-00',
              doctorName: 'Synthetic Doctor 00',
              userId: user.id,
              reason: 'Synthetic QA');
          final freshReschedule = provider.upcomingAppointments
              .any((apt) => apt.id == id && apt.timeSlot == '13:00 - 13:30');
          await provider.loadPastAppointments(user.id, email: user.email);
          final cancelled =
              await provider.cancelAppointment(id, 'Synthetic QA', user.id);
          await provider.loadPastAppointments(user.id,
              email: user.email, forceRefresh: true);
          mutationResult = {
            'sameAppointmentOnReplay': true,
            'bookedVisible': booked,
            'rescheduled': rescheduled,
            'rescheduleVisible': freshReschedule,
            'cancelled': cancelled,
            'removedFromCurrent':
                !provider.upcomingAppointments.any((apt) => apt.id == id),
            'cancelledInHistory': provider.pastAppointments.any((apt) =>
                apt.id == id && apt.status == AppointmentStatus.cancelled),
            'transport':
                'actual Android providers and demo Firebase callables; no receipt captured',
          };
          return developer.ServiceExtensionResponse.result(
              jsonEncode(mutationResult));
        case 'moreHistory':
          await context.read<AppointmentProvider>().loadMoreHistory();
        case 'refreshAuth':
          await context.read<AuthProvider>().refreshCurrentUser();
        case 'state':
          final types = <String>{};
          var syntheticTexts = 0;
          var updatedDirectoryVisible = false;
          void visit(Element element) {
            if (element.widget is Offstage &&
                (element.widget as Offstage).offstage) {
              return;
            }
            types.add(element.widget.runtimeType.toString());
            if (element.widget is Text &&
                (element.widget as Text).data ==
                    'A Synthetic Updated Department') {
              updatedDirectoryVisible = true;
            }
            if (element.widget is Text &&
                ((element.widget as Text).data?.startsWith('Synthetic') ??
                    false)) {
              syntheticTexts++;
            }
            element.visitChildren(visit);
          }
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          final patient = context.read<AppointmentProvider>();
          final doctor = context.read<DoctorAppointmentProvider>();
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'role': context.read<AuthProvider>().user?.role.name,
            'screens': types
                .where((t) => t.endsWith('Screen') || t.endsWith('Shell'))
                .toList(),
            'syntheticTexts': syntheticTexts,
            'updatedDirectoryVisible': updatedDirectoryVisible,
            'skeleton': types.any((t) => t.contains('Skeleton')),
            'patientLoading': patient.isLoading,
            'upcoming': patient.upcomingAppointments.length,
            'past': patient.pastAppointments.length,
            'historyLoading': patient.isLoadingHistory,
            'historyMore': patient.hasMoreHistory,
            'departmentReadStarts': DepartmentRepository.debugServerReads,
            'streamStarts': SessionStreamBuilder.debugStarts,
            'activeStreams': SessionStreamBuilder.debugActive,
            'streamCancellations': SessionStreamBuilder.debugCancellations,
            'patientError': patient.error != null,
            'doctorLoading': doctor.isLoading,
            'doctorAppointments': doctor.appointments.length,
            'doctorError': doctor.error != null,
          }));
      }
      return developer.ServiceExtensionResponse.result('{"ok":true}');
    } catch (_) {
      return developer.ServiceExtensionResponse.error(
          -32000, 'Synthetic loading QA action failed');
    }
  });
  app.main();
}
