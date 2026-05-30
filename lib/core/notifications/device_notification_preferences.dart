import 'package:flutter/foundation.dart';
import 'notification_preferences.dart';

class DeviceNotificationPreferences {
  final String platform;
  final bool supportsLocalReminders;
  final bool onlinePushEnabled;
  final NotificationDeliveryMode appointmentReminderDelivery;
  final NotificationDeliveryMode doctorDailySummaryDelivery;
  final String? timeZone;

  const DeviceNotificationPreferences({
    required this.platform,
    required this.supportsLocalReminders,
    required this.onlinePushEnabled,
    required this.appointmentReminderDelivery,
    required this.doctorDailySummaryDelivery,
    this.timeZone,
  });

  factory DeviceNotificationPreferences.current({
    required bool onlinePushEnabled,
    required NotificationDeliveryMode requestedAppointmentDelivery,
    required NotificationDeliveryMode requestedSummaryDelivery,
    String? timeZone,
  }) {
    final isWeb = kIsWeb;
    String platformName = 'unknown';
    bool supportsLocal = false;

    if (isWeb) {
      platformName = 'web';
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          platformName = 'android';
          supportsLocal = true;
          break;
        case TargetPlatform.iOS:
          platformName = 'ios';
          supportsLocal = true;
          break;
        case TargetPlatform.macOS:
          platformName = 'macos';
          break;
        case TargetPlatform.windows:
          platformName = 'windows';
          break;
        case TargetPlatform.linux:
          platformName = 'linux';
          break;
        default:
          platformName = 'unknown';
      }
    }

    final effectiveAppointmentDelivery = isWeb ? NotificationDeliveryMode.fcm : requestedAppointmentDelivery;
    final effectiveSummaryDelivery = isWeb ? NotificationDeliveryMode.fcm : requestedSummaryDelivery;

    return DeviceNotificationPreferences(
      platform: platformName,
      supportsLocalReminders: supportsLocal,
      onlinePushEnabled: onlinePushEnabled,
      appointmentReminderDelivery: effectiveAppointmentDelivery,
      doctorDailySummaryDelivery: effectiveSummaryDelivery,
      timeZone: timeZone,
    );
  }
}
