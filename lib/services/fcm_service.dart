import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'local_notification_service.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages silently
  // In production, this would trigger local notification or data sync
}

/// Firebase Cloud Messaging service for push notifications (singleton)
class FCMService {
  // Singleton pattern
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final LocalNotificationService _localNotificationService =
      LocalNotificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Whether [initialize] has already completed successfully
  bool _initialized = false;

  // Stream controller for notification taps
  final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get onMessageTapped => _messageStreamController.stream;

  /// Initialize FCM and local notifications.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      // Request permission
      await _requestPermission();

      // Initialize local notifications via the shared singleton
      await _localNotificationService.initialize(
        onTap: (payload) {
          if (payload != null) {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            final message = RemoteMessage(data: data);
            _messageStreamController.add(message);
          }
        },
      );

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Check if app was opened from terminated state via notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      _initialized = true;
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: 'FCM Service Initialization Failed');
    }
  }

  /// Request notification permission
  Future<bool> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;

    // Show local notification when app is in foreground
    if (notification != null) {
      _localNotificationService.showNotification(
        id: notification.hashCode,
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle notification tap when app is opened from background
  void _handleMessageOpenedApp(RemoteMessage message) {
    _messageStreamController.add(message);
  }

  /// Get FCM token
  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  /// Subscribe to topic (not supported on web)
  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) return; // Topic subscription not supported on web
    await _messaging.subscribeToTopic(topic);
  }

  /// Unsubscribe from topic (not supported on web)
  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) return; // Topic unsubscription not supported on web
    await _messaging.unsubscribeFromTopic(topic);
  }

  /// Save FCM token to Firestore for user
  Future<void> saveTokenToDatabase(String userId) async {
    try {
      final token = await getToken();
      if (token != null) {
        // Save to users collection (legacy support)
        await _firestore.collection('users').doc(userId).update({
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }).catchError((e, stack) {
          FirebaseCrashlytics.instance
              .recordError(e, stack, reason: 'Failed to update user FCM token');
        });

        // Save to user_tokens collection (for Cloud Functions)
        // dart:io Platform is not available on web, so use 'web' as a fallback.
        final platform = kIsWeb ? 'web' : _getNativePlatform();
        await _firestore.collection('user_tokens').doc(userId).set({
          'token': token,
          'updatedAt': FieldValue.serverTimestamp(),
          'platform': platform,
        }, SetOptions(merge: true));
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        await _firestore.collection('users').doc(userId).update({
          'fcmTokens': FieldValue.arrayUnion([newToken]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }).catchError((e, stack) {
          FirebaseCrashlytics.instance.recordError(e, stack,
              reason: 'Failed to update refreshed FCM token');
        });

        // Update user_tokens collection
        final refreshPlatform = kIsWeb ? 'web' : _getNativePlatform();
        await _firestore.collection('user_tokens').doc(userId).set({
          'token': newToken,
          'updatedAt': FieldValue.serverTimestamp(),
          'platform': refreshPlatform,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      // getToken() can throw on web (requires VAPID key) — don't let that
      // block the rest of the initialization flow.
      debugPrint('saveTokenToDatabase failed (safe to ignore on web): $e');
    }
  }

  /// Determine native platform name (only called when NOT on web).
  /// Separated into its own method so dart:io is only imported conditionally.
  String _getNativePlatform() {
    // On web, this should never be called, but default to 'unknown' as safety.
    try {
      // ignore: avoid_slow_async_io
      return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Remove FCM token when user logs out
  Future<void> removeTokenFromDatabase(String userId) async {
    try {
      final token = await getToken();
      if (token != null) {
        await _firestore.collection('users').doc(userId).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        }).catchError((e, stack) {
          FirebaseCrashlytics.instance.recordError(e, stack,
              reason: 'Failed to remove FCM token');
        });

        // Remove from user_tokens collection
        await _firestore
            .collection('user_tokens')
            .doc(userId)
            .delete()
            .catchError((_) {});
      }
    } catch (e) {
      // getToken() can throw on web (requires VAPID key) — don't let that
      // block the rest of the logout flow.
      debugPrint('removeTokenFromDatabase failed (safe to ignore on web): $e');
    }
  }

  /// Subscribe user to relevant topics
  Future<void> subscribeUserToTopics(
    String userId, {
    String? role,
    String? department,
  }) async {
    // Subscribe to general announcements
    await subscribeToTopic('announcements');

    // Subscribe to user-specific topic
    await subscribeToTopic('user_$userId');

    // Subscribe to role-based topic (e.g. role_student, role_doctor)
    if (role != null && role.isNotEmpty) {
      await subscribeToTopic('role_$role');
    }

    // Subscribe to department if provided
    if (department != null) {
      await subscribeToTopic('department_$department');
    }
  }

  /// Unsubscribe user from all topics
  Future<void> unsubscribeUserFromTopics(
    String userId, {
    String? role,
    String? department,
  }) async {
    await unsubscribeFromTopic('announcements');
    await unsubscribeFromTopic('user_$userId');

    if (role != null && role.isNotEmpty) {
      await unsubscribeFromTopic('role_$role');
    }

    if (department != null) {
      await unsubscribeFromTopic('department_$department');
    }
  }

  /// Dispose resources
  void dispose() {
    _messageStreamController.close();
  }
}
