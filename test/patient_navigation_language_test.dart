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
import 'package:uhc/l10n/kurdish_material_localizations.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/providers/notification_provider.dart';
import 'package:uhc/screens/patient/browse_doctors/doctor_list_screen.dart';
import 'package:uhc/screens/patient/main_shell.dart';
import 'package:uhc/screens/shared/language_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_FirebaseCoreWithStorage());
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('patient shell reserves content height above painted navigation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    messenger.setMockDecodedMessageHandler<Object?>(
        query,
        (_) async => [
              InternalQuerySnapshot(
                documents: [],
                documentChanges: [],
                metadata: InternalSnapshotMetadata(
                    hasPendingWrites: false, isFromCache: false),
              ),
            ]);
    messenger.setMockDecodedMessageHandler<Object?>(
        snapshots, (_) => Completer<Object?>().future);
    addTearDown(() {
      messenger.setMockDecodedMessageHandler<Object?>(query, null);
      messenger.setMockDecodedMessageHandler<Object?>(snapshots, null);
    });
    final auth = AuthProvider();
    final notifications = NotificationProvider();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<NotificationProvider>.value(
            value: notifications),
      ],
      child: _app(
        locale: const Locale('en'),
        child: const MainShell(initialIndex: 1, initializeNotifications: false),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    final bar = find.byType(PatientBottomNavigationBar);
    expect(tester.getRect(find.byType(DoctorListScreen)).bottom,
        lessThanOrEqualTo(tester.getRect(bar).top));
    final painted = tester
        .widget<DecoratedBox>(find
            .descendant(
              of: bar,
              matching: find.byType(DecoratedBox),
            )
            .first)
        .decoration as BoxDecoration;
    expect(painted.color?.a, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    notifications.dispose();
  });

  for (final language in ['en', 'ar', 'ku']) {
    for (final brightness in Brightness.values) {
      testWidgets('$language $brightness navigation fits narrow large text',
          (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 0;
        await tester.pumpWidget(_app(
          locale: Locale(language),
          brightness: brightness,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 780),
              textScaler: TextScaler.linear(1.6),
              padding: EdgeInsets.only(bottom: 24),
            ),
            child: StatefulBuilder(builder: (context, setState) {
              return Scaffold(
                body: ListView.builder(
                  itemCount: 30,
                  itemBuilder: (_, index) => SizedBox(
                    height: 56,
                    child: Text('Row $index'),
                  ),
                ),
                bottomNavigationBar: PatientBottomNavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (value) =>
                      setState(() => selected = value),
                ),
              );
            }),
          ),
        ));
        await tester.pumpAndSettle();
        final bar = find.byType(PatientBottomNavigationBar);
        final labels = find.descendant(of: bar, matching: find.byType(Text));
        expect(labels, findsNWidgets(4));
        for (final label in labels.evaluate()) {
          final paragraph = label.renderObject! as RenderParagraph;
          expect(paragraph.didExceedMaxLines, isFalse);
          final bounds = tester.getRect(find.byWidget(label.widget));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(bounds.bottom,
              lessThanOrEqualTo(tester.getRect(bar).bottom - 24));
        }
        final list = find.byType(ListView);
        expect(tester.getRect(list).bottom,
            lessThanOrEqualTo(tester.getRect(bar).top));
        await tester.drag(list, const Offset(0, -2400));
        await tester.pumpAndSettle();
        expect(find.text('Row 29').hitTestable(), findsOneWidget);
        expect(tester.getRect(find.text('Row 29')).bottom,
            lessThanOrEqualTo(tester.getRect(bar).top));
        await tester.tap(find.byIcon(Icons.calendar_today_outlined));
        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('language rows keep selection during pending and failed saves',
      (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    final locale = LocaleProvider();
    final auth = _DelayedLanguageAuth();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: Consumer<LocaleProvider>(
        builder: (_, value, __) => _app(
          locale: value.locale,
          child: const LanguageScreen(),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    final english = find.widgetWithText(ListTile, 'English').first;
    final arabic =
        find.widgetWithText(ListTile, AppLocale.languageNames['ar']!);
    final kurdish =
        find.widgetWithText(ListTile, AppLocale.languageNames['ku']!);
    expect(tester.widget<ListTile>(english).selected, isTrue);
    await tester.tap(english);
    expect(auth.calls, 0);
    await tester.tap(arabic);
    await tester.tap(arabic);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.widget<ListTile>(english).selected, isTrue);
    expect(tester.widget<ListTile>(kurdish).enabled, isFalse);
    await tester.tap(kurdish);
    expect(auth.calls, 1);
    auth.result.complete(false);
    await tester.pumpAndSettle();
    expect(locale.locale.languageCode, 'en');
    expect(
        (await SharedPreferences.getInstance()).getString('app_locale'), 'en');
    expect(tester.widget<ListTile>(english).selected, isTrue);
    expect(tester.widget<ListTile>(arabic).enabled, isTrue);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    auth.result = Completer<bool>();
    await tester.tap(kurdish);
    await tester.pump();
    expect(auth.calls, 2);
    auth.result.complete(true);
    await tester.pumpAndSettle();
    expect(locale.locale.languageCode, 'ku');
    expect(tester.widget<ListTile>(kurdish).selected, isTrue);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(Directionality.of(tester.element(kurdish)), TextDirection.rtl);
    expect(
        (await SharedPreferences.getInstance()).getString('app_locale'), 'ku');
    await tester.tap(kurdish);
    expect(auth.calls, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    locale.dispose();
  });
}

Widget _app({
  required Locale locale,
  required Widget child,
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      locale: locale,
      theme: ThemeData(brightness: brightness),
      localizationsDelegates: [
        ...AppLocalizations.localizationsDelegates,
        const FallbackLocalizationsDelegate(),
        const FallbackCupertinoLocalizationsDelegate(),
        const FallbackWidgetsLocalizationsDelegate(),
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

class _DelayedLanguageAuth extends AuthProvider {
  var result = Completer<bool>();
  int calls = 0;
  @override
  bool get isAuthenticated => true;
  @override
  Future<bool> updateLanguage(String languageCode) {
    calls++;
    return result.future;
  }
}

class _FirebaseCoreWithStorage extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}
