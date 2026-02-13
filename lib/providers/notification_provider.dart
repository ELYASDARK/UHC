import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../services/fcm_service.dart';
import '../data/repositories/notification_repository.dart';
import '../data/models/notification_model.dart';

/// Provider for managing notifications state
class NotificationProvider extends ChangeNotifier {
  final FCMService _fcmService = FCMService();
  final NotificationRepository _notificationRepo = NotificationRepository();

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _error;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Initialize FCM and load notifications
  Future<void> initialize(String userId) async {
    try {
      // Initialize FCM
      await _fcmService.initialize();

      // Save token to database
      await _fcmService.saveTokenToDatabase(userId);

      // Subscribe to topics
      await _fcmService.subscribeUserToTopics(userId);

      // Load notifications
      await loadNotifications(userId);

      // Listen for notification taps
      _fcmService.onMessageTapped.listen((message) {
        _handleNotificationTap(message);
      });
    } catch (e, stack) {
      _error = e.toString();
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'NotificationProvider Error: initialize');
      notifyListeners();
    }
  }

  /// Load user notifications
  Future<void> loadNotifications(String userId) async {
    _isLoading = true;
    _error = null;
    // Note: Don't call notifyListeners() here to avoid "setState during build" error
    // The finally block will notify listeners when loading completes

    try {
      _notifications = await _notificationRepo.getUserNotifications(userId);
      _unreadCount = await _notificationRepo.getUnreadCount(userId);
      _error = null;
    } catch (e, stack) {
      _error = e.toString();
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'NotificationProvider Error: loadNotifications');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _notificationRepo.markAsRead(notificationId);

      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1 && !_notifications[index].isRead) {
        _notifications[index] = _notifications[index].copyWith(isRead: true);
        _unreadCount = (_unreadCount > 0) ? _unreadCount - 1 : 0;
        notifyListeners();
      }
    } catch (e, stack) {
      _error = e.toString();
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'NotificationProvider Error: markAsRead');
      notifyListeners();
    }
  }

  /// Mark all as read
  Future<void> markAllAsRead(String userId) async {
    try {
      await _notificationRepo.markAllAsRead(userId);

      _notifications =
          _notifications.map((n) => n.copyWith(isRead: true)).toList();
      _unreadCount = 0;
      notifyListeners();
    } catch (e, stack) {
      _error = e.toString();
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'NotificationProvider Error: markAllAsRead');
      notifyListeners();
    }
  }

  /// Delete notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _notificationRepo.deleteNotification(notificationId);

      final wasUnread = _notifications.any(
        (n) => n.id == notificationId && !n.isRead,
      );
      _notifications.removeWhere((n) => n.id == notificationId);
      if (wasUnread) {
        _unreadCount = (_unreadCount > 0) ? _unreadCount - 1 : 0;
      }
      notifyListeners();
    } catch (e, stack) {
      _error = e.toString();
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'NotificationProvider Error: deleteNotification');
      notifyListeners();
    }
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    // Handle navigation based on notification data
    final data = message.data;
    final appointmentId = data['appointmentId'];

    if (appointmentId != null) {
      // Navigate to appointment details
      // This would typically use a navigation service or callback
    }
  }

  /// Clean up on logout
  Future<void> onLogout(String userId) async {
    await _fcmService.removeTokenFromDatabase(userId);
    await _fcmService.unsubscribeUserFromTopics(userId);
    _notifications.clear();
    _unreadCount = 0;
    notifyListeners();
  }

  /// Enable push notifications for user
  Future<void> enablePushNotifications(String userId) async {
    try {
      await _fcmService.initialize();
      await _fcmService.saveTokenToDatabase(userId);
      await _fcmService.subscribeUserToTopics(userId);
    } catch (e, stack) {
      _error = e.toString();
      FirebaseCrashlytics.instance.recordError(e, stack,
          reason: 'NotificationProvider Error: enablePushNotifications');
      notifyListeners();
    }
  }

  /// Disable push notifications for user
  Future<void> disablePushNotifications(String userId) async {
    try {
      await _fcmService.removeTokenFromDatabase(userId);
      await _fcmService.unsubscribeUserFromTopics(userId);
    } catch (e, stack) {
      _error = e.toString();
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'NotificationProvider Error');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _fcmService.dispose();
    super.dispose();
  }
}
