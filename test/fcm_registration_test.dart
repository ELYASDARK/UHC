// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:uhc/services/fcm_service.dart';

void main() {
  final platform = _RegistrationPlatform();
  late FCMService service;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseMessagingPlatform.instance = platform;
    service = FCMService();
  });

  test('registration emitted before the native future completes is returned',
      () async {
    final finish = Completer<void>();
    platform.registerAction = () {
      platform.registered.add('synthetic-installation');
      return finish.future;
    };
    final registration = service.getToken();
    finish.complete();
    expect(await registration, 'synthetic-installation');
    expect(platform.registered.hasListener, isFalse);
  });

  test('native registration failure releases the event subscription', () async {
    platform.registerAction =
        () async => throw StateError('registration failed');
    await expectLater(service.getToken(), throwsStateError);
    expect(platform.registered.hasListener, isFalse);
  });

  test(
      'registration stream errors are returned and the next attempt can recover',
      () async {
    platform.registerAction = () async {
      platform.registered.addError(StateError('registration stream failed'));
    };
    await expectLater(service.getToken(), throwsStateError);
    expect(platform.registered.hasListener, isFalse);
    platform.registerAction =
        () async => platform.registered.add('recovered-installation');
    expect(await service.getToken(), 'recovered-installation');
  });

  test('unregister does not create a fresh registration during deletion',
      () async {
    platform.registerAction = () async => fail('Deletion must not register');
    final before = platform.unregistered;
    await service.deleteToken();
    expect(platform.unregistered, before + 1);
  });
}

// Only the external messaging SDK boundary is replaced. No live FCM traffic.
class _RegistrationPlatform extends FirebaseMessagingPlatform
    with MockPlatformInterfaceMixin {
  final registered = StreamController<String>.broadcast(sync: true);
  late Future<void> Function() registerAction;
  int unregistered = 0;

  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) => this;
  @override
  Stream<String> get onRegistered => registered.stream;
  @override
  Future<void> register({String? vapidKey, String? serviceWorkerScriptPath}) =>
      registerAction();
  @override
  Future<void> unregister() async => unregistered++;
}
