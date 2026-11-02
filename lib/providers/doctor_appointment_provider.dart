import 'dart:async';
import '../core/utils/session_read_cache.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/notifications/notification_preferences.dart';
import '../data/models/appointment_model.dart';
import '../data/models/doctor_model.dart';
import '../data/repositories/appointment_repository.dart';
import '../data/repositories/user_repository.dart';
import '../services/local_notification_service.dart';

/// Provider for managing doctor-side appointment state
class DoctorAppointmentProvider extends ChangeNotifier {
  final AppointmentRepository _appointmentRepo;

  final String? sessionUserId;
  final String? sessionScope;
  bool _hasLoaded = false;
  bool _hasLoadedFull = false;
  bool _loadingFull = false;
  DateTime? _loadedAt;
  Future<void>? _loadInFlight;
  Future<void>? _maintenanceInFlight;
  int _mutationsPending = 0;
  final _reads = SessionReadCache<List<AppointmentModel>>(
      retention: Duration.zero, timeout: const Duration(seconds: 15));
  Future<void>? _photoLoad;
  DateTime? _lastPhotoRefresh;
  bool _disposed = false;
  int _loadGeneration = 0;
  String? loadedDoctorId;

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  DoctorAppointmentProvider(
      {this.sessionUserId,
      this.sessionScope,
      AppointmentRepository? appointmentRepository})
      : _appointmentRepo = appointmentRepository ?? AppointmentRepository();
  final UserRepository _userRepo = UserRepository();

  List<AppointmentModel> _appointments = [];
  bool _isLoading = false;
  String? _error;
  Map<String, String?> _patientPhotos = {};

  // Daily notification config (set once via configureDailyNotifications)
  String? _dailyNotifDoctorUserId;
  Map<String, List<TimeSlot>>? _dailyNotifSchedule;
  Future<void>? _dailyScheduleInFlight;
  DateTime? _lastDailyScheduleAt;
  static const Duration _dailyScheduleCooldown = Duration(seconds: 5);

  // Getters
  List<AppointmentModel> get appointments => _appointments;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  bool get hasLoadedFull => _hasLoadedFull;
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

  Future<void> loadAppointments(String doctorId, {bool forceRefresh = true}) =>
      _loadDoctorAppointments(doctorId,
          dashboard: false, forceRefresh: forceRefresh);

  Future<void> loadDashboardAppointments(String doctorId) =>
      _loadDoctorAppointments(doctorId, dashboard: true, forceRefresh: true);

  bool _isCurrentLoad(int generation) =>
      !_disposed && generation == _loadGeneration;

  Future<void> _loadDoctorAppointments(String doctorId,
      {required bool dashboard, required bool forceRefresh}) {
    if (_disposed) return Future.value();
    if (loadedDoctorId != doctorId) {
      clear();
      loadedDoctorId = doctorId;
    }
    if (_loadInFlight != null) {
      if (dashboard || _loadingFull) return _loadInFlight!;
      return _loadInFlight!
          .then((_) => loadAppointments(doctorId, forceRefresh: forceRefresh));
    }
    if (!forceRefresh &&
        _hasLoadedFull &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(seconds: 30)) {
      return Future.value();
    }
    final generation = ++_loadGeneration;
    _reads.bindSession('$doctorId/$dashboard');
    _loadingFull = !dashboard;
    _isLoading = true;
    _error = null;
    notifyListeners();
    return _loadInFlight =
        _readAppointments(doctorId, generation, dashboard: dashboard);
  }

  Future<void> _readAppointments(String doctorId, int generation,
      {required bool dashboard}) async {
    try {
      final appointments = await _reads.read(() => dashboard
          ? _appointmentRepo.getDoctorDashboardAppointments(doctorId)
          : _appointmentRepo.getAllDoctorAppointments(doctorId));
      if (!_isCurrentLoad(generation)) return;
      if (dashboard && _hasLoadedFull) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        _appointments = [
          ..._appointments.where((apt) => apt.appointmentDate.isBefore(today)),
          ...appointments,
        ];
      } else {
        _appointments = appointments;
      }
      _hasLoaded = true;
      _hasLoadedFull = _hasLoadedFull || !dashboard;
      _loadedAt = DateTime.now();
    } catch (error) {
      if (_isCurrentLoad(generation)) {
        if (error is FirebaseException &&
            ['permission-denied', 'unauthenticated'].contains(error.code)) {
          _appointments = [];
          _patientPhotos.clear();
          _hasLoaded = false;
          _hasLoadedFull = false;
        }
        _error = 'Unable to refresh appointments. Please try again.';
      }
    } finally {
      if (_isCurrentLoad(generation)) {
        _isLoading = false;
        _loadInFlight = null;
        notifyListeners();
      }
    }
    if (!_isCurrentLoad(generation) || _error != null) return;
    _runDashboardPostLoadWork(doctorId);
    unawaited(scheduleDailyNotifications());
  }

  /// Pause maintenance after its current server operation before a user write.
  Future<T> _mutate<T>(Future<T> Function() write) async {
    _mutationsPending++;
    try {
      await _maintenanceInFlight;
      if (_disposed) throw StateError('The session has ended.');
      final result = await write();
      _loadGeneration++;
      _loadInFlight = null;
      _reads.invalidate();
      _loadedAt = null;
      return result;
    } finally {
      _mutationsPending--;
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
      await _mutate(() => _appointmentRepo.updateAppointmentStatus(
            appointmentId,
            status,
            statusUpdatedBy: statusUpdatedBy,
          ));

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

  Future<bool> confirmCheckIn(
    String appointmentId,
    String qrCode,
    String doctorId,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _mutate(() =>
          _appointmentRepo.confirmAppointmentCheckIn(appointmentId, qrCode));
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
      await _mutate(() => _appointmentRepo.cancelAppointment(
            appointmentId,
            reason,
            statusUpdatedBy: statusUpdatedBy,
          ));

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
      await _mutate(
          () => _appointmentRepo.updateMedicalNotes(appointmentId, notes));
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
      await _mutate(() => _appointmentRepo.completeAppointment(
            appointmentId,
            notes: notes,
            statusUpdatedBy: statusUpdatedBy,
          ));

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
    _loadGeneration++;
    loadedDoctorId = null;
    _reads.bindSession(null);
    _loadInFlight = null;
    _hasLoaded = false;
    _hasLoadedFull = false;
    _loadedAt = null;
    _isLoading = false;
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
    if (_disposed ||
        _dailyNotifDoctorUserId == null ||
        _dailyNotifSchedule == null) {
      return;
    }
    if (_dailyScheduleInFlight != null) {
      debugPrint(
        'Daily summary scheduling skipped: a previous sync is still in progress.',
      );
      await _dailyScheduleInFlight;
      return;
    }

    final now = DateTime.now();
    if (_lastDailyScheduleAt != null &&
        now.difference(_lastDailyScheduleAt!) < _dailyScheduleCooldown) {
      debugPrint(
        'Daily summary scheduling skipped: cooldown active (${now.difference(_lastDailyScheduleAt!).inSeconds}s < ${_dailyScheduleCooldown.inSeconds}s).',
      );
      return;
    }

    final run = _scheduleDailyNotificationsInternal();
    _dailyScheduleInFlight = run;
    try {
      await run;
      _lastDailyScheduleAt = DateTime.now();
    } finally {
      _dailyScheduleInFlight = null;
    }
  }

  Future<void> _scheduleDailyNotificationsInternal() async {
    if (kIsWeb) return;
    if (_dailyNotifDoctorUserId == null || _dailyNotifSchedule == null) return;

    final notifService = LocalNotificationService();

    try {
      // Cancel existing daily summary local notifications
      await notifService.cancelDoctorDailySummaries();
    } catch (e) {
      debugPrint('Failed to cancel old daily summaries: $e');
    }

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_dailyNotifDoctorUserId)
          .get();
      if (_disposed) return;
      final userData = userSnap.data();
      if (userData == null) return;
      final isDoctor = userData['role'] == 'doctor';
      final prefsMap =
          userData['notificationSettings'] as Map<String, dynamic>?;
      final settings = NotificationPreferences.fromMap(prefsMap,
          isDoctor: isDoctor, isWeb: kIsWeb);

      if (!settings.doctorDailySummaryEnabled) {
        return;
      }

      // Only schedule local daily summaries if in local delivery mode!
      if (settings.doctorDailySummaryDelivery !=
          NotificationDeliveryMode.local) {
        return;
      }

      final timeString = settings.doctorDailySummaryTime;

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

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        if (_disposed) return;
        final notificationDate = today.add(Duration(days: dayOffset));
        // Configured time on notificationDate
        final scheduledTime = notificationDate
            .add(Duration(hours: targetHour, minutes: targetMin));

        // Skip if time has already passed
        if (scheduledTime.isBefore(now)) continue;

        // Target date is tomorrow relative to notificationDate
        final targetDate = notificationDate.add(const Duration(days: 1));
        final targetDayName = _dayNames[targetDate.weekday - 1];

        // Skip if it's not a working day tomorrow
        final daySlots = _dailyNotifSchedule![targetDayName];
        if (daySlots == null || daySlots.isEmpty) continue;

        const title = "Tomorrow's UHC Schedule";
        const body = "Open UHC to review tomorrow's schedule.";

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
      }
    } catch (e) {
      debugPrint('Error inside _scheduleDailyNotificationsInternal: $e');
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
  Future<void> _autoMarkNoShow(
    String doctorId, {
    required int generation,
  }) async {
    if (!_isCurrentLoad(generation)) return;
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

    debugPrint(
        'Auto no-show: marking ${overdue.length} overdue appointment(s)');

    final changedIds = <String>{};
    for (final apt in overdue) {
      if (!_isCurrentLoad(generation) || _mutationsPending > 0) break;
      try {
        await _appointmentRepo.updateAppointmentStatus(
          apt.id,
          AppointmentStatus.noShow,
          statusUpdatedBy: 'system_auto',
        );
        changedIds.add(apt.id);
      } catch (e) {
        debugPrint('Auto no-show failed for ${apt.id}: $e');
      }
    }

    if (!_isCurrentLoad(generation)) return;
    final overdueIds = changedIds;
    _appointments = _appointments
        .map((apt) => overdueIds.contains(apt.id)
            ? apt.copyWith(status: AppointmentStatus.noShow)
            : apt)
        .toList();
    notifyListeners();
  }

  /// Batch-fetch profile photos for all unique patients in the appointment list.
  Future<void> _fetchPatientPhotos() async {
    final pending = _photoLoad;
    if (pending != null) await pending;
    if (_disposed) return;
    if (_photoLoad != null) return _photoLoad!;
    if (_lastPhotoRefresh == null ||
        DateTime.now().difference(_lastPhotoRefresh!) >=
            const Duration(minutes: 5)) {
      _patientPhotos.clear();
      _lastPhotoRefresh = DateTime.now();
    }
    final work = _readPatientPhotos();
    _photoLoad = work;
    try {
      await work;
    } finally {
      if (identical(_photoLoad, work)) _photoLoad = null;
    }
  }

  Future<void> _readPatientPhotos() async {
    final generation = _loadGeneration;
    final uniqueIds = _appointments
        .map((a) => a.patientId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    // Only fetch IDs we haven't cached yet
    final idsToFetch =
        uniqueIds.where((id) => !_patientPhotos.containsKey(id)).toList();
    if (idsToFetch.isEmpty) return;
    var next = 0;
    await Future.wait(List.generate(4, (_) async {
      while (next < idsToFetch.length && _isCurrentLoad(generation)) {
        final id = idsToFetch[next++];
        try {
          final user = await _userRepo.getUserById(id);
          if (_isCurrentLoad(generation)) _patientPhotos[id] = user?.photoUrl;
        } catch (_) {
          // Transient failures can be retried on a later refresh.
        }
      }
    }));
    if (_isCurrentLoad(generation)) notifyListeners();
  }

  void _runDashboardPostLoadWork(String doctorId) {
    unawaited(_fetchPatientPhotos());
    if (_maintenanceInFlight != null || _mutationsPending > 0) return;
    final work = _autoMarkNoShow(doctorId, generation: _loadGeneration);
    _maintenanceInFlight = work;
    unawaited(work.whenComplete(() {
      if (identical(_maintenanceInFlight, work)) _maintenanceInFlight = null;
    }));
  }
}
