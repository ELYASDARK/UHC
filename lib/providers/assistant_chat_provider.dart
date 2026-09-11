import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/models/assistant_chat_model.dart';
import '../data/models/user_model.dart';
import '../services/assistant_functions_service.dart';

/// Screen-scoped ChangeNotifier for the AI Scheduling Assistant chat session.
/// Guarantees account isolation, prevents late async repopulation after clear/dispose,
/// and manages slot offer validation, idempotency, and quota states.
class AssistantChatProvider extends ChangeNotifier {
  String? _patientId;
  final AssistantFunctionsService _functionsService;
  final Uuid _uuid = const Uuid();

  List<AssistantChatMessage> _messages = [];
  Map<String, AssistantOffer> _offersById = {};
  bool _isLoading = false;
  bool _isSending = false;
  bool _isConfirming = false;
  bool _isClearing = false;
  bool _isRefreshing = false;
  bool _refreshPending = false;
  String? _confirmingOfferId;
  AssistantMessageStatus _currentStatus = AssistantMessageStatus.ready;
  String? _reasonCode;
  DateTime? _resetAt;
  Timer? _quotaResetTimer;
  String? _errorMessage;
  String? _unsentDraft;
  int _revision = 0;

  // Client request ID deduplication across retries
  String? _activeClientRequestId;
  String? _lastSentDraft;

  // Operation generation token: incremented on clear, account switch, or dispose.
  // In-flight async callbacks matching an older generation are strictly discarded.
  int _generation = 0;
  bool _isDisposed = false;

  // Booking idempotency key preserved across network retries to prevent double booking.
  String? _activeBookingIdempotencyKey;
  String? _activeBookingOfferId;

  AssistantChatProvider({
    String? patientId,
    AssistantFunctionsService? functionsService,
  })  : _patientId = patientId,
        _functionsService = functionsService ?? FirebaseAssistantFunctionsService();

  // Getters
  String? get patientId => _patientId;
  List<AssistantChatMessage> get messages => List.unmodifiable(_messages);
  List<AssistantOffer> get offers => List.unmodifiable(_offersById.values);
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  bool get isConfirming => _isConfirming;
  bool get isClearing => _isClearing;
  bool get isRefreshing => _isRefreshing;
  bool get isRefreshPending => _refreshPending;
  String? get confirmingOfferId => _confirmingOfferId;
  AssistantMessageStatus get currentStatus => _currentStatus;
  String? get reasonCode => _reasonCode;
  DateTime? get resetAt => _resetAt;
  String? get errorMessage => _errorMessage;
  String? get unsentDraft => _unsentDraft;
  int get revision => _revision;
  bool get isDisposed => _isDisposed;
  String? get activeBookingOfferId => _activeBookingOfferId;

  bool get isDailyLimit => _currentStatus == AssistantMessageStatus.dailyLimit;
  bool get isThrottled => _currentStatus == AssistantMessageStatus.throttled;
  bool get isDisabled => _currentStatus == AssistantMessageStatus.disabled;
  bool get isUnavailable => _currentStatus == AssistantMessageStatus.unavailable;

  /// Retrieves an offer by ID from cached session offers.
  AssistantOffer? getOfferById(String offerId) => _offersById[offerId];

  /// List of offers corresponding to a message.
  List<AssistantOffer> getOffersForMessage(AssistantChatMessage message) {
    if (message.offerIds.isEmpty) return const [];
    return message.offerIds
        .map((id) => _offersById[id])
        .whereType<AssistantOffer>()
        .toList();
  }

  /// Account switch or logout: wipe sensitive state, cancel in-flight, and re-initialize if new valid patient.
  void updateActiveUser({required String? userId, required UserRole? role}) {
    if (_isDisposed) return;

    final isAuthorizedPatient = userId != null &&
        userId.isNotEmpty &&
        (role == UserRole.student || role == UserRole.staff);
    final sanitizedId = isAuthorizedPatient ? userId : null;

    if (_patientId == sanitizedId) return;

    _quotaResetTimer?.cancel();
    _patientId = sanitizedId;
    _generation++;
    _messages = [];
    _offersById = {};
    _isLoading = false;
    _isSending = false;
    _isConfirming = false;
    _isClearing = false;
    _isRefreshing = false;
    _refreshPending = false;
    _confirmingOfferId = null;
    _activeBookingIdempotencyKey = null;
    _activeBookingOfferId = null;
    _activeClientRequestId = null;
    _lastSentDraft = null;
    _currentStatus = AssistantMessageStatus.ready;
    _reasonCode = null;
    _resetAt = null;
    _errorMessage = null;
    _unsentDraft = null;
    _revision = 0;

    notifyListeners();

    if (_patientId != null && !_isDisposed) {
      initialize();
    }
  }

  /// Initial load of server-owned chat history.
  Future<void> initialize() async {
    if (_patientId == null || _patientId!.isEmpty || _isLoading || _isClearing || _isDisposed) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final currentGen = _generation;

    try {
      final history = await _functionsService.getHistory();
      if (_isDisposed || currentGen != _generation) return;

      _messages = history.messages;
      if (_messages.length > 20) {
        _messages = _messages.sublist(_messages.length - 20);
      }
      _offersById = {for (final o in history.offers) o.offerId: o};
      _revision = history.revision;
      _resetAt = history.resetAt;
      _currentStatus = history.status ?? AssistantMessageStatus.ready;
    } on AssistantFunctionException catch (e) {
      if (_isDisposed || currentGen != _generation) return;
      _errorMessage = e.message;
      if (e.status != null) _currentStatus = e.status!;
      if (e.reasonCode != null) _reasonCode = e.reasonCode;
      _resetAt = e.resetAt;
    } catch (e) {
      if (_isDisposed || currentGen != _generation) return;
      _errorMessage = e.toString();
    } finally {
      if (!_isDisposed && currentGen == _generation) {
        _isLoading = false;
        _scheduleQuotaReset();
        notifyListeners();
        if (_refreshPending) {
          _refreshPending = false;
          refreshHistory();
        }
      }
    }
  }

  /// Refreshes availability of offers on open/resume without invoking AI.
  Future<void> refreshHistory({bool force = false}) async {
    if (_patientId == null || _patientId!.isEmpty || _isDisposed || _isClearing) return;
    if (_isSending || _isConfirming || _isLoading) {
      _refreshPending = true;
      return;
    }
    if (_isRefreshing) return;

    _isRefreshing = true;
    notifyListeners();

    final currentGen = _generation;

    try {
      final history = await _functionsService.getHistory();
      if (_isDisposed || currentGen != _generation) return;

      if (history.revision >= _revision || force) {
        _messages = history.messages;
        if (_messages.length > 20) {
          _messages = _messages.sublist(_messages.length - 20);
        }
        _offersById = {for (final o in history.offers) o.offerId: o};
        _revision = history.revision;
        _resetAt = history.resetAt;
        _currentStatus = history.status ?? AssistantMessageStatus.ready;
      }
    } on AssistantFunctionException catch (e) {
      if (_isDisposed || currentGen != _generation) return;
      _errorMessage = e.message;
      if (e.status != null) _currentStatus = e.status!;
      _reasonCode = e.reasonCode ?? e.code;
      _resetAt = e.resetAt;
      debugPrint('Failed to refresh assistant history: $e');
    } catch (e) {
      if (_isDisposed || currentGen != _generation) return;
      _errorMessage = e.toString();
      _reasonCode = 'history_load_failed';
      debugPrint('Failed to refresh assistant history: $e');
    } finally {
      if (!_isDisposed && currentGen == _generation) {
        _isRefreshing = false;
        _scheduleQuotaReset();
        notifyListeners();
      }
    }
  }

  /// Sends a message in the selected locale with clientRequestId deduplication.
  Future<bool> sendMessage(String text, {required String localeCode}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || cleanText.length > 500) {
      _errorMessage = 'Message cannot exceed 500 characters.';
      notifyListeners();
      return false;
    }

    if (_patientId == null || _patientId!.isEmpty || _isSending || _isClearing || _isDisposed || _isRefreshing) return false;

    _isSending = true;
    _errorMessage = null;
    _unsentDraft = cleanText; // Retain draft in case of failure

    final currentGen = _generation;

    // Reuse clientRequestId across retries of the same draft text
    if (_activeClientRequestId == null || _lastSentDraft != cleanText) {
      _activeClientRequestId = _uuid.v4();
      _lastSentDraft = cleanText;
    }
    final clientRequestId = _activeClientRequestId;

    // Optimistically append the patient message
    final optimisticMsg = AssistantChatMessage(
      id: 'opt_${DateTime.now().millisecondsSinceEpoch}',
      sender: 'patient',
      text: cleanText,
      status: AssistantMessageStatus.ready,
      createdAt: DateTime.now(),
      isPending: true,
    );

    _messages = [..._messages, optimisticMsg];
    if (_messages.length > 20) {
      _messages = _messages.sublist(_messages.length - 20);
    }
    notifyListeners();

    try {
      final result = await _functionsService.sendMessage(
        message: cleanText,
        locale: localeCode,
        clientRequestId: clientRequestId,
      );

      if (_isDisposed || currentGen != _generation) return false;

      final isAccepted = result.success &&
          (result.status == AssistantMessageStatus.ready ||
              result.status == AssistantMessageStatus.clarify ||
              result.status == AssistantMessageStatus.outOfScope);

      _currentStatus = result.status;
      _reasonCode = result.reasonCode;
      _resetAt = result.resetAt;
      _revision = result.revision;

      if (isAccepted) {
        _unsentDraft = null; // Cleared on confirmed transmission
        _activeClientRequestId = null;
        _lastSentDraft = null;

        // Replace offers authoritatively with server list
        _offersById = {for (final offer in result.offers) offer.offerId: offer};

        // Replace optimistic message with confirmed version
        final confirmedPatientMsg = AssistantChatMessage(
          id: optimisticMsg.id,
          sender: 'patient',
          text: cleanText,
          status: AssistantMessageStatus.ready,
          createdAt: optimisticMsg.createdAt,
          isPending: false,
        );

        final assistantMsg = AssistantChatMessage(
          id: 'asst_${DateTime.now().millisecondsSinceEpoch}',
          sender: 'assistant',
          text: result.message,
          status: result.status,
          reasonCode: result.reasonCode,
          offerIds: result.status == AssistantMessageStatus.ready
              ? result.offers.map((o) => o.offerId).toList()
              : const [],
          createdAt: DateTime.now(),
        );

        _messages = [
          ..._messages.where((m) => m.id != optimisticMsg.id),
          confirmedPatientMsg,
          assistantMsg,
        ];
        if (_messages.length > 20) {
          _messages = _messages.sublist(_messages.length - 20);
        }

        return true;
      } else {
        // Preserve recoverable draft on rejection or quota limit
        _unsentDraft = cleanText;
        _activeClientRequestId = null;
        _errorMessage = result.message.isNotEmpty ? result.message : 'Request could not be processed.';

        // Remove optimistic message so fictional confirmed message is not created
        _messages = _messages.where((m) => m.id != optimisticMsg.id).toList();

        // If assistant provided an explanation, append the assistant response
        if (result.message.isNotEmpty) {
          final assistantMsg = AssistantChatMessage(
            id: 'asst_${DateTime.now().millisecondsSinceEpoch}',
            sender: 'assistant',
            text: result.message,
            status: result.status,
            reasonCode: result.reasonCode,
            offerIds: const [],
            createdAt: DateTime.now(),
          );
          _messages = [..._messages, assistantMsg];
          if (_messages.length > 20) {
            _messages = _messages.sublist(_messages.length - 20);
          }
        }

        return false;
      }
    } on AssistantFunctionException catch (e) {
      if (_isDisposed || currentGen != _generation) return false;

      _unsentDraft = cleanText;
      // Retain _activeClientRequestId so retrying this draft reuses the clientRequestId
      _errorMessage = e.message;
      if (e.status != null) _currentStatus = e.status!;
      _reasonCode = e.reasonCode ?? e.code;
      _resetAt = e.resetAt;

      _messages = _messages.where((m) => m.id != optimisticMsg.id).toList();
      return false;
    } catch (e) {
      if (_isDisposed || currentGen != _generation) return false;
      _unsentDraft = cleanText;
      // Retain _activeClientRequestId so retrying this draft reuses the clientRequestId
      _errorMessage = e.toString();
      _messages = _messages.where((m) => m.id != optimisticMsg.id).toList();
      return false;
    } finally {
      if (!_isDisposed && currentGen == _generation) {
        _isSending = false;
        _scheduleQuotaReset();
        notifyListeners();
        if (_refreshPending) {
          _refreshPending = false;
          refreshHistory();
        }
      }
    }
  }

  /// Explicit affirmative confirmation of an appointment offer.
  /// Idempotency key is preserved across uncertain network retries to prevent double booking.
  Future<ConfirmAssistantAppointmentResult?> confirmOffer(
    AssistantOffer offer, {
    String? notes,
  }) async {
    if (_patientId == null || _patientId!.isEmpty || _isConfirming || _isClearing || _isDisposed) return null;

    final isRetry = _activeBookingOfferId == offer.offerId;
    // Backend checks appointment_idempotency before checking offer expiry.
    // If not a retry, check bookable locally before calling server.
    if (!isRetry && !offer.isBookable(DateTime.now())) {
      _errorMessage = 'This appointment slot is no longer available.';
      _offersById[offer.offerId] = offer.copyWith(isAvailable: false);
      notifyListeners();
      await refreshHistory();
      return null;
    }

    _isConfirming = true;
    _confirmingOfferId = offer.offerId;
    _errorMessage = null;
    notifyListeners();

    final currentGen = _generation;

    // Maintain or generate idempotency identity
    if (_activeBookingOfferId != offer.offerId || _activeBookingIdempotencyKey == null) {
      _activeBookingOfferId = offer.offerId;
      _activeBookingIdempotencyKey = 'asst_confirm_${_patientId ?? 'patient'}_${offer.offerId}';
    }

    try {
      final result = await _functionsService.confirmAppointment(
        offerId: offer.offerId,
        confirmed: true,
        notes: notes,
        idempotencyKey: _activeBookingIdempotencyKey,
      );

      if (_isDisposed || currentGen != _generation) return null;

      // Strict receipt validation: success == true, appointmentId.isNotEmpty, bookingReference.isNotEmpty
      if (!result.success || !result.isValid) {
        _errorMessage = 'Failed to confirm appointment.';
        notifyListeners();
        return null;
      }

      // Affirmative booking success: clear idempotency key and mark offer consumed
      _activeBookingIdempotencyKey = null;
      _activeBookingOfferId = null;
      _offersById.remove(offer.offerId);

      return result;
    } on AssistantFunctionException catch (e) {
      if (_isDisposed || currentGen != _generation) return null;
      _errorMessage = e.message;

      if (e.isOfferExpiredOrTaken) {
        // Slot taken or expired: reset idempotency key, mark unavailable and refresh
        _activeBookingIdempotencyKey = null;
        _activeBookingOfferId = null;
        _offersById[offer.offerId] = offer.copyWith(isAvailable: false);
        await refreshHistory();
      }
      // For network errors, preserve _activeBookingIdempotencyKey for retry!
      return null;
    } catch (e) {
      if (_isDisposed || currentGen != _generation) return null;
      _errorMessage = e.toString();
      return null;
    } finally {
      if (!_isDisposed && currentGen == _generation) {
        _isConfirming = false;
        _confirmingOfferId = null;
        notifyListeners();
        if (_refreshPending) {
          _refreshPending = false;
          refreshHistory();
        }
      }
    }
  }

  /// Invalidates old callbacks while keeping visible history until clear succeeds.
  Future<bool> clearChat() async {
    if (_patientId == null || _patientId!.isEmpty || _isClearing || _isDisposed) return false;
    _isClearing = true;
    _quotaResetTimer?.cancel();
    _generation++;
    final currentGen = _generation;
    _isSending = false;
    _isLoading = false;
    _isConfirming = false;
    _isRefreshing = false;
    _confirmingOfferId = null;
    _refreshPending = false;
    _errorMessage = null;
    notifyListeners();

    var cleared = false;
    try {
      cleared = await _functionsService.clearHistory();
    } catch (_) {
      // A failed response does not prove that the server deleted the conversation.
    }
    if (_isDisposed || currentGen != _generation) return false;
    _isClearing = false;

    if (cleared) {
      _messages = [];
      _offersById = {};
      _currentStatus = AssistantMessageStatus.ready;
      _reasonCode = null;
      _resetAt = null;
      _revision = 0;
      _unsentDraft = null;
      _activeClientRequestId = null;
      _lastSentDraft = null;
      _activeBookingIdempotencyKey = null;
      _activeBookingOfferId = null;
    } else {
      _messages = _messages.where((message) => !message.isPending).toList();
      await refreshHistory(force: true);
      if (_isDisposed || currentGen != _generation) return false;
      _errorMessage = 'Failed to clear chat on server.';
    }
    _scheduleQuotaReset();
    notifyListeners();
    return cleared;
  }

  void _scheduleQuotaReset() {
    _quotaResetTimer?.cancel();
    final reset = _resetAt;
    if (!isDailyLimit || reset == null || _isDisposed) return;
    final delay = reset.difference(DateTime.now());
    // A stale server timestamp must not create an immediate refresh loop.
    if (delay <= Duration.zero) {
      _currentStatus = AssistantMessageStatus.ready;
      _reasonCode = null;
      _resetAt = null;
      _errorMessage = null;
      return;
    }
    _quotaResetTimer = Timer(delay, () {
      if (_isDisposed || _isClearing) return;
      _currentStatus = AssistantMessageStatus.ready;
      _reasonCode = null;
      _resetAt = null;
      _errorMessage = null;
      notifyListeners();
      unawaited(refreshHistory(force: true));
    });
  }

  /// Updates draft text (e.g. while editing).
  void setDraft(String? draft) {
    _unsentDraft = draft;
  }

  /// Clears any transient error message.
  void clearErrorMessage() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _quotaResetTimer?.cancel();
    _isDisposed = true;
    _generation++;
    super.dispose();
  }
}
