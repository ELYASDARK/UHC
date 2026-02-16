import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';

/// One-time screen shown after login to link a Google account.
/// Users must link their account before they can proceed to the app.
class LinkGoogleScreen extends StatefulWidget {
  final VoidCallback onLinked;

  const LinkGoogleScreen({super.key, required this.onLinked});

  @override
  State<LinkGoogleScreen> createState() => _LinkGoogleScreenState();
}

class _LinkGoogleScreenState extends State<LinkGoogleScreen> {
  bool _isLoading = false;

  Future<void> _linkGoogle() async {
    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.linkWithGoogle();

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      widget.onLinked();
    } else {
      final errorMsg = authProvider.errorMessage ?? 'Failed to link account';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleBack() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text(
            'You must link your Google account to proceed. Do you want to sign out instead?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      context.read<AuthProvider>().signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    size: 56,
                    color: AppColors.primary,
                  ),
                ).animate().fadeIn(duration: 500.ms).scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1.0, 1.0),
                      duration: 500.ms,
                    ),

                const SizedBox(height: 32),

                // Title
                Text(
                  'Link Your Google Account',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimaryLight,
                  ),
                )
                    .animate(delay: 200.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1),

                const SizedBox(height: 16),

                // Subtitle
                Text(
                  'For security and easy access, please link your account with Google. This is a one-time setup.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    height: 1.5,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                )
                    .animate(delay: 350.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1),

                const SizedBox(height: 16),

                // Benefits list
                _BenefitItem(
                  icon: Icons.security_rounded,
                  text: 'Enhanced account security',
                  delay: 500.ms,
                ),
                _BenefitItem(
                  icon: Icons.speed_rounded,
                  text: 'Faster login with Google',
                  delay: 600.ms,
                ),
                _BenefitItem(
                  icon: Icons.sync_rounded,
                  text: 'Keep your data synced',
                  delay: 700.ms,
                ),

                const Spacer(flex: 2),

                // Link button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _linkGoogle,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Image.asset(
                            'assets/icons/google.svg',
                            width: 24,
                            height: 24,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.g_mobiledata_rounded,
                              size: 28,
                            ),
                          ),
                    label: Text(
                      _isLoading ? 'Linking...' : 'Link with Google',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                    ),
                  ),
                )
                    .animate(delay: 800.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2),

                // Sign Out Option
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton(
                    onPressed: _handleBack,
                    child: Text(
                      'Sign Out',
                      style: GoogleFonts.roboto(
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ).animate(delay: 1000.ms).fadeIn(duration: 400.ms),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final Duration delay;

  const _BenefitItem({
    required this.icon,
    required this.text,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.success),
          ),
          const SizedBox(width: 14),
          Text(
            text,
            style: GoogleFonts.roboto(
              fontSize: 15,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
        ],
      ),
    ).animate(delay: delay).fadeIn(duration: 400.ms).slideX(begin: 0.1);
  }
}
