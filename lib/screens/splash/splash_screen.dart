import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Animated splash screen
class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Widget _buildLogoImage() {
    return SizedBox(
      width: 170,
      height: 170,
      child: Image.asset(
        'assets/icons/icon_splash.png',
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return const Center(
            child: Icon(
              Icons.local_hospital_rounded,
              size: 100,
              color: Colors.white,
            ),
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(
            Icons.local_hospital_rounded,
            size: 100,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Set system UI overlay style for immersive experience
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.primaryDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Keep a short minimum display time for visual continuity
    // but avoid blocking app navigation for multiple seconds.
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 900)),
      _performInitialization(),
    ]);

    if (!mounted) return;

    widget.onComplete();
  }

  Future<void> _performInitialization() async {
    // Intentionally no blocking work here.
    // Startup-critical initialization is handled elsewhere.
    return;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo with animation
              _buildLogoImage()
                  .animate()
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    duration: 600.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(duration: 400.ms),

              const SizedBox(height: 32),

              // App name
              Text(
                AppLocalizations.of(context).appFullName,
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
                textAlign: TextAlign.center,
              )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.3),

              const SizedBox(height: 8),

              // Tagline
              Text(
                AppLocalizations.of(context).appTagline,
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 0.5,
                ),
              )
                  .animate(delay: 500.ms)
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.3),

              const SizedBox(height: 80),

              // Loading indicator
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ).animate(delay: 800.ms).fadeIn(duration: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}
