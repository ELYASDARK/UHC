import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'l10n/kurdish_material_localizations.dart';
import 'firebase_options.dart';
import 'core/constants/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/appointment_provider.dart';
import 'providers/doctor_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/doctor_appointment_provider.dart';
import 'providers/document_provider.dart';
import 'services/local_notification_service.dart';
import 'services/fcm_service.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/link_google_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/patient/main_shell.dart';
import 'screens/doctor/doctor_shell.dart';
import 'screens/super_admin/super_admin_shell.dart';
import 'data/repositories/doctor_repository.dart';
import 'data/models/doctor_model.dart';
import 'data/models/user_model.dart';

/// Global navigator key for navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _crashlyticsEnabled = false;

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
    await _configureFirestoreDefaults();
    // Crashlytics is not supported on web in this app setup.
    // Guard all Crashlytics hooks to avoid web assertion failures.
    if (!kIsWeb) {
      _crashlyticsEnabled = true;

      // Pass all uncaught "fatal" errors from the framework to Crashlytics
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };

      // Pass all uncaught async errors to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
  } catch (e) {
    debugPrint('Failed to initialize Firebase: $e');
    // If Firebase fails, we can't use Crashlytics to report it, but we should clear the error logic
    // or maybe show a fallback UI (though runAPP hasn't happened yet).
    // Printing to console is the best fallback here.
  }

  // Load theme before running app so correct theme is applied on first frame
  final themeProvider = await ThemeProvider.create();

  // Start app immediately - show UI first
  runApp(UHCApp(themeProvider: themeProvider));

  // Defer non-critical initialization after first frame is rendered
  // This prevents blocking the main thread during startup
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _initializeServicesAsync();
  });
}

Future<void> _configureFirestoreDefaults() async {
  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('Failed to configure Firestore defaults: $e');
  }
}

/// Initialize non-critical services asynchronously after app starts
Future<void> _initializeServicesAsync() async {
  // Small delay to allow UI to stabilize first
  await Future.delayed(const Duration(milliseconds: 500));

  // Initialize local notification service
  try {
    await LocalNotificationService().initialize();
  } catch (e, stack) {
    debugPrint('Failed to initialize local notifications: $e');
    await _recordNonFatalError(
      e,
      stack,
      reason: 'LocalNotificationService Initialization',
    );
  }

  // Initialize FCM service
  try {
    await FCMService().initialize();
  } catch (e, stack) {
    debugPrint('Failed to initialize FCM: $e');
    await _recordNonFatalError(
      e,
      stack,
      reason: 'FCMService Initialization',
    );
  }
}

Future<void> _recordNonFatalError(
  Object error,
  StackTrace stack, {
  String? reason,
}) async {
  if (!_crashlyticsEnabled || kIsWeb) return;
  try {
    await FirebaseCrashlytics.instance
        .recordError(error, stack, reason: reason);
  } catch (_) {
    // Ignore secondary reporting errors.
  }
}

class UHCApp extends StatelessWidget {
  final ThemeProvider themeProvider;

  const UHCApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AppointmentProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => DoctorProvider()),
        ChangeNotifierProvider(create: (_) => DoctorAppointmentProvider()),
        ChangeNotifierProvider(create: (_) => DocumentProvider()),
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

  bool _bootReady = false;
  bool _onboardingComplete = false;

  // Auth flow: 0 = login, 1 = forgot password
  int _authScreen = 0;

  // Doctor role state
  final DoctorRepository _doctorRepository = DoctorRepository();
  DoctorModel? _doctorModel;
  bool _doctorLoading = false;
  bool _doctorFetchFailed = false;
  String? _lastDoctorUserId;

  @override
  void initState() {
    super.initState();
    _initializeBootState();
  }

  Future<void> _warmupBootAssets() async {
    const bootAssets = <String>[
      'assets/icons/icon_splash_new.png',
    ];

    for (final assetPath in bootAssets) {
      try {
        await rootBundle.load(assetPath);
      } catch (e) {
        debugPrint('Boot asset warmup failed for $assetPath: $e');
      }
    }
  }

  Future<void> _initializeBootState() async {
    final prefsFuture = SharedPreferences.getInstance();

    // Keep a short minimum visual startup duration for smoothness.
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 900)),
      _warmupBootAssets(),
      prefsFuture,
    ]);
    final prefs = await prefsFuture;
    final complete = prefs.getBool(_onboardingKey) ?? false;

    if (!mounted) return;
    setState(() {
      _onboardingComplete = complete;
      _bootReady = true;
    });
  }

  /// Fetch the DoctorModel for a doctor-role user.
  /// Called once per userId; results cached until user changes or retry.
  Future<void> _fetchDoctorModel(String userId) async {
    if (_doctorLoading) return;
    _doctorLoading = true;
    _doctorFetchFailed = false;
    _lastDoctorUserId = userId;
    setState(() {});

    try {
      final doc = await _doctorRepository.getDoctorByUserId(userId);
      if (!mounted) return;
      setState(() {
        _doctorModel = doc;
        _doctorLoading = false;
        _doctorFetchFailed = doc == null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _doctorLoading = false;
        _doctorFetchFailed = true;
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

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    final isRestoringAuthenticatedSession =
        authProvider.state == AuthState.initial ||
            (authProvider.state == AuthState.loading &&
                authProvider.firebaseUser != null &&
                !authProvider.isAuthenticated);

    Widget screen;

    // Show one unified boot screen during startup or auth restore.
    if (!_bootReady || isRestoringAuthenticatedSession) {
      screen = const SplashScreen();
    } else if (!_onboardingComplete) {
      // Show onboarding if not complete.
      screen = OnboardingScreen(onComplete: _completeOnboarding);
    } else if (authProvider.isAuthenticated) {
      // Check auth state
      if (!authProvider.isGoogleLinked) {
        // Check if Google is linked — show link screen if not
        screen = LinkGoogleScreen(
          onLinked: () {
            if (mounted) setState(() {});
          },
        );
      } else {
        final currentUser = authProvider.currentUser;
        if (currentUser?.role == UserRole.superAdmin) {
          // Route superAdmin to dedicated governance shell
          screen = const SuperAdminShell();
        } else if (currentUser?.role == UserRole.doctor) {
          // Route doctor role to DoctorShell
          if (!_doctorLoading &&
              _doctorModel == null &&
              !_doctorFetchFailed &&
              _lastDoctorUserId != currentUser!.id) {
            // Schedule fetch after this build frame
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fetchDoctorModel(currentUser.id);
            });
            screen = const SplashScreen();
          } else if (_doctorLoading) {
            // Loading state
            screen = const SplashScreen();
          } else if (_doctorFetchFailed || _doctorModel == null) {
            // Error state: doctor profile not found or fetch failed
            screen = Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text(
                        'Doctor profile not found',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your account has the doctor role but no linked doctor profile was found. Contact an administrator.',
                        style: TextStyle(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          _doctorFetchFailed = false;
                          _lastDoctorUserId = null;
                          setState(() {});
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          try {
                            await authProvider.signOut();
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Logout failed. Please try again.'),
                              ),
                            );
                          }
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            screen = DoctorShell(doctor: _doctorModel!);
          }
        } else {
          screen = const MainShell();
        }
      }
    } else {
      // User signed out — clear cached doctor state for fresh fetch on re-login
      _doctorModel = null;
      _lastDoctorUserId = null;
      _doctorFetchFailed = false;

      // Auth screens
      switch (_authScreen) {
        case 1:
          screen = ForgotPasswordScreen(
            onBackTap: () => setState(() => _authScreen = 0),
          );
          break;
        default:
          screen = LoginScreen(
            onForgotPasswordTap: () => setState(() => _authScreen = 1),
            onLoginSuccess: () {},
          );
          break;
      }
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: defaultOverlayStyle,
      child: screen,
    );
  }
}
