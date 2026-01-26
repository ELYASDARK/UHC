import 'package:flutter/material.dart';
import '../data/models/appointment_model.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../services/local_notification_service.dart';

/// Provider for managing appointments state
class AppointmentProvider extends ChangeNotifier {
  final AppointmentRepository _appointmentRepo = AppointmentRepository();
  final LocalNotificationService _notificationService =
      LocalNotificationService();
  final NotificationRepository _notificationRepo = NotificationRepository();

  List<AppointmentModel> _upcomingAppointments = [];
  List<AppointmentModel> _pastAppointments = [];
  AppointmentModel? _selectedAppointment;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<AppointmentModel> get upcomingAppointments => _upcomingAppointments;
  List<AppointmentModel> get pastAppointments => _pastAppointments;
  AppointmentModel? get selectedAppointment => _selectedAppointment;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get upcomingCount => _upcomingAppointments.length;

  /// Load user's appointments
  Future<void> loadAppointments(String userId, {String? email}) async {
    _isLoading = true;
    _error = null;
    // Note: Don't call notifyListeners() here to avoid "setState during build" error
    // The finally block will notify listeners when loading completes

    try {
      _upcomingAppointments = await _appointmentRepo.getUpcomingAppointments(
        userId,
        email: email,
      );
      _pastAppointments = await _appointmentRepo.getPastAppointments(
        userId,
        email: email,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load only upcoming appointments
  Future<void> loadUpcomingAppointments(String userId, {String? email}) async {
    try {
      _upcomingAppointments = await _appointmentRepo.getUpcomingAppointments(
        userId,
        email: email,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Load only past appointments
  Future<void> loadPastAppointments(String userId, {String? email}) async {
    try {
      _pastAppointments = await _appointmentRepo.getPastAppointments(
        userId,
        email: email,
      );
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Get appointment by ID
  Future<AppointmentModel?> getAppointmentById(String appointmentId) async {
    try {
      _selectedAppointment = await _appointmentRepo.getAppointmentById(
        appointmentId,
      );
      notifyListeners();
      return _selectedAppointment;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Book a new appointment
  Future<String?> bookAppointment(AppointmentModel appointment) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Check if time slot is available
      final isAvailable = await _appointmentRepo.isTimeSlotAvailable(
        appointment.doctorId,
        appointment.appointmentDate,
        appointment.timeSlot,
      );

      if (!isAvailable) {
        _error = 'This time slot is no longer available';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // Create appointment
      final appointmentId = await _appointmentRepo.createAppointment(
        appointment,
      );

      // Schedule local device notifications (1 week, 1 day, 1 hour before)
      await _notificationService.scheduleAppointmentReminders(
        appointmentId: appointmentId,
        doctorName: appointment.doctorName,
        appointmentTime: appointment.appointmentDate,
        timeSlot: appointment.timeSlot,
      );

      // Create Firebase notifications:
      // 1. Immediate confirmation notification
      await _notificationRepo.sendAppointmentConfirmation(
        userId: appointment.patientId,
        appointmentId: appointmentId,
        doctorName: appointment.doctorName,
        appointmentTime: appointment.appointmentDate,
        timeSlot: appointment.timeSlot,
      );

      // 2. Schedule 3 reminder notifications in Firebase (1 week, 1 day, 1 hour before)
      await _notificationRepo.scheduleAppointmentReminders(
        userId: appointment.patientId,
        appointmentId: appointmentId,
        doctorName: appointment.doctorName,
        appointmentTime: appointment.appointmentDate,
        timeSlot: appointment.timeSlot,
      );

      // Refresh upcoming appointments
      await loadUpcomingAppointments(appointment.patientId);

      _error = null;
      return appointmentId;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Cancel appointment
  Future<bool> cancelAppointment(
    String appointmentId,
    String reason,
    String userId, {
    String? doctorName,
    DateTime? appointmentTime,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Get appointment details if not provided
      AppointmentModel? appointment;
      if (doctorName == null || appointmentTime == null) {
        appointment = await _appointmentRepo.getAppointmentById(appointmentId);
      }

      await _appointmentRepo.cancelAppointment(appointmentId, reason);

      // Cancel scheduled local reminders
      await _notificationService.cancelAppointmentReminders(appointmentId);

      // Send cancellation notification to Firebase (also deletes pending reminders)
      await _notificationRepo.sendAppointmentCancellation(
        userId: userId,
        appointmentId: appointmentId,
        doctorName: doctorName ?? appointment?.doctorName ?? 'Unknown',
        appointmentTime:
            appointmentTime ?? appointment?.appointmentDate ?? DateTime.now(),
        reason: reason,
      );

      // Refresh appointments
      await loadAppointments(userId);

      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete appointment permanently
  Future<bool> deleteAppointment(String appointmentId, String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _appointmentRepo.deleteAppointment(appointmentId);

      // Cancel scheduled reminders
      await _notificationService.cancelAppointmentReminders(appointmentId);

      // Refresh appointments
      await loadAppointments(userId);

      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Delete all appointments for a user (useful for testing cleanup)
  Future<bool> deleteAllAppointments(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _appointmentRepo.deleteAllUserAppointments(userId);

      // Cancel all notifications
      await _notificationService.cancelAllNotifications();

      _upcomingAppointments = [];
      _pastAppointments = [];

      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reschedule appointment
  Future<bool> rescheduleAppointment({
    required String appointmentId,
    required DateTime newDate,
    required String newTimeSlot,
    required String doctorId,
    required String doctorName,
    required String userId,
    DateTime? oldAppointmentTime,
    String? reason,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Get old appointment time if not provided
      DateTime oldTime = oldAppointmentTime ?? DateTime.now();
      if (oldAppointmentTime == null) {
        final oldAppointment = await _appointmentRepo.getAppointmentById(
          appointmentId,
        );
        if (oldAppointment != null) {
          oldTime = oldAppointment.appointmentDate;
        }
      }

      // Check if new time slot is available
      final isAvailable = await _appointmentRepo.isTimeSlotAvailable(
        doctorId,
        newDate,
        newTimeSlot,
      );

      if (!isAvailable) {
        _error = 'This time slot is not available';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      await _appointmentRepo.rescheduleAppointment(
        appointmentId,
        newDate,
        newTimeSlot,
        reason,
      );

      // Cancel old local reminders and schedule new ones
      await _notificationService.cancelAppointmentReminders(appointmentId);
      await _notificationService.scheduleAppointmentReminders(
        appointmentId: appointmentId,
        doctorName: doctorName,
        appointmentTime: newDate,
        timeSlot: newTimeSlot,
      );

      // Update Firebase notifications (delete old, create rescheduled notification + new reminders)
      await _notificationRepo.sendAppointmentRescheduled(
        userId: userId,
        appointmentId: appointmentId,
        doctorName: doctorName,
        oldAppointmentTime: oldTime,
        newAppointmentTime: newDate,
        newTimeSlot: newTimeSlot,
      );

      // Refresh appointments
      await loadAppointments(userId);

      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check time slot availability
  Future<bool> checkTimeSlotAvailability(
    String doctorId,
    DateTime date,
    String timeSlot,
  ) async {
    try {
      return await _appointmentRepo.isTimeSlotAvailable(
        doctorId,
        date,
        timeSlot,
      );
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Select an appointment
  void selectAppointment(AppointmentModel appointment) {
    _selectedAppointment = appointment;
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedAppointment = null;
    notifyListeners();
  }

  /// Clear all data (on logout)
  void clear() {
    _upcomingAppointments = [];
    _pastAppointments = [];
    _selectedAppointment = null;
    _error = null;
    notifyListeners();
  }
}
