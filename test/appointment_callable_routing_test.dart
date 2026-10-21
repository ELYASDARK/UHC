// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
    StandardMessageCodec(),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final requests = <Map<String, dynamic>>[];
  late AppointmentRepository appointments;
  Map<String, dynamic> response = {};
  var denied = false;
  var nativeCalls = 0;
  var localCalls = 0;

  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(_FirebaseDemoCore());
    final app = await Firebase.initializeApp(
      name: 'appointment-callable-routing',
      options: EmulatorConfig.syntheticDemoOptions,
    );
    appointments = AppointmentRepository(
      firestore: FirebaseFirestore.instanceFor(app: app),
      functions: FirebaseFunctions.instanceFor(app: app),
    );
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    requests.clear();
    response = {};
    denied = false;
    nativeCalls = 0;
    localCalls = 0;
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      nativeCalls++;
      expect(EmulatorConfig.isEmulatorEnabled, isFalse,
          reason: 'Android emulator calls must avoid the native IID lookup.');
      final arguments = (message as List).single as Map;
      requests.add({
        'name': arguments['functionName'],
        'data': Map<String, dynamic>.from(arguments['parameters'] as Map),
      });
      if (denied) {
        return [
          'permission-denied',
          'Appointment is not owned by this patient.',
          {
            'code': 'permission-denied',
            'message': 'Appointment is not owned by this patient.',
            'additionalData': {'reasonCode': 'wrong_patient'},
          },
        ];
      }
      return [response];
    });
  });

  tearDown(() {
    messenger.setMockDecodedMessageHandler<Object?>(channel, null);
    debugDefaultTargetPlatformOverride = null;
    expect(localCalls > 0, EmulatorConfig.isEmulatorEnabled);
    expect(nativeCalls > 0, !EmulatorConfig.isEmulatorEnabled);
  });

  Future<T> throughSelectedAdapter<T>(Future<T> Function() action) =>
      http.runWithClient(
          action,
          () => MockClient((request) async {
                localCalls++;
                expect(EmulatorConfig.isEmulatorEnabled, isTrue);
                expect(request.url.origin, 'http://10.0.2.2:5001');
                expect(request.url.pathSegments.take(2),
                    ['demo-uhc-test', 'us-central1']);
                expect(
                    request.headers.containsKey('Firebase-Instance-ID-Token'),
                    isFalse);
                final envelope = jsonDecode(request.body) as Map;
                requests.add({
                  'name': request.url.pathSegments.last,
                  'data': Map<String, dynamic>.from(envelope['data'] as Map),
                });
                return http.Response(
                  jsonEncode(denied
                      ? {
                          'error': {
                            'status': 'PERMISSION_DENIED',
                            'message':
                                'Appointment is not owned by this patient.',
                            'details': {'reasonCode': 'wrong_patient'},
                          },
                        }
                      : {'result': response}),
                  denied ? 403 : 200,
                );
              }));

  test('day availability uses the selected callable adapter and typed result',
      () async {
    response = {
      'success': true,
      'doctorId': 'doctor-local',
      'appointmentDate': '2026-10-22',
      'doctorName': 'Local Doctor',
      'department': 'dermatology',
      'slots': [
        {
          'timeSlot': '14:00 - 14:30',
          'startTime': '14:00',
          'endTime': '14:30',
          'isAvailable': false,
        },
      ],
    };
    final result = await throughSelectedAdapter(() =>
        appointments.getDoctorDayAvailability(
            doctorId: 'doctor-local', date: DateTime(2026, 10, 22)));

    expect(result.success, isTrue);
    expect(result.doctorName, 'Local Doctor');
    expect(result.slots.single.isAvailable, isFalse);
    expect(requests, [
      {
        'name': 'getDoctorDayAvailability',
        'data': {'doctorId': 'doctor-local', 'date': '2026-10-22'},
      },
    ]);
  });

  test('direct booking preserves its request reference and returned receipt',
      () async {
    final date = DateTime.utc(2026, 10, 22);
    response = {
      'appointmentId': 'appointment-local',
      'bookingReference': 'UHC-LOCAL',
      'qrCode': 'local-qr',
    };
    final receipt = await throughSelectedAdapter(
        () => appointments.createAppointment(AppointmentModel(
              id: '',
              patientId: 'patient-local',
              patientName: 'Local Patient',
              patientEmail: 'local@example.test',
              doctorId: 'doctor-local',
              doctorName: 'Local Doctor',
              department: 'dermatology',
              appointmentDate: date,
              timeSlot: '14:00 - 14:30',
              type: AppointmentType.consultation,
              notes: 'Booking notes',
              bookingReference: 'UHC-REQUEST',
              createdAt: date,
              updatedAt: date,
            )));
    expect(receipt.appointmentId, 'appointment-local');
    expect(receipt.bookingReference, 'UHC-LOCAL');
    expect(receipt.qrCode, 'local-qr');
    expect(requests.single['name'], 'createAppointment');
    expect(requests.single['data'],
        containsPair('bookingReference', 'UHC-REQUEST'));
    expect(requests.single['data'], containsPair('patientId', 'patient-local'));
    expect(requests.single['data'],
        containsPair('appointmentDate', date.toIso8601String()));
  });

  test('selected adapter preserves appointment authorization failures',
      () async {
    denied = true;
    await expectLater(
      throughSelectedAdapter(
          () => appointments.cancelAppointment('another-patients', 'Cancel')),
      throwsA(isA<FirebaseFunctionsException>()
          .having((failure) => failure.code, 'code', 'permission-denied')
          .having((failure) => failure.details, 'details',
              {'reasonCode': 'wrong_patient'})),
    );
  });
}

class _FirebaseDemoCore extends MockFirebaseApp {
  @override
  Future<CoreInitializeResponse> initializeApp(
          String appName, CoreFirebaseOptions options) async =>
      CoreInitializeResponse(
          name: appName, options: options, pluginConstants: {});
}
