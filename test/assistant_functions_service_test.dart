// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/data/models/assistant_chat_model.dart';
import 'package:uhc/services/assistant_functions_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
    StandardMessageCodec(),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FirebaseAssistantFunctionsService assistant;
  var firebaseCode = 'resource-exhausted';
  var firebaseDetails = <String, Object?>{};

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    assistant = FirebaseAssistantFunctionsService(
        functions: FirebaseFunctions.instance);
    firebaseCode = 'resource-exhausted';
    firebaseDetails = {
      'status': 'daily_limit',
      'reasonCode': 'upstream_daily_limit_reached',
      'resetAt': '2026-10-21T03:00:00+03:00',
    };
    // Exercise the real Firebase SDK and UHC adapter; replace only the native call.
    messenger.setMockDecodedMessageHandler<Object?>(
        channel,
        (_) async => [
              firebaseCode,
              'Backend wording may change',
              {
                'code': firebaseCode,
                'message': 'Backend wording may change',
                'additionalData': firebaseDetails,
              },
            ]);
  });

  tearDown(
      () => messenger.setMockDecodedMessageHandler<Object?>(channel, null));

  test('callable failures never log patient text or backend error prose',
      () async {
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      await expectLater(
        assistant.sendMessage(message: 'Private patient scheduling request'),
        throwsA(isA<AssistantFunctionException>()),
      );
    } finally {
      debugPrint = originalDebugPrint;
    }
    final output = messages.join('\n');
    expect(output, isNot(contains('Private patient scheduling request')));
    expect(output, isNot(contains('Backend wording may change')));
  });

  test('local daily quota remains a daily limit when status is omitted',
      () async {
    firebaseDetails = {'reasonCode': 'local_daily_cap_reached'};
    await expectLater(
      assistant.sendMessage(message: 'Find a slot'),
      throwsA(isA<AssistantFunctionException>().having(
        (failure) => failure.kind,
        'kind',
        AssistantFailureKind.dailyLimit,
      )),
    );
  });

  final invocations = <AssistantFunctionOperation, Future<Object?> Function()>{
    AssistantFunctionOperation.sendMessage: () =>
        assistant.sendMessage(message: 'Find a slot'),
    AssistantFunctionOperation.history: () => assistant.getHistory(),
    AssistantFunctionOperation.clearHistory: () => assistant.clearHistory(),
    AssistantFunctionOperation.confirmAppointment: () =>
        assistant.confirmAppointment(
          offerId: 'offer_123',
          confirmed: true,
          idempotencyKey: 'confirmation_123',
        ),
  };

  for (final invocation in invocations.entries) {
    test('daily-limit metadata survives the ${invocation.key.name} callable',
        () async {
      await expectLater(
          invocation.value(),
          throwsA(
            isA<AssistantFunctionException>()
                .having((failure) => failure.kind, 'kind',
                    AssistantFailureKind.dailyLimit)
                .having((failure) => failure.status, 'status',
                    AssistantMessageStatus.dailyLimit)
                .having((failure) => failure.reasonCode, 'reason',
                    'upstream_daily_limit_reached')
                .having((failure) => failure.resetAt, 'UTC reset',
                    DateTime.utc(2026, 10, 21))
                .having((failure) => failure.operation, 'operation',
                    invocation.key),
          ));
    });
  }

  final failuresWithoutStatus = [
    (
      operation: AssistantFunctionOperation.sendMessage,
      code: 'failed-precondition',
      expected: AssistantFailureKind.throttled
    ),
    (
      operation: AssistantFunctionOperation.confirmAppointment,
      code: 'failed-precondition',
      expected: AssistantFailureKind.staleOffer
    ),
    (
      operation: AssistantFunctionOperation.history,
      code: 'internal',
      expected: AssistantFailureKind.historyLoad
    ),
  ];
  for (final scenario in failuresWithoutStatus) {
    test(
        '${scenario.operation.name} classifies ${scenario.code} independently of error text',
        () async {
      firebaseCode = scenario.code;
      firebaseDetails = {};
      await expectLater(
          invocations[scenario.operation]!(),
          throwsA(
            isA<AssistantFunctionException>()
                .having((failure) => failure.kind, 'kind', scenario.expected),
          ));
    });
  }
}
