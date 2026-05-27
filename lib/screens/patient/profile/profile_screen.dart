import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../admin/dashboard/admin_dashboard_screen.dart';
import '../../shared/notification_settings_screen.dart';
import 'edit_profile_screen.dart';
import '../documents/medical_documents_screen.dart';
import '../../shared/change_password_screen.dart';
import '../../auth/forgot_password_screen.dart';
import '../../../core/widgets/responsive_layout.dart';

/// Profile and settings screen
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                AppLocalizations.of(context).privacyPolicy,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Text(
                    LegalText.privacyPolicy,
                    style: GoogleFonts.roboto(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTermsOfService(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                AppLocalizations.of(context).termsOfService,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Text(
                    LegalText.termsOfService,
                    style: GoogleFonts.roboto(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpSupport(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Help & Support',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(
                Icons.email_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Email Support'),
              subtitle: const Text('support@uhc.edu'),
              contentPadding: EdgeInsets.zero,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opening email client...')),
                );
                // In real app: launchUrl(Uri.parse('mailto:support@uhc.edu'));
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.phone_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Call Center'),
              subtitle: const Text('+1 (555) 123-4567'),
              contentPadding: EdgeInsets.zero,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Opening dialer...')),
                );
                // In real app: launchUrl(Uri.parse('tel:+15551234567'));
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showVersionInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            String versionText;
            if (snapshot.hasData) {
              versionText =
                  'Version ${snapshot.data!.version} (Build ${snapshot.data!.buildNumber})';
            } else if (snapshot.hasError) {
              versionText = 'Version Info Unavailable';
            } else {
              versionText = 'Loading...';
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.surfaceLight,
                  child: Icon(
                    Icons.info_outline,
                    size: 30,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).appName,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  versionText,
                  style: GoogleFonts.roboto(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                const Text(
                  '© 2025 University Health Center\nAll rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final user = authProvider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isSuperAdmin = user?.isSuperAdmin ?? false;
    final isAdmin = user?.isAdmin ?? false;
    final isAdminLike = isAdmin || isSuperAdmin;
    final accentColor =
        isSuperAdmin ? const Color(0xFFD32F2F) : AppColors.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.profile,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: ResponsivePage(
        maxWidth: UhcResponsive.isWide(context) ? 1080 : 980,
        bottomPadding:
            UhcResponsive.isWide(context) ? 32 : (isSuperAdmin ? 32 : 100),
        alignment: UhcResponsive.isWide(context)
            ? AlignmentDirectional.topStart
            : Alignment.topCenter,
        child: _buildProfileContent(
          context: context,
          authProvider: authProvider,
          themeProvider: themeProvider,
          localeProvider: localeProvider,
          userName: user?.fullName ?? 'User',
          userEmail: user?.email ?? '',
          userPhotoUrl: user?.photoUrl,
          slotType: user?.superAdminType?.name,
          initialEmail: authProvider.firebaseUser?.email ?? user?.email,
          isDark: isDark,
          l10n: l10n,
          isSuperAdmin: isSuperAdmin,
          isAdminLike: isAdminLike,
          accentColor: accentColor,
        ),
      ),
    );
  }

  Widget _buildProfileContent({
    required BuildContext context,
    required AuthProvider authProvider,
    required ThemeProvider themeProvider,
    required LocaleProvider localeProvider,
    required String userName,
    required String userEmail,
    required String? userPhotoUrl,
    required String? slotType,
    required String? initialEmail,
    required bool isDark,
    required AppLocalizations l10n,
    required bool isSuperAdmin,
    required bool isAdminLike,
    required Color accentColor,
  }) {
    final header = _buildProfileHeader(
      userName,
      userEmail,
      userPhotoUrl,
      isDark,
      l10n: l10n,
      isSuperAdmin: isSuperAdmin,
      slotType: slotType,
      accentColor: accentColor,
    );

    final appearance = _buildSection(
      l10n.appearance,
      [
        _buildSettingTile(
          icon: Icons.dark_mode_rounded,
          title: l10n.darkMode,
          trailing: Switch(
            value: themeProvider.isDarkMode,
            onChanged: (_) => _applyThemeChange(themeProvider, authProvider),
          ),
          isDark: isDark,
          accentColor: accentColor,
        ),
        if (!isSuperAdmin)
          _buildSettingTile(
            icon: Icons.language_rounded,
            title: l10n.language,
            subtitle: localeProvider.languageName,
            onTap: () => _showLanguageDialog(context, l10n),
            isDark: isDark,
            accentColor: accentColor,
          ),
      ],
      isDark,
    );

    final notifications = !isAdminLike
        ? _buildSection(
            l10n.notificationSettings,
            [
              _buildSettingTile(
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
                accentColor: accentColor,
              ),
            ],
            isDark,
          )
        : null;

    final account = _buildSection(
      l10n.account,
      [
        _buildSettingTile(
          icon: Icons.person,
          title: l10n.editProfile,
          subtitle: l10n.updateProfile,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
          ),
          isDark: isDark,
          accentColor: accentColor,
        ),
        _buildSettingTile(
          icon: Icons.lock,
          title: l10n.changePassword,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
          ),
          isDark: isDark,
          accentColor: accentColor,
        ),
        _buildSettingTile(
          icon: Icons.lock_reset_rounded,
          title: l10n.forgotPassword,
          subtitle: l10n.sendResetLink,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ForgotPasswordScreen(
                onBackTap: () => Navigator.of(context).pop(),
                initialEmail: initialEmail,
                launchedFromProfile: true,
              ),
            ),
          ),
          isDark: isDark,
          accentColor: accentColor,
        ),
        if (!isSuperAdmin)
          _buildSettingTile(
            icon: Icons.folder_shared_rounded,
            title: l10n.medicalDocuments,
            subtitle: l10n.manageYourMedicalRecords,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MedicalDocumentsScreen()),
            ),
            isDark: isDark,
            accentColor: accentColor,
          ),
      ],
      isDark,
    );

    final about = _buildSection(
      l10n.about,
      [
        _buildSettingTile(
          icon: Icons.privacy_tip_rounded,
          title: l10n.privacyPolicy,
          onTap: () => _showPrivacyPolicy(context),
          isDark: isDark,
          accentColor: accentColor,
        ),
        _buildSettingTile(
          icon: Icons.description_rounded,
          title: l10n.termsOfService,
          onTap: () => _showTermsOfService(context),
          isDark: isDark,
          accentColor: accentColor,
        ),
        _buildSettingTile(
          icon: Icons.help_rounded,
          title: l10n.helpAndSupport,
          onTap: () => _showHelpSupport(context),
          isDark: isDark,
          accentColor: accentColor,
        ),
        _buildSettingTile(
          icon: Icons.info_rounded,
          title: l10n.version,
          trailing: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Text(
                  snapshot.data!.version,
                  style: GoogleFonts.roboto(color: Colors.grey),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          onTap: () => _showVersionInfo(context),
          isDark: isDark,
          accentColor: accentColor,
        ),
      ],
      isDark,
    );

    final admin = isAdminLike
        ? _buildSection(
            l10n.admin,
            [
              _buildSettingTile(
                icon: Icons.admin_panel_settings,
                title: l10n.adminDashboard,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminDashboardScreen()),
                ),
                isDark: isDark,
                accentColor: accentColor,
              ),
            ],
            isDark,
          )
        : null;

    final logout = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showLogoutDialog(context, authProvider, l10n),
        icon: const Icon(Icons.logout_rounded, color: AppColors.error),
        label: Text(
          l10n.logout,
          style: GoogleFonts.poppins(color: AppColors.error),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.error),
        ),
      ),
    );

    if (UhcResponsive.isWide(context)) {
      return Column(
        children: [
          header,
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    account,
                    const SizedBox(height: 16),
                    about,
                    const SizedBox(height: 18),
                    logout,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    appearance,
                    if (notifications != null) ...[
                      const SizedBox(height: 16),
                      notifications,
                    ],
                    if (admin != null) ...[
                      const SizedBox(height: 16),
                      admin,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        const SizedBox(height: 20),
        appearance,
        if (notifications != null) ...[
          const SizedBox(height: 14),
          notifications,
        ],
        const SizedBox(height: 14),
        account,
        const SizedBox(height: 14),
        about,
        if (admin != null) ...[
          const SizedBox(height: 14),
          admin,
        ],
        const SizedBox(height: 20),
        logout,
      ],
    );
  }

  void _showLanguageDialog(BuildContext context, AppLocalizations l10n) {
    final localeProvider = context.read<LocaleProvider>();
    final currentLocale = localeProvider.locale.languageCode;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.selectLanguage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('English'),
              trailing: currentLocale == 'en'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                _applyLanguageChange(dialogContext, 'en');
              },
            ),
            ListTile(
              title: const Text('العربية'),
              trailing: currentLocale == 'ar'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                _applyLanguageChange(dialogContext, 'ar');
              },
            ),
            ListTile(
              title: const Text('کوردی'),
              trailing: currentLocale == 'ku'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                _applyLanguageChange(dialogContext, 'ku');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _applyLanguageChange(
    BuildContext dialogContext,
    String languageCode,
  ) async {
    final localeProvider = context.read<LocaleProvider>();
    final authProvider = context.read<AuthProvider>();

    await localeProvider.setLocaleByCode(languageCode);
    await authProvider.updateLanguage(languageCode);

    if (!dialogContext.mounted) return;
    Navigator.pop(dialogContext);
  }

  Future<void> _applyThemeChange(
    ThemeProvider themeProvider,
    AuthProvider authProvider,
  ) async {
    await themeProvider.toggleTheme();
    await authProvider.updateThemeMode(themeProvider.themeMode.name);
  }

  Widget _buildProfileHeader(
    String name,
    String email,
    String? photoUrl,
    bool isDark, {
    required AppLocalizations l10n,
    required bool isSuperAdmin,
    required String? slotType,
    required Color accentColor,
  }) {
    // Get user initial for the avatar
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U';

    return Column(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            );
          },
          child: Stack(
            children: [
              // Avatar Container matching Home Screen style but larger
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: isSuperAdmin
                        ? accentColor.withValues(alpha: isDark ? 0.55 : 0.35)
                        : (isDark
                            ? Colors.white10
                            : Colors.grey.withValues(alpha: 0.1)),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: photoUrl != null && photoUrl.isNotEmpty
                      ? (photoUrl.startsWith('http')
                          ? Image.network(
                              photoUrl,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _buildDefaultAvatar(
                                      initial, isDark, accentColor),
                            )
                          // Web or Mobile with local path (not supported without dart:io)
                          // See: https://github.com/flutter/flutter/issues/33646
                          : _buildDefaultAvatar(initial, isDark, accentColor))
                      : _buildDefaultAvatar(initial, isDark, accentColor),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.3),
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
        Text(
          email,
          style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey),
        ),
        if (isSuperAdmin) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield, size: 14, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  slotType == 'backup'
                      ? '${l10n.superAdmin} • BACKUP'
                      : '${l10n.superAdmin} • PRIMARY',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildDefaultAvatar(String initial, bool isDark, Color accentColor) {
    return Center(
      child: Text(
        initial,
        style: GoogleFonts.outfit(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : accentColor,
        ),
      ),
    );
  }

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
        const SizedBox(height: 8),
        Material(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    required bool isDark,
    Color accentColor = AppColors.primary,
  }) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      minLeadingWidth: 38,
      minVerticalPadding: 8,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: accentColor, size: 18),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: GoogleFonts.roboto(fontSize: 11.5, color: Colors.grey),
            )
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  void _showLogoutDialog(
    BuildContext outerContext,
    AuthProvider authProvider,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: outerContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          l10n.logout,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              final notificationProvider =
                  outerContext.read<NotificationProvider>();

              try {
                await authProvider.signOut(
                  beforeSignOut: notificationProvider.onLogout,
                );
              } catch (_) {
                if (!outerContext.mounted) return;
                ScaffoldMessenger.of(outerContext).showSnackBar(
                  const SnackBar(
                    content: Text('Logout failed. Please try again.'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: Text(
              l10n.logout,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class LegalText {
  static const String privacyPolicy = 'Last updated: January 2025\n\n'
      '1. Introduction\n'
      'Welcome to UHC App. We respect your privacy and are committed to protecting your personal data.\n\n'
      '2. Data We Collect\n'
      'We collect information you provide directly to us, such as when you create an account, update your profile, or book appointments.\n\n'
      '3. How We Use Your Data\n'
      'We use your data to provide, maintain, and improve our services, including processing appointments and sending notifications.\n\n'
      '4. Data Security\n'
      'We implement appropriate security measures to protect your personal information.\n\n'
      '5. Contact Us\n'
      'If you have any questions about this Privacy Policy, please contact support@uhc.edu.';

  static const String termsOfService = '1. Acceptance of Terms\n'
      'By accessing or using our app, you agree to be bound by these Terms of Service.\n\n'
      '2. User Accounts\n'
      'You are responsible for maintaining the confidentiality of your account credentials.\n\n'
      '3. Appointments\n'
      'Appointment bookings are subject to availability. Cancellations must be made at least 24 hours in advance.\n\n'
      '4. Code of Conduct\n'
      'You agree to use the service for lawful purposes only and respect university policies.\n\n'
      '5. Modifications\n'
      'We reserve the right to modify these terms at any time.';
}
