// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/utils/localization_helper.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/models/doctor_model.dart';
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

  for (final code in ['en', 'ar', 'ku']) {
    test(
      '$code recognizes canonical and legacy labels, preserves custom text',
      () async {
        final l10n = await AppLocalizations.delegate.load(Locale(code));
        for (final value in ['generalMedicine', 'General Medicine']) {
          expect(
            LocalizationHelper.translateDepartment(value, l10n),
            l10n.generalMedicine,
          );
        }
        expect(
          LocalizationHelper.translateDepartment('clinicalPsychology', l10n),
          l10n.clinicalPsychology,
        );
        for (final custom in [
          'Custom clinic / بەش',
          'unknownDepartment',
          'General Medicine Annex',
          '',
        ]) {
          expect(LocalizationHelper.translateDepartment(custom, l10n), custom);
        }
        final labels = [
          l10n.regularVisit,
          l10n.followUp,
          l10n.consultation,
          l10n.emergency,
        ];
        final types = [
          AppointmentType.regularCheckup,
          AppointmentType.followUp,
          AppointmentType.consultation,
          AppointmentType.emergency,
        ];
        for (var i = 0; i < types.length; i++) {
          expect(
            LocalizationHelper.translateAppointmentType(types[i], l10n),
            labels[i],
          );
        }
      },
    );

    for (final brightness in Brightness.values) {
      testWidgets(
        '$code $brightness detail wraps enlarged labels and keeps Complete disabled',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final provider = DoctorAppointmentProvider();
          final now = DateTime.now();
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: provider,
              child: MaterialApp(
                locale: Locale(code),
                theme: ThemeData(brightness: brightness),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  ...AppLocalizations.localizationsDelegates,
                  FallbackLocalizationsDelegate(),
                  FallbackCupertinoLocalizationsDelegate(),
                  FallbackWidgetsLocalizationsDelegate(),
                ],
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.7)),
                  child: child!,
                ),
                home: DoctorAppointmentDetailScreen(
                  appointment: AppointmentModel(
                    id: 'synthetic-labels',
                    patientId: 'patient',
                    patientName: 'Synthetic Patient',
                    patientEmail: 'patient@example.test',
                    doctorId: 'doctor',
                    doctorName: 'Synthetic Doctor',
                    department: 'clinicalPsychology',
                    appointmentDate: now,
                    timeSlot: '09:30 - 10:00',
                    createdAt: now,
                    updatedAt: now,
                  ),
                  doctor: DoctorModel(
                    id: 'doctor',
                    userId: 'doctor',
                    name: 'Synthetic Doctor',
                    email: 'doctor@example.test',
                    departmentId: 'clinicalPsychology',
                    specialization: 'General',
                    createdAt: now,
                    updatedAt: now,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = await AppLocalizations.delegate.load(Locale(code));
          await tester.ensureVisible(find.text(l10n.clinicalPsychology));
          await tester.pumpAndSettle();
          expect(find.text(l10n.regularVisit), findsOneWidget);
          expect(find.text('clinicalPsychology'), findsNothing);
          expect(find.text('Regular Checkup'), findsNothing);
          expect(
            Directionality.of(
              tester.element(find.text(l10n.clinicalPsychology)),
            ),
            code == 'en' ? TextDirection.ltr : TextDirection.rtl,
          );
          final complete = find.ancestor(
            of: find.byIcon(Icons.task_alt_rounded),
            matching: find.byType(ElevatedButton),
          );
          expect(tester.widget<ElevatedButton>(complete).onPressed, isNull);
          expect(tester.getSize(find.text(l10n.clinicalPsychology)).width,
              greaterThan(220));
          final cancel = find.widgetWithText(OutlinedButton, l10n.cancel);
          await tester.ensureVisible(cancel);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(cancel);
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(640));
          await tester.tap(cancel);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          provider.dispose();
        },
      );
    }
  }
}
