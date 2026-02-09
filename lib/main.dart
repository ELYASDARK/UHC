import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'providers/doctor_provider.dart';
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

  // Set preferred orientation (fast operation)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style (fast operation)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize only Firebase core before app starts - it's required for auth
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Failed to initialize Firebase: $e');
  }

  // Start app immediately - show UI first
  runApp(const UHCApp());

  // Defer non-critical initialization after first frame is rendered
  // This prevents blocking the main thread during startup
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _initializeServicesAsync();
  });
}

/// Initialize non-critical services asynchronously after app starts
Future<void> _initializeServicesAsync() async {
  // Small delay to allow UI to stabilize first
  await Future.delayed(const Duration(milliseconds: 500));

  // Initialize local notification service
  try {
    await LocalNotificationService().initialize();
  } catch (e) {
    debugPrint('Failed to initialize local notifications: $e');
  }

  // Initialize FCM service
  try {
    await FCMService().initialize();
  } catch (e) {
    debugPrint('Failed to initialize FCM: $e');
  }
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
        ChangeNotifierProvider(create: (_) => DoctorProvider()),
      ],
      child: Consumer2<ThemeProvider, LocaleProvider>(
        builder: (context, themeProvider, localeProvider, _) {
          return MaterialApp(
            title: 'UHC - University Health Center',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,

            // Custom Scroll Behavior for Web/Desktop
            scrollBehavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.mouse,
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.unknown,
              },
            ),

            // Theme
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,

            // Localization
            locale: localeProvider.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
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

  // Auth flow: 0 = login, 1 = register, 2 = forgot password
  int _authScreen = 0;

  /// Called when splash screen animation/delay completes
  /// This ensures onboarding is checked BEFORE we leave the splash
  Future<void> _onSplashComplete() async {
    // Check onboarding status before leaving splash
    final prefs = await SharedPreferences.getInstance();
    final complete = prefs.getBool(_onboardingKey) ?? false;

    if (!mounted) return;

    setState(() {
      _onboardingComplete = complete;
      _showSplash = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // Show splash screen first (onboarding check happens when splash completes)
    if (_showSplash) {
      return SplashScreen(onComplete: _onSplashComplete);
    }

    // Show onboarding if not complete (checked during splash completion)
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
