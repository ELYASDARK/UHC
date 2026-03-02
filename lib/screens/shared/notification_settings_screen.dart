import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/doctor_appointment_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/local_notification_service.dart';
import '../../l10n/app_localizations.dart';

/// Notification settings model
class NotificationSettings {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool appointmentReminders;
  final bool reminder1Week;
  final bool reminder24Hours;
  final bool reminder1Hour;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool dailySummary;
  final String dailySummaryTime;

  NotificationSettings({
    this.pushEnabled = true,
    this.emailEnabled = false,
    this.appointmentReminders = true,
    this.reminder1Week = true,
    this.reminder24Hours = true,
    this.reminder1Hour = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.dailySummary = true,
    this.dailySummaryTime = '21:00',
  });

  NotificationSettings copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? appointmentReminders,
    bool? reminder1Week,
    bool? reminder24Hours,
    bool? reminder1Hour,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? dailySummary,
    String? dailySummaryTime,
  }) {
    return NotificationSettings(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      appointmentReminders: appointmentReminders ?? this.appointmentReminders,
      reminder1Week: reminder1Week ?? this.reminder1Week,
      reminder24Hours: reminder24Hours ?? this.reminder24Hours,
      reminder1Hour: reminder1Hour ?? this.reminder1Hour,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      dailySummary: dailySummary ?? this.dailySummary,
      dailySummaryTime: dailySummaryTime ?? this.dailySummaryTime,
    );
  }
}

/// Notification settings screen
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  NotificationSettings _settings = NotificationSettings();
  bool _isLoading = true;
  bool _areNotificationsEnabled = true;
  final LocalNotificationService _notificationService =
      LocalNotificationService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
  }

  @override
  void reassemble() {
    super.reassemble();
    _loadSettings();
  }

  Future<void> _checkPermissions() async {
    bool enabled = true;
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        enabled =
            await androidImplementation.areNotificationsEnabled() ?? false;
      }
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      // For iOS, we rely on the service to check/request
      enabled = await _notificationService.requestPermissions();
    }

    if (mounted) {
      setState(() {
        _areNotificationsEnabled = enabled;
      });
    }
  }

  Future<void> _loadSettings() async {
    final authProvider = context.read<AuthProvider>();
    final prefs = await SharedPreferences.getInstance();
    final user = authProvider.currentUser;

    bool emailEnabled = prefs.getBool('settings_email_notifications') ?? false;

    // Prefer server setting for email, fallback to local
    if (user?.notificationSettings?.containsKey('email_notifications') ==
        true) {
      emailEnabled = user!.notificationSettings!['email_notifications'];
      prefs.setBool('settings_email_notifications', emailEnabled);
    }

    setState(() {
      _settings = NotificationSettings(
        pushEnabled: prefs.getBool('settings_push_notifications') ?? true,
        emailEnabled: emailEnabled,
        appointmentReminders:
            prefs.getBool('notif_appointment_reminders') ?? true,
        reminder1Week: prefs.getBool('notif_reminder_1w') ?? true,
        reminder24Hours: prefs.getBool('notif_reminder_24h') ?? true,
        reminder1Hour: prefs.getBool('notif_reminder_1h') ?? true,
        soundEnabled: prefs.getBool('notif_sound') ?? true,
        vibrationEnabled: prefs.getBool('notif_vibration') ?? true,
        dailySummary: prefs.getBool('notif_daily_summary') ?? true,
        dailySummaryTime:
            prefs.getString('notif_daily_summary_time') ?? '21:00',
      );
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    // 1. Save locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);

    // 2. Sync to backend
    if (mounted) {
      try {
        await context.read<AuthProvider>().updateNotificationPreferences({
          key: value,
        });
      } catch (e) {
        debugPrint('Failed to sync setting $key: $e');
        // We don't block the UI or show error for background sync failures usually,
        // unless critical.
      }
    }
  }

  Future<void> _saveSettingString(String key, String value) async {
    // 1. Save locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);

    // 2. Sync to backend
    if (mounted) {
      try {
        await context.read<AuthProvider>().updateNotificationPreferences({
          key: value,
        });
      } catch (e) {
        debugPrint('Failed to sync setting $key: $e');
        // We don't block the UI or show error for background sync failures usually,
        // unless critical.
      }
    }
  }

  Future<void> _togglePushNotifications(bool value) async {
    setState(() {
      _settings = _settings.copyWith(pushEnabled: value);
    });
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
          // For doctors: reschedule daily summary if it was enabled
          if (authProvider.currentUser!.isDoctor &&
              _settings.dailySummary &&
              mounted) {
            context
                .read<DoctorAppointmentProvider>()
                .scheduleDailyNotifications();
          }
        } else {
          await notifProvider.disablePushNotifications(
            authProvider.currentUser!.id,
          );
          // For doctors: cancel daily summary when push is disabled
          if (authProvider.currentUser!.isDoctor) {
            await LocalNotificationService().cancelDoctorDailySummaries();
          }
        }
      }
    }
  }

  Future<void> _toggleEmailNotifications(bool value) async {
    setState(() {
      _settings = _settings.copyWith(emailEnabled: value);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('settings_email_notifications', value);

    if (mounted) {
      final authProvider = context.read<AuthProvider>();
      await authProvider.updateNotificationPreferences({
        'email_notifications': value,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final authProvider = context.watch<AuthProvider>();
    final isDoctor = authProvider.currentUser?.isDoctor ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationSettings), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Permission Warning Banner
                if (!_areNotificationsEnabled)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_off_outlined,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.systemNotificationsDisabled,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.tapToEnableInSettings,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Core Notification Methods Section
                _buildSectionHeader(
                  l10n.notificationSettings,
                  Icons.phone_iphone_rounded,
                ),
                _buildSettingCard(
                  isDark: isDark,
                  children: [
                    _buildSwitchTile(
                      title: l10n.pushNotifications,
                      subtitle: l10n.receiveAlertsOnDevice,
                      value: _settings.pushEnabled,
                      onChanged: _togglePushNotifications,
                    ),
                    if (isDoctor && _settings.pushEnabled) ...[
                      const Divider(height: 1),
                      _buildSubSwitchTile(
                        title: l10n.dailySummaryTitle,
                        subtitle: l10n.dailySummarySubtitle,
                        value: _settings.dailySummary,
                        onChanged: (value) async {
                          setState(() {
                            _settings = _settings.copyWith(dailySummary: value);
                          });
                          await _saveSetting('notif_daily_summary', value);
                          if (context.mounted) {
                            context
                                .read<DoctorAppointmentProvider>()
                                .scheduleDailyNotifications();
                          }
                        },
                      ),
                      if (_settings.dailySummary) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 0),
                            title: Text(l10n.summaryTime,
                                style: TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 14)),
                            subtitle: Text(l10n.summaryTimeSubtitle,
                                style: TextStyle(fontSize: 11)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Builder(
                                builder: (context) {
                                  final parts =
                                      _settings.dailySummaryTime.split(':');
                                  final hour = parts.isNotEmpty
                                      ? int.tryParse(parts[0]) ?? 21
                                      : 21;
                                  final minute = parts.length > 1
                                      ? int.tryParse(parts[1]) ?? 0
                                      : 0;
                                  final time =
                                      TimeOfDay(hour: hour, minute: minute);
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
                              final parts =
                                  _settings.dailySummaryTime.split(':');
                              final initialTime = TimeOfDay(
                                hour: parts.isNotEmpty
                                    ? int.tryParse(parts[0]) ?? 21
                                    : 21,
                                minute: parts.length > 1
                                    ? int.tryParse(parts[1]) ?? 0
                                    : 0,
                              );
                              final time = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                              );
                              if (time != null && mounted) {
                                final timeStr =
                                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                                setState(() {
                                  _settings = _settings.copyWith(
                                      dailySummaryTime: timeStr);
                                });
                                await _saveSettingString(
                                    'notif_daily_summary_time', timeStr);
                                if (context.mounted) {
                                  context
                                      .read<DoctorAppointmentProvider>()
                                      .scheduleDailyNotifications();
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                    if (!isDoctor && _settings.pushEnabled) ...[
                      const Divider(height: 1),
                      _buildSubSwitchTile(
                        title: l10n.appointmentReminders,
                        subtitle: l10n.receiveRemindersForUpcomingAppointments,
                        value: _settings.appointmentReminders,
                        onChanged: (value) async {
                          setState(() {
                            _settings = _settings.copyWith(
                              appointmentReminders: value,
                            );
                          });
                          await _saveSetting(
                            'notif_appointment_reminders',
                            value,
                          );
                        },
                      ),
                      if (_settings.appointmentReminders) ...[
                        const Divider(height: 1),
                        _buildSubSwitchTile(
                          title: l10n.weekReminder1,
                          subtitle: l10n.getNotified1WeekBefore,
                          value: _settings.reminder1Week,
                          onChanged: (value) async {
                            setState(() {
                              _settings = _settings.copyWith(
                                reminder1Week: value,
                              );
                            });
                            await _saveSetting('notif_reminder_1w', value);
                          },
                        ),
                        const Divider(height: 1),
                        _buildSubSwitchTile(
                          title: l10n.hourReminder24,
                          subtitle: l10n.getNotified24HoursBefore,
                          value: _settings.reminder24Hours,
                          onChanged: (value) async {
                            setState(() {
                              _settings = _settings.copyWith(
                                reminder24Hours: value,
                              );
                            });
                            await _saveSetting('notif_reminder_24h', value);
                          },
                        ),
                        const Divider(height: 1),
                        _buildSubSwitchTile(
                          title: l10n.hourReminder1,
                          subtitle: l10n.getNotified1HourBefore,
                          value: _settings.reminder1Hour,
                          onChanged: (value) async {
                            setState(() {
                              _settings = _settings.copyWith(
                                reminder1Hour: value,
                              );
                            });
                            await _saveSetting('notif_reminder_1h', value);
                          },
                        ),
                      ],
                    ],
                    const Divider(height: 1),
                    _buildSwitchTile(
                      title: l10n.emailNotifications,
                      subtitle: l10n.receiveSummariesViaEmail,
                      value: _settings.emailEnabled,
                      onChanged: _toggleEmailNotifications,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Sound & Vibration Section
                _buildSectionHeader(l10n.soundAndVibration, Icons.volume_up),
                _buildSettingCard(
                  isDark: isDark,
                  children: [
                    _buildSwitchTile(
                      title: l10n.sound,
                      subtitle: l10n.playSoundForNotifications,
                      value: _settings.soundEnabled,
                      onChanged: (value) async {
                        setState(() {
                          _settings = _settings.copyWith(soundEnabled: value);
                        });
                        await _saveSetting('notif_sound', value);
                      },
                    ),
                    const Divider(height: 1),
                    _buildSwitchTile(
                      title: l10n.vibration,
                      subtitle: l10n.vibrateForNotifications,
                      value: _settings.vibrationEnabled,
                      onChanged: (value) async {
                        setState(() {
                          _settings = _settings.copyWith(
                            vibrationEnabled: value,
                          );
                        });
                        await _saveSetting('notif_vibration', value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Test Notification Button
                OutlinedButton.icon(
                  onPressed: _sendTestNotification,
                  icon: const Icon(Icons.notifications_active),
                  label: Text(l10n.sendTestNotification),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Info Text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.info,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.manageNotificationPermissionsInSettings,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    // Use AppColors for cleaner look
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildSubSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    final l10n = AppLocalizations.of(context);
    try {
      await _notificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: l10n.testNotificationTitle,
        body: l10n.testNotificationBody,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.testNotificationSentSuccess),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
