// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/providers/appointment_provider.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  test(
      'Competing booking shows a clean conflict and clears it on the next attempt',
      () async {
    final repository = _FailingBookingRepository();
    final provider = AppointmentProvider(appointmentRepository: repository);
    addTearDown(provider.dispose);

    expect(await provider.bookAppointment(_appointment()), isNull);
    expect(provider.bookingFailureCode, 'already-exists');
    expect(provider.error,
        'This time slot was just booked. Please choose another time.');
    expect(provider.isLoading, isFalse);

    repository.failure = FirebaseFunctionsException(
      code: 'permission-denied',
      message:
          'Internal authorization detail\n#0 package:private/source.dart:42',
    );
    expect(await provider.bookAppointment(_appointment()), isNull);
    expect(provider.bookingFailureCode, 'permission-denied');
    expect(
        provider.error, 'Unable to complete your booking. Please try again.');
    expect(provider.error, isNot(contains('Internal')));
    expect(provider.error, isNot(contains('package:')));
  });

  test(
      'Unexpected booking failures never expose exception text or stack traces',
      () async {
    final repository = _FailingBookingRepository()
      ..failure = StateError('Private implementation detail\n#0 stack frame');
    final provider = AppointmentProvider(appointmentRepository: repository);
    addTearDown(provider.dispose);

    expect(await provider.bookAppointment(_appointment()), isNull);
    expect(provider.bookingFailureCode, isNull);
    expect(
        provider.error, 'Unable to complete your booking. Please try again.');
    expect(provider.isLoading, isFalse);
  });
}

class _FailingBookingRepository extends AppointmentRepository {
  Object failure = FirebaseFunctionsException(
    code: 'already-exists',
    message: 'This time slot is no longer available.\n#0 native stack trace',
  );

  @override
  Future<AppointmentBookingResult> createAppointment(
      AppointmentModel appointment) async {
    throw failure;
  }
}

AppointmentModel _appointment() => AppointmentModel(
      id: '',
      patientId: 'test-patient',
      patientName: 'Test Patient',
      patientEmail: 'test@example.com',
      doctorId: 'test-doctor',
      doctorName: 'Test Doctor',
      department: 'dentistry',
      appointmentDate: DateTime(2026, 10, 22),
      timeSlot: '09:00 - 09:30',
      createdAt: DateTime(2026, 10, 21),
      updatedAt: DateTime(2026, 10, 21),
    );
