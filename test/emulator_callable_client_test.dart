import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uhc/services/emulator_callable_client.dart';

void main() {
  const timeout = Duration(seconds: 1);

  EmulatorCallableClient localClient(http.Client client,
          {Future<String?> Function()? getIdToken}) =>
      EmulatorCallableClient(
        projectId: 'demo-uhc-test',
        host: '10.0.2.2',
        getIdToken: getIdToken ?? () async => 'emulator-user-token',
        enabled: true,
        isRelease: false,
        client: client,
      );

  test('authenticated callable uses local protocol without IID or API key',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(),
          'http://10.0.2.2:5001/demo-uhc-test/us-central1/sendAssistantMessage');
      expect(request.headers['authorization'], 'Bearer emulator-user-token');
      expect(request.headers['content-type'], contains('application/json'));
      expect(
          request.headers.containsKey('Firebase-Instance-ID-Token'), isFalse);
      expect(request.url.query, isEmpty);
      expect(jsonDecode(request.body), {
        'data': {'message': 'Find a clinic appointment'},
      });
      return http.Response('{"result":{"status":"ok","revision":2}}', 200);
    });
    addTearDown(client.close);

    expect(
      await localClient(client).call(
          'sendAssistantMessage', {'message': 'Find a clinic appointment'},
          timeout: timeout),
      {'status': 'ok', 'revision': 2},
    );
  });

  test('alternate data envelope and null success retain their values',
      () async {
    final responses = ['{"data":[1,true]}', '{"result":null}'];
    final client =
        MockClient((_) async => http.Response(responses.removeAt(0), 200));
    addTearDown(client.close);
    final callable = localClient(client);

    expect(await callable.call('getAssistantHistory', {}, timeout: timeout),
        [1, true]);
    expect(await callable.call('clearAssistantHistory', {}, timeout: timeout),
        isNull);
  });

  for (final httpStatus in [200, 429]) {
    test(
        'structured callable error preserves quota details at HTTP $httpStatus',
        () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'result': {'ignored': true},
            'error': {
              'status': 'RESOURCE_EXHAUSTED',
              'message': 'Daily quota reached',
              'details': {'reasonCode': 'local_daily_cap_reached'},
            },
          }),
          httpStatus));
      addTearDown(client.close);

      await expectLater(
        localClient(client).call('sendAssistantMessage', {}, timeout: timeout),
        throwsA(isA<FirebaseFunctionsException>()
            .having((failure) => failure.code, 'code', 'resource-exhausted')
            .having(
                (failure) => failure.message, 'message', 'Daily quota reached')
            .having((failure) => failure.details, 'details',
                {'reasonCode': 'local_daily_cap_reached'})),
      );
    });
  }

  final invalidResponses = [
    'not-json',
    '[]',
    '{}',
    '{"error":null}',
    '{"error":{"status":"MADE_UP"}}',
  ];
  for (final body in invalidResponses) {
    test('malformed callable response fails as internal: $body', () async {
      final client = MockClient((_) async => http.Response(body, 200));
      addTearDown(client.close);
      await expectLater(
        localClient(client).call('getAssistantHistory', {}, timeout: timeout),
        throwsA(isA<FirebaseFunctionsException>()
            .having((failure) => failure.code, 'code', 'internal')),
      );
    });
  }

  test('redirect cannot forward emulator authorization to another host',
      () async {
    final client = MockClient((request) async {
      expect(request.followRedirects, isFalse);
      return http.Response('', 302,
          headers: {'location': 'https://example.com'});
    });
    addTearDown(client.close);
    await expectLater(
      localClient(client).call('getAssistantHistory', {}, timeout: timeout),
      throwsA(isA<FirebaseFunctionsException>()
          .having((failure) => failure.code, 'code', 'internal')),
    );
  });

  test('network outage is unavailable and injected client remains caller owned',
      () async {
    final client =
        _TrackedClient((_) async => throw http.ClientException('offline'));
    addTearDown(client.close);
    await expectLater(
      localClient(client).call('getAssistantHistory', {}, timeout: timeout),
      throwsA(isA<FirebaseFunctionsException>()
          .having((failure) => failure.code, 'code', 'unavailable')),
    );
    expect(client.closed, isFalse);
  });

  test('authentication completing after deadline never issues a request',
      () async {
    final token = Completer<String?>();
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{"result":{}}', 200);
    });
    addTearDown(client.close);
    final callable = localClient(client, getIdToken: () => token.future);

    await expectLater(
      callable.call('getAssistantHistory', {},
          timeout: const Duration(milliseconds: 10)),
      throwsA(isA<FirebaseFunctionsException>()
          .having((failure) => failure.code, 'code', 'deadline-exceeded')),
    );
    token.complete('late-token');
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
  });

  test('response stream shares the deadline and owned clients are closed',
      () async {
    final responseBody = StreamController<List<int>>();
    addTearDown(responseBody.close);
    final client = _TrackedClient.streaming(
        (_, __) async => http.StreamedResponse(responseBody.stream, 200));
    final callable = EmulatorCallableClient(
      projectId: 'demo-uhc-test',
      host: 'localhost',
      getIdToken: () async => null,
      enabled: true,
      isRelease: false,
    );

    await http.runWithClient(
      () => expectLater(
        callable.call('getAssistantHistory', {},
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<FirebaseFunctionsException>()
            .having((failure) => failure.code, 'code', 'deadline-exceeded')),
      ),
      () => client,
    );
    expect(client.closed, isTrue);
  });

  final invalidConfigs = [
    (
      projectId: 'uhca-20800',
      host: 'localhost',
      enabled: true,
      isRelease: false
    ),
    (
      projectId: 'demo-uhc-test',
      host: 'example.com',
      enabled: true,
      isRelease: false
    ),
    (
      projectId: 'demo-uhc-test',
      host: 'localhost:5001',
      enabled: true,
      isRelease: false
    ),
    (
      projectId: 'demo-uhc-test',
      host: 'localhost',
      enabled: false,
      isRelease: false
    ),
    (
      projectId: 'demo-uhc-test',
      host: 'localhost',
      enabled: true,
      isRelease: true
    ),
  ];
  for (final config in invalidConfigs) {
    test('unsafe emulator configuration is rejected: $config', () {
      expect(
        () => EmulatorCallableClient(
          projectId: config.projectId,
          host: config.host,
          getIdToken: () async => null,
          enabled: config.enabled,
          isRelease: config.isRelease,
        ),
        throwsStateError,
      );
    });
  }

  for (final name in [
    '../getAssistantHistory',
    '/other',
    'name?target=live',
    ''
  ]) {
    test('callable path escape is rejected: $name', () async {
      final client = MockClient((_) async => fail('Unsafe request was sent.'));
      addTearDown(client.close);
      await expectLater(
        localClient(client).call(name, {}, timeout: timeout),
        throwsArgumentError,
      );
    });
  }
}

class _TrackedClient extends MockClient {
  _TrackedClient(super.handler);
  _TrackedClient.streaming(super.handler) : super.streaming();

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}
