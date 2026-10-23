import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../data/models/assistant_chat_model.dart';
import 'firebase_callable.dart';

enum AssistantFunctionOperation {
  sendMessage('sendAssistantMessage', Duration(seconds: 70),
      'Failed to send message to assistant.'),
  history('getAssistantHistory', Duration(seconds: 20),
      'Failed to fetch assistant history.'),
  clearHistory('clearAssistantHistory', Duration(seconds: 15),
      'Failed to clear assistant history.'),
  confirmAppointment('confirmAssistantAppointment', Duration(seconds: 30),
      'Failed to confirm assistant appointment.');

  const AssistantFunctionOperation(
      this.callableName, this.timeout, this.failureMessage);

  final String callableName;
  final Duration timeout;
  final String failureMessage;
}

class AssistantFunctionException implements Exception {
  final String code;
  final String message;
  final AssistantMessageStatus? status;
  final String? reasonCode;
  final DateTime? resetAt;
  final AssistantFunctionOperation? operation;

  const AssistantFunctionException({
    required this.code,
    required this.message,
    this.status,
    this.reasonCode,
    this.resetAt,
    this.operation,
  });

  factory AssistantFunctionException.fromFirebase(
    FirebaseFunctionsException failure,
    AssistantFunctionOperation operation,
  ) {
    final details = failure.details;
    final fields = details is Map ? details : const <String, Object?>{};
    final rawStatus = fields['status'];
    final rawReason = fields['reasonCode'];
    final rawReset = fields['resetAt'];
    return AssistantFunctionException(
      code: failure.code,
      message: failure.message ?? operation.failureMessage,
      status: rawStatus is String
          ? AssistantMessageStatus.fromString(rawStatus)
          : null,
      reasonCode: rawReason is String ? rawReason : null,
      resetAt: rawReset is String ? DateTime.tryParse(rawReset)?.toUtc() : null,
      operation: operation,
    );
  }

  AssistantFailureKind get kind {
    final statusKind = switch (status) {
      AssistantMessageStatus.dailyLimit => AssistantFailureKind.dailyLimit,
      AssistantMessageStatus.throttled => AssistantFailureKind.throttled,
      AssistantMessageStatus.disabled => AssistantFailureKind.disabled,
      AssistantMessageStatus.unavailable => AssistantFailureKind.unavailable,
      _ => null,
    };
    if (statusKind != null) return statusKind;
    final reasonKind = switch (reasonCode) {
      'upstream_daily_limit_reached' ||
      'local_daily_cap_reached' =>
        AssistantFailureKind.dailyLimit,
      'upstream_throttled' ||
      'user_rate_limited' ||
      'project_rate_limited' =>
        AssistantFailureKind.throttled,
      'assistant_disabled' ||
      'assistant_unconfigured' ||
      'synthetic_mismatch_rejected' =>
        AssistantFailureKind.disabled,
      'upstream_unavailable' ||
      'upstream_error' ||
      'catalog_overflow' ||
      'schedule_match_error' =>
        AssistantFailureKind.unavailable,
      'offer_expired' || 'offer_taken' => AssistantFailureKind.staleOffer,
      'history_load_failed' => AssistantFailureKind.historyLoad,
      _ => null,
    };
    if (reasonKind != null) return reasonKind;
    return switch (code) {
      'unauthenticated' => AssistantFailureKind.unauthenticated,
      'permission-denied' => AssistantFailureKind.permissionDenied,
      'not-found' => AssistantFailureKind.notFound,
      'resource-exhausted' => AssistantFailureKind.throttled,
      'already-exists' ||
      'failed-precondition' =>
        operation == AssistantFunctionOperation.sendMessage
            ? AssistantFailureKind.throttled
            : AssistantFailureKind.staleOffer,
      _ when operation == AssistantFunctionOperation.history =>
        AssistantFailureKind.historyLoad,
      'unavailable' ||
      'deadline-exceeded' ||
      'internal' ||
      'unknown' =>
        AssistantFailureKind.unavailable,
      _ => AssistantFailureKind.unknown,
    };
  }

  AssistantMessageStatus? get failureStatus => switch (kind) {
        AssistantFailureKind.dailyLimit => AssistantMessageStatus.dailyLimit,
        AssistantFailureKind.throttled => AssistantMessageStatus.throttled,
        AssistantFailureKind.disabled => AssistantMessageStatus.disabled,
        AssistantFailureKind.unavailable => AssistantMessageStatus.unavailable,
        _ => null,
      };

  bool get isDailyLimit => kind == AssistantFailureKind.dailyLimit;
  bool get isThrottled => kind == AssistantFailureKind.throttled;
  bool get isOfferExpiredOrTaken => kind == AssistantFailureKind.staleOffer;
  bool get isUnauthenticated => kind == AssistantFailureKind.unauthenticated;
  bool get isPermissionDenied => kind == AssistantFailureKind.permissionDenied;
  bool get isNotFound => kind == AssistantFailureKind.notFound;
  bool get isUnavailable => kind == AssistantFailureKind.unavailable;

  @override
  String toString() =>
      'AssistantFunctionException(code: $code, message: $message)';
}

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
    return _call(
      AssistantFunctionOperation.sendMessage,
      {
        'message': sanitizedMessage,
        if (locale != null) 'locale': locale,
        if (clientRequestId != null) 'clientRequestId': clientRequestId,
      },
      SendAssistantMessageResult.fromJson,
    );
  }

  @override
  Future<GetAssistantHistoryResult> getHistory() => _call(
        AssistantFunctionOperation.history,
        const {},
        GetAssistantHistoryResult.fromJson,
      );

  @override
  Future<bool> clearHistory() => _call(
        AssistantFunctionOperation.clearHistory,
        const {},
        (response) => response['success'] == true,
      );

  @override
  Future<ConfirmAssistantAppointmentResult> confirmAppointment({
    required String offerId,
    required bool confirmed,
    String? notes,
    String? idempotencyKey,
  }) async {
    if (offerId.trim().isEmpty || !confirmed) {
      throw AssistantFunctionException(
        code: 'invalid-argument',
        message: offerId.trim().isEmpty
            ? 'offerId is required.'
            : 'confirmed must be explicitly true.',
      );
    }
    return _call(
      AssistantFunctionOperation.confirmAppointment,
      {
        'offerId': offerId.trim(),
        'confirmed': true,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
          'idempotencyKey': idempotencyKey.trim(),
      },
      ConfirmAssistantAppointmentResult.fromJson,
    );
  }

  Future<T> _call<T>(
    AssistantFunctionOperation operation,
    Map<String, Object?> payload,
    T Function(Map<String, dynamic>) decode,
  ) async {
    try {
      final response = await invokeFirebaseCallable(
        _functions,
        operation.callableName,
        payload,
        timeout: operation.timeout,
      );
      return decode(Map<String, dynamic>.from(response as Map));
    } on FirebaseFunctionsException catch (failure) {
      debugPrint('${operation.callableName} failed: code=${failure.code}');
      throw AssistantFunctionException.fromFirebase(failure, operation);
    } on Exception catch (failure) {
      throw _unexpectedFailure(operation, failure);
    } on TypeError catch (failure) {
      throw _unexpectedFailure(operation, failure);
    }
  }

  AssistantFunctionException _unexpectedFailure(
      AssistantFunctionOperation operation, Object failure) {
    debugPrint('${operation.callableName} failed: ${failure.runtimeType}');
    return AssistantFunctionException(
      code: 'unknown',
      message: operation.failureMessage,
      operation: operation,
    );
  }
}
