import 'package:flutter/material.dart';
import '../data/models/appointment_model.dart';
import '../data/models/notification_model.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/user_repository.dart';

/// Provider for managing doctor-side appointment state
class DoctorAppointmentProvider extends ChangeNotifier {
  final AppointmentRepository _appointmentRepo = AppointmentRepository();
  final NotificationRepository _notificationRepo = NotificationRepository();
  final UserRepository _userRepo = UserRepository();

  List<AppointmentModel> _appointments = [];
  bool _isLoading = false;
  String? _error;
  Map<String, String?> _patientPhotos = {};

  // Getters
  List<AppointmentModel> get appointments => _appointments;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, String?> get patientPhotos => _patientPhotos;

  List<AppointmentModel> get upcomingAppointments {
    final now = DateTime.now();
    return _appointments.where((apt) {
      final isUpcoming = apt.appointmentDate.isAfter(now) ||
          apt.appointmentDate.isAtSameMomentAs(now);
      final isActive = apt.status == AppointmentStatus.pending ||
          apt.status == AppointmentStatus.confirmed;
      return isUpcoming && isActive;
    }).toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  List<AppointmentModel> get pastAppointments {
    final now = DateTime.now();
    return _appointments.where((apt) {
      final isPastDate = apt.appointmentDate.isBefore(now);
      final isTerminal = apt.status == AppointmentStatus.completed ||
          apt.status == AppointmentStatus.cancelled ||
          apt.status == AppointmentStatus.noShow;
      return isPastDate || isTerminal;
    }).toList()
      ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
  }

  int get todayCount {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _appointments.where((apt) {
      final isToday = apt.appointmentDate.isAfter(
            startOfDay.subtract(const Duration(seconds: 1)),
          ) &&
          apt.appointmentDate.isBefore(endOfDay);
      final isActive = apt.status == AppointmentStatus.pending ||
          apt.status == AppointmentStatus.confirmed;
      return isToday && isActive;
    }).length;
  }

  AppointmentModel? get nextAppointment {
    final upcoming = upcomingAppointments;
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// Load all appointments for this doctor
  Future<void> loadAppointments(String doctorId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _appointments = await _appointmentRepo.getAllDoctorAppointments(doctorId);
      await _fetchPatientPhotos();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update appointment status (confirm, complete, no-show, cancel)
  ///
  /// [appointment] is needed to send a notification to the patient.
  /// [doctorName] is the display name shown in the notification.
  Future<bool> updateStatus(
    String appointmentId,
    AppointmentStatus status,
    String doctorId, {
    String? statusUpdatedBy,
    AppointmentModel? appointment,
    String? doctorName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _appointmentRepo.updateAppointmentStatus(
        appointmentId,
        status,
        statusUpdatedBy: statusUpdatedBy,
      );

      // Notify the patient about the status change
      if (appointment != null && doctorName != null) {
        await _notifyPatientStatusChange(appointment, status, doctorName);
      }

      // Refresh
      await loadAppointments(doctorId);
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Cancel appointment with a reason
  ///
  /// [appointment] is needed to send a cancellation notification to the patient.
  /// [doctorName] is the display name shown in the notification.
  Future<bool> cancelAppointment(
    String appointmentId,
    String reason,
    String doctorId, {
    String? statusUpdatedBy,
    AppointmentModel? appointment,
    String? doctorName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _appointmentRepo.cancelAppointment(
        appointmentId,
        reason,
        statusUpdatedBy: statusUpdatedBy,
      );

      // Notify the patient about the cancellation (best-effort)
      if (appointment != null && doctorName != null) {
        try {
          await _notificationRepo.sendAppointmentCancellation(
            userId: appointment.patientId,
            appointmentId: appointmentId,
            doctorName: doctorName,
            appointmentTime: appointment.appointmentDate,
            reason: reason,
          );
        } catch (e) {
          debugPrint('Failed to send cancellation notification: $e');
        }
      }

      await loadAppointments(doctorId);
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Update medical notes on an appointment
  Future<bool> updateMedicalNotes(
    String appointmentId,
    String notes,
    String doctorId,
  ) async {
    try {
      await _appointmentRepo.updateMedicalNotes(appointmentId, notes);
      // Refresh
      await loadAppointments(doctorId);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Mark appointment as completed with optional notes
  ///
  /// [appointment] is needed to send a notification to the patient.
  /// [doctorName] is the display name shown in the notification.
  Future<bool> completeAppointment(
    String appointmentId,
    String doctorId, {
    String? notes,
    String? statusUpdatedBy,
    AppointmentModel? appointment,
    String? doctorName,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _appointmentRepo.completeAppointment(
        appointmentId,
        notes: notes,
        statusUpdatedBy: statusUpdatedBy,
      );

      // Notify the patient that the appointment is completed
      if (appointment != null && doctorName != null) {
        await _notifyPatientStatusChange(
          appointment,
          AppointmentStatus.completed,
          doctorName,
        );
      }

      await loadAppointments(doctorId);
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Get appointment history between a patient and this doctor
  Future<List<AppointmentModel>> getPatientHistory(
    String patientId,
    String doctorId,
  ) async {
    try {
      return await _appointmentRepo.getPatientAppointmentsWithDoctor(
        patientId,
        doctorId,
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return [];
    }
  }

  /// Clear all data (on logout)
  void clear() {
    _appointments = [];
    _patientPhotos = {};
    _error = null;
    notifyListeners();
  }

  /// Increment QR scan failure count for an appointment (persisted to Firestore)
  Future<void> incrementQrScanFailures(String appointmentId) async {
    try {
      await _appointmentRepo.incrementQrScanFailures(appointmentId);
    } catch (e) {
      debugPrint('Failed to increment QR scan failures: $e');
    }
  }

  // ── Private helpers ──

  /// Send a Firestore notification to the patient when a doctor changes
  /// the appointment status (confirmed, completed, no-show).
  /// Cancellation is handled separately via [cancelAppointment].
  Future<void> _notifyPatientStatusChange(
    AppointmentModel appointment,
    AppointmentStatus newStatus,
    String doctorName,
  ) async {
    try {
      final String title;
      final String body;

      switch (newStatus) {
        case AppointmentStatus.confirmed:
          title = 'Appointment Confirmed';
          body =
              'Your appointment with Dr. $doctorName on ${_formatDate(appointment.appointmentDate)} at ${appointment.timeSlot} has been confirmed by the doctor.';
          break;
        case AppointmentStatus.completed:
          title = 'Appointment Completed';
          body =
              'Your appointment with Dr. $doctorName on ${_formatDate(appointment.appointmentDate)} has been marked as completed.';
          break;
        case AppointmentStatus.noShow:
          title = 'Marked as No-Show';
          body =
              'Your appointment with Dr. $doctorName on ${_formatDate(appointment.appointmentDate)} was marked as no-show.';
          break;
        default:
          return; // No notification for other statuses
      }

      await _notificationRepo.createNotification(
        NotificationModel(
          id: '',
          userId: appointment.patientId,
          title: title,
          body: body,
          type: NotificationType.appointmentConfirmation,
          data: {'appointmentId': appointment.id},
          createdAt: DateTime.now(),
          appointmentId: appointment.id,
          reminderType: ReminderType.immediate,
          isDelivered: true,
        ),
      );
    } catch (e) {
      debugPrint('Failed to send notification: $e');
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Batch-fetch profile photos for all unique patients in the appointment list.
  Future<void> _fetchPatientPhotos() async {
    final uniqueIds = _appointments.map((a) => a.patientId).toSet();
    // Only fetch IDs we haven't cached yet
    final idsToFetch = uniqueIds.where((id) => !_patientPhotos.containsKey(id));
    for (final id in idsToFetch) {
      try {
        final user = await _userRepo.getUserById(id);
        _patientPhotos[id] = user?.photoUrl;
      } catch (_) {
        _patientPhotos[id] = null;
      }
    }
  }
}
