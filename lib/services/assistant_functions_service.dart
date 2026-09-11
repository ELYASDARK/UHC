import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../data/models/assistant_chat_model.dart';

/// Exception thrown by assistant functions service.
class AssistantFunctionException implements Exception {
  final String code;
  final String message;
  final AssistantMessageStatus? status;
  final String? reasonCode;
  final DateTime? resetAt;

  const AssistantFunctionException({
    required this.code,
    required this.message,
    this.status,
    this.reasonCode,
    this.resetAt,
  });

  bool get isDailyLimit =>
      status == AssistantMessageStatus.dailyLimit ||
      code == 'resource-exhausted' && reasonCode == 'upstream_daily_limit_reached';

  bool get isThrottled =>
      status == AssistantMessageStatus.throttled ||
      code == 'resource-exhausted';

  bool get isOfferExpiredOrTaken =>
      code == 'already-exists' || code == 'failed-precondition';

  bool get isUnauthenticated => code == 'unauthenticated';
  bool get isPermissionDenied => code == 'permission-denied';
  bool get isNotFound => code == 'not-found';
  bool get isUnavailable => code == 'unavailable';

  @override
  String toString() => 'AssistantFunctionException(code: $code, message: $message)';
}

/// Abstract contract for assistant backend functions communication.
/// Enables mock and fake boundaries for unit and widget tests without live Firebase.
abstract class AssistantFunctionsService {
  Future<SendAssistantMessageResult> sendMessage({
    required String message,
    String? locale,
    String? clientRequestId,
  });

  Future<GetAssistantHistoryResult> getHistory();

  Future<bool> clearHistory();

  Future<ConfirmAssistantAppointmentResult> confirmAppointment({
    required String offerId,
    required bool confirmed,
    String? notes,
    String? idempotencyKey,
  });
}

/// Production implementation using `cloud_functions`.
class FirebaseAssistantFunctionsService implements AssistantFunctionsService {
  final FirebaseFunctions _functions;

  FirebaseAssistantFunctionsService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<SendAssistantMessageResult> sendMessage({
    required String message,
    String? locale,
    String? clientRequestId,
  }) async {
    final sanitizedMessage = message.trim();
    if (sanitizedMessage.isEmpty) {
      throw const AssistantFunctionException(
        code: 'invalid-argument',
        message: 'Message cannot be empty.',
      );
    }

    try {
      final callable = _functions.httpsCallable(
        'sendAssistantMessage',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 70)),
      );

      final payload = <String, dynamic>{
        'message': sanitizedMessage,
        if (locale != null) 'locale': locale,
        if (clientRequestId != null) 'clientRequestId': clientRequestId,
      };

      final response = await callable.call<Map<dynamic, dynamic>>(payload);
      final rawData = Map<String, dynamic>.from(response.data);
      return SendAssistantMessageResult.fromJson(rawData);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('sendAssistantMessage failed: code=${e.code}');
      final details = e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      DateTime? resetAt;
      if (details?['resetAt'] is String) {
        try {
          resetAt = DateTime.parse(details!['resetAt'] as String).toUtc();
        } catch (_) {}
      }

      throw AssistantFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to send message to assistant.',
        reasonCode: details?['reasonCode'] as String?,
        resetAt: resetAt,
      );
    } catch (e) {
      debugPrint('sendAssistantMessage unexpected error: code=unknown');
      throw AssistantFunctionException(
        code: 'unknown',
        message: 'Unexpected error calling assistant service.',
      );
    }
  }

  @override
  Future<GetAssistantHistoryResult> getHistory() async {
    try {
      final callable = _functions.httpsCallable(
        'getAssistantHistory',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
      );

      final response = await callable.call<Map<dynamic, dynamic>>(<String, dynamic>{});
      final rawData = Map<String, dynamic>.from(response.data);
      return GetAssistantHistoryResult.fromJson(rawData);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('getAssistantHistory failed: code=${e.code}');
      throw AssistantFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to fetch assistant history.',
      );
    } catch (e) {
      debugPrint('getAssistantHistory unexpected error: code=unknown');
      throw AssistantFunctionException(
        code: 'unknown',
        message: 'Unexpected error calling assistant history service.',
      );
    }
  }

  @override
  Future<bool> clearHistory() async {
    try {
      final callable = _functions.httpsCallable(
        'clearAssistantHistory',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      final response = await callable.call<Map<dynamic, dynamic>>(<String, dynamic>{});
      final rawData = Map<String, dynamic>.from(response.data);
      return rawData['success'] == true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('clearAssistantHistory failed: code=${e.code}');
      throw AssistantFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to clear assistant history.',
      );
    } catch (e) {
      debugPrint('clearAssistantHistory unexpected error: code=unknown');
      throw AssistantFunctionException(
        code: 'unknown',
        message: 'Unexpected error calling clear assistant history service.',
      );
    }
  }

  @override
  Future<ConfirmAssistantAppointmentResult> confirmAppointment({
    required String offerId,
    required bool confirmed,
    String? notes,
    String? idempotencyKey,
  }) async {
    if (offerId.trim().isEmpty) {
      throw const AssistantFunctionException(
        code: 'invalid-argument',
        message: 'offerId is required.',
      );
    }

    if (!confirmed) {
      throw const AssistantFunctionException(
        code: 'invalid-argument',
        message: 'confirmed must be explicitly true.',
      );
    }

    try {
      final callable = _functions.httpsCallable(
        'confirmAssistantAppointment',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      final payload = <String, dynamic>{
        'offerId': offerId.trim(),
        'confirmed': true,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          'idempotencyKey': idempotencyKey.trim(),
      };

      final response = await callable.call<Map<dynamic, dynamic>>(payload);
      final rawData = Map<String, dynamic>.from(response.data);
      return ConfirmAssistantAppointmentResult.fromJson(rawData);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('confirmAssistantAppointment failed: code=${e.code}');
      throw AssistantFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to confirm assistant appointment.',
      );
    } catch (e) {
      debugPrint('confirmAssistantAppointment unexpected error: code=unknown');
      throw AssistantFunctionException(
        code: 'unknown',
        message: 'Unexpected error calling confirm assistant appointment service.',
      );
    }
  }
}
