import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// flutter_localizations is used via app_localizations_ku.dart fallback delegates
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'l10n/kurdish_material_localizations.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/appointment_provider.dart';
import 'providers/notification_provider.dart';
import 'services/local_notification_service.dart';
import 'services/fcm_service.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/home/main_shell.dart';

/// Global navigator key for navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize local notification service
  await LocalNotificationService().initialize();

  // Initialize FCM service
  await FCMService().initialize();

  runApp(const UHCApp());
}

class UHCApp extends StatelessWidget {
  const UHCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return MaterialApp(
            title: 'UHC - University Health Center',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,

            // Theme
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,

            // Localization
            locale: localeProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              // Use fallback delegates that handle Kurdish RTL
              FallbackLocalizationsDelegate(),
              FallbackCupertinoLocalizationsDelegate(),
              FallbackWidgetsLocalizationsDelegate(),
            ],

            home: const AppNavigator(),
          );
        },
      ),
    );
  }
}

/// Main app navigator handling auth state and navigation flow
class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  static const String _onboardingKey = 'onboarding_complete';

  bool _showSplash = true;
  bool _onboardingComplete = false;
  bool _onboardingChecked = false;

  // Auth flow: 0 = login, 1 = register, 2 = forgot password
  int _authScreen = 0;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final complete = prefs.getBool(_onboardingKey) ?? false;
    if (mounted) {
      setState(() {
        _onboardingComplete = complete;
        _onboardingChecked = true;
      });
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    if (mounted) {
      setState(() {
        _onboardingComplete = true;
      });
    }
  }

  void _onSplashComplete() {
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // Show splash screen first
    if (_showSplash) {
      return SplashScreen(onComplete: _onSplashComplete);
    }

    // Wait for onboarding check
    if (!_onboardingChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show onboarding if not complete
    if (!_onboardingComplete) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }

    // Check auth state
    if (authProvider.isAuthenticated) {
      return const MainShell();
    }

    // Auth screens
    switch (_authScreen) {
      case 1:
        return RegisterScreen(
          onLoginTap: () => setState(() => _authScreen = 0),
          onRegisterSuccess: () {},
        );
      case 2:
        return ForgotPasswordScreen(
          onBackTap: () => setState(() => _authScreen = 0),
        );
      default:
        return LoginScreen(
          onRegisterTap: () => setState(() => _authScreen = 1),
          onForgotPasswordTap: () => setState(() => _authScreen = 2),
          onLoginSuccess: () {},
        );
    }
  }
}
