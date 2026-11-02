import 'package:uhc/providers/appointment_provider.dart';
import 'dart:async';
// Regression for cross-doctor cached clinical-data disclosure.
// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/models/doctor_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/providers/doctor_appointment_provider.dart';
import 'package:uhc/providers/notification_provider.dart';
import 'package:uhc/screens/doctor/dashboard/doctor_dashboard_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_Core());
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('a disposed session ignores a late appointment response', () async {
    final repository = _DelayedRepository();
    final provider = _Provider(repository);
    final pending = provider.loadDashboardAppointments('synthetic-doctor-a');
    provider.dispose();
    repository.reply.complete(await _Repository()
        .getDoctorDashboardAppointments('synthetic-doctor-a'));
    await pending;
    expect(provider.appointments, isEmpty);
  });

  test('a disposed patient session ignores late appointment data', () async {
    final repository = _DelayedPatientRepository();
    final provider = AppointmentProvider(appointmentRepository: repository);
    final pending = provider.loadAppointments('synthetic-patient');
    provider.dispose();
    repository.reply.complete(await _Repository()
        .getDoctorDashboardAppointments('synthetic-doctor-a'));
    await pending;
    expect(provider.upcomingAppointments, isEmpty);
    expect(provider.pastAppointments, isEmpty);
  });

  testWidgets(
      'doctor B dashboard reloads instead of displaying doctor A clinical data',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Repository();
    final provider = _Provider(repository);
    await provider.loadDashboardAppointments('synthetic-doctor-a');
    expect(repository.queriedDoctors, ['synthetic-doctor-a']);
    // Even accidental provider reuse must reload when the doctor changes.
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DoctorAppointmentProvider>.value(
            value: provider),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DoctorDashboardScreen(
            doctor: _doctorB(), referenceTime: DateTime(2026, 10, 29, 8)),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Patient A'), findsNothing);
    expect(find.text('patient-a@example.test'), findsNothing);
    expect(repository.queriedDoctors,
        ['synthetic-doctor-a', 'synthetic-doctor-b']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    provider.dispose();
  });
}

DoctorModel _doctorB() => DoctorModel(
      id: 'synthetic-doctor-b',
      userId: 'synthetic-user-b',
      name: 'Synthetic Doctor B',
      email: 'doctor-b@example.test',
      departmentId: 'generalMedicine',
      specialization: 'General',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _Repository extends AppointmentRepository {
  final queriedDoctors = <String>[];
  @override
  Future<List<AppointmentModel>> getDoctorDashboardAppointments(
      String doctorId) async {
    queriedDoctors.add(doctorId);
    if (doctorId != 'synthetic-doctor-a') return [];
    return [
      AppointmentModel(
        id: 'synthetic-appointment-a',
        patientId: '',
        patientName: 'Synthetic Patient A',
        patientEmail: 'patient-a@example.test',
        doctorId: 'synthetic-doctor-a',
        doctorName: 'Synthetic Doctor A',
        department: 'generalMedicine',
        appointmentDate: DateTime(2099, 1, 1),
        timeSlot: '09:00 - 09:30',
        status: AppointmentStatus.confirmed,
        isCheckedIn: true,
        medicalNotes: 'Synthetic confidential notes belonging to doctor A',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      )
    ];
  }
}

class _Provider extends DoctorAppointmentProvider {
  _Provider(_Repository repository) : super(appointmentRepository: repository);
  @override
  Future<void> configureDailyNotifications(
      {required String doctorUserId,
      required Map<String, List<TimeSlot>> weeklySchedule,
      String? dailyNotificationTime}) async {}
}

class _Core extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}

class _DelayedRepository extends _Repository {
  final reply = Completer<List<AppointmentModel>>();
  @override
  Future<List<AppointmentModel>> getDoctorDashboardAppointments(
          String doctorId) =>
      reply.future;
}

class _DelayedPatientRepository extends AppointmentRepository {
  final reply = Completer<List<AppointmentModel>>();
  @override
  Future<List<AppointmentModel>> getUpcomingAppointments(String userId,
          {String? email}) =>
      reply.future;
  @override
  Future<List<AppointmentModel>> getPastAppointments(String userId,
          {String? email}) async =>
      [];
}
