import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/widgets/custom_text_field.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';

class InitialPasswordChangeScreen extends StatefulWidget {
  const InitialPasswordChangeScreen({super.key});

  @override
  State<InitialPasswordChangeScreen> createState() =>
      _InitialPasswordChangeScreenState();
}

class _InitialPasswordChangeScreenState
    extends State<InitialPasswordChangeScreen> {
  static const int _minimumPasswordLength = 8;

  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.completeInitialPasswordChange(
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.errorMessage ?? 'Failed to update password.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text(
          'You need to choose a new password before using the app. Do you want to sign out instead?',
        ),
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

    if (shouldSignOut != true || !mounted) return;

    try {
      final notificationProvider = context.read<NotificationProvider>();
      await context.read<AuthProvider>().signOut(
            beforeSignOut: notificationProvider.onLogout,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logout failed. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmSignOut();
      },
      child: Scaffold(
        body: ResponsivePage(
          safeArea: true,
          maxWidth: 520,
          alignment: Alignment.center,
          bottomPadding: 32,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: AppColors.primary,
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Choose a New Password',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This one-time step replaces the temporary password from your administrator.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    height: 1.45,
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 28),
                CustomTextField(
                  controller: _passwordController,
                  label: 'New Password',
                  hintText: 'Enter new password',
                  obscureText: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a new password';
                    }
                    if (value.length < _minimumPasswordLength) {
                      return 'Password must be at least $_minimumPasswordLength characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _confirmController,
                  label: 'Confirm Password',
                  hintText: 'Re-enter new password',
                  obscureText: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_isLoading) {
                      _submit();
                    }
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm the new password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Update Password',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isLoading ? null : _confirmSignOut,
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
