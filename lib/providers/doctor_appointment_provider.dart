import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/appointment_model.dart';
import '../data/models/doctor_model.dart';
import '../data/models/notification_model.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/user_repository.dart';
import '../services/local_notification_service.dart';

/// Provider for managing doctor-side appointment state
class DoctorAppointmentProvider extends ChangeNotifier {
  final AppointmentRepository _appointmentRepo = AppointmentRepository();
  final NotificationRepository _notificationRepo = NotificationRepository();
  final UserRepository _userRepo = UserRepository();

  List<AppointmentModel> _appointments = [];
  bool _isLoading = false;
  String? _error;
  Map<String, String?> _patientPhotos = {};

  // Daily notification config (set once via configureDailyNotifications)
  String? _dailyNotifDoctorUserId;
  Map<String, List<TimeSlot>>? _dailyNotifSchedule;

  // Getters
  List<AppointmentModel> get appointments => _appointments;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, String?> get patientPhotos => _patientPhotos;

  List<AppointmentModel> get upcomingAppointments {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return _appointments.where((apt) {
      // Compare against start of today (midnight) instead of current time,
      // because appointmentDate is stored as midnight of the appointment day.
      final isUpcoming = !apt.appointmentDate.isBefore(startOfToday);
      final isActive = apt.status == AppointmentStatus.pending ||
          apt.status == AppointmentStatus.confirmed;
      return isUpcoming && isActive;
    }).toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  List<AppointmentModel> get pastAppointments {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return _appointments.where((apt) {
      // Appointment date is before today (not just before current time)
      final isPastDate = apt.appointmentDate.isBefore(startOfToday);
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

  /// Map from DateTime.weekday (1=Mon … 7=Sun) to weeklySchedule key.
  static const _dayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// Configure daily summary notifications.
  /// Call once from the dashboard screen after login.
  /// After this, every [loadAppointments] call will auto-schedule.
  Future<void> configureDailyNotifications({
    required String doctorUserId,
    required Map<String, List<TimeSlot>> weeklySchedule,
    String? dailyNotificationTime,
  }) async {
    _dailyNotifDoctorUserId = doctorUserId;
    _dailyNotifSchedule = weeklySchedule;

    // Sync admin-set notification time to SharedPreferences
    if (dailyNotificationTime != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notif_daily_summary_time', dailyNotificationTime);
    }

    // If appointments are already loaded, schedule immediately
    if (_appointments.isNotEmpty) {
      scheduleDailyNotifications();
    }
  }

  /// Load all appointments for this doctor
  Future<void> loadAppointments(String doctorId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _appointments = await _appointmentRepo.getAllDoctorAppointments(doctorId);

      // Auto-mark overdue pending appointments as no-show (best-effort)
      await _autoMarkNoShow(doctorId);

      await _fetchPatientPhotos();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // Best-effort: schedule daily summary notifications in background
    scheduleDailyNotifications();
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
    _dailyNotifDoctorUserId = null;
    _dailyNotifSchedule = null;
    // Cancel any scheduled daily summary local notifications
    LocalNotificationService().cancelDoctorDailySummaries();
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

  /// Schedule daily summary notifications for the next 7 days.
  /// For each day, checks if tomorrow is a working day and counts pending
  /// appointments. Cancels all existing summaries first, then recreates.
  /// Internal routine to sync local notifications with Firestore/SharedPreferences
  Future<void> scheduleDailyNotifications() async {
    if (_dailyNotifDoctorUserId == null || _dailyNotifSchedule == null) return;

    final notifService = LocalNotificationService();

    final prefs = await SharedPreferences.getInstance();
    final dailySummaryEnabled = prefs.getBool('notif_daily_summary') ?? true;
    if (!dailySummaryEnabled) {
      return;
    }

    final timeString = prefs.getString('notif_daily_summary_time') ?? '21:00';

    // Parse configured time
    int targetHour = 21;
    int targetMin = 0;
    try {
      final parts = timeString.split(':');
      if (parts.length == 2) {
        targetHour = int.parse(parts[0]);
        targetMin = int.parse(parts[1]);
      }
    } catch (_) {}

    try {
      // Cancel existing daily summary local notifications
      await notifService.cancelDoctorDailySummaries();

      // Delete existing future daily summary Firestore docs
      await _notificationRepo
          .deleteFutureDailySummaries(_dailyNotifDoctorUserId!);
    } catch (e) {
      debugPrint('Failed to clean old daily summaries: $e');
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
      final notificationDate = today.add(Duration(days: dayOffset));
      // Configured time on notificationDate
      final scheduledTime =
          notificationDate.add(Duration(hours: targetHour, minutes: targetMin));

      // Skip if time has already passed
      if (scheduledTime.isBefore(now)) continue;

      // Target date is tomorrow relative to notificationDate
      final targetDate = notificationDate.add(const Duration(days: 1));
      final targetDayName = _dayNames[targetDate.weekday - 1];

      // Skip if it's not a working day tomorrow
      final daySlots = _dailyNotifSchedule![targetDayName];
      if (daySlots == null || daySlots.isEmpty) continue;

      // Count pending appointments for target date
      final startOfTarget =
          DateTime(targetDate.year, targetDate.month, targetDate.day);
      final endOfTarget = startOfTarget.add(const Duration(days: 1));

      final pendingCount = _appointments.where((apt) {
        final isTargetDay = apt.appointmentDate.isAfter(
              startOfTarget.subtract(const Duration(seconds: 1)),
            ) &&
            apt.appointmentDate.isBefore(endOfTarget);
        return isTargetDay && apt.status == AppointmentStatus.pending;
      }).length;

      const title = "Tomorrow's Appointments";
      final body = pendingCount == 0
          ? 'You have no booked appointments tomorrow'
          : pendingCount == 1
              ? 'You have 1 booked appointment tomorrow'
              : 'You have $pendingCount booked appointments tomorrow';

      // Schedule local push notification
      try {
        await notifService.scheduleDoctorDailySummary(
          dayOffset: dayOffset,
          title: title,
          body: body,
          scheduledTime: scheduledTime,
        );
      } catch (e) {
        debugPrint('Failed to schedule daily summary local notif: $e');
      }

      // Create Firestore notification doc (for in-app notification list)
      try {
        await _notificationRepo.createNotification(
          NotificationModel(
            id: '',
            userId: _dailyNotifDoctorUserId!,
            title: title,
            body: body,
            type: NotificationType.dailySummary,
            data: {
              'targetDate': targetDate.toIso8601String(),
              'pendingCount': pendingCount,
            },
            createdAt: DateTime.now(),
            scheduledFor: scheduledTime,
            isDelivered: false,
          ),
        );
      } catch (e) {
        debugPrint('Failed to create daily summary Firestore doc: $e');
      }
    }
  }

  /// Auto-mark pending appointments as no-show when their time has passed.
  ///
  /// Logic: appointment slot is ~30 min. After the slot ends, the patient gets
  /// a 30-minute grace window. If still pending after that (60 min total from
  /// slot start), the system marks it no-show automatically.
  ///
  /// Only `pending` appointments are affected — `confirmed` means
  /// the patient checked in (QR scan), so that stays for the doctor to close.
  Future<void> _autoMarkNoShow(String doctorId) async {
    final now = DateTime.now();
    // 30 min appointment duration + 30 min grace = 60 min after slot start
    const autoNoShowMinutes = 60;

    final overdue = _appointments.where((apt) {
      if (apt.status != AppointmentStatus.pending) return false;

      final cutoff = apt.exactAppointmentTime
          .add(const Duration(minutes: autoNoShowMinutes));
      return now.isAfter(cutoff);
    }).toList();

    if (overdue.isEmpty) return;

    debugPrint('Auto no-show: marking ${overdue.length} overdue appointment(s)');

    for (final apt in overdue) {
      try {
        await _appointmentRepo.updateAppointmentStatus(
          apt.id,
          AppointmentStatus.noShow,
          statusUpdatedBy: 'system_auto',
        );
      } catch (e) {
        debugPrint('Auto no-show failed for ${apt.id}: $e');
      }
    }

    // Re-fetch so the local list reflects the updated statuses
    try {
      _appointments =
          await _appointmentRepo.getAllDoctorAppointments(doctorId);
    } catch (e) {
      debugPrint('Re-fetch after auto no-show failed: $e');
    }
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
