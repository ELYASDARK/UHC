// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/main.dart';
import 'package:uhc/providers/auth_provider.dart';
import 'package:uhc/providers/locale_provider.dart';
import 'package:uhc/providers/theme_provider.dart';
import 'package:uhc/screens/auth/login_screen.dart';
import 'package:uhc/screens/splash/splash_screen.dart';
import 'package:uhc/screens/patient/assistant/assistant_chat_screen.dart';
import 'package:uhc/screens/patient/booking/booking_success_screen.dart';
import 'package:uhc/screens/patient/main_shell.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_FirebaseCoreWithStorage());
    await Firebase.initializeApp();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  for (final action in [
    (label: 'Back to Home', tab: 0, page: _receipt()),
    (label: 'View My Appointments', tab: 2, page: _receipt()),
    (label: 'Book an Appointment', tab: 1, page: const AssistantChatScreen()),
  ]) {
    testWidgets('${action.label} honors a session that signed out',
        (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      final auth = AuthProvider();
      final locale = LocaleProvider();
      final theme = await ThemeProvider.create();
      addTearDown(auth.dispose);
      addTearDown(locale.dispose);
      addTearDown(theme.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppNavigator(key: AppNavigator.rootKey),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      expect(auth.isAuthenticated, isFalse);

      await tester.pumpAndSettle();
      final rootState = tester.state(find.byType(AppNavigator));
      Navigator.of(tester.element(find.byType(LoginScreen))).push(
        MaterialPageRoute(builder: (_) => action.page),
      );
      await tester.pumpAndSettle();
      final button = find.text(action.label).last;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(SplashScreen), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
      expect(tester.state(find.byType(AppNavigator)), same(rootState));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Widget _receipt() => BookingSuccessScreen(
      appointmentId: 'appointment-local-123',
      doctorName: 'Local Doctor',
      bookingReference: 'UHC-LOCAL-123',
      date: DateTime(2026, 10, 21),
      timeSlot: '09:00 - 09:30',
    );

class _FirebaseCoreWithStorage extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    final apps = await super.initializeCore();
    apps.single.options.storageBucket = 'demo-uhc-test.appspot.com';
    return apps;
  }
}
