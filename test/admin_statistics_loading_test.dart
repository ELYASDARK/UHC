// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:uhc/data/models/user_model.dart';
import 'package:uhc/data/models/admin_permissions_model.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/screens/admin/dashboard/admin_dashboard_screen.dart';
import 'package:uhc/screens/admin/analytics/appointment_analytics_screen.dart';
import 'package:uhc/services/admin_statistics_service.dart';

Map<String, dynamic> summary(int total, {bool partial = false}) => {
      'total': total,
      'truncated': partial,
      'statuses': {'completed': total},
      'departments': {'Synthetic': total},
      'days': <String, int>{},
    };

class ControlledStatistics extends AdminStatisticsService {
  final requests = <String, List<Completer<Map<String, dynamic>>>>{};
  int userCalls = 0, doctorCalls = 0;
  @override
  Future<int> users() async {
    userCalls++;
    return 12;
  }

  @override
  Future<int> doctors() async {
    doctorCalls++;
    return 3;
  }

  @override
  Future<Map<String, dynamic>> analytics(String period) {
    final pending = Completer<Map<String, dynamic>>();
    requests.putIfAbsent(period, () => []).add(pending);
    return pending.future;
  }
}

class SyntheticAuth extends AuthProvider {
  @override
  bool get isGoogleLinked => true;
  String identity = 'synthetic-admin';
  bool allowed = true;
  void revoke() {
    allowed = false;
    notifyListeners();
  }

  @override
  UserModel get user => UserModel(
      id: identity,
      email: 'synthetic@example.test',
      fullName: 'Synthetic Admin',
      role: UserRole.admin,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      adminPermissions: AdminPermissions.fromMap(
          {'analytics.view': allowed, 'users.view': allowed}));
  @override
  UserModel get currentUser => user;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('en');
    TestFirebaseCoreHostApi.setUp(_Core());
    await Firebase.initializeApp();
  });
  Future<void> show(WidgetTester tester, Widget page,
      {AuthProvider? auth, double textScale = 1}) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: page,
    );
    await tester.pumpWidget(auth == null
        ? app
        : ChangeNotifierProvider<AuthProvider>.value(value: auth, child: app));
    await tester.pump();
  }

  testWidgets(
      'English update header wraps at large text without extra requests',
      (tester) async {
    final data = ControlledStatistics();
    await show(tester, AppointmentAnalyticsScreen(statistics: data),
        textScale: 2);
    tester.view.physicalSize = const Size(320, 900);
    expect(find.text('Updating…'), findsOneWidget);
    expect(find.textContaining('processed'), findsNothing);
    final snapshot = DateTime(2026, 11, 1, 17, 20).toUtc().toIso8601String();
    data.requests['week']!.single.complete({
      ...summary(1),
      'asOf': snapshot,
      'days': {'2026-11-01': 1},
    });
    await tester.pumpAndSettle();
    final hint = find.text('Refresh to see the latest changes.');
    expect(hint, findsOneWidget);
    expect(Directionality.of(tester.element(hint)), TextDirection.ltr);
    expect(find.textContaining(snapshot), findsNothing);
    expect(find.textContaining('Snapshot'), findsNothing);
    expect(find.textContaining('Nov 1, 2026'), findsOneWidget);
    expect(find.textContaining('5:20'), findsOneWidget);
    expect(tester.getBottomLeft(hint).dy,
        lessThan(tester.getTopLeft(find.text('Total')).dy));
    await tester.pump(const Duration(minutes: 2));
    expect(data.requests['week'], hasLength(1));
  }, tags: ['large-text']);

  testWidgets(
      'unavailable snapshot time stays explicit and refresh keeps the selected period',
      (tester) async {
    final data = ControlledStatistics();
    await show(tester, AppointmentAnalyticsScreen(statistics: data));
    data.requests['week']!.single.complete({...summary(1), 'asOf': 'invalid'});
    await tester.pumpAndSettle();
    expect(find.text('Update time unavailable'), findsOneWidget);
    expect(find.text('Appointments added in this period.'), findsNothing);
    expect(find.textContaining('invalid'), findsNothing);
    await tester.tap(find.text('Month'));
    await tester.pump();
    data.requests['month']!.single.complete({
      ...summary(2),
      'asOf': DateTime(2026, 11, 1, 17, 20).toUtc().toIso8601String(),
    });
    await tester.pumpAndSettle();
    expect(find.text('Appointments added in this period.'), findsNothing);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(data.requests['week'], hasLength(1));
    expect(data.requests['month'], hasLength(2));
    data.requests['month']!.last.complete({
      ...summary(3),
      'asOf': DateTime(2026, 11, 1, 17, 25).toUtc().toIso8601String(),
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('5:25'), findsOneWidget);
    expect(find.textContaining('5:20'), findsNothing);
    expect(find.text('Update time unavailable'), findsNothing);
    expect(find.text('3'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'analytics contains long custom department labels on a narrow screen',
      (tester) async {
    final data = ControlledStatistics();
    await show(tester, AppointmentAnalyticsScreen(statistics: data));
    tester.view.physicalSize = const Size(320, 800);
    await tester.pump();
    final label = List.filled(120, 'D').join();
    data.requests['week']!.single.complete({
      ...summary(1),
      'departments': {label: 1}
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip(label), findsOneWidget);
    expect(find.text('Appointments added in this period.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'native statistics retries replace stalled reads without unlimited requests',
      (tester) async {
    final replies = <Completer<int>>[];
    final service = AdminStatisticsService(userCount: () {
      final reply = Completer<int>();
      replies.add(reply);
      return reply.future;
    });
    final first = service.users().catchError((_) => -1);
    final shared = service.users().catchError((_) => -1);
    expect(replies.length, 1);
    await tester.pump(const Duration(seconds: 15));
    expect(await first, -1);
    expect(await shared, -1);
    final replacement = service.users();
    expect(replies.length, 2);
    replies[1].complete(7);
    await tester.pump();
    expect(await replacement, 7);
    final next = service.users().catchError((_) => -1);
    await tester.pump(const Duration(seconds: 15));
    expect(await next, -1);
    await expectLater(
        service.users(), throwsA(isA<StatisticsRequestsPending>()));
    expect(replies.length, 3);
    replies[0].complete(999);
    replies[2].complete(99);
    await tester.pump();
    final recovered = service.users();
    replies.last.complete(8);
    await tester.pump();
    expect(await recovered, 8);
  });

  testWidgets(
      'dashboard starts independent reads and keeps navigation available through timeout and retry',
      (tester) async {
    final data = ControlledStatistics(), auth = SyntheticAuth();
    await show(tester, AdminDashboardScreen(statistics: data), auth: auth);
    expect(data.userCalls, 1);
    expect(data.doctorCalls, 1);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Loading...'), findsNWidgets(4));
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(find.text('Unavailable'), findsNWidgets(4));
    expect(find.text('0'), findsNothing);
    await tester.tap(find.text('Retry statistics'));
    await tester.pump();
    expect(data.userCalls, 1);
    expect(data.doctorCalls, 1);
    expect(data.requests['dashboard']!.length, 2);
    data.requests['dashboard']![0]
        .complete({'total': 999, 'pending': 0, 'today': 0, 'completed': 0});
    data.requests['dashboard']![1]
        .complete({'total': 7, 'pending': 2, 'today': 1, 'completed': 4});
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('999'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });
  testWidgets(
      'same-session permission revocation invalidates dashboard and analytics replies',
      (tester) async {
    final data = ControlledStatistics(), auth = SyntheticAuth();
    await show(tester, AdminDashboardScreen(statistics: data), auth: auth);
    auth.revoke();
    await tester.pump();
    data.requests['dashboard']!.single.complete(
        {'total': 999, 'pending': 999, 'today': 999, 'completed': 999});
    await tester.pumpAndSettle();
    expect(find.text('999'), findsNothing);
    expect(find.text('12'), findsNothing);
    expect(find.text('No access'), findsNWidgets(5));
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    final otherData = ControlledStatistics(), otherAuth = SyntheticAuth();
    await show(tester, AppointmentAnalyticsScreen(statistics: otherData),
        auth: otherAuth);
    otherAuth.revoke();
    await tester.pump();
    otherData.requests['week']!.single.complete(summary(999));
    await tester.pumpAndSettle();
    expect(find.text('999'), findsNothing);
    expect(find.text("You don't have access to this summary."), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    otherAuth.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
  testWidgets(
      'analytics partial data, period races, error and retry never show stale full totals',
      (tester) async {
    final data = ControlledStatistics();
    await show(tester, AppointmentAnalyticsScreen(statistics: data));
    await tester.tap(find.text('Month'));
    await tester.pump();
    await tester.tap(find.text('Year'));
    await tester.pump();
    data.requests['month']!.single.complete(summary(88));
    data.requests['week']!.single.complete(summary(99));
    await tester.pump();
    expect(find.text('88'), findsNothing);
    expect(find.text('99'), findsNothing);
    data.requests['year']!.single.complete(summary(5000, partial: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing the 5,000'), findsOneWidget);
    expect(find.text('Appointments added in this period.'), findsNothing);
    expect(find.text('Shown'), findsOneWidget);
    expect(find.text('Completion rate'), findsOneWidget);
    expect(find.text('Total'), findsNothing);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    data.requests['year']!.last.completeError(StateError('Controlled failure'));
    await tester.pumpAndSettle();
    expect(find.text('5000'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    data.requests['year']!.last.complete(summary(0));
    await tester.pumpAndSettle();
    expect(find.text('No appointments in this period.'), findsOneWidget);
    expect(find.textContaining('Showing the 5,000'), findsNothing);
  });
}

class _Core extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}
