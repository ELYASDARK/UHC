import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../core/notifications/notification_preferences.dart';
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
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _tokenOwnerUserId;
  int _tokenSessionVersion = 0;

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
      _recordError(e, stack, reason: 'FCM Service Initialization Failed');
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
    final sessionVersion = ++_tokenSessionVersion;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _tokenOwnerUserId = userId;

    try {
      final token = await getToken();
      if (_tokenOwnerUserId != userId ||
          sessionVersion != _tokenSessionVersion) {
        return;
      }

      if (token != null) {
        await _saveToken(userId, token);
      }

      if (_tokenOwnerUserId != userId ||
          sessionVersion != _tokenSessionVersion) {
        return;
      }

      _tokenRefreshSubscription =
          _messaging.onTokenRefresh.listen((newToken) async {
        if (_tokenOwnerUserId != userId ||
            sessionVersion != _tokenSessionVersion) {
          return;
        }

        await _saveToken(userId, newToken);
      });
    } catch (e) {
      debugPrint('saveTokenToDatabase failed (safe to ignore on web): $e');
    }
  }

  Future<void> _saveToken(String userId, String token) async {
    try {
      final userSnap = await _firestore.collection('users').doc(userId).get();
      final userData = userSnap.data();
      final isDoctor = userData?['role'] == 'doctor';
      final prefsMap = userData?['notificationSettings'] as Map<String, dynamic>?;
      final settings = NotificationPreferences.fromMap(prefsMap, isDoctor: isDoctor, isWeb: kIsWeb);

      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('uhc_device_id');
      if (deviceId == null) {
        deviceId = const Uuid().v4();
        await prefs.setString('uhc_device_id', deviceId);
      }

      final bytes = utf8.encode(token);
      final tokenHash = sha256.convert(bytes).toString();

      final platform = kIsWeb ? 'web' : _getNativePlatform();
      final supportsLocalReminders = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
           defaultTargetPlatform == TargetPlatform.iOS);

      final effectiveAppointmentReminderDelivery = kIsWeb
          ? NotificationDeliveryMode.fcm
          : settings.appointmentReminderDelivery;

      final effectiveDoctorDailySummaryDelivery = kIsWeb
          ? NotificationDeliveryMode.fcm
          : settings.doctorDailySummaryDelivery;

      String? timeZone;
      if (!kIsWeb) {
        try {
          final tzInfo = await FlutterTimezone.getLocalTimezone();
          timeZone = tzInfo.identifier;
        } catch (_) {}
      }

      await _firestore
          .collection('user_tokens')
          .doc(userId)
          .collection('tokens')
          .doc(tokenHash)
          .set({
        'token': token,
        'tokenHash': tokenHash,
        'deviceId': deviceId,
        'platform': platform,
        'supportsLocalReminders': supportsLocalReminders,
        'onlinePushEnabled': settings.onlinePushEnabled,
        'appointmentReminderDelivery': effectiveAppointmentReminderDelivery.name,
        'doctorDailySummaryDelivery': effectiveDoctorDailySummaryDelivery.name,
        'timeZone': timeZone,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error inside _saveToken helper: $e');
    }
  }

  /// Remove FCM token when user logs out
  Future<void> removeTokenFromDatabase(String userId) async {
    final shouldInvalidateDeviceToken =
        _tokenOwnerUserId == null || _tokenOwnerUserId == userId;

    if (shouldInvalidateDeviceToken) {
      _tokenSessionVersion++;
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      _tokenOwnerUserId = null;
    }

    try {
      final token = await getToken();
      if (token != null) {
        final bytes = utf8.encode(token);
        final tokenHash = sha256.convert(bytes).toString();
        await _firestore
            .collection('user_tokens')
            .doc(userId)
            .collection('tokens')
            .doc(tokenHash)
            .delete();
      }
    } catch (e) {
      debugPrint('Failed to delete FCM token document for $userId: $e');
    }

    if (!shouldInvalidateDeviceToken) return;

    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('Failed to delete local FCM token for $userId: $e');
    }
  }

  /// Subscribe user to relevant topics
  Future<void> subscribeUserToTopics(
    String userId, {
    String? role,
    String? department,
  }) async {
    // Keep topic subscriptions limited to non-sensitive broadcasts.
    // Private/user/role/department messages are delivered by token from Cloud Functions.
    await subscribeToTopic('announcements');
  }

  /// Unsubscribe user from all topics
  Future<void> unsubscribeUserFromTopics(
    String userId, {
    String? role,
    String? department,
  }) async {
    await unsubscribeFromTopic('announcements');
  }

  /// Dispose resources
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _messageStreamController.close();
  }

  String _getNativePlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'unknown';
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
