import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../data/models/doctor_model.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../shared/change_password_screen.dart';
import '../../shared/notification_settings_screen.dart';
import 'edit_doctor_profile_screen.dart';

/// Doctor profile & settings screen
///
/// Mirrors the patient [ProfileScreen] layout with doctor-specific additions:
///  - Department + specialization in the header
///  - Schedule availability info
class DoctorProfileScreen extends StatefulWidget {
  final DoctorModel doctor;
  final VoidCallback? onDoctorUpdated;

  const DoctorProfileScreen({
    super.key,
    required this.doctor,
    this.onDoctorUpdated,
  });

  @override
  State<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends State<DoctorProfileScreen> {
  // ───────────────────────── BUILD ─────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final locale = context.watch<LocaleProvider>();
    final user = auth.currentUser;
    final doctor = widget.doctor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            children: [
              // ── profile header ──
              _buildProfileHeader(
                name: doctor.name.isNotEmpty
                    ? doctor.name
                    : (user?.fullName ?? 'Doctor'),
                email: doctor.email.isNotEmpty
                    ? doctor.email
                    : (user?.email ?? ''),
                photoUrl: doctor.photoUrl ?? user?.photoUrl,
                specialization: doctor.specialization,
                departmentName: doctor.departmentName,
                isDark: isDark,
              ),

              const SizedBox(height: 32),

              // ── Appearance ──
              _buildSection(
                l10n.appearance,
                [
                  _settingTile(
                    icon: Icons.dark_mode_rounded,
                    title: l10n.darkMode,
                    trailing: Switch(
                      value: theme.isDarkMode,
                      onChanged: (_) => theme.toggleTheme(),
                    ),
                    isDark: isDark,
                  ),
                  _settingTile(
                    icon: Icons.language_rounded,
                    title: l10n.language,
                    subtitle: locale.languageName,
                    onTap: () => _showLanguageDialog(context, l10n),
                    isDark: isDark,
                  ),
                ],
                isDark,
              ),

              const SizedBox(height: 20),

              // ── Notifications ──
              _buildSection(
                l10n.notificationSettings,
                [
                  _settingTile(
                    icon: Icons.notifications_active_rounded,
                    title: l10n.notifications,
                    subtitle: l10n.notificationSettings,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    ),
                    isDark: isDark,
                  ),
                ],
                isDark,
              ),

              const SizedBox(height: 20),

              // ── Account ──
              _buildSection(
                l10n.account,
                [
                  _settingTile(
                    icon: Icons.edit_rounded,
                    title: l10n.editProfile,
                    onTap: () async {
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditDoctorProfileScreen(
                            doctor: widget.doctor,
                          ),
                        ),
                      );
                      if (result == true) {
                        widget.onDoctorUpdated?.call();
                      }
                    },
                    isDark: isDark,
                  ),
                  _settingTile(
                    icon: Icons.lock_rounded,
                    title: l10n.changePassword,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
                    isDark: isDark,
                  ),
                ],
                isDark,
              ),

              const SizedBox(height: 20),

              // ── About ──
              _buildSection(
                l10n.about,
                [
                  _settingTile(
                    icon: Icons.privacy_tip_rounded,
                    title: l10n.privacyPolicy,
                    onTap: () => _showLegalSheet(
                      context,
                      l10n.privacyPolicy,
                      _privacyPolicyText,
                    ),
                    isDark: isDark,
                  ),
                  _settingTile(
                    icon: Icons.description_rounded,
                    title: l10n.termsOfService,
                    onTap: () => _showLegalSheet(
                      context,
                      l10n.termsOfService,
                      _termsOfServiceText,
                    ),
                    isDark: isDark,
                  ),
                  _settingTile(
                    icon: Icons.help_rounded,
                    title: l10n.helpAndSupport,
                    onTap: () => _showLegalSheet(
                      context,
                      l10n.helpAndSupport,
                      _helpSupportText,
                    ),
                    isDark: isDark,
                  ),
                  _settingTile(
                    icon: Icons.info_rounded,
                    title: l10n.version,
                    trailing: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (_, snap) {
                        if (snap.hasData) {
                          return Text(
                            snap.data!.version,
                            style: GoogleFonts.roboto(color: Colors.grey),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    isDark: isDark,
                  ),
                ],
                isDark,
              ),

              const SizedBox(height: 32),

              // ── Logout ──
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showLogoutDialog(context, auth, l10n),
                  icon:
                      const Icon(Icons.logout_rounded, color: AppColors.error),
                  label: Text(
                    l10n.logout,
                    style: GoogleFonts.poppins(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────── PROFILE HEADER ─────────────────────
  Widget _buildProfileHeader({
    required String name,
    required String email,
    String? photoUrl,
    String? specialization,
    String? departmentName,
    required bool isDark,
  }) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';
    return Column(
      children: [
        // Avatar with edit overlay
        GestureDetector(
          onTap: () {
            // Navigate to edit profile
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditDoctorProfileScreen(doctor: widget.doctor),
              ),
            ).then((changed) {
              if (changed == true) widget.onDoctorUpdated?.call();
            });
          },
          child: Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.grey.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? Image.network(
                          photoUrl,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _defaultAvatar(initial, isDark),
                        )
                      : _defaultAvatar(initial, isDark),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.edit, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        if (specialization != null && specialization.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            specialization,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (departmentName != null && departmentName.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            departmentName,
            style: GoogleFonts.roboto(fontSize: 13, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          email,
          style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _defaultAvatar(String initial, bool isDark) {
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.outfit(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : AppColors.primary,
        ),
      ),
    );
  }

  // ───────────────────── REUSABLE BUILDERS ─────────────────────
  Widget _buildSection(String title, List<Widget> children, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    required bool isDark,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: GoogleFonts.roboto(fontSize: 12, color: Colors.grey),
            )
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  // ───────────────────── DIALOGS / SHEETS ─────────────────────
  void _showLanguageDialog(BuildContext context, AppLocalizations l10n) {
    final locale = context.read<LocaleProvider>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.language,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _langTile('English', 'en', locale),
            _langTile('کوردی', 'ku', locale),
            _langTile('العربية', 'ar', locale),
          ],
        ),
      ),
    );
  }

  Widget _langTile(String label, String code, LocaleProvider lp) {
    final selected = lp.locale.languageCode == code;
    return ListTile(
      title: Text(label),
      trailing:
          selected ? const Icon(Icons.check, color: AppColors.primary) : null,
      onTap: () {
        lp.setLocale(Locale(code));
        Navigator.pop(context);
      },
    );
  }

  void _showLogoutDialog(
    BuildContext ctx,
    AuthProvider auth,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logout,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              final userId = auth.currentUser?.id;
              final notificationProvider = ctx.read<NotificationProvider>();

              // Run cleanup in background so web logout is never blocked.
              if (userId != null) {
                unawaited(
                  notificationProvider.onLogout(userId).catchError((e) {
                    debugPrint('Notification cleanup on logout failed: $e');
                  }),
                );
              }

              await auth.signOut();
            },
            child: Text(l10n.logout,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showLegalSheet(BuildContext ctx, String title, String body) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, sc) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  child: Text(body,
                      style: GoogleFonts.roboto(fontSize: 14, height: 1.8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────── LEGAL PLACEHOLDER TEXT ─────────────────
  static const _privacyPolicyText = '''
University Health Center respects your privacy. Personal information collected 
through this application is used solely for healthcare service delivery.

We do not share your medical records with third parties without your consent, 
except as required by law. Data is stored securely using industry-standard 
encryption protocols.

For questions, contact: privacy@uhc.university.edu
''';

  static const _termsOfServiceText = '''
By using the UHC application, you agree to these terms of service.

This application is intended for use by registered students, staff, and 
healthcare providers of the university. Appointments booked through this 
app are subject to the health center's scheduling policies.

The health center reserves the right to cancel or reschedule appointments 
when necessary for operational reasons.
''';

  static const _helpSupportText = '''
Need help? Here's how to reach us:

• Email: support@uhc.university.edu
• Phone: +964 (0) 750 000 0000
• Visit: University Health Center, Main Campus

Office Hours: Sunday – Thursday, 8:00 AM – 4:00 PM

For medical emergencies, please call emergency services immediately.
''';
}
