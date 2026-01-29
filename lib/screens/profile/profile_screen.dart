import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/notification_provider.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/models/notification_model.dart';
import '../../services/local_notification_service.dart';
import '../admin/admin_dashboard_screen.dart';
import '../settings/notification_settings_screen.dart';
import 'edit_profile_screen.dart';
import '../documents/medical_documents_screen.dart';

/// Profile and settings screen
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _pushNotificationsEnabled = true;
  bool _emailNotificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;

    if (mounted) {
      setState(() {
        _pushNotificationsEnabled =
            prefs.getBool('settings_push_notifications') ?? true;

        // Prefer server setting for email, fallback to local
        if (user?.notificationSettings?.containsKey('email_notifications') ==
            true) {
          _emailNotificationsEnabled =
              user!.notificationSettings!['email_notifications'];
          // Sync local
          prefs.setBool(
            'settings_email_notifications',
            _emailNotificationsEnabled,
          );
        } else {
          _emailNotificationsEnabled =
              prefs.getBool('settings_email_notifications') ?? false;
        }
      });
    }
  }

  Future<void> _togglePushNotifications(bool value) async {
    setState(() => _pushNotificationsEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings_push_notifications', value);

    if (mounted) {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.currentUser != null) {
        final notifProvider = context.read<NotificationProvider>();
        if (value) {
          await notifProvider.enablePushNotifications(
            authProvider.currentUser!.id,
          );
        } else {
          await notifProvider.disablePushNotifications(
            authProvider.currentUser!.id,
          );
        }
      }
    }
  }

  Future<void> _toggleEmailNotifications(bool value) async {
    setState(() => _emailNotificationsEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings_email_notifications', value);

    if (mounted) {
      final authProvider = context.read<AuthProvider>();
      await authProvider.updateNotificationPreferences({
        'email_notifications': value,
      });
    }
  }

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
                'Privacy Policy',
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
                    'Last updated: January 2025\n\n'
                    '1. Introduction\n'
                    'Welcome to UHC App. We respect your privacy and are committed to protecting your personal data.\n\n'
                    '2. Data We Collect\n'
                    'We collect information you provide directly to us, such as when you create an account, update your profile, or book appointments.\n\n'
                    '3. How We Use Your Data\n'
                    'We use your data to provide, maintain, and improve our services, including processing appointments and sending notifications.\n\n'
                    '4. Data Security\n'
                    'We implement appropriate security measures to protect your personal information.\n\n'
                    '5. Contact Us\n'
                    'If you have any questions about this Privacy Policy, please contact support@uhc.edu.',
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
                'Terms of Service',
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
                    '1. Acceptance of Terms\n'
                    'By accessing or using our app, you agree to be bound by these Terms of Service.\n\n'
                    '2. User Accounts\n'
                    'You are responsible for maintaining the confidentiality of your account credentials.\n\n'
                    '3. Appointments\n'
                    'Appointment bookings are subject to availability. Cancellations must be made at least 24 hours in advance.\n\n'
                    '4. Code of Conduct\n'
                    'You agree to use the service for lawful purposes only and respect university policies.\n\n'
                    '5. Modifications\n'
                    'We reserve the right to modify these terms at any time.',
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
        content: Column(
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
              'UHC App',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Version 1.0.0 (Build 100)',
              style: GoogleFonts.roboto(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              '© 2025 University Health Center\nAll rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.profile,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile header
            _buildProfileHeader(
              user?.fullName ?? 'User',
              user?.email ?? '',
              user?.photoUrl,
              isDark,
            ),
            const SizedBox(height: 32),

            // Settings sections
            _buildSection(l10n.appearance, [
              _buildSettingTile(
                icon: Icons.dark_mode_rounded,
                title: l10n.darkMode,
                trailing: Switch(
                  value: themeProvider.isDarkMode,
                  onChanged: (_) => themeProvider.toggleTheme(),
                ),
                isDark: isDark,
              ),
              _buildSettingTile(
                icon: Icons.language_rounded,
                title: l10n.language,
                subtitle: localeProvider.languageName,
                onTap: () => _showLanguageDialog(context, l10n),
                isDark: isDark,
              ),
            ], isDark),

            const SizedBox(height: 20),

            _buildSection(l10n.notificationSettings, [
              _buildSettingTile(
                icon: Icons.notifications_rounded,
                title: l10n.pushNotifications,
                trailing: Switch(
                  value: _pushNotificationsEnabled,
                  onChanged: _togglePushNotifications,
                ),
                isDark: isDark,
              ),
              _buildSettingTile(
                icon: Icons.email_rounded,
                title: l10n.emailNotifications,
                trailing: Switch(
                  value: _emailNotificationsEnabled,
                  onChanged: _toggleEmailNotifications,
                ),
                isDark: isDark,
              ),
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
              ),
            ], isDark),

            // Account section
            const SizedBox(height: 20),
            _buildSection(l10n.account, [
              _buildSettingTile(
                icon: Icons.person,
                title: l10n.editProfile,
                subtitle: l10n.updateProfile,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ),
                isDark: isDark,
              ),
              _buildSettingTile(
                icon: Icons.lock,
                title: l10n.changePassword,
                subtitle: l10n.newPassword,
                onTap: () => _showChangePasswordDialog(context, l10n),
                isDark: isDark,
              ),
              _buildSettingTile(
                icon: Icons.folder_shared_rounded,
                title: l10n.medicalDocuments,
                subtitle: l10n.manageYourMedicalRecords,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MedicalDocumentsScreen(),
                  ),
                ),
                isDark: isDark,
              ),
            ], isDark),

            const SizedBox(height: 20),

            _buildSection(l10n.about, [
              _buildSettingTile(
                icon: Icons.privacy_tip_rounded,
                title: l10n.privacyPolicy,
                onTap: () => _showPrivacyPolicy(context),
                isDark: isDark,
              ),
              _buildSettingTile(
                icon: Icons.description_rounded,
                title: l10n.termsOfService,
                onTap: () => _showTermsOfService(context),
                isDark: isDark,
              ),
              _buildSettingTile(
                icon: Icons.help_rounded,
                title: l10n.helpAndSupport,
                onTap: () => _showHelpSupport(context),
                isDark: isDark,
              ),
              _buildSettingTile(
                icon: Icons.info_rounded,
                title: l10n.version,
                trailing: Text(
                  '1.0.0',
                  style: GoogleFonts.roboto(color: Colors.grey),
                ),
                onTap: () => _showVersionInfo(context),
                isDark: isDark,
              ),
            ], isDark),

            // Developer Testing section - only visible to admin
            if (user?.isAdmin == true) ...[
              const SizedBox(height: 20),
              _buildSection('Developer Testing', [
                _buildSettingTile(
                  icon: Icons.notification_add,
                  title: 'Send Test Notification',
                  onTap: () => _sendTestNotification(context),
                  isDark: isDark,
                ),
                _buildSettingTile(
                  icon: Icons.schedule,
                  title: 'Schedule Notification (30 sec)',
                  onTap: () => _scheduleTestNotification(context),
                  isDark: isDark,
                ),
                _buildSettingTile(
                  icon: Icons.delete_sweep,
                  title: 'Clear All Notifications',
                  onTap: () => _clearAllNotifications(context),
                  isDark: isDark,
                ),
              ], isDark),

              // Admin section - only visible to admin
              const SizedBox(height: 20),
              _buildSection('Admin', [
                _buildSettingTile(
                  icon: Icons.admin_panel_settings,
                  title: 'Admin Dashboard',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminDashboardScreen(),
                    ),
                  ),
                  isDark: isDark,
                ),
              ], isDark),
            ],

            const SizedBox(height: 32),

            // Logout button
            SizedBox(
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
            ),
          ],
        ),
      ),
    );
  }

  void _sendTestNotification(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    if (authProvider.user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login first')));
      return;
    }

    final notificationRepo = NotificationRepository();

    try {
      // Create a test notification
      final testNotification = NotificationModel(
        id: '',
        userId: authProvider.user!.id,
        title: 'Test Notification 🔔',
        body:
            'This is a test notification to verify the system is working! Created at ${DateTime.now().toString().substring(11, 19)}',
        type: NotificationType.appointmentConfirmation,
        createdAt: DateTime.now(),
        scheduledFor: null,
        reminderType: ReminderType.immediate,
        isDelivered: true,
      );

      await notificationRepo.createNotification(testNotification);

      // Reload notifications
      await notificationProvider.loadNotifications(authProvider.user!.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Test notification sent! Check the Alerts tab.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _scheduleTestNotification(BuildContext context) async {
    final localNotificationService = LocalNotificationService();

    // Schedule notification for 30 seconds from now
    final scheduledTime = DateTime.now().add(const Duration(seconds: 30));

    try {
      await localNotificationService.scheduleNotification(
        id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title: 'Scheduled Test Notification 📅',
        body:
            'This notification was scheduled 30 seconds ago. You can close the app and still receive it!',
        scheduledTime: scheduledTime,
        isAppointment: true,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Notification scheduled for 30 seconds from now!\n'
              'Close the app to test - you will still receive it.',
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _clearAllNotifications(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final notificationProvider = context.read<NotificationProvider>();

    if (authProvider.user == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Notifications'),
        content: const Text(
          'Are you sure you want to delete all notifications?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);

              final notificationRepo = NotificationRepository();
              await notificationRepo.deleteAllNotifications(
                authProvider.user!.id,
              );
              await notificationProvider.loadNotifications(
                authProvider.user!.id,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All notifications cleared'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            child: const Text(
              'Clear All',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, AppLocalizations l10n) {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.changePassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.currentPassword),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.newPassword),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.confirmPassword),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (newController.text != confirmController.text) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.passwordMismatch)));
                return;
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.passwordChanged),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: Text(l10n.change),
          ),
        ],
      ),
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
                localeProvider.setLocaleByCode('en');
                Navigator.pop(dialogContext);
              },
            ),
            ListTile(
              title: const Text('العربية'),
              trailing: currentLocale == 'ar'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                localeProvider.setLocaleByCode('ar');
                Navigator.pop(dialogContext);
              },
            ),
            ListTile(
              title: const Text('کوردی'),
              trailing: currentLocale == 'ku'
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                localeProvider.setLocaleByCode('ku');
                Navigator.pop(dialogContext);
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

  Widget _buildProfileHeader(
    String name,
    String email,
    String? photoUrl,
    bool isDark,
  ) {
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
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.grey.withOpacity(0.1),
                    width: 1.5,
                  ),
                ),
                child: ClipOval(
                  child: photoUrl != null
                      ? (photoUrl.startsWith('http')
                            ? Image.network(
                                photoUrl,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Center(
                                  child: Text(
                                    initial,
                                    style: GoogleFonts.outfit(
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              )
                            : (kIsWeb
                                  ? Center(
                                      child: Text(
                                        initial,
                                        style: GoogleFonts.outfit(
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    )
                                  : Image.file(
                                      File(photoUrl),
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Center(
                                        child: Text(
                                          initial,
                                          style: GoogleFonts.outfit(
                                            fontSize: 40,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    )))
                      : Center(
                          child: Text(
                            initial,
                            style: GoogleFonts.outfit(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
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
                        color: AppColors.primary.withOpacity(0.3),
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
      ],
    ).animate().fadeIn(duration: 400.ms);
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
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
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
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
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

  void _showLogoutDialog(
    BuildContext context,
    AuthProvider authProvider,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          l10n.logout,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              authProvider.signOut();
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
