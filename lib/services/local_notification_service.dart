import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

/// Local notifications service for scheduling and displaying notifications
class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Notification channels
  static const String _appointmentChannelId = 'appointment_reminders';
  static const String _appointmentChannelName = 'Appointment Reminders';
  static const String _generalChannelId = 'general_notifications';
  static const String _generalChannelName = 'General Notifications';
  static const String _backendChannelId = 'uhc_notifications';
  static const String _backendChannelName = 'UHC Notifications';

  // Callback for notification taps
  Function(String? payload)? onNotificationTap;
  bool _isInitialized = false;

  /// Generate deterministic stable notification IDs instead of using hashCode.
  int stableReminderId(String appointmentId, String reminderType) {
    final input = '$appointmentId:$reminderType';
    var hash = 0;
    for (final codeUnit in input.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash;
  }

  /// Initialize timezone helper
  Future<void> _configureLocalTimeZone() async {
    if (kIsWeb) return;

    tz_data.initializeTimeZones();

    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      final timeZoneName = tzInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Baghdad'));
      } catch (e) {
        debugPrint('Fallback timezone setting failed: $e');
      }
    }
  }

  /// Check if exact alarm scheduling is allowed on Android
  Future<bool> canScheduleExactAlarms() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        return await androidPlugin.canScheduleExactNotifications() ?? false;
      }
    }
    return true;
  }

  /// Initialize the notification service
  Future<void> initialize({Function(String? payload)? onTap}) async {
    if (kIsWeb) return;
    onNotificationTap = onTap;

    // Initialize timezone
    await _configureLocalTimeZone();

    // Android settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channels for Android
    await _createNotificationChannels();
    _isInitialized = true;
  }

  /// Create Android notification channels
  Future<void> _createNotificationChannels() async {
    if (kIsWeb) return;
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Appointment reminders channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _appointmentChannelId,
          _appointmentChannelName,
          description: 'Reminders for upcoming appointments',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      // General notifications channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _generalChannelId,
          _generalChannelName,
          description: 'General app notifications',
          importance: Importance.defaultImportance,
        ),
      );

      // Backend FCM payloads target this channel ID.
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _backendChannelId,
          _backendChannelName,
          description: 'Notifications delivered by University Health Center',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
  }

  /// Handle notification tap
  void _onNotificationResponse(NotificationResponse response) {
    onNotificationTap?.call(response.payload);
  }

  /// Request notification permissions (iOS / Android)
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    if (iosPlugin != null) {
      return await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Request notification permission
      final notificationGranted =
          (await androidPlugin.requestNotificationsPermission()) ?? false;

      // Request exact alarm permission for Android 12+ (optional, will use inexact if denied)
      try {
        await androidPlugin.requestExactAlarmsPermission();
      } catch (e) {
        debugPrint('Exact alarm permission not granted: $e');
      }

      return notificationGranted;
    }

    return true;
  }

  /// Show immediate notification
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool isAppointment = false,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool('notif_sound') ?? true;
    final vibrationEnabled = prefs.getBool('notif_vibration') ?? true;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isAppointment ? _appointmentChannelId : _generalChannelId,
        isAppointment ? _appointmentChannelName : _generalChannelName,
        importance:
            isAppointment ? Importance.high : Importance.defaultImportance,
        priority: isAppointment ? Priority.high : Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: soundEnabled,
      ),
    );

    await _notifications.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload);
  }

  /// Schedule a notification for a specific time
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    bool isAppointment = true,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final soundEnabled = prefs.getBool('notif_sound') ?? true;
    final vibrationEnabled = prefs.getBool('notif_vibration') ?? true;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        isAppointment ? _appointmentChannelId : _generalChannelId,
        isAppointment ? _appointmentChannelName : _generalChannelName,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: soundEnabled,
      ),
    );

    try {
      final scheduledTz = tz.TZDateTime.from(scheduledTime, tz.local);
      debugPrint(
        'Scheduling notification for: $scheduledTz (in ${scheduledTime.difference(DateTime.now()).inSeconds} seconds)',
      );

      try {
        await _notifications.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledTz,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: payload,
        );
      } catch (_) {
        await _notifications.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledTz,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      }

      debugPrint('Notification scheduled successfully with ID: $id');
    } catch (e, stack) {
      debugPrint('Failed to schedule notification: $e');
      _recordError(e, stack, reason: 'Scheduling Notification Failed');
    }
  }

  /// Schedule appointment reminder (1 week before)
  Future<void> scheduleAppointmentReminder1Week({
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    required String timeSlot,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    // Support version 2 check if available, otherwise fallback
    final apptRemindersEnabled = prefs.getBool('notif_appointment_reminders') ?? true;
    final oneWeekEnabled = prefs.getBool('notif_reminder_1w') ?? true;
    if (!apptRemindersEnabled || !oneWeekEnabled) return;

    final reminderTime = appointmentTime.subtract(const Duration(days: 7));

    if (reminderTime.isAfter(DateTime.now())) {
      final payload = jsonEncode({
        'type': 'appointment_reminder',
        'appointmentId': appointmentId,
        'reminderType': 'oneWeek',
      });

      await scheduleNotification(
        id: stableReminderId(appointmentId, 'oneWeek'),
        title: 'Appointment in 1 Week',
        body:
            'Reminder: Your appointment with Dr. $doctorName is in 1 week at $timeSlot',
        scheduledTime: reminderTime,
        payload: payload,
      );
    }
  }

  /// Schedule appointment reminder (1 day / 24 hours before)
  Future<void> scheduleAppointmentReminder1Day({
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    required String timeSlot,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final apptRemindersEnabled = prefs.getBool('notif_appointment_reminders') ?? true;
    final oneDayEnabled = prefs.getBool('notif_reminder_24h') ?? true;
    if (!apptRemindersEnabled || !oneDayEnabled) return;

    final reminderTime = appointmentTime.subtract(const Duration(hours: 24));

    if (reminderTime.isAfter(DateTime.now())) {
      final payload = jsonEncode({
        'type': 'appointment_reminder',
        'appointmentId': appointmentId,
        'reminderType': 'oneDay',
      });

      await scheduleNotification(
        id: stableReminderId(appointmentId, 'oneDay'),
        title: 'Appointment Tomorrow',
        body:
            'Your appointment with Dr. $doctorName is tomorrow at $timeSlot. Please arrive 10 minutes early.',
        scheduledTime: reminderTime,
        payload: payload,
      );
    }
  }

  /// Schedule appointment reminder (1 hour before)
  Future<void> scheduleAppointmentReminder1Hour({
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    required String timeSlot,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final apptRemindersEnabled = prefs.getBool('notif_appointment_reminders') ?? true;
    final oneHourEnabled = prefs.getBool('notif_reminder_1h') ?? true;
    if (!apptRemindersEnabled || !oneHourEnabled) return;

    final reminderTime = appointmentTime.subtract(const Duration(hours: 1));

    if (reminderTime.isAfter(DateTime.now())) {
      final payload = jsonEncode({
        'type': 'appointment_reminder',
        'appointmentId': appointmentId,
        'reminderType': 'oneHour',
      });

      await scheduleNotification(
        id: stableReminderId(appointmentId, 'oneHour'),
        title: 'Appointment in 1 Hour',
        body:
            'Your appointment with Dr. $doctorName is in 1 hour at $timeSlot. Time to get ready!',
        scheduledTime: reminderTime,
        payload: payload,
      );
    }
  }

  /// Schedule all 3 reminders for an appointment (1 week, 1 day, 1 hour before)
  Future<void> scheduleAppointmentReminders({
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    required String timeSlot,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final localEnabled = prefs.getBool('notif_local_reminders') ?? true;
    if (!localEnabled) {
      debugPrint('Local reminders are disabled by user settings. Skipping local scheduling.');
      return;
    }

    // Schedule 1 week before reminder
    await scheduleAppointmentReminder1Week(
      appointmentId: appointmentId,
      doctorName: doctorName,
      appointmentTime: appointmentTime,
      timeSlot: timeSlot,
    );

    // Schedule 1 day before reminder
    await scheduleAppointmentReminder1Day(
      appointmentId: appointmentId,
      doctorName: doctorName,
      appointmentTime: appointmentTime,
      timeSlot: timeSlot,
    );

    // Schedule 1 hour before reminder
    await scheduleAppointmentReminder1Hour(
      appointmentId: appointmentId,
      doctorName: doctorName,
      appointmentTime: appointmentTime,
      timeSlot: timeSlot,
    );
  }

  /// Cancel a scheduled notification
  Future<void> cancelNotification(int id) async {
    if (kIsWeb || !_isInitialized) return;
    await _notifications.cancel(id: id);
  }

  /// Cancel all appointment reminders (all 3: 1 week, 1 day, 1 hour)
  Future<void> cancelAppointmentReminders(String appointmentId) async {
    if (kIsWeb) return;
    await cancelNotification(stableReminderId(appointmentId, 'oneWeek')); // 1 week reminder
    await cancelNotification(stableReminderId(appointmentId, 'oneDay')); // 1 day reminder
    await cancelNotification(stableReminderId(appointmentId, 'oneHour')); // 1 hour reminder
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    if (kIsWeb || !_isInitialized) return;
    await _notifications.cancelAll();
  }

  /// Get pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (kIsWeb || !_isInitialized) return const [];
    return await _notifications.pendingNotificationRequests();
  }

  // ── Doctor Daily Summary Notifications ──

  /// Base notification ID for doctor daily summaries (7 IDs: 900000–900006).
  static const int _doctorDailySummaryBaseId = 900000;

  /// Schedule a single doctor daily summary local notification.
  Future<void> scheduleDoctorDailySummary({
    required int dayOffset,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (kIsWeb) return;
    await scheduleNotification(
      id: _doctorDailySummaryBaseId + dayOffset,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      payload: jsonEncode({'type': 'daily_summary'}),
      isAppointment: true,
    );
  }

  /// Cancel all 7 doctor daily summary notifications.
  Future<void> cancelDoctorDailySummaries() async {
    if (kIsWeb) return;
    for (int i = 0; i < 7; i++) {
      await cancelNotification(_doctorDailySummaryBaseId + i);
    }
  }

  void _recordError(
    Object error,
    StackTrace stack, {
    required String reason,
  }) {
    if (kIsWeb) return;
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
    } catch (_) {
      // Ignore Crashlytics failures.
    }
  }
}
