import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../services/local_notification_service.dart';
import '../../l10n/app_localizations.dart';

/// Notification settings model
class NotificationSettings {
  final bool appointmentReminders;
  final bool reminder24Hours;
  final bool reminder1Hour;
  final bool promotionalNotifications;
  final bool healthTips;
  final bool doctorUpdates;
  final bool soundEnabled;
  final bool vibrationEnabled;

  NotificationSettings({
    this.appointmentReminders = true,
    this.reminder24Hours = true,
    this.reminder1Hour = true,
    this.promotionalNotifications = false,
    this.healthTips = true,
    this.doctorUpdates = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  NotificationSettings copyWith({
    bool? appointmentReminders,
    bool? reminder24Hours,
    bool? reminder1Hour,
    bool? promotionalNotifications,
    bool? healthTips,
    bool? doctorUpdates,
    bool? soundEnabled,
    bool? vibrationEnabled,
  }) {
    return NotificationSettings(
      appointmentReminders: appointmentReminders ?? this.appointmentReminders,
      reminder24Hours: reminder24Hours ?? this.reminder24Hours,
      reminder1Hour: reminder1Hour ?? this.reminder1Hour,
      promotionalNotifications:
          promotionalNotifications ?? this.promotionalNotifications,
      healthTips: healthTips ?? this.healthTips,
      doctorUpdates: doctorUpdates ?? this.doctorUpdates,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
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
  final LocalNotificationService _notificationService =
      LocalNotificationService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _settings = NotificationSettings(
        appointmentReminders:
            prefs.getBool('notif_appointment_reminders') ?? true,
        reminder24Hours: prefs.getBool('notif_reminder_24h') ?? true,
        reminder1Hour: prefs.getBool('notif_reminder_1h') ?? true,
        promotionalNotifications: prefs.getBool('notif_promotional') ?? false,
        healthTips: prefs.getBool('notif_health_tips') ?? true,
        doctorUpdates: prefs.getBool('notif_doctor_updates') ?? true,
        soundEnabled: prefs.getBool('notif_sound') ?? true,
        vibrationEnabled: prefs.getBool('notif_vibration') ?? true,
      );
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationSettings), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Appointment Notifications Section
                _buildSectionHeader(
                  l10n.appointmentNotifications,
                  Icons.calendar_today,
                ),
                _buildSettingCard(
                  isDark: isDark,
                  children: [
                    _buildSwitchTile(
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
                ),
                const SizedBox(height: 16),

                // Updates Section
                _buildSectionHeader(
                  l10n.updatesAndTips,
                  Icons.lightbulb_outline,
                ),
                _buildSettingCard(
                  isDark: isDark,
                  children: [
                    _buildSwitchTile(
                      title: l10n.healthTipsNotification,
                      subtitle: l10n.dailyHealthTipsAndWellnessAdvice,
                      value: _settings.healthTips,
                      onChanged: (value) async {
                        setState(() {
                          _settings = _settings.copyWith(healthTips: value);
                        });
                        await _saveSetting('notif_health_tips', value);
                      },
                    ),
                    const Divider(height: 1),
                    _buildSwitchTile(
                      title: l10n.doctorUpdates,
                      subtitle: l10n.updatesFromYourDoctors,
                      value: _settings.doctorUpdates,
                      onChanged: (value) async {
                        setState(() {
                          _settings = _settings.copyWith(doctorUpdates: value);
                        });
                        await _saveSetting('notif_doctor_updates', value);
                      },
                    ),
                    const Divider(height: 1),
                    _buildSwitchTile(
                      title: l10n.promotionalNotifications,
                      subtitle: l10n.specialOffersAndPromotions,
                      value: _settings.promotionalNotifications,
                      onChanged: (value) async {
                        setState(() {
                          _settings = _settings.copyWith(
                            promotionalNotifications: value,
                          );
                        });
                        await _saveSetting('notif_promotional', value);
                      },
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
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.white; // Active thumb - white
        }
        return const Color(0xFF1A1A1A); // Inactive thumb - black
      }),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF42A5F5); // Active track - blue
        }
        return const Color(0xFFF5F5F5); // Inactive track - white/very light
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent; // No outline when active
        }
        return const Color(0xFFBDBDBD); // Gray outline when inactive
      }),
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
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white; // Active thumb - white
          }
          return const Color(0xFF1A1A1A); // Inactive thumb - black
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF42A5F5); // Active track - blue
          }
          return const Color(0xFFF5F5F5); // Inactive track - white/very light
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent; // No outline when active
          }
          return const Color(0xFFBDBDBD); // Gray outline when inactive
        }),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    try {
      await _notificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: 'Test Notification',
        body: 'This is a test notification from UHC App!',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test notification sent!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
