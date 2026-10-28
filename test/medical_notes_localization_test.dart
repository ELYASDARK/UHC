// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_functions/cloud_functions.dart';
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
import 'package:uhc/l10n/kurdish_material_localizations.dart';
import 'package:uhc/providers/doctor_appointment_provider.dart';
import 'package:uhc/screens/doctor/appointments/doctor_appointment_detail_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Review follow-up: the real false-return branch used an English literal.
  for (final code in ['en', 'ar', 'ku']) {
    testWidgets('$code notes save failure dismisses and retry succeeds',
        (tester) async {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _NotesRepository();
      final provider =
          DoctorAppointmentProvider(appointmentRepository: repository);
      final now = DateTime.now();
      final locale = ValueNotifier(Locale(code));
      addTearDown(locale.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, _) => MaterialApp(
            locale: value,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              FallbackLocalizationsDelegate(),
              FallbackCupertinoLocalizationsDelegate(),
              FallbackWidgetsLocalizationsDelegate(),
            ],
            home: DoctorAppointmentDetailScreen(
              appointment: AppointmentModel(
                  id: 'booking',
                  patientId: 'patient',
                  patientName: 'Synthetic Patient',
                  patientEmail: 'patient@example.test',
                  doctorId: 'doctor',
                  doctorName: 'Synthetic Doctor',
                  department: 'generalMedicine',
                  appointmentDate: now,
                  timeSlot: '09:30 - 10:00',
                  status: AppointmentStatus.confirmed,
                  createdAt: now,
                  updatedAt: now),
              doctor: DoctorModel(
                  id: 'doctor',
                  userId: 'doctor',
                  name: 'Synthetic Doctor',
                  email: 'doctor@example.test',
                  departmentId: 'generalMedicine',
                  specialization: 'General',
                  createdAt: now,
                  updatedAt: now),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final context =
          tester.element(find.byType(DoctorAppointmentDetailScreen));
      final l10n = AppLocalizations.of(context);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
          find.byType(TextField), 'Synthetic follow-up notes');
      await tester.ensureVisible(find.text(l10n.saveNotes));
      await tester.tap(find.text(l10n.saveNotes));
      await tester.pumpAndSettle();
      expect(find.text(l10n.notesSaveFailed), findsOneWidget);
      expect(find.text('Failed to save notes'), findsNothing);
      expect(find.textContaining('private'), findsNothing);
      expect(repository.savedNotes, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Synthetic follow-up notes');
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      repository.fail = false;
      await tester.tap(find.text(l10n.saveNotes));
      await tester.pumpAndSettle();
      expect(repository.savedNotes, 'Synthetic follow-up notes');
      expect(find.text(l10n.notesSaved), findsOneWidget);
      expect(find.text(l10n.notesSaveFailed), findsNothing);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      if (code == 'en') {
        // An emulator route transition exposed premature cancel-dialog controller disposal.
        await tester.tap(find.widgetWithText(OutlinedButton, l10n.cancel));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.descendant(
                of: find.byType(AlertDialog), matching: find.byType(TextField)),
            'Synthetic cancellation reason');
        await tester.tap(find.widgetWithText(TextButton, l10n.back));
        await tester.pump();
        locale.value = const Locale('ar');
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }
}

// Substitute only the persistence boundary; the screen and provider are real.
class _NotesRepository extends AppointmentRepository {
  bool fail = true;
  String? savedNotes;
  @override
  Future<void> updateMedicalNotes(String appointmentId, String notes) async {
    if (fail) {
      throw FirebaseFunctionsException(
          code: 'unavailable', message: 'private fixture trace');
    }
    savedNotes = notes;
  }

  @override
  Future<List<AppointmentModel>> getAllDoctorAppointments(
          String doctorId) async =>
      [];
}
