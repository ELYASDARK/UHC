import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../core/notifications/notification_preferences.dart';
import '../../services/local_notification_service.dart';
import '../../services/fcm_service.dart';
import '../../services/notification_scheduling_coordinator.dart';
import '../../core/widgets/responsive_layout.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationPreferences _prefs;
  bool _isLoading = true;
  bool _areNotificationsEnabled = true;
  bool _exactAlarmsAllowed = true;
  final LocalNotificationService _notificationService =
      LocalNotificationService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissions();
    });
  }

  Future<void> _checkPermissions() async {
    bool enabled = true;
    bool exactAllowed = true;
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    if (!kIsWeb) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImplementation =
            flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          enabled = await androidImplementation.areNotificationsEnabled() ?? false;
        }
        exactAllowed = await _notificationService.canScheduleExactAlarms();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        enabled = await _notificationService.requestPermissions();
      }
    }

    if (mounted) {
      setState(() {
        _areNotificationsEnabled = enabled;
        _exactAlarmsAllowed = exactAllowed;
      });
    }
  }

  Future<void> _loadSettings() async {
    final authProvider = context.read<AuthProvider>();
    final user = authProvider.currentUser;
    final isDoctor = user?.isDoctor ?? false;

    // Load from user document in Firestore
    final prefsMap = user?.notificationSettings;
    
    setState(() {
      _prefs = NotificationPreferences.fromMap(
        prefsMap,
        isDoctor: isDoctor,
        isWeb: kIsWeb,
      );
      _isLoading = false;
    });
  }

  Future<void> _updatePreferences(NotificationPreferences newPrefs) async {
    setState(() {
      _prefs = newPrefs;
    });

    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId != null) {
      try {
        // 1. Save to user document in Firestore
        await authProvider.updateNotificationPreferences(newPrefs.toMap());

        // 2. Re-register device token so token document is updated with new preferences
        await FCMService().saveTokenToDatabase(userId);

        // 3. Resync reminders
        await NotificationSchedulingCoordinator().resyncAfterSettingsChange(userId);
      } catch (e) {
        debugPrint('Failed to update notification preferences: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save settings: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _requestPermissions() async {
    final granted = await _notificationService.requestPermissions();
    await _checkPermissions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted
              ? 'Notification permission granted!'
              : 'Please enable notifications in system settings.'),
          backgroundColor: granted ? AppColors.success : AppColors.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = context.watch<AuthProvider>().currentUser;
    final isDoctor = user?.isDoctor ?? false;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        centerTitle: true,
      ),
      body: ResponsivePage(
        maxWidth: 800,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Permission Warnings
            if (!_areNotificationsEnabled)
              _buildWarningCard(
                isDark: isDark,
                icon: Icons.notifications_off_outlined,
                title: 'System Notifications Disabled',
                subtitle: kIsWeb
                    ? 'Browser notifications are disabled or blocked.'
                    : 'UHC does not have permission to show notifications on this device.',
                actionLabel: 'Enable Notifications',
                onActionPressed: _requestPermissions,
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),

            if (!_exactAlarmsAllowed && !kIsWeb)
              _buildWarningCard(
                isDark: isDark,
                icon: Icons.alarm_off_outlined,
                title: 'Exact Alarms Restricted',
                subtitle: 'Android system settings restrict exact alarms. Offline reminders may arrive slightly late.',
                actionLabel: 'Request Exact Alarms',
                onActionPressed: () async {
                  await _notificationService.requestPermissions();
                  await _checkPermissions();
                },
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),

            const SizedBox(height: 8),

            // 1. Notification Status Section
            _buildStatusCard(isDark).animate().fadeIn(duration: 400.ms, delay: 50.ms).slideY(begin: 0.05, end: 0),
            const SizedBox(height: 16),

            // 2. Important Appointment Updates Section
            _buildImportantUpdatesCard(isDark).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.05, end: 0),
            const SizedBox(height: 16),

            // 3. Online Push Notifications Section
            _buildPushNotificationsCard(isDark).animate().fadeIn(duration: 400.ms, delay: 150.ms).slideY(begin: 0.05, end: 0),
            const SizedBox(height: 16),

            // 4. Appointment & Consultation Reminders Section (Non-doctors only)
            if (!isDoctor) ...[
              _buildRemindersCard(isDark).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.05, end: 0),
              const SizedBox(height: 16),
            ],

            // 5. Daily Doctor Report Section (Doctors Only)
            if (isDoctor) ...[
              _buildDoctorReportCard(isDark).animate().fadeIn(duration: 400.ms, delay: 250.ms).slideY(begin: 0.05, end: 0),
              const SizedBox(height: 16),
            ],

            // 6. Admin Announcements Section
            _buildAdminAnnouncementsCard(isDark).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideY(begin: 0.05, end: 0),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildWarningCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onActionPressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.warning, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onActionPressed,
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                    foregroundColor: AppColors.warning,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Section 1: Notification Status Card
  Widget _buildStatusCard(bool isDark) {
    String platformName = 'Web';
    String localRemindersStatus = 'Not available';
    if (!kIsWeb) {
      platformName = defaultTargetPlatform == TargetPlatform.android ? 'Android' : 'iOS';
      localRemindersStatus = 'Available';
    }

    final pushStatusText = _areNotificationsEnabled ? 'Enabled' : 'Disabled / Needs permission';
    final pushStatusColor = _areNotificationsEnabled ? AppColors.success : AppColors.error;

    return _buildSectionCard(
      title: 'Notification Status',
      icon: Icons.info_outline,
      isDark: isDark,
      children: [
        Text(
          kIsWeb
              ? 'Browser push is enabled or disabled. Offline mobile reminders are not available on web.'
              : 'System notifications are enabled or disabled on this device.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoRow('Platform', platformName, isDark),
        _buildInfoRow(
          'Push Status',
          pushStatusText,
          isDark,
          valueColor: pushStatusColor,
          showBadge: true,
        ),
        _buildInfoRow(
          'Local Reminders',
          localRemindersStatus,
          isDark,
          valueColor: kIsWeb ? Colors.grey : AppColors.success,
          showBadge: true,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final useVerticalLayout = constraints.maxWidth < 400;
            if (useVerticalLayout) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _checkPermissions,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh Status'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _requestPermissions,
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Request Permissions'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checkPermissions,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh Status'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _requestPermissions,
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Request Permissions'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark, {Color? valueColor, bool showBadge = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          if (showBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (valueColor ?? (isDark ? Colors.grey[700] : Colors.grey[200]))!.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (valueColor ?? (isDark ? Colors.grey[600] : Colors.grey[300]))!.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: valueColor,
                ),
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.grey[300] : AppColors.textPrimaryLight,
              ),
            ),
        ],
      ),
    );
  }

  // Section 2: Important Appointment Updates
  Widget _buildImportantUpdatesCard(bool isDark) {
    return _buildSectionCard(
      title: 'Important Appointment Updates',
      icon: Icons.event_note,
      isDark: isDark,
      children: [
        Text(
          'Booking confirmations, cancellations, reschedules, and status updates are always saved in Alerts.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Appointment Updates', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Always saved in in-app alerts tab'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'ALWAYS ON',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Section 3: Online Push Notifications
  Widget _buildPushNotificationsCard(bool isDark) {
    final user = context.read<AuthProvider>().currentUser;
    final isDoctor = user?.isDoctor ?? false;

    return _buildSectionCard(
      title: 'Online Push Notifications',
      icon: Icons.notifications_active_outlined,
      isDark: isDark,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Online push notifications', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Receive real-time notifications on this device when push is available.'),
          value: _prefs.onlinePushEnabled,
          onChanged: (val) {
            var updatedPrefs = _prefs.copyWith(onlinePushEnabled: val);
            if (!val) {
              if (kIsWeb) {
                updatedPrefs = updatedPrefs.copyWith(
                  appointmentRemindersEnabled: false,
                  doctorDailySummaryEnabled: false,
                );
              } else {
                if (updatedPrefs.appointmentReminderDelivery == NotificationDeliveryMode.fcm) {
                  updatedPrefs = updatedPrefs.copyWith(
                    appointmentReminderDelivery: NotificationDeliveryMode.local,
                  );
                }
                if (updatedPrefs.doctorDailySummaryDelivery == NotificationDeliveryMode.fcm) {
                  updatedPrefs = updatedPrefs.copyWith(
                    doctorDailySummaryDelivery: NotificationDeliveryMode.local,
                  );
                }
              }
            } else {
              if (isDoctor) {
                updatedPrefs = updatedPrefs.copyWith(
                  doctorDailySummaryEnabled: true,
                  doctorDailySummaryDelivery: NotificationDeliveryMode.fcm,
                );
              } else {
                updatedPrefs = updatedPrefs.copyWith(
                  appointmentRemindersEnabled: true,
                  appointmentReminderDelivery: NotificationDeliveryMode.fcm,
                );
              }
            }
            _updatePreferences(updatedPrefs);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Note: Turning this off stops pop-up notifications on your screen, but updates will still be saved in your in-app Alerts tab.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ),
      ],
    );
  }

  // Section 4: Appointment & Consultation Reminders
  Widget _buildRemindersCard(bool isDark) {
    final enabled = _prefs.appointmentRemindersEnabled;
    final isPushOffOnWeb = kIsWeb && !_prefs.onlinePushEnabled;

    return _buildSectionCard(
      title: 'Appointment & Consultation Reminders',
      icon: Icons.alarm,
      isDark: isDark,
      children: isPushOffOnWeb
          ? [
              Text(
                'To receive reminders, please enable Online Push Notifications first.',
                style: TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ]
          : [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reminders', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Choose when and how UHC reminds you before appointments and consultations.'),
                value: enabled,
                onChanged: (val) {
                  _updatePreferences(_prefs.copyWith(appointmentRemindersEnabled: val));
                },
              ),
              if (enabled) ...[
                const Divider(height: 24),
                const Text('Timing switches', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                _buildSubSwitchTile(
                  title: '1 week before',
                  value: _prefs.reminderOneWeek,
                  onChanged: (val) => _updatePreferences(_prefs.copyWith(reminderOneWeek: val)),
                  isDark: isDark,
                ),
                _buildSubSwitchTile(
                  title: '1 day before',
                  value: _prefs.reminderOneDay,
                  onChanged: (val) => _updatePreferences(_prefs.copyWith(reminderOneDay: val)),
                  isDark: isDark,
                ),
                _buildSubSwitchTile(
                  title: '1 hour before',
                  value: _prefs.reminderOneHour,
                  onChanged: (val) => _updatePreferences(_prefs.copyWith(reminderOneHour: val)),
                  isDark: isDark,
                ),
                const Divider(height: 24),
                const Text('Delivery Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                if (kIsWeb)
                  _buildWebDeliveryOption(isDark)
                else
                  _buildMobileDeliveryOptions(isDark),
              ],
            ],
    );
  }

  Widget _buildSubSwitchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildWebDeliveryOption(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800]!.withValues(alpha: 0.4) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Online & synced',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 8),
              _buildBadge('Required on web', AppColors.success),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Offline mobile reminders are not available in the browser.',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDeliveryOptions(bool isDark) {
    final mode = _prefs.appointmentReminderDelivery;
    final isPushDisabled = !_prefs.onlinePushEnabled;

    return Column(
      children: [
        _buildDeliveryRadioCard(
          title: 'Online & synced',
          subtitle: isPushDisabled 
              ? 'Requires Online Push Notifications to be enabled.' 
              : 'Works across devices and appears in Alerts.',
          tag: isPushDisabled ? null : 'recommended',
          tagColor: AppColors.success,
          icon: Icons.cloud_outlined,
          isSelected: !isPushDisabled && mode == NotificationDeliveryMode.fcm,
          isDark: isDark,
          enabled: !isPushDisabled,
          onTap: isPushDisabled
              ? () {}
              : () {
                  _updatePreferences(_prefs.copyWith(appointmentReminderDelivery: NotificationDeliveryMode.fcm));
                },
        ),
        const SizedBox(height: 12),
        _buildDeliveryRadioCard(
          title: 'Offline on this device',
          subtitle: 'Works without internet, but only on this phone. It can be lost after app data wipe or reinstall.',
          icon: Icons.phone_android_outlined,
          isSelected: isPushDisabled || mode == NotificationDeliveryMode.local,
          isDark: isDark,
          onTap: () {
            _updatePreferences(_prefs.copyWith(appointmentReminderDelivery: NotificationDeliveryMode.local));
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Local reminders are only scheduled on this device. Web browsers cannot use them.',
          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: isDark ? Colors.grey[500] : Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _buildDeliveryRadioCard({
    required String title,
    required String subtitle,
    String? tag,
    Color? tagColor,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.06)
              : (isDark ? Colors.grey[900] : Colors.grey[50]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? AppColors.primary : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16, color: isSelected ? AppColors.primary : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isSelected ? AppColors.primary : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        if (tag != null) ...[
                          const SizedBox(width: 8),
                          _buildBadge(tag, tagColor ?? AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Section 5: Daily Doctor Report
  Widget _buildDoctorReportCard(bool isDark) {
    final enabled = _prefs.doctorDailySummaryEnabled;
    final isPushOffOnWeb = kIsWeb && !_prefs.onlinePushEnabled;

    return _buildSectionCard(
      title: 'Daily Doctor Report',
      icon: Icons.assignment_outlined,
      isDark: isDark,
      children: isPushOffOnWeb
          ? [
              Text(
                'To receive reports, please enable Online Push Notifications first.',
                style: TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ]
          : [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily report', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Receive a daily summary report of your upcoming schedule.'),
                value: enabled,
                onChanged: (val) {
                  _updatePreferences(_prefs.copyWith(doctorDailySummaryEnabled: val));
                },
              ),
              if (enabled) ...[
                const Divider(height: 24),
                const Text('Delivery Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                if (kIsWeb)
                  _buildDoctorWebDeliveryOption(isDark)
                else
                  _buildDoctorMobileDeliveryOptions(isDark),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Report time', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Choose when to receive your daily summary'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Builder(
                      builder: (context) {
                        final parts = _prefs.doctorDailySummaryTime.split(':');
                        final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 21 : 21;
                        final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
                        final time = TimeOfDay(hour: hour, minute: minute);
                        return Text(
                          time.format(context),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  onTap: () async {
                    final parts = _prefs.doctorDailySummaryTime.split(':');
                    final initialTime = TimeOfDay(
                      hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 21 : 21,
                      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
                    );
                    final time = await showTimePicker(
                      context: context,
                      initialTime: initialTime,
                    );
                    if (time != null) {
                      final timeStr =
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                      _updatePreferences(_prefs.copyWith(doctorDailySummaryTime: timeStr));
                    }
                  },
                ),
              ],
            ],
    );
  }

  Widget _buildDoctorWebDeliveryOption(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800]!.withValues(alpha: 0.4) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in_outlined, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Accurate online report',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 8),
              _buildBadge('Recommended', AppColors.success),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Calculated fresh from the backend at your chosen time.',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorMobileDeliveryOptions(bool isDark) {
    final mode = _prefs.doctorDailySummaryDelivery;
    final isPushDisabled = !_prefs.onlinePushEnabled;

    return Column(
      children: [
        _buildDeliveryRadioCard(
          title: 'Accurate online report',
          subtitle: isPushDisabled
              ? 'Requires Online Push Notifications to be enabled.'
              : 'Calculated fresh from the backend at your chosen time.',
          tag: isPushDisabled ? null : 'recommended',
          tagColor: AppColors.success,
          icon: Icons.cloud_outlined,
          isSelected: !isPushDisabled && mode == NotificationDeliveryMode.fcm,
          isDark: isDark,
          enabled: !isPushDisabled,
          onTap: isPushDisabled
              ? () {}
              : () {
                  _updatePreferences(_prefs.copyWith(doctorDailySummaryDelivery: NotificationDeliveryMode.fcm));
                },
        ),
        const SizedBox(height: 12),
        _buildDeliveryRadioCard(
          title: 'Offline reminder only',
          subtitle: 'Shows a reminder to open UHC. It does not guarantee fresh appointment counts.',
          icon: Icons.phone_android_outlined,
          isSelected: isPushDisabled || mode == NotificationDeliveryMode.local,
          isDark: isDark,
          onTap: () {
            _updatePreferences(_prefs.copyWith(doctorDailySummaryDelivery: NotificationDeliveryMode.local));
          },
        ),
      ],
    );
  }

  // Section 6: Admin Announcements
  Widget _buildAdminAnnouncementsCard(bool isDark) {
    return _buildSectionCard(
      title: 'Admin Announcements',
      icon: Icons.campaign_outlined,
      isDark: isDark,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Admin announcements', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Receive UHC announcements from administrators.'),
          value: _prefs.adminAnnouncementsEnabled,
          onChanged: (val) {
            _updatePreferences(_prefs.copyWith(adminAnnouncementsEnabled: val));
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Announcements are still saved in Alerts.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ),
      ],
    );
  }
}
