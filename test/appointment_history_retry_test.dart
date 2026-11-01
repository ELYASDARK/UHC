// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/data/models/appointment_model.dart';
import 'package:uhc/data/repositories/appointment_repository.dart';
import 'package:uhc/providers/appointment_provider.dart';

void main() {
  setUpAll(() async {
    TestFirebaseCoreHostApi.setUp(_Core());
    await Firebase.initializeApp();
  });

  testWidgets(
      'timed-out append retries retain earlier pages and cursor continuity',
      (tester) async {
    final repository = _HistoryReads();
    final provider = AppointmentProvider(appointmentRepository: repository);
    addTearDown(provider.dispose);
    final first = _page('first');
    repository.next.complete(first);
    await provider.loadPastAppointments('patient');
    final secondRead = repository.next = Completer();
    final more = provider.loadMoreHistory();
    await tester.pump(const Duration(seconds: 16));
    await more;
    expect(provider.historyError, isNotNull);
    expect(provider.pastAppointments.single.id, 'first');
    for (var attempt = 0; attempt < 2; attempt++) {
      final retry = provider.retryHistory();
      await tester.pump(const Duration(seconds: 16));
      await retry;
    }
    expect(repository.cursors, [null, first]);
    final retry = provider.retryHistory();
    final second = _page('second');
    secondRead.complete(second);
    await tester.pump();
    await retry;
    expect(provider.pastAppointments.map((a) => a.id), ['first', 'second']);
    expect(provider.historyError, isNull);
    expect(provider.hasMoreHistory, isTrue);
    repository.next = Completer();
    final last = provider.loadMoreHistory();
    expect(repository.cursors.last, same(second));
    repository.next.complete(_page('last', hasMore: false));
    await tester.pump();
    await last;
    expect(provider.pastAppointments.map((a) => a.id),
        ['first', 'second', 'last']);
    expect(provider.hasMoreHistory, isFalse);
    expect(repository.cursors.length, 3);
  });

  for (final timedOut in [false, true]) {
    testWidgets(
        'refresh queues one real first page behind an append, timeout=$timedOut',
        (tester) async {
      final repository = _HistoryReads();
      final provider = AppointmentProvider(appointmentRepository: repository);
      addTearDown(provider.dispose);
      final first = _page('first');
      repository.next.complete(first);
      await provider.loadPastAppointments('patient');
      final appendRead = repository.next = Completer();
      final append = provider.loadMoreHistory();
      if (timedOut) {
        await tester.pump(const Duration(seconds: 16));
        await append;
      }
      final refresh =
          provider.loadPastAppointments('patient', forceRefresh: true);
      final repeat =
          provider.loadPastAppointments('patient', forceRefresh: true);
      expect(repository.cursors, [null, first]);
      final resetRead = repository.next = Completer();
      appendRead.complete(_page('second'));
      await tester.pump();
      expect(repository.cursors, [null, first, null]);
      expect(provider.pastAppointments.map((a) => a.id), ['first', 'second']);
      resetRead.complete(_page('server-first'));
      await tester.pump();
      await Future.wait([append, refresh, repeat]);
      expect(provider.pastAppointments.single.id, 'server-first');
      expect(provider.hasMoreHistory, isTrue);
      expect(provider.historyError, isNull);
      repository.next = Completer();
      final settledRefresh =
          provider.loadPastAppointments('patient', forceRefresh: true);
      expect(repository.cursors, [null, first, null, null]);
      repository.next.complete(_page('new-first', hasMore: false));
      await tester.pump();
      await settledRefresh;
      expect(provider.pastAppointments.single.id, 'new-first');
      expect(provider.hasMoreHistory, isFalse);
    });
  }

  testWidgets(
      'denied pending history clears rows for listening widgets and drops queued refresh',
      (tester) async {
    final repository = _HistoryReads();
    final provider = AppointmentProvider(appointmentRepository: repository);
    addTearDown(provider.dispose);
    repository.next.complete(_page('authorized'));
    await provider.loadPastAppointments('patient');
    var displayedIds = provider.pastAppointments.map((a) => a.id).toList();
    provider.addListener(() {
      displayedIds = provider.pastAppointments.map((a) => a.id).toList();
    });
    repository.next = Completer();
    final append = provider.loadMoreHistory();
    final queued = provider.loadPastAppointments('patient', forceRefresh: true);
    repository.next.completeError(FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied'));
    await tester.pump();
    await Future.wait([append, queued]);
    expect(provider.pastAppointments, isEmpty);
    expect(displayedIds, isEmpty);
    expect(provider.hasLoadedHistory, isFalse);
    expect(provider.isLoadingHistory, isFalse);
    expect(provider.historyError, isNotNull);
    expect(repository.cursors.length, 2);
  });

  for (final switchOwner in [false, true]) {
    testWidgets(
        'invalidated pending append cannot publish or queue old refresh, switchOwner=$switchOwner',
        (tester) async {
      final repository = _HistoryReads();
      final provider = AppointmentProvider(appointmentRepository: repository);
      addTearDown(provider.dispose);
      repository.next.complete(_page('first'));
      await provider.loadPastAppointments('patient');
      final staleRead = repository.next = Completer();
      final append = provider.loadMoreHistory();
      final queued =
          provider.loadPastAppointments('patient', forceRefresh: true);
      if (!switchOwner) provider.invalidateAppointments();
      repository.next = Completer();
      final fresh = provider.loadPastAppointments(
          switchOwner ? 'other' : 'patient',
          forceRefresh: true);
      repository.next.complete(_page('fresh', hasMore: false));
      await tester.pump();
      await fresh;
      staleRead.complete(_page('stale'));
      await tester.pump();
      await Future.wait([append, queued]);
      expect(provider.pastAppointments.single.id, 'fresh');
      expect(provider.hasMoreHistory, isFalse);
      expect(provider.isLoadingHistory, isFalse);
      expect(provider.historyError, isNull);
      expect(repository.cursors.length, 3);
      expect(repository.owners.last, switchOwner ? 'other' : 'patient');
    });
  }
}

AppointmentHistoryPage _page(String id, {bool hasMore = true}) =>
    AppointmentHistoryPage(appointments: [_appointment(id)], hasMore: hasMore);

class _HistoryReads extends AppointmentRepository {
  var next = Completer<AppointmentHistoryPage>();
  final cursors = <AppointmentHistoryPage?>[];
  final owners = <String>[];
  @override
  Future<AppointmentHistoryPage> getPastAppointmentsPage(String userId,
      {String? email, AppointmentHistoryPage? after, int pageSize = 30}) {
    cursors.add(after);
    owners.add(userId);
    return next.future;
  }
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

class _Core extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}
