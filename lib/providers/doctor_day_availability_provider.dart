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

  DoctorDayAvailabilityProvider(this._repository);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool isAvailable(TimeSlot slot) {
    if (!slot.isValid || _availability?.success != true) return false;
    return _availability!.slots.any(
      (trustedSlot) =>
          trustedSlot.startTime == slot.startTime &&
          trustedSlot.endTime == slot.endTime &&
          trustedSlot.isAvailable,
    );
  }

  Future<void> load({required String doctorId, required DateTime date}) async {
    if (_isDisposed) return;
    final requestId = ++_requestId;
    _availability = null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final availability = await _repository.getDoctorDayAvailability(
        doctorId: doctorId,
        date: date,
      );
      if (_isDisposed || requestId != _requestId) return;
      _availability = availability;
    } catch (error) {
      if (_isDisposed || requestId != _requestId) return;
      // A failed read leaves every slot unavailable until the patient retries.
      _errorMessage = error.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestId++;
    super.dispose();
  }
}
