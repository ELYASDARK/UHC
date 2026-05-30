import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../data/models/appointment_model.dart';
import '../data/repositories/appointment_repository.dart';
import '../services/notification_scheduling_coordinator.dart';
import '../data/repositories/doctor_repository.dart';

/// Provider for managing appointments state
class AppointmentProvider extends ChangeNotifier {
  final AppointmentRepository _appointmentRepo = AppointmentRepository();
  final DoctorRepository _doctorRepo = DoctorRepository();

  List<AppointmentModel> _upcomingAppointments = [];
  List<AppointmentModel> _pastAppointments = [];
  AppointmentModel? _selectedAppointment;
  bool _isLoading = false;
  String? _error;
  Map<String, String?> _doctorPhotos = {};

  // Getters
  List<AppointmentModel> get upcomingAppointments => _upcomingAppointments;
  List<AppointmentModel> get pastAppointments => _pastAppointments;
  AppointmentModel? get selectedAppointment => _selectedAppointment;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get upcomingCount => _upcomingAppointments.length;
  Map<String, String?> get doctorPhotos => _doctorPhotos;

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
      await _fetchDoctorPhotos();
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
      // The backend transaction is the source of truth for slot availability.
      // If two users book at once, only the one that gets the slot lock succeeds.
      final appointmentId = await _appointmentRepo.createAppointment(
        appointment,
      );

      _error = null;
      unawaited(_runPostBookingTasks(appointment, appointmentId));
      return appointmentId;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _runPostBookingTasks(
    AppointmentModel appointment,
    String appointmentId,
  ) async {
    try {
      final coordinator = NotificationSchedulingCoordinator();
      await coordinator.scheduleLocalAppointmentReminders(
        appointment.copyWith(id: appointmentId),
      );
    } catch (e) {
      debugPrint('Failed to schedule local reminders: $e');
    }

    try {
      _upcomingAppointments = await _appointmentRepo.getUpcomingAppointments(
        appointment.patientId,
        email: appointment.patientEmail,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to refresh appointments after booking: $e');
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
      final coordinator = NotificationSchedulingCoordinator();
      await coordinator.cancelLocalAppointmentReminders(appointmentId);

      await _appointmentRepo.cancelAppointment(appointmentId, reason);

      await coordinator.resyncAfterSettingsChange(userId);

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
      final coordinator = NotificationSchedulingCoordinator();
      await coordinator.cancelLocalAppointmentReminders(appointmentId);

      await _appointmentRepo.deleteAppointment(appointmentId);

      await coordinator.resyncAfterSettingsChange(userId);

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

      // Cancel all local notifications on this device
      final coordinator = NotificationSchedulingCoordinator();
      await coordinator.cancelAllLocalReminders();

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

      final coordinator = NotificationSchedulingCoordinator();
      await coordinator.cancelLocalAppointmentReminders(appointmentId);

      await _appointmentRepo.rescheduleAppointment(
        appointmentId,
        newDate,
        newTimeSlot,
        reason,
      );

      await coordinator.resyncAfterSettingsChange(userId);

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
    _doctorPhotos = {};
    _error = null;
    notifyListeners();
  }

  /// Batch-fetch profile photos for all unique doctors across appointments.
  Future<void> _fetchDoctorPhotos() async {
    final allAppointments = [..._upcomingAppointments, ..._pastAppointments];
    final uniqueIds = allAppointments
        .map((a) => a.doctorId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    // Only fetch IDs we haven't cached yet
    final idsToFetch =
        uniqueIds.where((id) => !_doctorPhotos.containsKey(id)).toList();
    if (idsToFetch.isEmpty) return;
    // Fetch all doctor photos in parallel instead of sequentially (N+1 fix)
    await Future.wait(idsToFetch.map((id) async {
      try {
        final doctor = await _doctorRepo.getDoctorById(id);
        _doctorPhotos[id] = doctor?.photoUrl;
      } catch (_) {
        _doctorPhotos[id] = null;
      }
    }));
  }
}
