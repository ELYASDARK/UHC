// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:uhc/core/widgets/session_stream_builder.dart';
import 'package:uhc/data/models/admin_permissions_model.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/models/user_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/providers/appointment_provider.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/doctor_appointment_provider.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_Core());
    await Firebase.initializeApp();
  });

  test('current appointments and empty reuse do not wait for paginated history',
      () async {
    final repository = _Reads();
    final provider = AppointmentProvider(appointmentRepository: repository);
    await provider.loadAppointments('patient');
    final history = provider.loadPastAppointments('patient');
    final sameHistory = provider.loadPastAppointments('patient');
    expect(provider.isLoading, isFalse);
    expect(provider.hasLoadedUpcoming, isTrue);
    expect(provider.isLoadingHistory, isTrue);
    await provider.loadAppointments('patient', forceRefresh: false);
    expect(repository.currentReads, 1);
    expect(repository.historyReads, 1);
    repository.history.complete(AppointmentHistoryPage(
        appointments: [_appointment('first')], hasMore: true));
    await Future.wait([history, sameHistory]);
    repository.history = Completer();
    final more = provider.loadMoreHistory();
    final sameMore = provider.loadMoreHistory();
    repository.history.complete(AppointmentHistoryPage(
        appointments: [_appointment('second')], hasMore: false));
    await Future.wait([more, sameMore]);
    expect(provider.pastAppointments.map((apt) => apt.id), ['first', 'second']);
    expect(provider.hasMoreHistory, isFalse);
    expect(repository.historyReads, 2);
    provider.dispose();
  });

  test(
      'recoverable failure retains current data and permission denial clears it',
      () async {
    final repository = _Reads()..current = [_appointment('authorized')];
    final provider = AppointmentProvider(appointmentRepository: repository);
    await provider.loadAppointments('patient');
    repository.failure =
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    await provider.loadAppointments('patient');
    expect(provider.upcomingAppointments.single.id, 'authorized');
    expect(provider.error, isNotNull);
    repository.failure =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await provider.loadAppointments('patient');
    expect(provider.upcomingAppointments, isEmpty);
    expect(provider.hasLoadedUpcoming, isFalse);
    expect(provider.isLoading, isFalse);
    provider.dispose();
  });

  test(
      'doctor list is usable during maintenance and failed no-show stays pending',
      () async {
    final repository = _Reads()..current = [_appointment('overdue')];
    final provider =
        DoctorAppointmentProvider(appointmentRepository: repository);
    await provider.loadAppointments('doctor');
    expect(provider.hasLoadedFull, isTrue);
    expect(provider.isLoading, isFalse);
    expect(repository.statusWrites, 1);
    expect(provider.appointments.single.status, AppointmentStatus.pending);
    repository.status
        .completeError(StateError('server rejected status change'));
    await Future<void>.delayed(Duration.zero);
    expect(provider.appointments.single.status, AppointmentStatus.pending);
    await provider.loadAppointments('doctor', forceRefresh: false);
    expect(repository.currentReads, 1);
    provider.dispose();
  });

  test('a doctor mutation replaces a read that began before the write',
      () async {
    final original =
        _appointment('same').copyWith(appointmentDate: DateTime(2099));
    final repository = _Reads()..current = [original];
    final provider =
        DoctorAppointmentProvider(appointmentRepository: repository);
    await provider.loadAppointments('doctor');
    final stale = Completer<List<AppointmentModel>>();
    repository.pendingReads.add(stale);
    final refresh = provider.loadAppointments('doctor');
    repository.current = [
      original.copyWith(status: AppointmentStatus.confirmed)
    ];
    final mutation =
        provider.updateStatus('same', AppointmentStatus.confirmed, 'doctor');
    await Future<void>.delayed(Duration.zero);
    repository.status.complete();
    await Future<void>.delayed(Duration.zero);
    stale.complete([original]);
    await Future.wait([refresh, mutation]);
    expect(provider.appointments.single.status, AppointmentStatus.confirmed);
    expect(provider.error, isNull);
    expect(repository.currentReads, 3);
    provider.dispose();
  });

  testWidgets('rebuilds reuse one listener and query/session changes cancel it',
      (tester) async {
    final auth = _SessionAuth();
    var query = 1, listens = 0, cancels = 0;
    final controllers = <StreamController<String>>[];
    late StateSetter rebuild;
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return SessionStreamBuilder<String>(
            permission: 'users.view',
            queryKey: query,
            createStream: () {
              final controller = StreamController<String>(
                  onListen: () => listens++, onCancel: () => cancels++);
              controllers.add(controller);
              return controller.stream;
            },
            builder: (_, snapshot) => Text(snapshot.data ?? 'Loading'),
          );
        }),
      ),
    ));
    controllers.single.add('authorized-a');
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      rebuild(() {});
      await tester.pump();
    }
    expect(listens, 1);
    expect(cancels, 0);
    rebuild(() => query++);
    await tester.pump();
    expect(listens, 2);
    expect(cancels, 1);
    auth.identity = 'b';
    auth.notifyListeners();
    await tester.pump();
    expect(find.text('authorized-a'), findsNothing);
    expect(listens, 3);
    expect(cancels, 2);
    controllers.last.add('authorized-b');
    await tester.pump();
    auth.allowed = false;
    auth.notifyListeners();
    await tester.pump();
    expect(find.text('authorized-b'), findsNothing);
    expect(cancels, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      unawaited(controller.close());
    }
    await tester.pump(const Duration(seconds: 2));
    auth.dispose();
  });
}

AppointmentModel _appointment(String id) => AppointmentModel(
    id: id,
    patientId: '',
    patientName: 'Synthetic Patient',
    patientEmail: '',
    doctorId: '',
    doctorName: 'Synthetic Doctor',
    department: 'generalMedicine',
    appointmentDate: DateTime(2026, 1, 1),
    timeSlot: '09:00 - 09:30',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026));

class _Reads extends AppointmentRepository {
  var current = <AppointmentModel>[];
  Object? failure;
  var currentReads = 0, historyReads = 0, statusWrites = 0;
  var history = Completer<AppointmentHistoryPage>();
  final status = Completer<void>();
  final pendingReads = <Completer<List<AppointmentModel>>>[];
  @override
  Future<List<AppointmentModel>> getUpcomingAppointments(String userId,
      {String? email}) async {
    currentReads++;
    if (pendingReads.isNotEmpty) return pendingReads.removeAt(0).future;
    if (failure != null) throw failure!;
    return current;
  }

  @override
  Future<AppointmentHistoryPage> getPastAppointmentsPage(String userId,
      {String? email, AppointmentHistoryPage? after, int pageSize = 30}) {
    historyReads++;
    return history.future;
  }

  @override
  Future<List<AppointmentModel>> getAllDoctorAppointments(String doctorId) =>
      getUpcomingAppointments(doctorId);
  @override
  Future<void> updateAppointmentStatus(
      String appointmentId, AppointmentStatus next,
      {String? statusUpdatedBy}) {
    statusWrites++;
    return status.future;
  }
}

class _SessionAuth extends AuthProvider {
  String identity = 'a';
  bool allowed = true;
  @override
  bool get isAuthenticated => true;
  @override
  String get cacheSessionKey => '$identity:$allowed';
  @override
  UserModel get user => UserModel(
      id: identity,
      email: 'synthetic@example.test',
      fullName: 'Synthetic Admin',
      role: UserRole.admin,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      adminPermissions: AdminPermissions(usersView: allowed));
}

class _Core extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}
