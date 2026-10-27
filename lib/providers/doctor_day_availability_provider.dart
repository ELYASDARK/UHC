import 'package:flutter/foundation.dart';

import '../data/models/doctor_model.dart';
import '../data/repositories/appointment_repository.dart';

/// Keeps the selected day's trusted slots and discards superseded requests.
class DoctorDayAvailabilityProvider extends ChangeNotifier {
  final AppointmentRepository _repository;
  DoctorDayAvailability? _availability;
  bool _isLoading = false;
  String? _errorMessage;
  int _requestId = 0;
  bool _isDisposed = false;
  String? _requestKey;
  Future<void>? _inFlight;

  DoctorDayAvailabilityProvider(this._repository);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool isAvailable(TimeSlot slot) {
    if (_isLoading || !slot.isValid || _availability?.success != true) {
      return false;
    }
    return _availability!.slots.any(
      (trustedSlot) =>
          trustedSlot.startTime == slot.startTime &&
          trustedSlot.endTime == slot.endTime &&
          trustedSlot.isAvailable,
    );
  }

  bool isReadyFor({required String doctorId, required DateTime date}) =>
      !_isLoading &&
      _availability?.success == true &&
      _availability?.doctorId == doctorId &&
      _availability?.appointmentDate ==
          AppointmentRepository.formatClinicDate(date);

  Future<void> load({
    required String doctorId,
    required DateTime date,
    bool forceRefresh = false,
  }) {
    if (_isDisposed) return Future.value();
    final key = '$doctorId/${AppointmentRepository.formatClinicDate(date)}';
    if (!forceRefresh &&
        _isLoading &&
        _requestKey == key &&
        _inFlight != null) {
      return _inFlight!;
    }
    final requestId = ++_requestId;
    _requestKey = key;
    _availability = null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    return _inFlight = _load(doctorId, date, requestId);
  }

  Future<void> _load(String doctorId, DateTime date, int requestId) async {
    try {
      final availability = await _repository.getDoctorDayAvailability(
        doctorId: doctorId,
        date: date,
      );
      if (_isDisposed || requestId != _requestId) return;
      if (availability.success &&
          availability.doctorId == doctorId &&
          availability.appointmentDate ==
              AppointmentRepository.formatClinicDate(date)) {
        _availability = availability;
      } else {
        _errorMessage = 'availability-unavailable';
      }
    } catch (_) {
      if (_isDisposed || requestId != _requestId) return;
      // A failed read leaves every slot unavailable until the patient retries.
      _errorMessage = 'availability-unavailable';
    }
    _isLoading = false;
    _inFlight = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestId++;
    super.dispose();
  }
}
