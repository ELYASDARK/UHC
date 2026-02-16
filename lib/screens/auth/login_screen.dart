import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uhc/l10n/app_localizations.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../providers/auth_provider.dart';

/// Login screen
class LoginScreen extends StatefulWidget {
  final VoidCallback onForgotPasswordTap;
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.onForgotPasswordTap,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      // Dismiss keyboard
      FocusScope.of(context).unfocus();

      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (success && mounted) {
        widget.onLoginSuccess();
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

  Future<void> _handleGoogleSignIn() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isGoogleLoading = true;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signInWithGoogle();

    if (mounted) {
      setState(() {
        _isGoogleLoading = false;
      });
    }

    if (success && mounted) {
      widget.onLoginSuccess();
    } else if (mounted && authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = context.watch<AuthProvider>();
    final l10n = AppLocalizations.of(context);

    // Use a GestureDetector to dismiss keyboard on tap outside
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                // Header
                Text(
                  l10n.welcomeBack,
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
                  l10n.loginSubtitle(l10n.appName),
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                )
                    .animate(delay: 100.ms)
                    .fadeIn(duration: 400.ms)
                    .slideX(begin: -0.1),

                const SizedBox(height: 48),

                // Form
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Email field
                      CustomTextField(
                        label: l10n.email,
                        hintText: l10n.enterEmailHint,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: Icons.email_outlined,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.fieldRequired;
                          }
                          if (!value.contains('@')) {
                            return l10n.invalidEmail;
                          }
                          return null;
                        },
                      )
                          .animate(delay: 200.ms)
                          .fadeIn(duration: 400.ms)
                          .slideX(begin: 0.1),

                      const SizedBox(height: 20),

                      // Password field
                      CustomTextField(
                        label: l10n.password,
                        hintText: l10n.enterPasswordHint,
                        controller: _passwordController,
                        obscureText: true,
                        prefixIcon: Icons.lock_outline,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleLogin(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.fieldRequired;
                          }
                          if (value.length < 6) {
                            return l10n.weakPassword;
                          }
                          return null;
                        },
                      )
                          .animate(delay: 300.ms)
                          .fadeIn(duration: 400.ms)
                          .slideX(begin: 0.1),
                    ],
                  ),
                ),

                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onForgotPasswordTap,
                    child: Text(
                      l10n.forgotPassword,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ).animate(delay: 400.ms).fadeIn(duration: 400.ms),

                const SizedBox(height: 24),

                // Login button
                PrimaryButton(
                  text: l10n.login,
                  onPressed: _handleLogin,
                  isLoading: authProvider.isLoading && !_isGoogleLoading,
                )
                    .animate(delay: 500.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2),

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey[400])),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l10n.or,
                        style: GoogleFonts.roboto(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey[400])),
                  ],
                ).animate(delay: 600.ms).fadeIn(duration: 400.ms),

                const SizedBox(height: 24),

                // Google sign in
                SocialButton(
                  text: l10n.signInWithGoogle,
                  // Use a placeholder or asset if we have it
                  iconPath: 'assets/icons/google.png',
                  onPressed: _handleGoogleSignIn,
                  isLoading: _isGoogleLoading,
                )
                    .animate(delay: 700.ms)
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.2),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
