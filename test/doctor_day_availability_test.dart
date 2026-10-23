// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/data/models/doctor_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/providers/doctor_day_availability_provider.dart';

import 'support/test_appointment_repository.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  final mondayDate = DateTime(2026, 9, 14);
  final tuesdayDate = DateTime(2026, 9, 15);

  group('Trusted selected-day availability', () {
    test('a late failed request cannot replace the newer available day',
        () async {
      final oldRequest = Completer<DoctorDayAvailability>();
      final repo = TestAppointmentRepository(
        availabilityHandler: (doctorId, date) async {
          if (date == mondayDate) return oldRequest.future;
          return DoctorDayAvailability(
            success: true,
            doctorId: doctorId,
            appointmentDate: AppointmentRepository.formatClinicDate(date),
            doctorName: 'Doctor',
            department: 'generalMedicine',
            slots: const [
              DoctorDaySlot(
                timeSlot: '10:00 - 10:30',
                startTime: '10:00',
                endTime: '10:30',
                isAvailable: true,
              ),
            ],
          );
        },
      );
      final availability = DoctorDayAvailabilityProvider(repo);
      addTearDown(availability.dispose);
      final staleLoad = availability.load(doctorId: 'doctor', date: mondayDate);
      await availability.load(doctorId: 'doctor', date: tuesdayDate);
      oldRequest.completeError(Exception('Old request failed'));
      await staleLoad;

      expect(availability.errorMessage, isNull);
      expect(availability.isLoading, isFalse);
      expect(
          availability.isAvailable(
            TimeSlot(startTime: '10:00', endTime: '10:30'),
          ),
          isTrue);
    });

    test(
        'a changed schedule range cannot reuse availability for the old end time',
        () async {
      final repo = TestAppointmentRepository(
        availabilityHandler: (doctorId, date) async => DoctorDayAvailability(
          success: true,
          doctorId: doctorId,
          appointmentDate: AppointmentRepository.formatClinicDate(date),
          doctorName: 'Doctor',
          department: 'generalMedicine',
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
      final availability = DoctorDayAvailabilityProvider(repo);
      addTearDown(availability.dispose);
      await availability.load(doctorId: 'doctor', date: mondayDate);

      expect(
          availability.isAvailable(
            TimeSlot(startTime: '09:00', endTime: '09:30'),
          ),
          isTrue);
      expect(
          availability.isAvailable(
            TimeSlot(startTime: '09:00', endTime: '10:00'),
          ),
          isFalse);
    });
  });
}
