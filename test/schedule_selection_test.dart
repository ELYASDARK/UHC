// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/models/doctor_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/l10n/kurdish_material_localizations.dart';
import 'package:uhc/screens/patient/booking/booking_screen.dart';
import 'package:uhc/screens/patient/browse_doctors/doctor_schedule_screen.dart';

class TestAppointmentRepository extends AppointmentRepository {
  Future<DoctorDayAvailability> Function(String doctorId, DateTime date)?
      availabilityHandler;

  TestAppointmentRepository({this.availabilityHandler});

  @override
  Future<DoctorDayAvailability> getDoctorDayAvailability({
    required String doctorId,
    required DateTime date,
  }) async {
    if (availabilityHandler != null) {
      return availabilityHandler!(doctorId, date);
    }
    return DoctorDayAvailability(
      success: true,
      doctorId: doctorId,
      appointmentDate: AppointmentRepository.formatClinicDate(date),
      doctorName: 'Sarah Al-Mansoor',
      department: 'generalMedicine',
      slots: const [],
    );
  }
}

DoctorModel createTestDoctor({
  String id = 'doctor-123',
  String name = 'Sarah Al-Mansoor',
  bool isActive = true,
  bool isAvailable = true,
  Map<String, List<TimeSlot>> weeklySchedule = const {},
}) {
  return DoctorModel(
    id: id,
    userId: 'user-123',
    name: name,
    email: 'sarah@uhc.iq',
    departmentId: 'generalMedicine',
    specialization: 'Internal Medicine',
    isActive: isActive,
    isAvailable: isAvailable,
    weeklySchedule: weeklySchedule,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

Widget createTestApp({
  required Widget child,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      FallbackLocalizationsDelegate(),
      FallbackCupertinoLocalizationsDelegate(),
      FallbackWidgetsLocalizationsDelegate(),
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: child,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Monday, September 14, 2026 at 08:00
  final mondayDate = DateTime(2026, 9, 14, 8, 0);
  // Tuesday, September 15, 2026 at 08:00
  final tuesdayDate = DateTime(2026, 9, 15, 8, 0);
  // Friday, September 18, 2026 at 08:00
  final fridayDate = DateTime(2026, 9, 18, 8, 0);

  group('TimeSlot parser and validation unit tests', () {
    test('canonical 2-digit HH:mm format parses correctly without RangeError', () {
      expect(TimeSlot.parseMinutes('00:00'), equals(0));
      expect(TimeSlot.parseMinutes('09:00'), equals(540));
      expect(TimeSlot.parseMinutes('09:30'), equals(570));
      expect(TimeSlot.parseMinutes('14:30'), equals(870));
      expect(TimeSlot.parseMinutes('23:59'), equals(1439));
    });

    test('malformed, single-digit, and padded time strings are rejected', () {
      // Single digit (non-canonical)
      expect(TimeSlot.parseMinutes('9:00'), isNull);
      expect(TimeSlot.parseMinutes('09:0'), isNull);
      expect(TimeSlot.parseMinutes('9:3'), isNull);

      // Whitespace padding rejected
      expect(TimeSlot.parseMinutes(' 09:00'), isNull);
      expect(TimeSlot.parseMinutes('09:00 '), isNull);
      expect(TimeSlot.parseMinutes('09: 00'), isNull);

      // Out of range hours/minutes
      expect(TimeSlot.parseMinutes('24:00'), isNull);
      expect(TimeSlot.parseMinutes('25:00'), isNull);
      expect(TimeSlot.parseMinutes('09:60'), isNull);
      expect(TimeSlot.parseMinutes('-01:00'), isNull);

      // Non-time formats
      expect(TimeSlot.parseMinutes(''), isNull);
      expect(TimeSlot.parseMinutes('invalid'), isNull);
      expect(TimeSlot.parseMinutes('09-00'), isNull);
      expect(TimeSlot.parseMinutes('09:00:00'), isNull);
    });

    test('TimeSlot.isValid requires available, valid times, and positive duration', () {
      final validSlot = TimeSlot(startTime: '09:00', endTime: '09:30');
      expect(validSlot.isValid, isTrue);

      // Unavailable slot
      final unavailableSlot = TimeSlot(startTime: '09:00', endTime: '09:30', isAvailable: false);
      expect(unavailableSlot.isValid, isFalse);

      // End time before start time
      final invertedSlot = TimeSlot(startTime: '10:00', endTime: '09:00');
      expect(invertedSlot.isValid, isFalse);

      // Equal start and end time (zero duration)
      final zeroSlot = TimeSlot(startTime: '10:00', endTime: '10:00');
      expect(zeroSlot.isValid, isFalse);

      // Single-digit hours
      final singleDigitStart = TimeSlot(startTime: '9:00', endTime: '09:30');
      expect(singleDigitStart.isValid, isFalse);

      // Malformed strings
      final malformedStart = TimeSlot(startTime: 'bad', endTime: '09:30');
      expect(malformedStart.isValid, isFalse);

      final malformedEnd = TimeSlot(startTime: '09:00', endTime: 'bad');
      expect(malformedEnd.isValid, isFalse);
    });

    test('TimeSlot.fullDisplay returns formatted start and end time range', () {
      final slot = TimeSlot(startTime: '09:00', endTime: '09:30');
      expect(slot.display, equals('09:00'));
      expect(slot.fullDisplay, equals('09:00 - 09:30'));
    });
  });

  group('DoctorModel shared schedule selector unit tests', () {
    test('canonical weekdays list contains exact 7 lowercase days in order', () {
      expect(DoctorModel.canonicalWeekdays, equals([
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ]));

      expect(DoctorModel.dayOfWeekName(DateTime(2026, 9, 14)), equals('monday'));
      expect(DoctorModel.dayOfWeekName(DateTime(2026, 9, 15)), equals('tuesday'));
      expect(DoctorModel.dayOfWeekName(DateTime(2026, 9, 16)), equals('wednesday'));
      expect(DoctorModel.dayOfWeekName(DateTime(2026, 9, 17)), equals('thursday'));
      expect(DoctorModel.dayOfWeekName(DateTime(2026, 9, 18)), equals('friday'));
      expect(DoctorModel.dayOfWeekName(DateTime(2026, 9, 19)), equals('saturday'));
      expect(DoctorModel.dayOfWeekName(DateTime(2026, 9, 20)), equals('sunday'));
    });

    test('non-canonical keys in weeklySchedule are ignored by hasActiveSchedule', () {
      final validSlot = TimeSlot(startTime: '09:00', endTime: '09:30');
      final doctorWithInvalidKeys = createTestDoctor(
        weeklySchedule: {
          'holiday': [validSlot],
          'random_day': [validSlot],
          'sunday_night': [validSlot],
        },
      );

      expect(doctorWithInvalidKeys.hasActiveSchedule, isFalse);
      expect(doctorWithInvalidKeys.getAvailableSlots(mondayDate), isEmpty);
    });

    test('empty schedule offers no slots and never fabricates weekday fallbacks', () {
      final doctorEmptyMap = createTestDoctor(weeklySchedule: const {});
      final doctorEmptyDays = createTestDoctor(
        weeklySchedule: const {
          'monday': [],
          'tuesday': [],
          'wednesday': [],
          'thursday': [],
          'friday': [],
        },
      );

      expect(doctorEmptyMap.hasActiveSchedule, isFalse);
      expect(doctorEmptyDays.hasActiveSchedule, isFalse);

      // Verify that weekdays return empty lists, not fallback slots
      expect(doctorEmptyMap.getAvailableSlots(mondayDate), isEmpty);
      expect(doctorEmptyMap.getAvailableSlots(tuesdayDate), isEmpty);
      expect(doctorEmptyMap.getAvailableSlots(fridayDate), isEmpty);

      expect(doctorEmptyDays.getAvailableSlots(mondayDate), isEmpty);
      expect(doctorEmptyDays.getAvailableSlots(tuesdayDate), isEmpty);
      expect(doctorEmptyDays.getAvailableSlots(fridayDate), isEmpty);
    });

    test('missing weekday offers no slots while configured weekdays are preserved', () {
      final mondaySlot = TimeSlot(startTime: '09:00', endTime: '09:30');
      final doctor = createTestDoctor(
        weeklySchedule: {
          'monday': [mondaySlot],
          'tuesday': [], // explicitly empty
          // wednesday-sunday completely absent from map
        },
      );

      expect(doctor.hasActiveSchedule, isTrue);

      final mondaySlots = doctor.getAvailableSlots(mondayDate);
      expect(mondaySlots.length, equals(1));
      expect(mondaySlots.first.startTime, equals('09:00'));
      expect(mondaySlots.first.endTime, equals('09:30'));

      // Tuesday (empty) and Friday (missing) offer zero slots
      expect(doctor.getAvailableSlots(tuesdayDate), isEmpty);
      expect(doctor.getAvailableSlots(fridayDate), isEmpty);
    });

    test('unavailable doctor (isActive: false or isAvailable: false) offers no slots', () {
      final validSlots = [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '10:00', endTime: '10:30'),
      ];

      final inactiveDoctor = createTestDoctor(
        isActive: false,
        isAvailable: true,
        weeklySchedule: {'monday': validSlots},
      );
      final unavailableDoctor = createTestDoctor(
        isActive: true,
        isAvailable: false,
        weeklySchedule: {'monday': validSlots},
      );

      expect(inactiveDoctor.canBook, isFalse);
      expect(inactiveDoctor.hasActiveSchedule, isFalse);
      expect(inactiveDoctor.getAvailableSlots(mondayDate), isEmpty);

      expect(unavailableDoctor.canBook, isFalse);
      expect(unavailableDoctor.hasActiveSchedule, isFalse);
      expect(unavailableDoctor.getAvailableSlots(mondayDate), isEmpty);
    });

    test('disabled and malformed slots are filtered out', () {
      final slots = [
        TimeSlot(startTime: '09:00', endTime: '09:30', isAvailable: false), // disabled
        TimeSlot(startTime: 'invalid', endTime: '10:00', isAvailable: true), // malformed start
        TimeSlot(startTime: '25:00', endTime: '26:00', isAvailable: true), // out of range hour
        TimeSlot(startTime: '09:00', endTime: '25:00', isAvailable: true), // out of range end
        TimeSlot(startTime: '10:00', endTime: '09:00', isAvailable: true), // end before start
        TimeSlot(startTime: '10:00', endTime: '10:00', isAvailable: true), // zero duration
        TimeSlot(startTime: '10:00', endTime: 'bad_end', isAvailable: true), // malformed end
        TimeSlot(startTime: '', endTime: '11:00', isAvailable: true), // empty start
        TimeSlot(startTime: '10:00', endTime: '', isAvailable: true), // legacy start-only slot
        TimeSlot(startTime: '11:00', endTime: '11:30', isAvailable: true), // VALID
      ];

      // Test individual slot isValid flags
      expect(slots[0].isValid, isFalse);
      expect(slots[1].isValid, isFalse);
      expect(slots[2].isValid, isFalse);
      expect(slots[3].isValid, isFalse);
      expect(slots[4].isValid, isFalse);
      expect(slots[5].isValid, isFalse);
      expect(slots[6].isValid, isFalse);
      expect(slots[7].isValid, isFalse);
      expect(slots[8].isValid, isTrue);
      expect(slots[9].isValid, isTrue);

      final doctor = createTestDoctor(
        weeklySchedule: {'monday': slots},
      );

      final available = doctor.getAvailableSlots(mondayDate);
      expect(available.map((slot) => slot.fullDisplay),
          ['10:00', '11:00 - 11:30']);
    });

    test('day containing only disabled/malformed slots is treated as empty', () {
      final invalidSlots = [
        TimeSlot(startTime: '09:00', endTime: '09:30', isAvailable: false),
        TimeSlot(startTime: '10:00', endTime: '08:00', isAvailable: true),
      ];

      final doctor = createTestDoctor(
        weeklySchedule: {'monday': invalidSlots},
      );

      expect(doctor.hasActiveSchedule, isFalse);
      expect(doctor.getAvailableSlots(mondayDate), isEmpty);
    });

    test('real valid schedule preserved with correct display format', () {
      final slots = [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '09:30', endTime: '10:00'),
        TimeSlot(startTime: '14:00', endTime: '14:30'),
      ];

      final doctor = createTestDoctor(
        weeklySchedule: {
          'monday': slots,
          'wednesday': [TimeSlot(startTime: '11:00', endTime: '11:30')],
        },
      );

      expect(doctor.hasActiveSchedule, isTrue);
      final mondaySlots = doctor.getAvailableSlots(mondayDate);
      expect(mondaySlots.length, equals(3));
      expect(mondaySlots[0].display, equals('09:00'));
      expect(mondaySlots[0].fullDisplay, equals('09:00 - 09:30'));
      expect(mondaySlots[1].display, equals('09:30'));
      expect(mondaySlots[1].fullDisplay, equals('09:30 - 10:00'));
      expect(mondaySlots[2].display, equals('14:00'));
      expect(mondaySlots[2].fullDisplay, equals('14:00 - 14:30'));
    });
  });

  group('DoctorScheduleScreen deterministic user behavior widget tests', () {
    testWidgets('displays localized noScheduleSet when doctor has no schedule', (tester) async {
      final doctor = createTestDoctor(weeklySchedule: const {});

      await tester.pumpWidget(
        createTestApp(
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_no_schedule'),
            doctor: doctor,
            initialDate: mondayDate,
            captureNow: mondayDate,
            captureBookedSlots: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should display 0 time slots available
      expect(find.text('0 time slots available'), findsOneWidget);

      // Should display localized noScheduleSet message
      expect(find.text('No schedule set'), findsOneWidget);

      // Fallback appointment slots must NEVER appear
      expect(find.text('09:00 - 09:30'), findsNothing);
      expect(find.text('14:00 - 14:30'), findsNothing);
      expect(find.text('Book'), findsNothing);
    });

    testWidgets('displays localized noAvailableSlotsOnThisDay when day has no slots but doctor has schedule', (tester) async {
      final doctor = createTestDoctor(
        weeklySchedule: {
          'monday': [TimeSlot(startTime: '09:00', endTime: '09:30')],
        },
      );

      await tester.pumpWidget(
        createTestApp(
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_no_slots_today'),
            doctor: doctor,
            initialDate: tuesdayDate, // Tuesday has no schedule
            captureNow: mondayDate,
            captureBookedSlots: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 time slots available'), findsOneWidget);
      expect(find.text('No available slots on this day'), findsOneWidget);
      expect(find.text('No schedule set'), findsNothing);
    });

    testWidgets('displays valid active slots and allows booking confirmation', (tester) async {
      final doctor = createTestDoctor(
        weeklySchedule: {
          'monday': [
            TimeSlot(startTime: '09:00', endTime: '09:30'),
            TimeSlot(startTime: '10:00', endTime: '10:30'),
          ],
        },
      );

      await tester.pumpWidget(
        createTestApp(
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_valid_slots'),
            doctor: doctor,
            initialDate: mondayDate,
            captureNow: mondayDate,
            captureBookedSlots: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 time slots available'), findsOneWidget);
      expect(find.text('09:00 - 09:30'), findsOneWidget);
      expect(find.text('10:00 - 10:30'), findsOneWidget);

      // Tap the first slot book button
      final bookButtons = find.text('Book');
      expect(bookButtons, findsNWidgets(2));
      await tester.tap(bookButtons.first);
      await tester.pumpAndSettle();

      // Bottom confirmation sheet should appear
      expect(find.text('Confirm Booking'), findsWidgets);
      expect(find.text('Sarah Al-Mansoor'), findsOneWidget);
      expect(find.text('Internal Medicine'), findsOneWidget);
      expect(find.text('Sep 14, 2026'), findsOneWidget);
      expect(find.text('09:00 - 09:30'), findsWidgets);
    });

    testWidgets('arabic and kurdish localization renders appropriate no-schedule messages', (tester) async {
      final doctorNoSchedule = createTestDoctor(weeklySchedule: const {});
      final doctorMondayOnly = createTestDoctor(
        weeklySchedule: {
          'monday': [TimeSlot(startTime: '09:00', endTime: '09:30')],
        },
      );

      // Arabic: no schedule set
      await tester.pumpWidget(
        createTestApp(
          locale: const Locale('ar'),
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_ar_no_schedule'),
            doctor: doctorNoSchedule,
            initialDate: mondayDate,
            captureNow: mondayDate,
            captureBookedSlots: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('لم يتم تعيين جدول'), findsOneWidget);

      // Arabic: no slots on this day
      await tester.pumpWidget(
        createTestApp(
          locale: const Locale('ar'),
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_ar_no_slots'),
            doctor: doctorMondayOnly,
            initialDate: tuesdayDate,
            captureNow: mondayDate,
            captureBookedSlots: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('لا توجد مواعيد متاحة في هذا اليوم'), findsOneWidget);

      // Kurdish: no schedule set
      await tester.pumpWidget(
        createTestApp(
          locale: const Locale('ku'),
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_ku_no_schedule'),
            doctor: doctorNoSchedule,
            initialDate: mondayDate,
            captureNow: mondayDate,
            captureBookedSlots: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('هیچ خشتەیەک دیاری نەکراوە'), findsOneWidget);

      // Kurdish: no slots on this day
      await tester.pumpWidget(
        createTestApp(
          locale: const Locale('ku'),
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_ku_no_slots'),
            doctor: doctorMondayOnly,
            initialDate: tuesdayDate,
            captureNow: mondayDate,
            captureBookedSlots: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('هیچ کاتێک بەردەست نییە لەم ڕۆژەدا'), findsOneWidget);
    });
  });

  group('AppointmentModel exactAppointmentTime parsing tests', () {
    test('exactAppointmentTime parses minute correctly from range 09:30 - 10:00', () {
      final appt = AppointmentModel(
        id: 'appt-1',
        patientId: 'pat-1',
        patientName: 'Test Patient',
        patientEmail: 'pat@uhc.iq',
        doctorId: 'doctor-123',
        doctorName: 'Sarah Al-Mansoor',
        department: 'generalMedicine',
        appointmentDate: DateTime(2026, 9, 14),
        timeSlot: '09:30 - 10:00',
        type: AppointmentType.regularCheckup,
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );

      final exact = appt.exactAppointmentTime;
      expect(exact.year, equals(2026));
      expect(exact.month, equals(9));
      expect(exact.day, equals(14));
      expect(exact.hour, equals(9));
      expect(exact.minute, equals(30));
      expect(exact, equals(DateTime(2026, 9, 14, 9, 30)));
    });
  });

  group('AppointmentRepository formatClinicDate and availability models', () {
    test('formatClinicDate formats clinic calendar date YYYY-MM-DD without timezone shifting', () {
      expect(AppointmentRepository.formatClinicDate(DateTime(2026, 9, 14)), equals('2026-09-14'));
      expect(AppointmentRepository.formatClinicDate(DateTime(2026, 1, 5)), equals('2026-01-05'));
      expect(AppointmentRepository.formatClinicDate(DateTime(2026, 12, 31, 23, 59, 59)), equals('2026-12-31'));
      expect(AppointmentRepository.formatClinicDate(DateTime(2026, 4, 1, 0, 0, 0)), equals('2026-04-01'));
    });

    test('DoctorDayAvailability and DoctorDaySlot parse backend callable response correctly', () {
      final map = {
        'success': true,
        'doctorId': 'doctor-123',
        'appointmentDate': '2026-09-14',
        'doctorName': 'Dr. Sarah Al-Mansoor',
        'department': 'generalMedicine',
        'slots': [
          {
            'timeSlot': '09:00 - 09:30',
            'startTime': '09:00',
            'endTime': '09:30',
            'isAvailable': true,
          },
          {
            'timeSlot': '09:30 - 10:00',
            'startTime': '09:30',
            'endTime': '10:00',
            'isAvailable': false,
          },
        ],
      };

      final availability = DoctorDayAvailability.fromMap(map);
      expect(availability.success, isTrue);
      expect(availability.doctorId, equals('doctor-123'));
      expect(availability.appointmentDate, equals('2026-09-14'));
      expect(availability.doctorName, equals('Dr. Sarah Al-Mansoor'));
      expect(availability.department, equals('generalMedicine'));
      expect(availability.slots.length, equals(2));

      expect(availability.slots[0].timeSlot, equals('09:00 - 09:30'));
      expect(availability.slots[0].startTime, equals('09:00'));
      expect(availability.slots[0].endTime, equals('09:30'));
      expect(availability.slots[0].isAvailable, isTrue);

      expect(availability.slots[1].timeSlot, equals('09:30 - 10:00'));
      expect(availability.slots[1].startTime, equals('09:30'));
      expect(availability.slots[1].endTime, equals('10:00'));
      expect(availability.slots[1].isAvailable, isFalse);
    });

    test('DoctorDayAvailability handles empty or malformed maps safely', () {
      final emptyAvailability = DoctorDayAvailability.fromMap({});
      expect(emptyAvailability.success, isFalse);
      expect(emptyAvailability.doctorId, isEmpty);
      expect(emptyAvailability.appointmentDate, isEmpty);
      expect(emptyAvailability.doctorName, isEmpty);
      expect(emptyAvailability.department, isEmpty);
      expect(emptyAvailability.slots, isEmpty);

      final slot = DoctorDaySlot.fromMap({});
      expect(slot.timeSlot, isEmpty);
      expect(slot.startTime, isEmpty);
      expect(slot.endTime, isEmpty);
      expect(slot.isAvailable, isFalse);
    });
  });

  group('DoctorScheduleScreen error UI and date-race widget tests', () {
    testWidgets('shows localized error and retry button on failure and recovers after retry', (tester) async {
      final doctor = createTestDoctor(
        weeklySchedule: {
          'monday': [TimeSlot(startTime: '09:00', endTime: '09:30')],
        },
      );

      var failRequest = true;
      int callCount = 0;
      final repo = TestAppointmentRepository(
        availabilityHandler: (docId, date) async {
          callCount++;
          if (failRequest) {
            throw Exception('Simulated network error');
          }
          return DoctorDayAvailability(
            success: true,
            doctorId: docId,
            appointmentDate: AppointmentRepository.formatClinicDate(date),
            doctorName: doctor.name,
            department: doctor.departmentId,
            slots: const [
              DoctorDaySlot(
                timeSlot: '09:00 - 09:30',
                startTime: '09:00',
                endTime: '09:30',
                isAvailable: true,
              ),
            ],
          );
        },
      );

      await tester.pumpWidget(
        createTestApp(
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_error_test'),
            doctor: doctor,
            initialDate: mondayDate,
            captureNow: mondayDate,
            appointmentRepository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error UI must be displayed
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Slots must NOT be shown / selectable during error state
      expect(find.text('Book'), findsNothing);
      expect(callCount, equals(1));

      // Tap retry with successful response
      failRequest = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(callCount, equals(2));
      expect(find.text('Something went wrong'), findsNothing);
      expect(find.text('09:00 - 09:30'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);
    });

    testWidgets('guards against date-race and discards out-of-order availability responses', (tester) async {
      final doctor = createTestDoctor(
        weeklySchedule: {
          'monday': [TimeSlot(startTime: '09:00', endTime: '09:30')],
          'tuesday': [TimeSlot(startTime: '10:00', endTime: '10:30')],
        },
      );

      final Completer<DoctorDayAvailability> mondayCompleter = Completer();
      final Completer<DoctorDayAvailability> tuesdayCompleter = Completer();

      final repo = TestAppointmentRepository(
        availabilityHandler: (docId, date) {
          if (date.day == mondayDate.day) {
            return mondayCompleter.future;
          } else {
            return tuesdayCompleter.future;
          }
        },
      );

      await tester.pumpWidget(
        createTestApp(
          child: DoctorScheduleScreen(
            key: const Key('doctor_schedule_race_test'),
            doctor: doctor,
            initialDate: mondayDate,
            captureNow: mondayDate,
            appointmentRepository: repo,
          ),
        ),
      );
      await tester.pump(); // Loading Monday

      // Trigger day selection for Tuesday via TableCalendar onDaySelected
      final tableCalendarFinder = find.byType(TableCalendar);
      expect(tableCalendarFinder, findsOneWidget);
      final TableCalendar tableCalendar = tester.widget(tableCalendarFinder);
      tableCalendar.onDaySelected?.call(tuesdayDate, tuesdayDate);
      await tester.pump();

      // Complete Tuesday response FIRST
      tuesdayCompleter.complete(
        DoctorDayAvailability(
          success: true,
          doctorId: doctor.id,
          appointmentDate: '2026-09-15',
          doctorName: doctor.name,
          department: doctor.departmentId,
          slots: const [
            DoctorDaySlot(
              timeSlot: '10:00 - 10:30',
              startTime: '10:00',
              endTime: '10:30',
              isAvailable: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Now resolve the late Monday response LATER
      mondayCompleter.complete(
        DoctorDayAvailability(
          success: true,
          doctorId: doctor.id,
          appointmentDate: '2026-09-14',
          doctorName: doctor.name,
          department: doctor.departmentId,
          slots: const [
            DoctorDaySlot(
              timeSlot: '09:00 - 09:30',
              startTime: '09:00',
              endTime: '09:30',
              isAvailable: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Ensure late Monday response did not overwrite Tuesday
      expect(find.text('10:00 - 10:30'), findsOneWidget);
      expect(find.text('09:00 - 09:30'), findsNothing);
    });

    testWidgets('BookingScreen shows error and retry button on availability failure and recovers', (tester) async {
      final doctor = createTestDoctor(
        weeklySchedule: {
          'monday': [TimeSlot(startTime: '09:00', endTime: '09:30')],
        },
      );

      var failRequest = true;
      final repo = TestAppointmentRepository(
        availabilityHandler: (docId, date) async {
          if (failRequest) {
            throw Exception('Simulated booking error');
          }
          return DoctorDayAvailability(
            success: true,
            doctorId: docId,
            appointmentDate: AppointmentRepository.formatClinicDate(date),
            doctorName: doctor.name,
            department: doctor.departmentId,
            slots: const [
              DoctorDaySlot(
                timeSlot: '09:00 - 09:30',
                startTime: '09:00',
                endTime: '09:30',
                isAvailable: true,
              ),
            ],
          );
        },
      );

      await tester.pumpWidget(
        createTestApp(
          child: BookingScreen(
            doctor: doctor,
            initialDate: mondayDate,
            appointmentRepository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error UI must be displayed
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Tap retry with successful response
      failRequest = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong'), findsNothing);
      expect(find.text('09:00'), findsOneWidget);
    });
  });
}
