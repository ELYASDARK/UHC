import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

/// Repository for notification-related Firestore operations
class NotificationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'notifications';

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      _firestore.collection(_collection);

  /// Get user's notifications (only delivered ones)
  Future<List<NotificationModel>> getUserNotifications(
    String userId, {
    int limit = 50,
  }) async {
    final now = DateTime.now();
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    // Filter to show only delivered notifications or those scheduled for now/past
    return snapshot.docs
        .map((doc) => NotificationModel.fromFirestore(doc))
        .where((notification) {
          // Show immediate notifications or scheduled ones that are due
          if (notification.scheduledFor == null) return true;
          return notification.scheduledFor!.isBefore(now) ||
              notification.scheduledFor!.isAtSameMomentAs(now);
        })
        .toList();
  }

  /// Get unread notifications count (only for delivered notifications)
  Future<int> getUnreadCount(String userId) async {
    final now = DateTime.now();
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    // Count only delivered notifications
    return snapshot.docs
        .map((doc) => NotificationModel.fromFirestore(doc))
        .where((notification) {
          if (notification.scheduledFor == null) return true;
          return notification.scheduledFor!.isBefore(now);
        })
        .length;
  }

  /// Create notification
  Future<String> createNotification(NotificationModel notification) async {
    final docRef = await _notificationsRef.add(notification.toFirestore());
    await docRef.update({'id': docRef.id});
    return docRef.id;
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    await _notificationsRef.doc(notificationId).update({'isRead': true});
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    await batch.commit();
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    await _notificationsRef.doc(notificationId).delete();
  }

  /// Delete all user notifications
  Future<void> deleteAllNotifications(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .get();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  /// Delete all notifications for a specific appointment
  Future<void> deleteAppointmentNotifications(String appointmentId) async {
    final batch = _firestore.batch();
    final snapshot = await _notificationsRef
        .where('appointmentId', isEqualTo: appointmentId)
        .get();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  /// Stream user's notifications for real-time updates
  Stream<List<NotificationModel>> streamNotifications(String userId) {
    return _notificationsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          return snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .where((notification) {
                if (notification.scheduledFor == null) return true;
                return notification.scheduledFor!.isBefore(now);
              })
              .toList();
        });
  }

  /// Stream unread count for real-time updates
  Stream<int> streamUnreadCount(String userId) {
    return _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          return snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .where((notification) {
                if (notification.scheduledFor == null) return true;
                return notification.scheduledFor!.isBefore(now);
              })
              .length;
        });
  }

  /// Schedule 3 appointment reminder notifications (1 week, 1 day, 1 hour before)
  /// These are stored in Firebase and shown when their scheduledFor time passes
  Future<List<String>> scheduleAppointmentReminders({
    required String userId,
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    required String timeSlot,
  }) async {
    final List<String> notificationIds = [];
    final now = DateTime.now();

    // Calculate reminder times
    final oneWeekBefore = appointmentTime.subtract(const Duration(days: 7));
    final oneDayBefore = appointmentTime.subtract(const Duration(days: 1));
    final oneHourBefore = appointmentTime.subtract(const Duration(hours: 1));

    // 1. Create 1 Week before reminder (if in the future)
    if (oneWeekBefore.isAfter(now)) {
      final weekReminder = NotificationModel(
        id: '',
        userId: userId,
        title: 'Appointment in 1 Week',
        body:
            'Reminder: Your appointment with Dr. $doctorName is in 1 week on ${_formatDate(appointmentTime)} at $timeSlot.',
        type: NotificationType.appointmentReminder,
        data: {'appointmentId': appointmentId, 'reminderType': 'oneWeek'},
        createdAt: oneWeekBefore,
        appointmentId: appointmentId,
        scheduledFor: oneWeekBefore,
        reminderType: ReminderType.oneWeek,
        isDelivered: false,
      );
      final id = await createNotification(weekReminder);
      notificationIds.add(id);
    }

    // 2. Create 1 Day before reminder (if in the future)
    if (oneDayBefore.isAfter(now)) {
      final dayReminder = NotificationModel(
        id: '',
        userId: userId,
        title: 'Appointment Tomorrow',
        body:
            'Reminder: Your appointment with Dr. $doctorName is tomorrow at $timeSlot. Please arrive 10 minutes early.',
        type: NotificationType.appointmentReminder,
        data: {'appointmentId': appointmentId, 'reminderType': 'oneDay'},
        createdAt: oneDayBefore,
        appointmentId: appointmentId,
        scheduledFor: oneDayBefore,
        reminderType: ReminderType.oneDay,
        isDelivered: false,
      );
      final id = await createNotification(dayReminder);
      notificationIds.add(id);
    }

    // 3. Create 1 Hour before reminder (if in the future)
    if (oneHourBefore.isAfter(now)) {
      final hourReminder = NotificationModel(
        id: '',
        userId: userId,
        title: 'Appointment in 1 Hour',
        body:
            'Your appointment with Dr. $doctorName is in 1 hour at $timeSlot. Time to get ready!',
        type: NotificationType.appointmentReminder,
        data: {'appointmentId': appointmentId, 'reminderType': 'oneHour'},
        createdAt: oneHourBefore,
        appointmentId: appointmentId,
        scheduledFor: oneHourBefore,
        reminderType: ReminderType.oneHour,
        isDelivered: false,
      );
      final id = await createNotification(hourReminder);
      notificationIds.add(id);
    }

    return notificationIds;
  }

  /// Send immediate appointment confirmation notification
  Future<void> sendAppointmentConfirmation({
    required String userId,
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    required String timeSlot,
  }) async {
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: 'Booking Confirmed',
      body:
          'Your appointment with Dr. $doctorName on ${_formatDate(appointmentTime)} at $timeSlot has been confirmed.',
      type: NotificationType.appointmentConfirmation,
      data: {'appointmentId': appointmentId},
      createdAt: DateTime.now(),
      appointmentId: appointmentId,
      scheduledFor: null, // Immediate notification
      reminderType: ReminderType.immediate,
      isDelivered: true,
    );
    await createNotification(notification);
  }

  /// Send appointment cancellation notification
  Future<void> sendAppointmentCancellation({
    required String userId,
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    String? reason,
  }) async {
    // First, delete any pending reminders for this appointment
    await deleteAppointmentNotifications(appointmentId);

    // Then create the cancellation notification
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: 'Appointment Cancelled',
      body:
          'Your appointment with Dr. $doctorName on ${_formatDate(appointmentTime)} has been cancelled.${reason != null ? ' Reason: $reason' : ''}',
      type: NotificationType.appointmentCancellation,
      data: {'appointmentId': appointmentId},
      createdAt: DateTime.now(),
      appointmentId: appointmentId,
      scheduledFor: null,
      reminderType: ReminderType.immediate,
      isDelivered: true,
    );
    await createNotification(notification);
  }

  /// Send appointment rescheduled notification and reschedule reminders
  Future<void> sendAppointmentRescheduled({
    required String userId,
    required String appointmentId,
    required String doctorName,
    required DateTime oldAppointmentTime,
    required DateTime newAppointmentTime,
    required String newTimeSlot,
  }) async {
    // Delete old reminders
    await deleteAppointmentNotifications(appointmentId);

    // Create rescheduled notification
    final notification = NotificationModel(
      id: '',
      userId: userId,
      title: 'Appointment Rescheduled',
      body:
          'Your appointment with Dr. $doctorName has been rescheduled to ${_formatDate(newAppointmentTime)} at $newTimeSlot.',
      type: NotificationType.appointmentRescheduled,
      data: {'appointmentId': appointmentId},
      createdAt: DateTime.now(),
      appointmentId: appointmentId,
      scheduledFor: null,
      reminderType: ReminderType.immediate,
      isDelivered: true,
    );
    await createNotification(notification);

    // Schedule new reminders
    await scheduleAppointmentReminders(
      userId: userId,
      appointmentId: appointmentId,
      doctorName: doctorName,
      appointmentTime: newAppointmentTime,
      timeSlot: newTimeSlot,
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
