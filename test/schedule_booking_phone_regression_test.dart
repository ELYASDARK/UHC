// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/models/doctor_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/providers/doctor_appointment_provider.dart';
import 'package:uhc/providers/doctor_day_availability_provider.dart';
import 'package:uhc/screens/doctor/appointments/doctor_appointment_detail_screen.dart';
import 'package:uhc/screens/doctor/schedule/doctor_schedule_entries.dart';
import 'package:uhc/screens/doctor/schedule/doctor_schedule_management_screen.dart';
import 'package:uhc/screens/patient/booking/booking_screen.dart';

import 'support/test_appointment_repository.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  final date = DateTime(2026, 10, 26);
  final slots = [
    TimeSlot(startTime: '09:00', endTime: '09:30'),
    TimeSlot(startTime: '09:30', endTime: '10:00'),
    TimeSlot(startTime: '10:00', endTime: '10:30'),
  ];

  test('range, legacy start and removed-schedule bookings stay visible once',
      () {
    for (final time in ['09:30 - 10:00', ' 9:30 ', '09:30 – 10:00']) {
      final rows = doctorScheduleEntries(
        doctorId: 'doctor',
        date: date,
        slots: slots,
        appointments: [_appointment(date, time)],
      );
      expect(rows.length, 3);
      expect(rows[1].appointment?.id, 'booking');
      expect(rows[1].slot.startTime, '09:30');
    }
    final rows = doctorScheduleEntries(
      doctorId: 'doctor',
      date: date,
      slots: [],
      appointments: [_appointment(date, '09:30 - 10:00')],
    );
    expect(rows.single.appointment?.id, 'booking');
  });

  test(
      'overlaps hide free rows, preserve separate bookings and ignore wrong identity',
      () {
    final booking = _appointment(date, '09:15 - 10:00');
    final rows = doctorScheduleEntries(
      doctorId: 'doctor',
      date: date,
      slots: slots,
      appointments: [
        booking,
        booking,
        _appointment(date, '11:00', id: 'removed'),
        _appointment(date, '10:00', id: 'wrong-doctor', doctorId: 'other'),
        _appointment(date.add(const Duration(days: 1)), '10:00',
            id: 'wrong-day'),
        _appointment(date, '10:00',
            id: 'cancelled', status: AppointmentStatus.cancelled),
      ],
    );
    expect(
        rows.map((row) => row.appointment?.id), ['booking', null, 'removed']);
    expect(rows[1].slot.startTime, '10:00');
    expect(scheduleSlotsOverlap(slots[0], slots[1]), isFalse);
    expect(scheduleSlotIsPast(date, '09:00', date.add(const Duration(days: 1))),
        isTrue);
    expect(
        scheduleSlotIsPast(date, '09:00', date.add(const Duration(hours: 10))),
        isTrue);
    expect(
        scheduleSlotIsPast(
            date, '09:00', date.subtract(const Duration(days: 1))),
        isFalse);
  });

  test(
      'availability deduplicates only matching inflight reads and rejects wrong identity',
      () async {
    final first = Completer<DoctorDayAvailability>();
    final newer = Completer<DoctorDayAvailability>();
    var calls = 0;
    final provider = DoctorDayAvailabilityProvider(TestAppointmentRepository(
      availabilityHandler: (_, __) =>
          ++calls == 1 ? first.future : newer.future,
    ));
    addTearDown(provider.dispose);
    final load = provider.load(doctorId: 'doctor', date: date);
    final same = provider.load(
        doctorId: 'doctor', date: date.add(const Duration(hours: 2)));
    expect(identical(load, same), isTrue);
    expect(calls, 1);
    final refresh =
        provider.load(doctorId: 'doctor', date: date, forceRefresh: true);
    expect(calls, 2);
    newer.complete(_availability('other', date));
    await refresh;
    first.complete(_availability('doctor', date));
    await load;
    expect(provider.errorMessage, isNotNull);
    expect(provider.isAvailable(slots.first), isFalse);
    expect(provider.isReadyFor(doctorId: 'doctor', date: date), isFalse);
  });

  test(
      'availability clears trusted slots immediately and ignores completion after disposal',
      () async {
    final pending = Completer<DoctorDayAvailability>();
    var calls = 0;
    final provider = DoctorDayAvailabilityProvider(TestAppointmentRepository(
      availabilityHandler: (id, day) async =>
          ++calls == 1 ? _availability(id, day) : pending.future,
    ));
    await provider.load(doctorId: 'doctor', date: date);
    expect(provider.isAvailable(slots.first), isTrue);
    final refresh = provider.load(doctorId: 'doctor', date: date);
    expect(provider.isLoading, isTrue);
    expect(provider.isAvailable(slots.first), isFalse);
    provider.dispose();
    pending.completeError(Exception('internal network error'));
    await refresh;
  });

  testWidgets(
      'schedule ignores old date responses, retries failures and disposes safely',
      (tester) async {
    final repo = _ScheduleRepository();
    final now = DateTime.now();
    await tester.pumpWidget(_app(DoctorScheduleManagementScreen(
      doctor: _doctor(),
      appointmentRepository: repo,
    )));
    await tester.pump(const Duration(seconds: 1));
    final calendar = tester.widget<TableCalendar>(find.byType(TableCalendar));
    final selected = now.add(const Duration(days: 1));
    calendar.onDaySelected!(selected, selected);
    await tester.pump();
    repo.requests[1].complete([_appointment(selected, '09:30 - 10:00')]);
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Patient'), findsOneWidget);
    repo.requests.first.completeError(Exception('private old request trace'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Patient'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
    final next = selected.add(const Duration(days: 1));
    tester.widget<TableCalendar>(find.byType(TableCalendar)).onDaySelected!(
        next, next);
    await tester.pump();
    repo.requests[2].completeError(Exception('private current request trace'));
    await tester.pumpAndSettle();
    expect(find.text('Available'), findsNothing);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repo.requests.length, 4);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.requests.last.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'date Continue advances while availability is pending and time remains disabled',
      (tester) async {
    final pending = Completer<DoctorDayAvailability>();
    final doctor = _doctor();
    await tester.pumpWidget(_app(BookingScreen(
      doctor: doctor,
      appointmentRepository: TestAppointmentRepository(
          availabilityHandler: (_, __) => pending.future),
    )));
    await tester.pumpAndSettle();
    final selected = DateTime.now().add(const Duration(days: 1));
    tester.widget<TableCalendar>(find.byType(TableCalendar)).onDaySelected!(
        selected, selected);
    await tester.pump();
    final continueButton =
        find.widgetWithText(ElevatedButton, 'Continue').first;
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNotNull);
    tester.widget<ElevatedButton>(continueButton).onPressed!();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 1);
    expect(find.text('Checking available times...'), findsWidgets);
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);
    pending.complete(_availability(doctor.id, selected));
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);
    await tester.ensureVisible(find.text('09:00').last);
    await tester.tap(find.text('09:00').last);
    await tester.pump();
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final status in AppointmentStatus.values) {
    testWidgets(
        'detail $status remains scrollable with large text and keyboard',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = DoctorAppointmentProvider();
      await tester
          .pumpWidget(ChangeNotifierProvider<DoctorAppointmentProvider>.value(
        value: provider,
        child: _app(
            DoctorAppointmentDetailScreen(
              appointment:
                  _appointment(DateTime.now(), '09:30 - 10:00', status: status),
              doctor: _doctor(),
            ),
            largeText: true),
      ));
      await tester.pumpAndSettle();
      final actions = find.byIcon(Icons.task_alt_rounded);
      if (status == AppointmentStatus.pending ||
          status == AppointmentStatus.confirmed) {
        expect(actions, findsOneWidget);
        final button =
            find.ancestor(of: actions, matching: find.byType(ElevatedButton));
        expect(tester.widget<ElevatedButton>(button).onPressed,
            status == AppointmentStatus.pending ? isNull : isNotNull);
        await tester
            .ensureVisible(find.widgetWithText(OutlinedButton, 'Cancel'));
        await tester.pumpAndSettle();
      }
      if (status == AppointmentStatus.confirmed ||
          status == AppointmentStatus.completed) {
        await tester.ensureVisible(find.text('Patient Documents'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text('Patient Documents')).bottom,
            lessThanOrEqualTo(640));
      }
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      if (status == AppointmentStatus.pending ||
          status == AppointmentStatus.confirmed) {
        await tester
            .ensureVisible(find.widgetWithText(OutlinedButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(
            tester
                .getRect(find.widgetWithText(OutlinedButton, 'Cancel'))
                .bottom,
            lessThanOrEqualTo(360));
      }
      await tester.ensureVisible(find.text('Save Notes'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Save Notes')).bottom,
          lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }
}

Widget _app(Widget child, {bool largeText = false}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: largeText
          ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.7)),
                child: child!,
              )
          : null,
      home: child,
    );

DoctorModel _doctor() => DoctorModel(
      id: 'doctor',
      userId: 'doctor-user',
      name: 'Synthetic Doctor',
      email: 'doctor@example.test',
      departmentId: 'generalMedicine',
      specialization: 'General',
      weeklySchedule: {
        for (final day in DoctorModel.canonicalWeekdays)
          day: [
            TimeSlot(startTime: '09:00', endTime: '09:30'),
            TimeSlot(startTime: '09:30', endTime: '10:00'),
          ]
      },
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

AppointmentModel _appointment(
  DateTime day,
  String time, {
  String id = 'booking',
  String doctorId = 'doctor',
  AppointmentStatus status = AppointmentStatus.pending,
}) =>
    AppointmentModel(
      id: id,
      patientId: 'patient',
      patientName: 'Synthetic Patient',
      patientEmail: 'patient@example.test',
      doctorId: doctorId,
      doctorName: 'Synthetic Doctor',
      department: 'generalMedicine',
      appointmentDate: day,
      timeSlot: time,
      status: status,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

DoctorDayAvailability _availability(String doctorId, DateTime day) =>
    DoctorDayAvailability(
      success: true,
      doctorId: doctorId,
      appointmentDate: AppointmentRepository.formatClinicDate(day),
      doctorName: 'Synthetic Doctor',
      department: 'generalMedicine',
      slots: const [
        DoctorDaySlot(
            timeSlot: '09:00 - 09:30',
            startTime: '09:00',
            endTime: '09:30',
            isAvailable: true)
      ],
    );

class _ScheduleRepository extends AppointmentRepository {
  final requests = <Completer<List<AppointmentModel>>>[];

  @override
  Future<List<AppointmentModel>> getDoctorAppointments(
      String doctorId, DateTime date,
      {bool requireServer = false}) {
    expect(requireServer, isTrue);
    final pending = Completer<List<AppointmentModel>>();
    requests.add(pending);
    return pending.future;
  }
}
