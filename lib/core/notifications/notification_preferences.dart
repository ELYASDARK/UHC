enum NotificationDeliveryMode {
  fcm,
  local,
}

enum NotificationPlatform {
  android,
  ios,
  web,
  macos,
  windows,
  linux,
  unknown,
}

class NotificationPreferences {
  final int version;
  final bool onlinePushEnabled;

  final bool appointmentStatusAlertsEnabled;
  final bool appointmentStatusAlertsLocked;

  final bool adminAnnouncementsEnabled;

  final bool appointmentRemindersEnabled;
  final NotificationDeliveryMode appointmentReminderDelivery;
  final bool reminderOneWeek;
  final bool reminderOneDay;
  final bool reminderOneHour;

  final bool doctorDailySummaryEnabled;
  final NotificationDeliveryMode doctorDailySummaryDelivery;
  final String doctorDailySummaryTime;

  final bool emailEnabled;

  const NotificationPreferences({
    required this.version,
    required this.onlinePushEnabled,
    required this.appointmentStatusAlertsEnabled,
    required this.appointmentStatusAlertsLocked,
    required this.adminAnnouncementsEnabled,
    required this.appointmentRemindersEnabled,
    required this.appointmentReminderDelivery,
    required this.reminderOneWeek,
    required this.reminderOneDay,
    required this.reminderOneHour,
    required this.doctorDailySummaryEnabled,
    required this.doctorDailySummaryDelivery,
    required this.doctorDailySummaryTime,
    required this.emailEnabled,
  });

  factory NotificationPreferences.fromMap(
    Map<String, dynamic>? map, {
    required bool isDoctor,
    required bool isWeb,
  }) {
    if (map == null || map['version'] != 2) {
      final push = map?['push'] ?? map?['settings_push_notifications'] ?? true;
      final email = map?['email'] ?? map?['email_notifications'] ?? map?['settings_email_notifications'] ?? false;
      final apptReminders = map?['notif_appointment_reminders'] ?? !isDoctor;
      final oneWeek = map?['notif_reminder_1w'] ?? !isDoctor;
      final oneDay = map?['notif_reminder_24h'] ?? !isDoctor;
      final oneHour = map?['notif_reminder_1h'] ?? !isDoctor;
      final dailySummary = map?['notif_daily_summary'] ?? isDoctor;
      final dailySummaryTime = map?['notif_daily_summary_time'] ?? '21:00';

      return NotificationPreferences(
        version: 2,
        onlinePushEnabled: push,
        appointmentStatusAlertsEnabled: true,
        appointmentStatusAlertsLocked: true,
        adminAnnouncementsEnabled: true,
        appointmentRemindersEnabled: apptReminders,
        appointmentReminderDelivery: NotificationDeliveryMode.fcm,
        reminderOneWeek: oneWeek,
        reminderOneDay: oneDay,
        reminderOneHour: oneHour,
        doctorDailySummaryEnabled: dailySummary,
        doctorDailySummaryDelivery: NotificationDeliveryMode.fcm,
        doctorDailySummaryTime: dailySummaryTime,
        emailEnabled: email,
      );
    }

    final remindersMap = map['appointmentReminders'] as Map<dynamic, dynamic>? ?? {};
    final summaryMap = map['doctorDailySummary'] as Map<dynamic, dynamic>? ?? {};
    final statusMap = map['appointmentStatusAlerts'] as Map<dynamic, dynamic>? ?? {};
    final adminMap = map['adminAnnouncements'] as Map<dynamic, dynamic>? ?? {};

    var reminderDelivery = _parseDeliveryMode(remindersMap['delivery']);
    var summaryDelivery = _parseDeliveryMode(summaryMap['delivery']);

    if (isWeb) {
      reminderDelivery = NotificationDeliveryMode.fcm;
      summaryDelivery = NotificationDeliveryMode.fcm;
    }

    return NotificationPreferences(
      version: 2,
      onlinePushEnabled: map['onlinePushEnabled'] ?? true,
      appointmentStatusAlertsEnabled: statusMap['enabled'] ?? true,
      appointmentStatusAlertsLocked: statusMap['locked'] ?? true,
      adminAnnouncementsEnabled: adminMap['enabled'] ?? true,
      appointmentRemindersEnabled: remindersMap['enabled'] ?? !isDoctor,
      appointmentReminderDelivery: reminderDelivery,
      reminderOneWeek: remindersMap['oneWeek'] ?? !isDoctor,
      reminderOneDay: remindersMap['oneDay'] ?? !isDoctor,
      reminderOneHour: remindersMap['oneHour'] ?? !isDoctor,
      doctorDailySummaryEnabled: summaryMap['enabled'] ?? isDoctor,
      doctorDailySummaryDelivery: summaryDelivery,
      doctorDailySummaryTime: summaryMap['time'] ?? '21:00',
      emailEnabled: map['email'] ?? false,
    );
  }

  static NotificationDeliveryMode _parseDeliveryMode(dynamic value) {
    if (value == 'local') return NotificationDeliveryMode.local;
    return NotificationDeliveryMode.fcm;
  }

  Map<String, dynamic> toMap() {
    return {
      'version': 2,
      'onlinePushEnabled': onlinePushEnabled,
      'appointmentStatusAlerts': {
        'enabled': appointmentStatusAlertsEnabled,
        'locked': appointmentStatusAlertsLocked,
      },
      'adminAnnouncements': {
        'enabled': adminAnnouncementsEnabled,
      },
      'appointmentReminders': {
        'enabled': appointmentRemindersEnabled,
        'delivery': appointmentReminderDelivery.name,
        'oneWeek': reminderOneWeek,
        'oneDay': reminderOneDay,
        'oneHour': reminderOneHour,
      },
      'doctorDailySummary': {
        'enabled': doctorDailySummaryEnabled,
        'delivery': doctorDailySummaryDelivery.name,
        'time': doctorDailySummaryTime,
      },
      'email': emailEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? onlinePushEnabled,
    bool? appointmentRemindersEnabled,
    NotificationDeliveryMode? appointmentReminderDelivery,
    bool? reminderOneWeek,
    bool? reminderOneDay,
    bool? reminderOneHour,
    bool? doctorDailySummaryEnabled,
    NotificationDeliveryMode? doctorDailySummaryDelivery,
    String? doctorDailySummaryTime,
    bool? emailEnabled,
    bool? adminAnnouncementsEnabled,
  }) {
    return NotificationPreferences(
      version: version,
      onlinePushEnabled: onlinePushEnabled ?? this.onlinePushEnabled,
      appointmentStatusAlertsEnabled: appointmentStatusAlertsEnabled,
      appointmentStatusAlertsLocked: appointmentStatusAlertsLocked,
      adminAnnouncementsEnabled: adminAnnouncementsEnabled ?? this.adminAnnouncementsEnabled,
      appointmentRemindersEnabled: appointmentRemindersEnabled ?? this.appointmentRemindersEnabled,
      appointmentReminderDelivery: appointmentReminderDelivery ?? this.appointmentReminderDelivery,
      reminderOneWeek: reminderOneWeek ?? this.reminderOneWeek,
      reminderOneDay: reminderOneDay ?? this.reminderOneDay,
      reminderOneHour: reminderOneHour ?? this.reminderOneHour,
      doctorDailySummaryEnabled: doctorDailySummaryEnabled ?? this.doctorDailySummaryEnabled,
      doctorDailySummaryDelivery: doctorDailySummaryDelivery ?? this.doctorDailySummaryDelivery,
      doctorDailySummaryTime: doctorDailySummaryTime ?? this.doctorDailySummaryTime,
      emailEnabled: emailEnabled ?? this.emailEnabled,
    );
  }
}
