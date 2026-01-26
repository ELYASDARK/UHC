import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../providers/auth_provider.dart';

/// Register screen
class RegisterScreen extends StatefulWidget {
  final VoidCallback onLoginTap;
  final VoidCallback onRegisterSuccess;

  const RegisterScreen({
    super.key,
    required this.onLoginTap,
    required this.onRegisterSuccess,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.registerWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
      );

      if (success && mounted) {
        widget.onRegisterSuccess();
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
    setState(() {
      _isGoogleLoading = true;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signInWithGoogle();

    setState(() {
      _isGoogleLoading = false;
    });

    if (success && mounted) {
      widget.onRegisterSuccess();
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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Back button
              IconButton(
                onPressed: widget.onLoginTap,
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                ),
              ).animate().fadeIn(duration: 300.ms),

              const SizedBox(height: 24),

              // Header
              Text(
                'Create Account ✨',
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
                    'Join ${AppStrings.appName} to book appointments easily',
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

              const SizedBox(height: 40),

              // Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Full name field
                    CustomTextField(
                          label: AppStrings.fullName,
                          hintText: 'Enter your full name',
                          controller: _nameController,
                          keyboardType: TextInputType.name,
                          prefixIcon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppStrings.fieldRequired;
                            }
                            if (value.length < 2) {
                              return 'Name is too short';
                            }
                            return null;
                          },
                        )
                        .animate(delay: 200.ms)
                        .fadeIn(duration: 400.ms)
                        .slideX(begin: 0.1),

                    const SizedBox(height: 20),

                    // Email field
                    CustomTextField(
                          label: AppStrings.email,
                          hintText: 'Enter your email',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icons.email_outlined,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppStrings.fieldRequired;
                            }
                            if (!value.contains('@')) {
                              return AppStrings.invalidEmail;
                            }
                            return null;
                          },
                        )
                        .animate(delay: 300.ms)
                        .fadeIn(duration: 400.ms)
                        .slideX(begin: 0.1),

                    const SizedBox(height: 20),

                    // Password field
                    CustomTextField(
                          label: AppStrings.password,
                          hintText: 'Create a password',
                          controller: _passwordController,
                          obscureText: true,
                          prefixIcon: Icons.lock_outline,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppStrings.fieldRequired;
                            }
                            if (value.length < 6) {
                              return AppStrings.weakPassword;
                            }
                            return null;
                          },
                        )
                        .animate(delay: 400.ms)
                        .fadeIn(duration: 400.ms)
                        .slideX(begin: 0.1),

                    const SizedBox(height: 20),

                    // Confirm password field
                    CustomTextField(
                          label: AppStrings.confirmPassword,
                          hintText: 'Confirm your password',
                          controller: _confirmPasswordController,
                          obscureText: true,
                          prefixIcon: Icons.lock_outline,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _handleRegister(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return AppStrings.fieldRequired;
                            }
                            if (value != _passwordController.text) {
                              return AppStrings.passwordMismatch;
                            }
                            return null;
                          },
                        )
                        .animate(delay: 500.ms)
                        .fadeIn(duration: 400.ms)
                        .slideX(begin: 0.1),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Register button
              PrimaryButton(
                    text: AppStrings.register,
                    onPressed: _handleRegister,
                    isLoading: authProvider.isLoading && !_isGoogleLoading,
                  )
                  .animate(delay: 600.ms)
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
                      'OR',
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[400])),
                ],
              ).animate(delay: 700.ms).fadeIn(duration: 400.ms),

              const SizedBox(height: 24),

              // Google sign in
              SocialButton(
                    text: 'Sign up with Google',
                    iconPath: '',
                    onPressed: _handleGoogleSignIn,
                    isLoading: _isGoogleLoading,
                  )
                  .animate(delay: 800.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.2),

              const SizedBox(height: 32),

              // Login link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.alreadyHaveAccount,
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onLoginTap,
                    child: Text(
                      AppStrings.signIn,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ).animate(delay: 900.ms).fadeIn(duration: 400.ms),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
