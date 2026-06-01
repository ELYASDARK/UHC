import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../core/notifications/notification_preferences.dart';
import '../data/models/appointment_model.dart';
import 'local_notification_service.dart';

class NotificationSchedulingCoordinator {
  static final NotificationSchedulingCoordinator _instance =
      NotificationSchedulingCoordinator._internal();
  factory NotificationSchedulingCoordinator() => _instance;
  NotificationSchedulingCoordinator._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final LocalNotificationService _localNotificationService =
      LocalNotificationService();

  static const _dayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  Future<void> resyncAfterLogin(String userId) async {
    if (kIsWeb) return;
    await _resync(userId);
  }

  Future<void> resyncAfterSettingsChange(String userId) async {
    if (kIsWeb) return;
    await _resync(userId);
  }

  Future<void> resyncDoctorDailySummaryAfterSettingsChange(
      String doctorUserId) async {
    if (kIsWeb) return;

    try {
      await _ensureLocalNotificationsInitialized();
      await _localNotificationService.cancelDoctorDailySummaries();

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(doctorUserId)
          .get();
      final userData = userSnap.data();
      if (userData == null || userData['role'] != 'doctor') return;

      final prefsMap =
          userData['notificationSettings'] as Map<String, dynamic>?;
      final settings = NotificationPreferences.fromMap(
        prefsMap,
        isDoctor: true,
        isWeb: kIsWeb,
      );

      if (!settings.doctorDailySummaryEnabled ||
          settings.doctorDailySummaryDelivery !=
              NotificationDeliveryMode.local) {
        return;
      }

      final doctorSnap = await FirebaseFirestore.instance
          .collection('doctors')
          .where('userId', isEqualTo: doctorUserId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (doctorSnap.docs.isEmpty) return;

      final schedule = doctorSnap.docs.first.data()['weeklySchedule']
              as Map<String, dynamic>? ??
          const <String, dynamic>{};

      final timeParts = settings.doctorDailySummaryTime.split(':');
      var targetHour = 21;
      var targetMinute = 0;
      if (timeParts.length == 2) {
        targetHour = int.tryParse(timeParts[0]) ?? targetHour;
        targetMinute = int.tryParse(timeParts[1]) ?? targetMinute;
      }
      targetHour = targetHour.clamp(0, 23).toInt();
      targetMinute = targetMinute.clamp(0, 59).toInt();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
        final notificationDate = today.add(Duration(days: dayOffset));
        final scheduledTime = notificationDate.add(
          Duration(hours: targetHour, minutes: targetMinute),
        );
        if (!scheduledTime.isAfter(now)) continue;

        final targetDate = notificationDate.add(const Duration(days: 1));
        final daySlots = schedule[_dayNames[targetDate.weekday - 1]];
        final hasSlots = daySlots is Iterable && daySlots.isNotEmpty;
        if (!hasSlots) continue;

        await _localNotificationService.scheduleDoctorDailySummary(
          dayOffset: dayOffset,
          title: "Tomorrow's UHC Schedule",
          body: "Open UHC to review tomorrow's schedule.",
          scheduledTime: scheduledTime,
        );
      }
    } catch (e, stack) {
      debugPrint(
          '[NotificationSchedulingCoordinator] Error resyncing doctor daily summary: $e');
      try {
        FirebaseCrashlytics.instance.recordError(e, stack,
            reason: 'Doctor Daily Summary Local Resync Failed');
      } catch (_) {}
    }
  }

  Future<void> _resync(String userId) async {
    if (kIsWeb) return;
    try {
      debugPrint(
          '[NotificationSchedulingCoordinator] Calling resyncUserNotificationSchedules for $userId');
      final callable =
          _functions.httpsCallable('resyncUserNotificationSchedules');
      final response = await callable.call<Map<String, dynamic>>({
        'userId': userId,
      });

      final data = response.data;
      final bool localScheduleRequired = data['localScheduleRequired'] ?? false;
      final appointments = data['appointments'] as List<dynamic>? ?? [];

      await _ensureLocalNotificationsInitialized();
      await _cancelPendingAppointmentReminders();

      if (localScheduleRequired) {
        debugPrint(
            '[NotificationSchedulingCoordinator] Local scheduling required. Scheduling ${appointments.length} appointments.');
        for (final appt in appointments) {
          final appointmentId = appt['appointmentId'] as String;
          final doctorName = appt['doctorName'] as String;
          final timeSlot = appt['timeSlot'] as String;
          final reminders = appt['reminders'] as Map<dynamic, dynamic>? ?? {};

          if (reminders['oneWeek'] != null) {
            final time = DateTime.parse(reminders['oneWeek']);
            if (time.isAfter(DateTime.now())) {
              final payload = jsonEncode({
                'type': 'appointment_reminder',
                'appointmentId': appointmentId,
                'reminderType': 'oneWeek',
              });
              await _localNotificationService.scheduleNotification(
                id: _localNotificationService.stableReminderId(
                    appointmentId, 'oneWeek'),
                title: 'Appointment in 1 Week',
                body:
                    'Reminder: Your appointment with Dr. $doctorName is in 1 week at $timeSlot',
                scheduledTime: time,
                payload: payload,
              );
            }
          }

          if (reminders['oneDay'] != null) {
            final time = DateTime.parse(reminders['oneDay']);
            if (time.isAfter(DateTime.now())) {
              final payload = jsonEncode({
                'type': 'appointment_reminder',
                'appointmentId': appointmentId,
                'reminderType': 'oneDay',
              });
              await _localNotificationService.scheduleNotification(
                id: _localNotificationService.stableReminderId(
                    appointmentId, 'oneDay'),
                title: 'Appointment Tomorrow',
                body:
                    'Your appointment with Dr. $doctorName is tomorrow at $timeSlot. Please arrive 10 minutes early.',
                scheduledTime: time,
                payload: payload,
              );
            }
          }

          if (reminders['oneHour'] != null) {
            final time = DateTime.parse(reminders['oneHour']);
            if (time.isAfter(DateTime.now())) {
              final payload = jsonEncode({
                'type': 'appointment_reminder',
                'appointmentId': appointmentId,
                'reminderType': 'oneHour',
              });
              await _localNotificationService.scheduleNotification(
                id: _localNotificationService.stableReminderId(
                    appointmentId, 'oneHour'),
                title: 'Appointment in 1 Hour',
                body:
                    'Your appointment with Dr. $doctorName is in 1 hour at $timeSlot. Time to get ready!',
                scheduledTime: time,
                payload: payload,
              );
            }
          }
        }
      } else {
        debugPrint(
            '[NotificationSchedulingCoordinator] Local scheduling NOT required.');
      }
    } catch (e, stack) {
      debugPrint('[NotificationSchedulingCoordinator] Error during resync: $e');
      try {
        FirebaseCrashlytics.instance.recordError(e, stack,
            reason: 'Notification Scheduling Resync Failed');
      } catch (_) {}
    }
  }

  Future<void> scheduleLocalAppointmentReminders(
      AppointmentModel appointment) async {
    if (kIsWeb) return;

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(appointment.patientId)
          .get();
      final userData = userSnap.data();
      final isDoctor = userData?['role'] == 'doctor';
      final prefsMap =
          userData?['notificationSettings'] as Map<String, dynamic>?;
      final settings = NotificationPreferences.fromMap(prefsMap,
          isDoctor: isDoctor, isWeb: kIsWeb);

      if (!settings.appointmentRemindersEnabled) return;
      if (settings.appointmentReminderDelivery !=
          NotificationDeliveryMode.local) {
        return;
      }

      await _ensureLocalNotificationsInitialized();
      final appointmentTime = appointment.exactAppointmentTime;
      final appointmentId = appointment.id;
      final doctorName = appointment.doctorName;
      final timeSlot = appointment.timeSlot;

      if (settings.reminderOneWeek) {
        final time = appointmentTime.subtract(const Duration(days: 7));
        if (time.isAfter(DateTime.now())) {
          final payload = jsonEncode({
            'type': 'appointment_reminder',
            'appointmentId': appointmentId,
            'reminderType': 'oneWeek',
          });
          await _localNotificationService.scheduleNotification(
            id: _localNotificationService.stableReminderId(
                appointmentId, 'oneWeek'),
            title: 'Appointment in 1 Week',
            body:
                'Reminder: Your appointment with Dr. $doctorName is in 1 week at $timeSlot',
            scheduledTime: time,
            payload: payload,
          );
        }
      }

      if (settings.reminderOneDay) {
        final time = appointmentTime.subtract(const Duration(hours: 24));
        if (time.isAfter(DateTime.now())) {
          final payload = jsonEncode({
            'type': 'appointment_reminder',
            'appointmentId': appointmentId,
            'reminderType': 'oneDay',
          });
          await _localNotificationService.scheduleNotification(
            id: _localNotificationService.stableReminderId(
                appointmentId, 'oneDay'),
            title: 'Appointment Tomorrow',
            body:
                'Your appointment with Dr. $doctorName is tomorrow at $timeSlot. Please arrive 10 minutes early.',
            scheduledTime: time,
            payload: payload,
          );
        }
      }

      if (settings.reminderOneHour) {
        final time = appointmentTime.subtract(const Duration(hours: 1));
        if (time.isAfter(DateTime.now())) {
          final payload = jsonEncode({
            'type': 'appointment_reminder',
            'appointmentId': appointmentId,
            'reminderType': 'oneHour',
          });
          await _localNotificationService.scheduleNotification(
            id: _localNotificationService.stableReminderId(
                appointmentId, 'oneHour'),
            title: 'Appointment in 1 Hour',
            body:
                'Your appointment with Dr. $doctorName is in 1 hour at $timeSlot. Time to get ready!',
            scheduledTime: time,
            payload: payload,
          );
        }
      }
    } catch (e, stack) {
      debugPrint(
          '[NotificationSchedulingCoordinator] Error scheduling single appt reminders: $e');
      try {
        FirebaseCrashlytics.instance.recordError(e, stack,
            reason: 'Single Appointment Local Scheduling Failed');
      } catch (_) {}
    }
  }

  Future<void> cancelLocalAppointmentReminders(String appointmentId) async {
    if (kIsWeb) return;
    await _ensureLocalNotificationsInitialized();
    await _localNotificationService.cancelAppointmentReminders(appointmentId);
  }

  Future<void> cancelAllLocalReminders() async {
    if (kIsWeb) return;
    await _ensureLocalNotificationsInitialized();
    await _localNotificationService.cancelAllNotifications();
  }

  Future<void> _cancelPendingAppointmentReminders() async {
    await _ensureLocalNotificationsInitialized();
    final pending = await _localNotificationService.getPendingNotifications();

    for (final request in pending) {
      final payload = request.payload;
      if (payload == null || payload.isEmpty) continue;

      try {
        final data = jsonDecode(payload);
        if (data is Map && data['type'] == 'appointment_reminder') {
          await _localNotificationService.cancelNotification(request.id);
        }
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> _ensureLocalNotificationsInitialized() async {
    if (kIsWeb) return;
    await _localNotificationService.initialize();
  }
}
