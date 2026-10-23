import 'package:uhc/data/repositories/appointment_repository.dart';

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
