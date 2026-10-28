// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/notification_provider.dart';
import 'package:uhc/screens/patient/browse_doctors/doctor_list_screen.dart';
import 'package:uhc/screens/patient/departments/department_browsing_screen.dart';
import 'package:uhc/screens/patient/home/home_screen.dart';
import 'package:uhc/screens/patient/main_shell.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_FirebaseCoreWithStorage());
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'Selecting a department keeps the doctor list inside the patient shell',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const query = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.queryGet',
      FirebaseFirestoreHostApi.pigeonChannelCodec,
    );
    const snapshots = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.querySnapshot',
      FirebaseFirestoreHostApi.pigeonChannelCodec,
    );
    final metadata =
        InternalSnapshotMetadata(hasPendingWrites: false, isFromCache: false);
    messenger.setMockDecodedMessageHandler<Object?>(
        query,
        (_) async => [
              InternalQuerySnapshot(
                documents: [
                  InternalDocumentSnapshot(
                      path: 'departments/dentistry',
                      data: {
                        'key': 'dentistry',
                        'name': 'Dentistry',
                        'description': 'Dental appointments',
                        'isActive': true,
                      },
                      metadata: metadata),
                  InternalDocumentSnapshot(
                      path: 'departments/generalMedicine',
                      data: {
                        'key': 'generalMedicine',
                        'name': 'General Medicine',
                        'isActive': true,
                      },
                      metadata: metadata)
                ],
                documentChanges: [],
                metadata: metadata,
              ),
            ]);
    // Keep the doctors stream loading: navigation must remain usable during a read.
    messenger.setMockDecodedMessageHandler<Object?>(
        snapshots, (_) => Completer<Object?>().future);
    addTearDown(() {
      messenger.setMockDecodedMessageHandler<Object?>(query, null);
      messenger.setMockDecodedMessageHandler<Object?>(snapshots, null);
    });
    final auth = AuthProvider();
    final notifications = NotificationProvider();
    addTearDown(auth.dispose);
    addTearDown(notifications.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<NotificationProvider>.value(
            value: notifications),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainShell(initializeNotifications: false),
      ),
    ));
    await tester.pumpAndSettle();
    final viewAll = find.widgetWithText(TextButton, 'View All');
    await tester.ensureVisible(viewAll);
    await tester.tap(viewAll);
    await tester.pumpAndSettle();
    expect(find.byType(DepartmentBrowsingScreen), findsOneWidget);
    final departmentCard = find.descendant(
      of: find.byType(DepartmentBrowsingScreen),
      matching: find.text('Dentistry'),
    );
    expect(departmentCard, findsOneWidget);
    final transition = ModalRoute.of(tester.element(departmentCard))!
        .reverseTransitionDuration;
    await tester.tap(departmentCard);
    await tester.pump();
    await tester.pump(transition);
    await tester.pump();

    expect(find.byType(DepartmentBrowsingScreen).hitTestable(), findsNothing);
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.byType(DoctorListScreen), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Dentistry').hitTestable(),
        findsOneWidget);
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Dentistry'))
            .selected,
        isTrue);
    final home = find.text('Home').hitTestable();
    expect(home, findsOneWidget);
    await tester.tap(home);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HomeScreen).hitTestable(), findsOneWidget);
    expect(find.byType(DoctorListScreen).hitTestable(), findsNothing);
    // Regression: fixed-height Home cards overflowed with Android font scale 1.7.
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump(const Duration(seconds: 2));
    final departmentLabel = find.descendant(
        of: find.byType(HomeScreen), matching: find.text('General'));
    await tester.ensureVisible(departmentLabel);
    await tester.pump(const Duration(milliseconds: 400));
    final paragraph = tester.renderObject<RenderParagraph>(departmentLabel);
    final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 7));
    expect(boxes.map((box) => box.top).toSet(), hasLength(1),
        reason:
            'A single department word must fit on one line at font scale 1.7');
    await tester.ensureVisible(find.text('Stay Hydrated'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Stay Hydrated').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FirebaseCoreWithStorage extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}
