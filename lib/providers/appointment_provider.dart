import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../data/models/appointment_model.dart';
import '../data/repositories/appointment_repository.dart';
import '../services/notification_scheduling_coordinator.dart';
import '../data/repositories/doctor_repository.dart';
import '../core/utils/session_read_cache.dart';

/// Provider for managing appointments state
class AppointmentProvider extends ChangeNotifier {
  final AppointmentRepository _appointmentRepo;
  final String? sessionUserId;
  final String? sessionScope;
  int _generation = 0;
  String? _ownerId;
  String? _ownerEmail;
  Future<void>? _currentLoad;
  _HistoryRequest? _historyRequest;
  bool _historyRefreshQueued = false;
  bool _historyRetryReset = true;
  DateTime? _currentLoadedAt;
  DateTime? _historyLoadedAt;
  bool _hasLoadedUpcoming = false;
  bool _hasLoadedHistory = false;
  bool _historyLoading = false;
  bool _upcomingLoading = false;
  String? _historyError;
  AppointmentHistoryPage? _historyPage;
  static const _retention = Duration(seconds: 30);
  final _currentReads = SessionReadCache<List<AppointmentModel>>(
      retention: _retention, timeout: const Duration(seconds: 15));
  Future<void>? _photoLoad;
  DateTime? _lastPhotoRefresh;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  final DoctorRepository _doctorRepo = DoctorRepository();

  List<AppointmentModel> _upcomingAppointments = [];
  List<AppointmentModel> _pastAppointments = [];
  AppointmentModel? _selectedAppointment;
  bool _isLoading = false;
  String? _error;
  String? _bookingFailureCode;
  Map<String, String?> _doctorPhotos = {};

  AppointmentProvider(
      {this.sessionUserId,
      this.sessionScope,
      AppointmentRepository? appointmentRepository})
      : _appointmentRepo = appointmentRepository ?? AppointmentRepository();

  // Getters
  List<AppointmentModel> get upcomingAppointments => _upcomingAppointments;
  List<AppointmentModel> get pastAppointments => _pastAppointments;
  AppointmentModel? get selectedAppointment => _selectedAppointment;
  bool get isLoading => _isLoading || _upcomingLoading;
  bool get hasLoadedUpcoming => _hasLoadedUpcoming;
  bool get hasLoadedHistory => _hasLoadedHistory;
  bool get isLoadingHistory => _historyLoading;
  bool get hasMoreHistory => _historyPage?.hasMore ?? false;
  String? get historyError => _historyError;
  String? get error => _error;
  String? get bookingFailureCode => _bookingFailureCode;
  int get upcomingCount => _upcomingAppointments.length;
  Map<String, String?> get doctorPhotos => _doctorPhotos;

  bool _current(int generation) => !_disposed && generation == _generation;

  void _bindOwner(String userId, String? email) {
    if (_ownerId != userId) {
      clear();
      _ownerId = userId;
    }
    _ownerEmail = email ?? _ownerEmail;
    _currentReads.bindSession(userId);
  }

  bool _fresh(DateTime? loadedAt) =>
      loadedAt != null && DateTime.now().difference(loadedAt) < _retention;

  /// The current list becomes usable without waiting for history or portraits.
  Future<void> loadAppointments(String userId,
      {String? email, bool forceRefresh = true}) {
    if (_disposed || (sessionUserId != null && sessionUserId != userId)) {
      return Future.value();
    }
    _bindOwner(userId, email);
    if (_currentLoad != null) return _currentLoad!;
    if (!forceRefresh && _fresh(_currentLoadedAt)) return Future.value();
    final generation = _generation;
    _upcomingLoading = true;
    _error = null;
    notifyListeners();
    final load = _readUpcoming(userId, generation);
    _currentLoad = load;
    return load;
  }

  Future<void> _readUpcoming(String userId, int generation) async {
    try {
      final upcoming = await _currentReads.read(
          () => _appointmentRepo.getUpcomingAppointments(userId,
              email: _ownerEmail),
          forceRefresh: true);
      if (!_current(generation)) return;
      _upcomingAppointments = upcoming;
      _hasLoadedUpcoming = true;
      _currentLoadedAt = DateTime.now();
      unawaited(_fetchDoctorPhotos());
    } catch (error) {
      if (!_current(generation)) return;
      _discardIfUnauthorized(error);
      _error = 'Unable to refresh appointments. Please try again.';
      notifyListeners();
    } finally {
      if (_current(generation)) {
        _upcomingLoading = false;
        _currentLoad = null;
        notifyListeners();
      }
    }
  }

  Future<void> loadUpcomingAppointments(String userId, {String? email}) =>
      loadAppointments(userId, email: email);

  /// History is requested only when needed; subsequent pages never truncate it.
  Future<void> loadPastAppointments(String userId,
      {String? email, bool forceRefresh = false}) {
    if (_disposed || (sessionUserId != null && sessionUserId != userId)) {
      return Future.value();
    }
    _bindOwner(userId, email);
    final pending = _historyRequest;
    if (forceRefresh && pending != null && !pending.reset) {
      _historyRefreshQueued = true;
    }
    if (pending == null && !forceRefresh && _fresh(_historyLoadedAt)) {
      return Future.value();
    }
    return _startHistory(reset: true);
  }

  Future<void> loadMoreHistory() {
    if (_historyRequest != null) return _startHistory(reset: false);
    if (!hasMoreHistory || _ownerId == null) return Future.value();
    return _startHistory(reset: false);
  }

  /// Retry keeps the failed page's cursor and append/reset meaning.
  Future<void> retryHistory() {
    if (_disposed || _ownerId == null) return Future.value();
    return _startHistory(reset: _historyRetryReset);
  }

  Future<void> _startHistory({required bool reset}) {
    var request = _historyRequest;
    if (request?.waiter != null) return request!.waiter!;
    _historyLoading = true;
    _historyError = null;
    if (request == null) {
      request =
          _HistoryRequest(reset: reset, after: reset ? null : _historyPage);
      _historyRequest = request;
      _historyRetryReset = reset;
      request.completion = _readHistory(_generation, request);
    }
    notifyListeners();
    return request.waiter = _waitForHistory(_generation, request);
  }

  Future<void> _waitForHistory(int generation, _HistoryRequest request) async {
    try {
      await request.completion.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      if (_current(generation) && identical(_historyRequest, request)) {
        _historyError = 'Unable to refresh history. Please try again.';
      }
    } finally {
      if (_current(generation) && identical(_historyRequest, request)) {
        request.waiter = null;
        _historyLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _readHistory(int generation, _HistoryRequest request) async {
    try {
      final page = await Future.sync(() =>
          _appointmentRepo.getPastAppointmentsPage(_ownerId!,
              email: _ownerEmail, after: request.after));
      if (!_current(generation)) return;
      final byId = {
        if (!request.reset)
          for (final apt in _pastAppointments) apt.id: apt,
        for (final apt in page.appointments) apt.id: apt
      };
      _pastAppointments = byId.values.toList()
        ..sort((a, b) => b.appointmentDate.compareTo(a.appointmentDate));
      _historyPage = page;
      _hasLoadedHistory = true;
      _historyLoadedAt = DateTime.now();
      _historyError = null;
      unawaited(_fetchDoctorPhotos());
    } catch (error) {
      if (!_current(generation)) return;
      _discardIfUnauthorized(error);
      _historyError = 'Unable to refresh history. Please try again.';
      notifyListeners();
    } finally {
      if (_current(generation) && identical(_historyRequest, request)) {
        _historyRequest = null;
        _historyLoading = false;
        final refreshQueued = _historyRefreshQueued;
        _historyRefreshQueued = false;
        notifyListeners();
        // A first-page refresh must use a new query after the append settles.
        if (refreshQueued) await _startHistory(reset: true);
      }
    }
  }

  void _discardIfUnauthorized(Object error) {
    if (error is FirebaseException &&
        ['permission-denied', 'unauthenticated'].contains(error.code)) {
      invalidateAppointments();
      _upcomingAppointments = [];
      _pastAppointments = [];
      _doctorPhotos.clear();
      _selectedAppointment = null;
      _hasLoadedUpcoming = false;
      _hasLoadedHistory = false;
      _currentLoadedAt = null;
      _historyLoadedAt = null;
      _historyPage = null;
    }
  }

  /// Mutations invalidate outstanding reads before requesting fresh lists.
  void invalidateAppointments() {
    _generation++;
    _currentReads.invalidate();
    _historyRequest = null;
    _historyRefreshQueued = false;
    _historyRetryReset = true;
    _currentLoad = null;
    _upcomingLoading = false;
    _historyLoading = false;
    _currentLoadedAt = null;
    _historyLoadedAt = null;
    _historyPage = null;
  }

  /// Get appointment by ID
  Future<AppointmentModel?> getAppointmentById(String appointmentId) async {
    final generation = _generation;
    try {
      final appointment = await _appointmentRepo.getAppointmentById(
        appointmentId,
      );
      if (!_current(generation)) return null;
      _selectedAppointment = appointment;
      notifyListeners();
      return _selectedAppointment;
    } catch (e) {
      if (!_current(generation)) return null;
      _discardIfUnauthorized(e);
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Returns a receipt, or null with a display-safe error on booking failure.
  Future<AppointmentBookingResult?> bookAppointment(
    AppointmentModel appointment,
  ) async {
    _isLoading = true;
    _error = null;
    _bookingFailureCode = null;
    notifyListeners();

    try {
      // The backend transaction is the source of truth for slot availability.
      // If two users book at once, only the one that gets the slot lock succeeds.
      final bookingResult = await _appointmentRepo.createAppointment(
        appointment,
      );

      invalidateAppointments();
      _error = null;
      unawaited(_runPostBookingTasks(appointment, bookingResult.appointmentId));
      return bookingResult;
    } on FirebaseFunctionsException catch (e) {
      _bookingFailureCode = e.code;
      _error = e.code == 'already-exists'
          ? 'This time slot was just booked. Please choose another time.'
          : 'Unable to complete your booking. Please try again.';
      return null;
    } catch (_) {
      _error = 'Unable to complete your booking. Please try again.';
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
    final generation = _generation;
    try {
      final coordinator = NotificationSchedulingCoordinator();
      await coordinator.scheduleLocalAppointmentReminders(
        appointment.copyWith(id: appointmentId),
      );
    } catch (e) {
      debugPrint('Failed to schedule local reminders: $e');
    }

    if (!_current(generation)) return;
    await loadAppointments(appointment.patientId,
        email: appointment.patientEmail);
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

      invalidateAppointments();
      await loadAppointments(userId);
      if (_hasLoadedHistory) {
        unawaited(loadPastAppointments(userId, forceRefresh: true));
      }

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

      invalidateAppointments();
      await loadAppointments(userId);
      if (_hasLoadedHistory) {
        unawaited(loadPastAppointments(userId, forceRefresh: true));
      }

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

      invalidateAppointments();
      await loadAppointments(userId);
      if (_hasLoadedHistory) {
        unawaited(loadPastAppointments(userId, forceRefresh: true));
      }

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
    invalidateAppointments();
    _currentReads.bindSession(null);
    _ownerId = null;
    _ownerEmail = null;
    _hasLoadedUpcoming = false;
    _hasLoadedHistory = false;
    _historyError = null;
    _isLoading = false;
    _bookingFailureCode = null;
    _upcomingAppointments = [];
    _pastAppointments = [];
    _selectedAppointment = null;
    _doctorPhotos = {};
    _error = null;
    notifyListeners();
  }

  /// Batch-fetch profile photos for all unique doctors across appointments.
  Future<void> _fetchDoctorPhotos() async {
    final pending = _photoLoad;
    if (pending != null) await pending;
    if (_disposed) return;
    if (_photoLoad != null) return _photoLoad!;
    if (_lastPhotoRefresh == null ||
        DateTime.now().difference(_lastPhotoRefresh!) >=
            const Duration(minutes: 5)) {
      _doctorPhotos.clear();
      _lastPhotoRefresh = DateTime.now();
    }
    final work = _readDoctorPhotos();
    _photoLoad = work;
    try {
      await work;
    } finally {
      if (identical(_photoLoad, work)) _photoLoad = null;
    }
  }

  Future<void> _readDoctorPhotos() async {
    final allAppointments = [..._upcomingAppointments, ..._pastAppointments];
    final uniqueIds = allAppointments
        .map((a) => a.doctorId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    // Only fetch IDs we haven't cached yet
    final idsToFetch =
        uniqueIds.where((id) => !_doctorPhotos.containsKey(id)).toList();
    if (idsToFetch.isEmpty) return;
    final generation = _generation;
    // Four workers bound concurrent portrait reads, regardless of history size.
    var next = 0;
    await Future.wait(List.generate(4, (_) async {
      while (next < idsToFetch.length && _current(generation)) {
        final id = idsToFetch[next++];
        try {
          final doctor = await _doctorRepo.getDoctorById(id);
          if (_current(generation)) _doctorPhotos[id] = doctor?.photoUrl;
        } catch (_) {
          // A failed portrait read is retried by a later list refresh.
        }
      }
    }));
    if (_current(generation)) notifyListeners();
  }
}

class _HistoryRequest {
  _HistoryRequest({required this.reset, required this.after});

  final bool reset;
  final AppointmentHistoryPage? after;
  late final Future<void> completion;
  Future<void>? waiter;
}
