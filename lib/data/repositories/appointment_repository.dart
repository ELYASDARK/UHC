import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/appointment_model.dart';

/// Repository for appointment-related Firestore operations
class AppointmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static const String _collection = 'appointments';

  CollectionReference<Map<String, dynamic>> get _appointmentsRef =>
      _firestore.collection(_collection);

  static const int _queryBatchSize = 500;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchAllPages(
    Query<Map<String, dynamic>> query, {
    int batchSize = _queryBatchSize,
  }) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (true) {
      var pageQuery = query.limit(batchSize);
      if (lastDoc != null) {
        pageQuery = pageQuery.startAfterDocument(lastDoc);
      }

      final snapshot = await pageQuery.get();
      docs.addAll(snapshot.docs);

      if (snapshot.docs.length < batchSize) break;
      lastDoc = snapshot.docs.last;
    }

    return docs;
  }

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
    // Compare against *start of today* (midnight), not DateTime.now().
    // appointmentDate is stored as midnight of the appointment day, so
    // comparing against the exact current time would incorrectly classify
    // today's appointments as "past".
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    try {
      // Query by date on the server, then page through bounded batches so
      // older limited pages cannot hide valid upcoming appointments.
      var docs = await _fetchAllPages(_appointmentsRef
          .where('patientId', isEqualTo: userId)
          .where(
            'appointmentDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
          )
          .orderBy('appointmentDate', descending: true));

      // If no results and email is provided, try by patientEmail only
      if (docs.isEmpty && email != null) {
        docs = await _fetchAllPages(_appointmentsRef
            .where('patientEmail', isEqualTo: email)
            .where(
              'appointmentDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
            )
            .orderBy('appointmentDate', descending: true));
      }

      // Filter for upcoming appointments and pending/confirmed status in-memory
      final appointments =
          docs.map((doc) => AppointmentModel.fromFirestore(doc)).where((apt) {
        // Appointment is upcoming if its date is today or later
        final isUpcoming = !apt.appointmentDate.isBefore(startOfToday);
        final isActive = apt.status == AppointmentStatus.pending ||
            apt.status == AppointmentStatus.confirmed;
        return isUpcoming && isActive;
      }).toList();

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
    // Compare against *start of today* (midnight) to stay consistent
    // with getUpcomingAppointments. Today's active appointments are
    // NOT past.
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    try {
      // Page by appointmentDate so history is complete without one huge read.
      var docs = await _fetchAllPages(_appointmentsRef
          .where('patientId', isEqualTo: userId)
          .orderBy('appointmentDate', descending: true));

      // If no results and email is provided, try by patientEmail only
      if (docs.isEmpty && email != null) {
        docs = await _fetchAllPages(_appointmentsRef
            .where('patientEmail', isEqualTo: email)
            .orderBy('appointmentDate', descending: true));
      }

      // Filter for past/history appointments in-memory:
      // - Appointments with dates strictly before today, OR
      // - Cancelled appointments (any date), OR
      // - Completed appointments, OR
      // - No-show appointments
      final appointments =
          docs.map((doc) => AppointmentModel.fromFirestore(doc)).where((apt) {
        final isPastDate = apt.appointmentDate.isBefore(startOfToday);
        final isCancelled = apt.status == AppointmentStatus.cancelled;
        final isCompleted = apt.status == AppointmentStatus.completed;
        final isNoShow = apt.status == AppointmentStatus.noShow;
        return isPastDate || isCancelled || isCompleted || isNoShow;
      }).toList();

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
      final docs = await _fetchAllPages(_appointmentsRef
          .where('doctorId', isEqualTo: doctorId)
          .where(
            'appointmentDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'appointmentDate',
            isLessThan: Timestamp.fromDate(endOfDay),
          )
          .orderBy('appointmentDate', descending: true));

      // Filter by date and status in-memory
      return docs
          .map((doc) => AppointmentModel.fromFirestore(doc))
          .where((apt) {
        final isOnDate = apt.appointmentDate.isAfter(
              startOfDay.subtract(const Duration(seconds: 1)),
            ) &&
            apt.appointmentDate.isBefore(endOfDay);
        final isActive = apt.status == AppointmentStatus.pending ||
            apt.status == AppointmentStatus.confirmed;
        return isOnDate && isActive;
      }).toList()
        ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
    } catch (e) {
      debugPrint('Error getting doctor appointments: $e');
      return [];
    }
  }

  /// Create appointment
  Future<String> createAppointment(AppointmentModel appointment) async {
    final callable = _functions.httpsCallable('createAppointment');
    final result = await callable.call<Map<String, dynamic>>({
      'bookingReference': appointment.bookingReference,
      'patientId': appointment.patientId,
      'doctorId': appointment.doctorId,
      'doctorName': appointment.doctorName,
      'department': appointment.department,
      'appointmentDate': appointment.appointmentDate.toIso8601String(),
      'timeSlot': appointment.timeSlot,
      'type': appointment.type.name,
      'notes': appointment.notes,
    });
    return result.data['appointmentId'] as String;
  }

  /// Delete appointment permanently
  Future<void> deleteAppointment(String appointmentId) async {
    final callable = _functions.httpsCallable('deleteAppointment');
    await callable.call<void>({'appointmentId': appointmentId});
  }

  /// Delete all appointments for a user (useful for testing cleanup)
  Future<void> deleteAllUserAppointments(String userId) async {
    final snapshot =
        await _appointmentsRef.where('patientId', isEqualTo: userId).get();

    // Use batched writes for efficiency (chunked to respect 500 limit)
    final docs = snapshot.docs;
    for (var i = 0; i < docs.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < docs.length) ? i + 500 : docs.length;
      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }
      await batch.commit();
    }
  }

  /// Update appointment status (with optional statusUpdatedBy tracking)
  Future<void> updateAppointmentStatus(
    String appointmentId,
    AppointmentStatus status, {
    String? statusUpdatedBy,
  }) async {
    final callable = _functions.httpsCallable('updateAppointmentStatus');
    await callable.call<void>({
      'appointmentId': appointmentId,
      'status': status.name,
      'statusUpdatedBy': statusUpdatedBy,
    });
  }

  /// Cancel appointment
  Future<void> cancelAppointment(
    String appointmentId,
    String reason, {
    String? statusUpdatedBy,
  }) async {
    final callable = _functions.httpsCallable('cancelAppointment');
    await callable.call<void>({
      'appointmentId': appointmentId,
      'reason': reason,
      'statusUpdatedBy': statusUpdatedBy,
    });
  }

  /// Reschedule appointment
  Future<void> rescheduleAppointment(
    String appointmentId,
    DateTime newDate,
    String newTimeSlot,
    String? reason,
  ) async {
    final callable = _functions.httpsCallable('rescheduleAppointment');
    await callable.call<void>({
      'appointmentId': appointmentId,
      'appointmentDate': newDate.toIso8601String(),
      'timeSlot': newTimeSlot,
      'reason': reason,
    });
  }

  /// Mark appointment as completed
  Future<void> completeAppointment(
    String appointmentId, {
    String? notes,
    String? statusUpdatedBy,
  }) async {
    final callable = _functions.httpsCallable('updateAppointmentStatus');
    await callable.call<void>({
      'appointmentId': appointmentId,
      'status': AppointmentStatus.completed.name,
      'statusUpdatedBy': statusUpdatedBy,
    });
    if (notes != null) {
      await updateMedicalNotes(appointmentId, notes);
    }
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

    final docs = await _fetchAllPages(
      query.orderBy('appointmentDate', descending: true),
      batchSize: 1000,
    );
    return docs.map((doc) => AppointmentModel.fromFirestore(doc)).toList();
  }

  /// Stream user's appointments for real-time updates
  Stream<List<AppointmentModel>> streamUserAppointments(String userId) {
    return _appointmentsRef
        .where('patientId', isEqualTo: userId)
        .orderBy('appointmentDate', descending: true)
        .limit(200)
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
      final snapshot = await _appointmentsRef
          .where('doctorId', isEqualTo: doctorId)
          .where('timeSlot', isEqualTo: timeSlot)
          .where(
            'appointmentDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where(
            'appointmentDate',
            isLessThan: Timestamp.fromDate(endOfDay),
          )
          .orderBy('appointmentDate')
          .get();

      // Filter results in-memory for date range and status
      final conflictingAppointments = snapshot.docs.where((doc) {
        final data = doc.data();
        final appointmentDate = (data['appointmentDate'] as Timestamp).toDate();
        final status = data['status'] as String?;

        // Check if appointment is on the same day and is active (pending or confirmed)
        final isOnSameDay = appointmentDate.isAfter(
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

  // ─── Doctor-facing methods ───────────────────────────────────────

  /// Get all appointments for a doctor (no date filter)
  Future<List<AppointmentModel>> getAllDoctorAppointments(
    String doctorId,
  ) async {
    try {
      final docs = await _fetchAllPages(_appointmentsRef
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('appointmentDate', descending: true));
      final appointments =
          docs.map((doc) => AppointmentModel.fromFirestore(doc)).toList();
      appointments.sort(
        (a, b) => b.appointmentDate.compareTo(a.appointmentDate),
      );
      return appointments;
    } catch (e) {
      debugPrint('Error getting all doctor appointments: $e');
      return [];
    }
  }

  /// Fast dashboard query: only today and future appointments.
  Future<List<AppointmentModel>> getDoctorDashboardAppointments(
    String doctorId,
  ) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    try {
      final docs = await _fetchAllPages(_appointmentsRef
          .where('doctorId', isEqualTo: doctorId)
          .where(
            'appointmentDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday),
          )
          .orderBy('appointmentDate', descending: true));
      final appointments =
          docs.map((doc) => AppointmentModel.fromFirestore(doc)).toList();
      appointments.sort(
        (a, b) => a.appointmentDate.compareTo(b.appointmentDate),
      );
      return appointments;
    } catch (e) {
      debugPrint('Error getting doctor dashboard appointments: $e');
      return [];
    }
  }

  /// Update medical notes on an appointment
  Future<void> updateMedicalNotes(
    String appointmentId,
    String notes,
  ) async {
    final callable = _functions.httpsCallable('updateMedicalNotes');
    await callable.call<void>({
      'appointmentId': appointmentId,
      'notes': notes,
    });
  }

  /// Get all appointments between a patient and a specific doctor
  Future<List<AppointmentModel>> getPatientAppointmentsWithDoctor(
    String patientId,
    String doctorId,
  ) async {
    try {
      final docs = await _fetchAllPages(_appointmentsRef
          .where('doctorId', isEqualTo: doctorId)
          .where('patientId', isEqualTo: patientId)
          .orderBy('appointmentDate', descending: true));
      final appointments =
          docs.map((doc) => AppointmentModel.fromFirestore(doc)).toList();
      appointments.sort(
        (a, b) => b.appointmentDate.compareTo(a.appointmentDate),
      );
      return appointments;
    } catch (e) {
      debugPrint('Error getting patient appointments with doctor: $e');
      return [];
    }
  }

  /// Atomically increment the QR scan failure counter
  Future<void> incrementQrScanFailures(String appointmentId) async {
    final callable = _functions.httpsCallable('incrementQrScanFailures');
    await callable.call<void>({'appointmentId': appointmentId});
  }
}
