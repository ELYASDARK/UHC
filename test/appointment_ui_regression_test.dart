// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uhc/core/widgets/loading_skeleton.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/models/doctor_model.dart';
import 'package:uhc/data/models/user_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/l10n/kurdish_material_localizations.dart';
import 'package:uhc/providers/appointment_provider.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/doctor_appointment_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/screens/shared/language_screen.dart';
import 'package:uhc/screens/auth/login_screen.dart';
import 'package:uhc/screens/doctor/appointments/doctor_appointment_detail_screen.dart';
import 'package:uhc/screens/patient/appointments/my_appointments_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_FirebaseCoreWithStorage());
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'first appointment visit never claims empty while query is pending',
      (tester) async {
    final repository = _DelayedAppointments();
    final appointments = AppointmentProvider(appointmentRepository: repository);
    final auth = _PatientAuth();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AppointmentProvider>.value(value: appointments),
      ],
      child: _app(const MyAppointmentsScreen()),
    ));
    expect(find.text('No upcoming appointments'), findsNothing);
    expect(find.byType(AppointmentCardSkeleton), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(AppointmentCardSkeleton), findsWidgets);
    repository.result.complete([_appointment()]);
    await tester.pumpAndSettle();
    expect(find.byType(AppointmentCardSkeleton), findsNothing);
    expect(find.text('Test Doctor'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    appointments.dispose();
    auth.dispose();
  });

  testWidgets(
      'manual check-in unlocks Complete only after successful confirmation',
      (tester) async {
    final provider = _DoctorAppointments();
    final now = DateTime.now();
    final doctor = DoctorModel(
      id: 'doctor',
      userId: 'doctor-user',
      name: 'Test Doctor',
      email: 'doctor@example.test',
      departmentId: 'generalMedicine',
      specialization: 'General',
      createdAt: now,
      updatedAt: now,
    );
    await tester
        .pumpWidget(ChangeNotifierProvider<DoctorAppointmentProvider>.value(
      value: provider,
      child: _app(DoctorAppointmentDetailScreen(
          appointment: _appointment(failures: 5), doctor: doctor)),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    final lockedComplete = find.ancestor(
      of: find.byIcon(Icons.task_alt_rounded),
      matching: find.byType(ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(lockedComplete).onPressed, isNull);
    await tester.tap(lockedComplete);
    await tester.tap(lockedComplete);
    expect(provider.completionCalls, 0);
    final manual = find.text('Confirm (Manual)');
    await tester.ensureVisible(manual);
    await tester.tap(manual);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump();
    expect(provider.confirmationCalls, 1);
    expect(tester.widget<ElevatedButton>(lockedComplete).onPressed, isNull);
    provider.confirmation.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(lockedComplete).onPressed, isNull);
    expect(provider.completionCalls, 0);
    provider.confirmation = Completer<bool>();
    await tester.tap(manual);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump();
    expect(provider.confirmationCalls, 2);
    expect(tester.widget<ElevatedButton>(lockedComplete).onPressed, isNull);
    provider.confirmation.complete(true);
    await tester.pumpAndSettle();
    // The newly revealed medical-notes section has a delayed entrance animation.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(provider.receivedCode, 'test-qr');
    expect(find.byType(DoctorAppointmentDetailScreen), findsOneWidget);
    expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
    final unlockedComplete = find.ancestor(
      of: find.byIcon(Icons.task_alt_rounded),
      matching: find.byType(ElevatedButton),
    );
    expect(
        tester.widget<ElevatedButton>(unlockedComplete).onPressed, isNotNull);
    final complete = tester.widget<ElevatedButton>(unlockedComplete).onPressed!;
    complete();
    complete();
    await tester.pump();
    expect(provider.completionCalls, 1);
    provider.completion.complete(false);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('login language menu changes locale in place on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();
    final locale = LocaleProvider();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
      ],
      child: Consumer<LocaleProvider>(
        builder: (_, value, __) => MaterialApp(
          locale: value.locale,
          localizationsDelegates: [
            ...AppLocalizations.localizationsDelegates,
            const FallbackLocalizationsDelegate(),
            const FallbackCupertinoLocalizationsDelegate(),
            const FallbackWidgetsLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginScreen(onForgotPasswordTap: () {}, onLoginSuccess: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('login-language-menu'));
    for (final code in ['ar', 'ku', 'en']) {
      final wasRtl = locale.isRtl;
      expect(
          tester.getCenter(menu).dx, wasRtl ? greaterThan(160) : lessThan(160));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      for (final name in AppLocale.languageNames.values) {
        expect(find.widgetWithText(CheckedPopupMenuItem<String>, name),
            findsOneWidget);
      }
      await tester.tap(find.widgetWithText(
          CheckedPopupMenuItem<String>, AppLocale.languageNames[code]!));
      await tester.pumpAndSettle();
      expect(locale.locale.languageCode, code);
      expect(Directionality.of(tester.element(menu)),
          code == 'en' ? TextDirection.ltr : TextDirection.rtl);
      expect((await SharedPreferences.getInstance()).getString('app_locale'),
          code);
      expect(find.byType(LanguageScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    // A newly created provider restores the last selection from local storage.
    await locale.setLocaleByCode('ku');
    final restored = LocaleProvider();
    await tester.pumpAndSettle();
    expect(restored.locale.languageCode, 'ku');
    await tester.pumpWidget(const SizedBox.shrink());
    restored.dispose();
    auth.dispose();
    locale.dispose();
  });

  testWidgets('signed-out language selection persists and updates direction',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();
    final locale = LocaleProvider();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
      ],
      child: Consumer<LocaleProvider>(
          builder: (context, value, _) => MaterialApp(
                locale: value.locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const LanguageScreen(),
              )),
    ));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text(AppLocale.languageNames['ar']!));
    await tester.pumpAndSettle();
    expect(locale.locale.languageCode, 'ar');
    expect(Directionality.of(tester.element(find.byType(ListView))),
        TextDirection.rtl);
    expect(
        (await SharedPreferences.getInstance()).getString('app_locale'), 'ar');
    await tester.tap(find.text('English').first);
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.byType(ListView))),
        TextDirection.ltr);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    locale.dispose();
  });
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

AppointmentModel _appointment({int failures = 0}) {
  final now = DateTime.now();
  final time =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  return AppointmentModel(
    id: 'appointment',
    patientId: 'patient',
    patientName: 'Test Patient',
    patientEmail: 'patient@example.test',
    doctorId: '',
    doctorName: 'Test Doctor',
    department: 'generalMedicine',
    appointmentDate: now,
    timeSlot: '$time - $time',
    createdAt: now,
    updatedAt: now,
    qrCode: 'test-qr',
    bookingReference: 'TEST1234',
    qrScanFailures: failures,
  );
}

class _DelayedAppointments extends AppointmentRepository {
  final result = Completer<List<AppointmentModel>>();
  @override
  Future<List<AppointmentModel>> getUpcomingAppointments(String userId,
          {String? email}) =>
      result.future;
  @override
  Future<List<AppointmentModel>> getPastAppointments(String userId,
          {String? email}) async =>
      [];
}

class _PatientAuth extends AuthProvider {
  @override
  UserModel get user => UserModel(
      id: 'patient',
      email: 'patient@example.test',
      fullName: 'Test Patient',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026));
}

class _DoctorAppointments extends DoctorAppointmentProvider {
  String? receivedCode;
  int confirmationCalls = 0;
  int completionCalls = 0;
  Completer<bool> confirmation = Completer<bool>();
  final completion = Completer<bool>();
  @override
  Future<bool> confirmCheckIn(
      String appointmentId, String qrCode, String doctorId) async {
    receivedCode = qrCode;
    confirmationCalls++;
    return confirmation.future;
  }

  @override
  Future<bool> completeAppointment(String appointmentId, String doctorId,
      {String? notes,
      String? statusUpdatedBy,
      AppointmentModel? appointment,
      String? doctorName}) {
    completionCalls++;
    return completion.future;
  }
}

class _FirebaseCoreWithStorage extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}
