import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/appointment_model.dart';

/// Repository for appointment-related Firestore operations
class AppointmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'appointments';

  CollectionReference<Map<String, dynamic>> get _appointmentsRef =>
      _firestore.collection(_collection);

  /// Get appointment by ID
  Future<AppointmentModel?> getAppointmentById(String appointmentId) async {
    final doc = await _appointmentsRef.doc(appointmentId).get();
    if (doc.exists) {
      return AppointmentModel.fromFirestore(doc);
    }
    return null;
  }

  /// Get user's upcoming appointments
  Future<List<AppointmentModel>> getUpcomingAppointments(
    String userId, {
    String? email,
  }) async {
    final now = DateTime.now();
    try {
      // First try by patientId only (no date filter to avoid index)
      var snapshot = await _appointmentsRef
          .where('patientId', isEqualTo: userId)
          .get();

      // If no results and email is provided, try by patientEmail only
      if (snapshot.docs.isEmpty && email != null) {
        snapshot = await _appointmentsRef
            .where('patientEmail', isEqualTo: email)
            .get();
      }

      // Filter for upcoming appointments and pending/confirmed status in-memory
      final appointments = snapshot.docs
          .map((doc) => AppointmentModel.fromFirestore(doc))
          .where((apt) {
            final isUpcoming =
                apt.appointmentDate.isAfter(now) ||
                apt.appointmentDate.isAtSameMomentAs(now);
            final isActive =
                apt.status == AppointmentStatus.pending ||
                apt.status == AppointmentStatus.confirmed;
            return isUpcoming && isActive;
          })
          .toList();

      // Sort by appointment date
      appointments.sort(
        (a, b) => a.appointmentDate.compareTo(b.appointmentDate),
      );

      return appointments;
    } catch (e) {
      debugPrint('Error getting upcoming appointments: $e');
      return [];
    }
  }

  /// Get user's past appointments (includes cancelled, completed, no-show, and past dates)
  Future<List<AppointmentModel>> getPastAppointments(
    String userId, {
    String? email,
  }) async {
    final now = DateTime.now();
    try {
      // First try by patientId only (no date filter to avoid index)
      var snapshot = await _appointmentsRef
          .where('patientId', isEqualTo: userId)
          .get();

      // If no results and email is provided, try by patientEmail only
      if (snapshot.docs.isEmpty && email != null) {
        snapshot = await _appointmentsRef
            .where('patientEmail', isEqualTo: email)
            .get();
      }

      // Filter for past/history appointments in-memory:
      // - Appointments with past dates, OR
      // - Cancelled appointments (any date), OR
      // - Completed appointments, OR
      // - No-show appointments
      final appointments = snapshot.docs
          .map((doc) => AppointmentModel.fromFirestore(doc))
          .where((apt) {
            final isPastDate = apt.appointmentDate.isBefore(now);
            final isCancelled = apt.status == AppointmentStatus.cancelled;
            final isCompleted = apt.status == AppointmentStatus.completed;
            final isNoShow = apt.status == AppointmentStatus.noShow;
            return isPastDate || isCancelled || isCompleted || isNoShow;
          })
          .toList();

      // Sort by appointment date (newest first)
      appointments.sort(
        (a, b) => b.appointmentDate.compareTo(a.appointmentDate),
      );

      // Limit to 50
      return appointments.take(50).toList();
    } catch (e) {
      debugPrint('Error getting past appointments: $e');
      return [];
    }
  }

  /// Get doctor's appointments for a specific date
  Future<List<AppointmentModel>> getDoctorAppointments(
    String doctorId,
    DateTime date,
  ) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      // Simplified query - only filter by doctorId
      final snapshot = await _appointmentsRef
          .where('doctorId', isEqualTo: doctorId)
          .get();

      // Filter by date and status in-memory
      return snapshot.docs
          .map((doc) => AppointmentModel.fromFirestore(doc))
          .where((apt) {
            final isOnDate =
                apt.appointmentDate.isAfter(
                  startOfDay.subtract(const Duration(seconds: 1)),
                ) &&
                apt.appointmentDate.isBefore(endOfDay);
            final isActive =
                apt.status == AppointmentStatus.pending ||
                apt.status == AppointmentStatus.confirmed;
            return isOnDate && isActive;
          })
          .toList()
        ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
    } catch (e) {
      debugPrint('Error getting doctor appointments: $e');
      return [];
    }
  }

  /// Create appointment
  Future<String> createAppointment(AppointmentModel appointment) async {
    final docRef = await _appointmentsRef.add(appointment.toFirestore());
    await docRef.update({'id': docRef.id});
    return docRef.id;
  }

  /// Delete appointment permanently
  Future<void> deleteAppointment(String appointmentId) async {
    await _appointmentsRef.doc(appointmentId).delete();
  }

  /// Delete all appointments for a user (useful for testing cleanup)
  Future<void> deleteAllUserAppointments(String userId) async {
    final snapshot = await _appointmentsRef
        .where('patientId', isEqualTo: userId)
        .get();

    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// Update appointment status
  Future<void> updateAppointmentStatus(
    String appointmentId,
    AppointmentStatus status,
  ) async {
    await _appointmentsRef.doc(appointmentId).update({
      'status': status.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Cancel appointment
  Future<void> cancelAppointment(String appointmentId, String reason) async {
    await _appointmentsRef.doc(appointmentId).update({
      'status': AppointmentStatus.cancelled.name,
      'cancelReason': reason,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Reschedule appointment
  Future<void> rescheduleAppointment(
    String appointmentId,
    DateTime newDate,
    String newTimeSlot,
    String? reason,
  ) async {
    await _appointmentsRef.doc(appointmentId).update({
      'appointmentDate': Timestamp.fromDate(newDate),
      'timeSlot': newTimeSlot,
      'rescheduleReason': reason,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Mark appointment as completed
  Future<void> completeAppointment(
    String appointmentId, {
    String? notes,
  }) async {
    final updates = <String, dynamic>{
      'status': AppointmentStatus.completed.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    };
    if (notes != null) {
      updates['medicalNotes'] = notes;
    }
    await _appointmentsRef.doc(appointmentId).update(updates);
  }

  /// Get all appointments (admin)
  Future<List<AppointmentModel>> getAllAppointments({
    DateTime? startDate,
    DateTime? endDate,
    AppointmentStatus? status,
  }) async {
    Query<Map<String, dynamic>> query = _appointmentsRef;

    if (startDate != null) {
      query = query.where(
        'appointmentDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    }
    if (endDate != null) {
      query = query.where(
        'appointmentDate',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    final snapshot = await query
        .orderBy('appointmentDate', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => AppointmentModel.fromFirestore(doc))
        .toList();
  }

  /// Stream user's appointments for real-time updates
  Stream<List<AppointmentModel>> streamUserAppointments(String userId) {
    return _appointmentsRef
        .where('patientId', isEqualTo: userId)
        .orderBy('appointmentDate', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppointmentModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// Check if time slot is available
  Future<bool> isTimeSlotAvailable(
    String doctorId,
    DateTime date,
    String timeSlot,
  ) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      // Simplified query - only filter by doctorId and timeSlot
      // Filter by date and status in-memory to avoid composite index requirement
      final snapshot = await _appointmentsRef
          .where('doctorId', isEqualTo: doctorId)
          .where('timeSlot', isEqualTo: timeSlot)
          .get();

      // Filter results in-memory for date range and status
      final conflictingAppointments = snapshot.docs.where((doc) {
        final data = doc.data();
        final appointmentDate = (data['appointmentDate'] as Timestamp).toDate();
        final status = data['status'] as String?;

        // Check if appointment is on the same day and is active (pending or confirmed)
        final isOnSameDay =
            appointmentDate.isAfter(
              startOfDay.subtract(const Duration(seconds: 1)),
            ) &&
            appointmentDate.isBefore(endOfDay);
        final isActive = status == 'pending' || status == 'confirmed';

        return isOnSameDay && isActive;
      });

      return conflictingAppointments.isEmpty;
    } catch (e) {
      // If query fails, assume slot is available to not block booking
      debugPrint('Error checking time slot availability: $e');
      return true;
    }
  }
}
