import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uhc/core/theme/app_theme.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/l10n/kurdish_material_localizations.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/screens/shared/language_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_FirebaseCoreWithStorage());
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final language in ['en', 'ar', 'ku']) {
    for (final brightness in Brightness.values) {
      testWidgets(
          '$language $brightness language names fit and remain selectable at large text',
          (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'app_locale': language});
        final locale = LocaleProvider();
        final auth = AuthProvider();
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>.value(value: locale),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: Consumer<LocaleProvider>(
            builder: (_, currentLocale, __) => MaterialApp(
              locale: currentLocale.locale,
              theme: brightness == Brightness.light
                  ? AppTheme.lightTheme
                  : AppTheme.darkTheme,
              localizationsDelegates: const [
                ...AppLocalizations.localizationsDelegates,
                FallbackLocalizationsDelegate(),
                FallbackCupertinoLocalizationsDelegate(),
                FallbackWidgetsLocalizationsDelegate(),
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const LanguageScreen(),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(find.byType(ListTile), findsNWidgets(3));
        final heading = find.descendant(
            of: find.byType(AppBar), matching: find.byType(Text));
        expect(
            (tester.renderObject(heading) as RenderParagraph).didExceedMaxLines,
            isFalse);
        expect(find.text('English'), findsNWidgets(2));
        for (final name in ['العربية', 'Arabic', 'کوردی', 'Kurdish']) {
          expect(find.text(name).hitTestable(), findsOneWidget);
        }
        final rows = find.byType(ListTile).evaluate();
        expect(
            rows.where((row) => (row.widget as ListTile).selected).length, 1);
        final selectedNativeName = switch (language) {
          'ar' => 'العربية',
          'ku' => 'کوردی',
          _ => 'English',
        };
        expect(
            tester
                .widget<ListTile>(
                    find.widgetWithText(ListTile, selectedNativeName).first)
                .selected,
            isTrue);
        for (final row in rows) {
          final tile = row.widget as ListTile;
          expect(tile.enabled, isTrue);
          final rowFinder = find.byWidget(tile);
          final rowBounds = tester.getRect(rowFinder);
          final labels = find.descendant(
            of: rowFinder,
            matching: find.byType(Text),
          );
          expect(labels, findsNWidgets(2));
          for (final label in labels.evaluate()) {
            final paragraph = label.renderObject! as RenderParagraph;
            expect(paragraph.didExceedMaxLines, isFalse);
            final bounds = tester.getRect(find.byWidget(label.widget));
            expect(rowBounds.contains(bounds.topLeft), isTrue);
            expect(rowBounds.contains(bounds.bottomRight), isTrue);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(320));
            expect(bounds.bottom, lessThanOrEqualTo(780));
          }
          expect((tile.subtitle! as Text).textDirection, TextDirection.ltr);
          expect(
              (tile.title! as Text).textDirection,
              (tile.title! as Text).data == 'English'
                  ? TextDirection.ltr
                  : TextDirection.rtl);
        }

        final nextLanguage = switch (language) {
          'en' => ('ar', 'Arabic'),
          'ar' => ('ku', 'Kurdish'),
          _ => ('en', 'English'),
        };
        final nextRow = find.widgetWithText(ListTile, nextLanguage.$2).first;
        await tester.tap(nextRow);
        await tester.pumpAndSettle();
        expect(locale.locale.languageCode, nextLanguage.$1);
        expect(tester.widget<ListTile>(nextRow).selected, isTrue);
        expect(Directionality.of(tester.element(nextRow)),
            nextLanguage.$1 == 'en' ? TextDirection.ltr : TextDirection.rtl);
        expect((await SharedPreferences.getInstance()).getString('app_locale'),
            nextLanguage.$1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        locale.dispose();
      });
    }
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
