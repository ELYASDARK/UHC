import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/config/emulator_config.dart';

/// Local callable transport that avoids the Android SDK's un-emulated IID lookup.
class EmulatorCallableClient {
  EmulatorCallableClient({
    required String projectId,
    required String host,
    required Future<String?> Function() getIdToken,
    required bool enabled,
    required bool isRelease,
    http.Client? client,
  })  : _getIdToken = getIdToken,
        _client = client {
    if (!enabled || isRelease || kReleaseMode) {
      throw StateError(
          'Local callable transport requires emulator debug mode.');
    }
    if (projectId != EmulatorConfig.demoProjectId ||
        !EmulatorConfig.isAllowedHost(host)) {
      throw StateError(
          'Local callable transport requires the loopback demo project.');
    }
    _endpoint = Uri(
      scheme: 'http',
      host: host.trim().toLowerCase(),
      port: 5001,
      path: '/$projectId/us-central1/',
    );
  }

  final Future<String?> Function() _getIdToken;
  final http.Client? _client;
  late final Uri _endpoint;

  Future<dynamic> call(
    String functionName,
    Map<String, dynamic> parameters, {
    required Duration timeout,
  }) async {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$').hasMatch(functionName)) {
      throw ArgumentError.value(
          functionName, 'functionName', 'Invalid callable name.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    final elapsed = Stopwatch()..start();
    final request = http.Request('POST', _endpoint.resolve(functionName))
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..body = jsonEncode({'data': parameters});
    final client = _client ?? http.Client();
    try {
      return await _send(client, request, elapsed, timeout).timeout(timeout);
    } on TimeoutException {
      throw FirebaseFunctionsException(
        code: 'deadline-exceeded',
        message: 'Local callable request timed out.',
      );
    } on http.ClientException {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Local callable emulator is unavailable.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<dynamic> _send(http.Client client, http.Request request,
      Stopwatch elapsed, Duration timeout) async {
    final token = await _getIdToken();
    // Future.timeout cannot cancel token acquisition; never send its late result.
    if (elapsed.elapsed >= timeout) {
      throw TimeoutException('Authentication timed out.');
    }
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final response = await http.Response.fromStream(await client.send(request));
    return _decodeResponse(response);
  }

  dynamic _decodeResponse(http.Response response) {
    final dynamic envelope;
    try {
      envelope = jsonDecode(response.body);
    } on FormatException {
      throw _invalidResponse();
    }
    if (envelope is! Map) throw _invalidResponse();
    if (envelope.containsKey('error')) {
      throw _callableFailure(envelope['error']);
    }
    if (response.statusCode != 200) throw _invalidResponse();
    if (envelope.containsKey('result')) return envelope['result'];
    if (envelope.containsKey('data')) return envelope['data'];
    throw _invalidResponse();
  }

  FirebaseFunctionsException _callableFailure(dynamic failure) {
    if (failure is! Map) return _invalidResponse();
    final status = failure['status'];
    final message = failure['message'];
    return FirebaseFunctionsException(
      code: _errorStatuses.contains(status)
          ? (status as String).toLowerCase().replaceAll('_', '-')
          : 'internal',
      message: message is String ? message : 'Local callable request failed.',
      details: failure['details'],
    );
  }

  FirebaseFunctionsException _invalidResponse() => FirebaseFunctionsException(
        code: 'internal',
        message: 'Local callable returned an invalid response.',
      );

  static const _errorStatuses = {
    'OK',
    'CANCELLED',
    'UNKNOWN',
    'INVALID_ARGUMENT',
    'DEADLINE_EXCEEDED',
    'NOT_FOUND',
    'ALREADY_EXISTS',
    'PERMISSION_DENIED',
    'RESOURCE_EXHAUSTED',
    'FAILED_PRECONDITION',
    'ABORTED',
    'OUT_OF_RANGE',
    'UNIMPLEMENTED',
    'INTERNAL',
    'UNAVAILABLE',
    'DATA_LOSS',
    'UNAUTHENTICATED',
  };
}
