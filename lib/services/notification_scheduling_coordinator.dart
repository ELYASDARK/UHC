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

  /// Resync reminders after login
  Future<void> resyncAfterLogin(String userId) async {
    if (kIsWeb) return;
    await _resync(userId);
  }

  /// Resync reminders after settings change
  Future<void> resyncAfterSettingsChange(String userId) async {
    if (kIsWeb) return;
    await _resync(userId);
  }

  /// Helper to trigger the resync cloud function and schedule local alarms
  Future<void> _resync(String userId) async {
    if (kIsWeb) return;
    try {
      debugPrint('[NotificationSchedulingCoordinator] Calling resyncUserNotificationSchedules for $userId');
      final callable = _functions.httpsCallable('resyncUserNotificationSchedules');
      final response = await callable.call<Map<String, dynamic>>({
        'userId': userId,
      });

      final data = response.data;
      final bool localScheduleRequired = data['localScheduleRequired'] ?? false;
      final appointments = data['appointments'] as List<dynamic>? ?? [];

      // First cancel all local notifications
      await _localNotificationService.cancelAllNotifications();

      // If user wants local notifications, schedule them
      if (localScheduleRequired) {
        debugPrint('[NotificationSchedulingCoordinator] Local scheduling required. Scheduling ${appointments.length} appointments.');
        for (final appt in appointments) {
          final appointmentId = appt['appointmentId'] as String;
          final doctorName = appt['doctorName'] as String;
          final timeSlot = appt['timeSlot'] as String;
          final reminders = appt['reminders'] as Map<dynamic, dynamic>? ?? {};

          // Schedule each active reminder
          if (reminders['oneWeek'] != null) {
            final time = DateTime.parse(reminders['oneWeek']);
            if (time.isAfter(DateTime.now())) {
              final payload = jsonEncode({
                'type': 'appointment_reminder',
                'appointmentId': appointmentId,
                'reminderType': 'oneWeek',
              });
              await _localNotificationService.scheduleNotification(
                id: _localNotificationService.stableReminderId(appointmentId, 'oneWeek'),
                title: 'Appointment in 1 Week',
                body: 'Reminder: Your appointment with Dr. $doctorName is in 1 week at $timeSlot',
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
                id: _localNotificationService.stableReminderId(appointmentId, 'oneDay'),
                title: 'Appointment Tomorrow',
                body: 'Your appointment with Dr. $doctorName is tomorrow at $timeSlot. Please arrive 10 minutes early.',
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
                id: _localNotificationService.stableReminderId(appointmentId, 'oneHour'),
                title: 'Appointment in 1 Hour',
                body: 'Your appointment with Dr. $doctorName is in 1 hour at $timeSlot. Time to get ready!',
                scheduledTime: time,
                payload: payload,
              );
            }
          }
        }
      } else {
        debugPrint('[NotificationSchedulingCoordinator] Local scheduling NOT required.');
      }
    } catch (e, stack) {
      debugPrint('[NotificationSchedulingCoordinator] Error during resync: $e');
      try {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Notification Scheduling Resync Failed');
      } catch (_) {}
    }
  }

  /// Schedule local reminders for a single appointment if user has local mode active.
  Future<void> scheduleLocalAppointmentReminders(AppointmentModel appointment) async {
    if (kIsWeb) return;

    try {
      final userSnap = await FirebaseFirestore.instance.collection('users').doc(appointment.patientId).get();
      final userData = userSnap.data();
      final isDoctor = userData?['role'] == 'doctor';
      final prefsMap = userData?['notificationSettings'] as Map<String, dynamic>?;
      final settings = NotificationPreferences.fromMap(prefsMap, isDoctor: isDoctor, isWeb: kIsWeb);

      if (!settings.appointmentRemindersEnabled) return;
      if (settings.appointmentReminderDelivery != NotificationDeliveryMode.local) return;

      final appointmentTime = appointment.exactAppointmentTime;
      final appointmentId = appointment.id;
      final doctorName = appointment.doctorName;
      final timeSlot = appointment.timeSlot;

      // 1 Week
      if (settings.reminderOneWeek) {
        final time = appointmentTime.subtract(const Duration(days: 7));
        if (time.isAfter(DateTime.now())) {
          final payload = jsonEncode({
            'type': 'appointment_reminder',
            'appointmentId': appointmentId,
            'reminderType': 'oneWeek',
          });
          await _localNotificationService.scheduleNotification(
            id: _localNotificationService.stableReminderId(appointmentId, 'oneWeek'),
            title: 'Appointment in 1 Week',
            body: 'Reminder: Your appointment with Dr. $doctorName is in 1 week at $timeSlot',
            scheduledTime: time,
            payload: payload,
          );
        }
      }

      // 1 Day
      if (settings.reminderOneDay) {
        final time = appointmentTime.subtract(const Duration(hours: 24));
        if (time.isAfter(DateTime.now())) {
          final payload = jsonEncode({
            'type': 'appointment_reminder',
            'appointmentId': appointmentId,
            'reminderType': 'oneDay',
          });
          await _localNotificationService.scheduleNotification(
            id: _localNotificationService.stableReminderId(appointmentId, 'oneDay'),
            title: 'Appointment Tomorrow',
            body: 'Your appointment with Dr. $doctorName is tomorrow at $timeSlot. Please arrive 10 minutes early.',
            scheduledTime: time,
            payload: payload,
          );
        }
      }

      // 1 Hour
      if (settings.reminderOneHour) {
        final time = appointmentTime.subtract(const Duration(hours: 1));
        if (time.isAfter(DateTime.now())) {
          final payload = jsonEncode({
            'type': 'appointment_reminder',
            'appointmentId': appointmentId,
            'reminderType': 'oneHour',
          });
          await _localNotificationService.scheduleNotification(
            id: _localNotificationService.stableReminderId(appointmentId, 'oneHour'),
            title: 'Appointment in 1 Hour',
            body: 'Your appointment with Dr. $doctorName is in 1 hour at $timeSlot. Time to get ready!',
            scheduledTime: time,
            payload: payload,
          );
        }
      }
    } catch (e, stack) {
      debugPrint('[NotificationSchedulingCoordinator] Error scheduling single appt reminders: $e');
      try {
        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Single Appointment Local Scheduling Failed');
      } catch (_) {}
    }
  }

  /// Cancel local reminders for a single appointment.
  Future<void> cancelLocalAppointmentReminders(String appointmentId) async {
    if (kIsWeb) return;
    await _localNotificationService.cancelAppointmentReminders(appointmentId);
  }

  /// Cancel all local notifications on this device.
  Future<void> cancelAllLocalReminders() async {
    if (kIsWeb) return;
    await _localNotificationService.cancelAllNotifications();
  }
}
