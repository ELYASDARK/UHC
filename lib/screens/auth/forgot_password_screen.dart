import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../providers/auth_provider.dart';
import 'package:uhc/l10n/app_localizations.dart';

/// Forgot password screen
class ForgotPasswordScreen extends StatefulWidget {
  final VoidCallback onBackTap;

  const ForgotPasswordScreen({super.key, required this.onBackTap});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.sendPasswordResetEmail(
        _emailController.text.trim(),
      );

      if (success && mounted) {
        setState(() {
          _emailSent = true;
        });
      } else if (mounted && authProvider.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage!),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context);

    // If l10n is null (shouldn't happen in valid context), we can fallback or let it throw.
    // Assuming context is valid.

    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Back button
                IconButton(
                  onPressed: widget.onBackTap,
                  icon: const Icon(Icons.arrow_back_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.grey[100],
                  ),
                ).animate().fadeIn(duration: 300.ms),

                const SizedBox(height: 40),

                if (_emailSent) ...[
                  // Success state
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.mark_email_read_rounded,
                            size: 60,
                            color: AppColors.success,
                          ),
                        ).animate().scale(
                          begin: const Offset(0.5, 0.5),
                          duration: 500.ms,
                          curve: Curves.elasticOut,
                        ),

                        const SizedBox(height: 32),

                        Text(
                          l10n.checkEmail,
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight,
                          ),
                          textAlign: TextAlign.center,
                        ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

                        const SizedBox(height: 16),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            l10n.resetEmailSentMessage(_emailController.text),
                            style: GoogleFonts.roboto(
                              fontSize: 16,
                              height: 1.6,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ).animate(delay: 300.ms).fadeIn(duration: 400.ms),

                        const SizedBox(height: 48),

                        PrimaryButton(
                          text: l10n.backToLogin,
                          onPressed: widget.onBackTap,
                        ).animate(delay: 400.ms).fadeIn(duration: 400.ms),
                      ],
                    ),
                  ),
                ] else ...[
                  // Reset password form
                  Text(
                    l10n.resetPassword,
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),

                  const SizedBox(height: 8),

                  Text(
                        l10n.resetPasswordSubtitle,
                        style: GoogleFonts.roboto(
                          fontSize: 16,
                          height: 1.5,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      )
                      .animate(delay: 100.ms)
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: -0.1),

                  const SizedBox(height: 48),

                  Form(
                        key: _formKey,
                        child: CustomTextField(
                          label: l10n.email,
                          hintText: l10n.enterEmailHint,
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icons.email_outlined,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _handleResetPassword(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.fieldRequired;
                            }
                            if (!value.contains('@')) {
                              return l10n.invalidEmail;
                            }
                            return null;
                          },
                        ),
                      )
                      .animate(delay: 200.ms)
                      .fadeIn(duration: 400.ms)
                      .slideX(begin: 0.1),

                  const SizedBox(height: 32),

                  PrimaryButton(
                        text: l10n.sendResetLink,
                        onPressed: _handleResetPassword,
                        isLoading: authProvider.isLoading,
                        icon: Icons.send_rounded,
                      )
                      .animate(delay: 300.ms)
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
