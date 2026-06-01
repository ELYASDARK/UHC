import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

/// Repository for notification-related Firestore operations
class NotificationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'notifications';

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      _firestore.collection(_collection);

  DateTime? _dateFromFirestoreValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  bool _isVisibleForClient(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return false;

    final isVisible = data['isVisible'];
    if (isVisible is bool) return isVisible;

    final scheduledFor = _dateFromFirestoreValue(data['scheduledFor']);
    if (scheduledFor == null) return true;
    if (!scheduledFor.isAfter(DateTime.now())) return true;

    return data['isDelivered'] == true;
  }

  /// Get user's notifications (only delivered ones)
  Future<List<NotificationModel>> getUserNotifications(
    String userId, {
    int limit = 50,
  }) async {
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit * 3)
        .get();

    return snapshot.docs
        .where(_isVisibleForClient)
        .map((doc) => NotificationModel.fromFirestore(doc))
        .take(limit)
        .toList();
  }

  /// Get unread notifications count (only for delivered notifications)
  Future<int> getUnreadCount(String userId) async {
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    return snapshot.docs.where(_isVisibleForClient).length;
  }

  /// Create notification
  Future<String> createNotification(NotificationModel notification) async {
    // Push-delivered and appointment notification records are backend-owned.
    // Keep this method as a safe no-op for legacy UI flows that still call it
    // after the corresponding Cloud Function has performed the trusted write.
    return '';
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    await _notificationsRef.doc(notificationId).update({'isRead': true});
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    // Chunk into batches of 500 (Firestore batch limit)
    final docs = snapshot.docs.where(_isVisibleForClient).toList();
    for (var i = 0; i < docs.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < docs.length) ? i + 500 : docs.length;
      for (var j = i; j < end; j++) {
        batch.update(docs[j].reference, {'isRead': true});
      }
      await batch.commit();
    }
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    await _notificationsRef.doc(notificationId).delete();
  }

  /// Delete all user notifications
  Future<void> deleteAllNotifications(String userId) async {
    final snapshot =
        await _notificationsRef.where('userId', isEqualTo: userId).get();

    // Chunk into batches of 500 (Firestore batch limit)
    final docs = snapshot.docs.where(_isVisibleForClient).toList();
    for (var i = 0; i < docs.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < docs.length) ? i + 500 : docs.length;
      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }
      await batch.commit();
    }
  }

  /// Delete all notifications for a specific appointment
  Future<void> deleteAppointmentNotifications({
    required String userId,
    required String appointmentId,
  }) async {
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('appointmentId', isEqualTo: appointmentId)
        .get();

    // Chunk into batches of 500 (Firestore batch limit)
    final docs = snapshot.docs.where(_isVisibleForClient).toList();
    for (var i = 0; i < docs.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500 < docs.length) ? i + 500 : docs.length;
      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }
      await batch.commit();
    }
  }

  /// Stream user's notifications for real-time updates
  Stream<List<NotificationModel>> streamNotifications(String userId) {
    return _notificationsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(150)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .where(_isVisibleForClient)
          .map((doc) => NotificationModel.fromFirestore(doc))
          .take(50)
          .toList();
    });
  }

  /// Stream unread count for real-time updates
  Stream<int> streamUnreadCount(String userId) {
    return _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.where(_isVisibleForClient).length);
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
    return [];
  }

  /// Send immediate appointment confirmation notification
  Future<void> sendAppointmentConfirmation({
    required String userId,
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    required String timeSlot,
  }) async {
    return;
  }

  /// Send appointment cancellation notification
  Future<void> sendAppointmentCancellation({
    required String userId,
    required String appointmentId,
    required String doctorName,
    required DateTime appointmentTime,
    String? reason,
  }) async {
    return;
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
    return;
  }

  /// Delete all future daily-summary notification docs for a user.
  /// Queries by userId and filters client-side for type == dailySummary
  /// with scheduledFor in the future.
  Future<void> deleteFutureDailySummaries(String userId) async {
    final now = DateTime.now();
    // Filter by type server-side to reduce data transfer
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'dailySummary')
        .get();

    final docsToDelete = snapshot.docs.where((doc) {
      final data = doc.data();
      final scheduledFor = (data['scheduledFor'] as Timestamp?)?.toDate();
      return scheduledFor != null && scheduledFor.isAfter(now);
    }).toList();

    // Chunk into batches of 500 (Firestore batch limit)
    for (var i = 0; i < docsToDelete.length; i += 500) {
      final batch = _firestore.batch();
      final end =
          (i + 500 < docsToDelete.length) ? i + 500 : docsToDelete.length;
      for (var j = i; j < end; j++) {
        batch.delete(docsToDelete[j].reference);
      }
      await batch.commit();
    }
  }
}
