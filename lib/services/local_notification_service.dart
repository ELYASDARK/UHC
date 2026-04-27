import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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

  // Callback for notification taps
  Function(String? payload)? onNotificationTap;

  /// Initialize the notification service
  Future<void> initialize({Function(String? payload)? onTap}) async {
    onNotificationTap = onTap;

    // Initialize timezone
    tz_data.initializeTimeZones();

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
  }

  /// Create Android notification channels
  Future<void> _createNotificationChannels() async {
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
    }
  }

  /// Handle notification tap
  void _onNotificationResponse(NotificationResponse response) {
    onNotificationTap?.call(response.payload);
  }

  /// Request notification permissions (iOS)
  Future<bool> requestPermissions() async {
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
        // Exact alarm permission not available or denied, will use inexact scheduling
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

      await _notifications.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledTz,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      debugPrint('Notification scheduled successfully with ID: $id');
    } catch (e, stack) {
      // If scheduling fails, log and continue gracefully.
      // Do NOT rethrow – the appointment is already created, and crashing here
      // would cause the user to see an error and potentially retry, creating
      // duplicate appointments.
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
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notif_appointment_reminders') == false) return;
    if (prefs.getBool('notif_reminder_1w') == false) return;

    final reminderTime = appointmentTime.subtract(const Duration(days: 7));

    if (reminderTime.isAfter(DateTime.now())) {
      final payload = jsonEncode({
        'type': 'appointment_reminder',
        'appointmentId': appointmentId,
        'reminderType': 'oneWeek',
      });

      await scheduleNotification(
        id: appointmentId.hashCode,
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
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notif_appointment_reminders') == false) return;
    if (prefs.getBool('notif_reminder_24h') == false) return;

    final reminderTime = appointmentTime.subtract(const Duration(hours: 24));

    if (reminderTime.isAfter(DateTime.now())) {
      final payload = jsonEncode({
        'type': 'appointment_reminder',
        'appointmentId': appointmentId,
        'reminderType': 'oneDay',
      });

      await scheduleNotification(
        id: appointmentId.hashCode + 1, // Different ID for 1 day reminder
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
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notif_appointment_reminders') == false) return;
    if (prefs.getBool('notif_reminder_1h') == false) return;

    final reminderTime = appointmentTime.subtract(const Duration(hours: 1));

    if (reminderTime.isAfter(DateTime.now())) {
      final payload = jsonEncode({
        'type': 'appointment_reminder',
        'appointmentId': appointmentId,
        'reminderType': 'oneHour',
      });

      await scheduleNotification(
        id: appointmentId.hashCode + 2, // Different ID for 1 hour reminder
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
    await _notifications.cancel(id: id);
  }

  /// Cancel all appointment reminders (all 3: 1 week, 1 day, 1 hour)
  Future<void> cancelAppointmentReminders(String appointmentId) async {
    await cancelNotification(appointmentId.hashCode); // 1 week reminder
    await cancelNotification(appointmentId.hashCode + 1); // 1 day reminder
    await cancelNotification(appointmentId.hashCode + 2); // 1 hour reminder
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Get pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
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
      // Ignore Crashlytics secondary failures.
    }
  }
}
