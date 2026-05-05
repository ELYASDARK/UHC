import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Unified boot/splash screen used during startup and auth restoration.
class SplashScreen extends StatelessWidget {
  static const double _logoSize = 170;
  static const String _primaryLogo = 'assets/icons/icon_splash_new.png';
  static const String _fallbackLogo = 'assets/icons/icon_splash.png';
  static const String _webLogoPath = 'icons/icon_splash_new.png';

  const SplashScreen({super.key});

  Widget _buildFallbackLogo() {
    return Image.asset(
      _fallbackLogo,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.local_hospital_rounded,
        size: 100,
        color: Colors.white,
      ),
    );
  }

  Widget _buildLogoImage() {
    if (kIsWeb) {
      return SizedBox(
        width: _logoSize,
        height: _logoSize,
        child: Image.network(
          _webLogoPath,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return _buildFallbackLogo();
          },
          errorBuilder: (_, __, ___) => _buildFallbackLogo(),
        ),
      );
    }

    return SizedBox(
      width: _logoSize,
      height: _logoSize,
      child: Image.asset(
        _primaryLogo,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return _buildFallbackLogo();
        },
        errorBuilder: (_, __, ___) => _buildFallbackLogo(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.primaryDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
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
                _buildLogoImage(),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context).appFullName,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).appTagline,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 56),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
