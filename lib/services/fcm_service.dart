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
import '../core/config/emulator_config.dart';
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

  FirebaseMessaging? _messagingInstance;
  FirebaseMessaging get _messaging {
    if (EmulatorConfig.isEmulatorEnabled) {
      throw StateError('FirebaseMessaging is disabled in emulator mode.');
    }
    return _messagingInstance ??= FirebaseMessaging.instance;
  }

  final LocalNotificationService _localNotificationService =
      LocalNotificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Whether [initialize] has already completed successfully
  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _tokenOwnerUserId;
  String? _registrationId;
  int _tokenSessionVersion = 0;

  // Stream controller for notification taps
  final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get onMessageTapped => _messageStreamController.stream;

  /// Initialize FCM and local notifications.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (EmulatorConfig.isEmulatorEnabled) return;
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
    if (EmulatorConfig.isEmulatorEnabled) return false;
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

  /// Register and return the installation ID used for direct FCM delivery.
  Future<String?> getToken() async {
    if (EmulatorConfig.isEmulatorEnabled) return null;
    final registered = Completer<String>();
    final subscription = _messaging.onRegistered.listen((id) {
      _registrationId = id;
      if (!registered.isCompleted) registered.complete(id);
    }, onError: (Object error, StackTrace stack) {
      if (!registered.isCompleted) registered.completeError(error, stack);
    });
    try {
      // Listen first: native platforms can emit before register() completes.
      final results = await Future.wait<Object?>([
        registered.future,
        _messaging.register(),
      ], eagerError: true)
          .timeout(const Duration(seconds: 30));
      return results.first as String;
    } finally {
      await subscription.cancel();
    }
  }

  /// Subscribe to topic (not supported on web)
  Future<void> subscribeToTopic(String topic) async {
    if (EmulatorConfig.isEmulatorEnabled) return;
    if (kIsWeb) return; // Topic subscription not supported on web
    await _messaging.subscribeToTopic(topic);
  }

  /// Unsubscribe from topic (not supported on web)
  Future<void> unsubscribeFromTopic(String topic) async {
    if (EmulatorConfig.isEmulatorEnabled) return;
    if (kIsWeb) return; // Topic unsubscription not supported on web
    await _messaging.unsubscribeFromTopic(topic);
  }

  /// Explicitly delete local FCM token (no-op in emulator mode)
  Future<void> deleteToken() async {
    if (EmulatorConfig.isEmulatorEnabled) return;
    try {
      await _messaging.unregister();
      _registrationId = null;
    } catch (e) {
      debugPrint('Failed to delete local FCM token: $e');
    }
  }

  /// Save FCM token to Firestore for user
  Future<void> saveTokenToDatabase(String userId) async {
    if (EmulatorConfig.isEmulatorEnabled) return;
    final sessionVersion = ++_tokenSessionVersion;
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _tokenOwnerUserId = userId;

    try {
      var pendingSave = Future<void>.value();
      // Keep the renewal listener active before triggering registration.
      _tokenRefreshSubscription = _messaging.onRegistered.listen((id) {
        if (_tokenOwnerUserId != userId ||
            sessionVersion != _tokenSessionVersion) {
          return;
        }
        _registrationId = id;
        pendingSave =
            pendingSave.then((_) => _saveToken(userId, id, sessionVersion));
      }, onError: (Object error) {
        debugPrint('FCM registration stream failed: $error');
      });
      await getToken();
      await pendingSave;
    } catch (e) {
      debugPrint('saveTokenToDatabase failed (safe to ignore on web): $e');
    }
  }

  Future<void> _saveToken(
      String userId, String token, int sessionVersion) async {
    if (EmulatorConfig.isEmulatorEnabled) return;
    try {
      final userSnap = await _firestore.collection('users').doc(userId).get();
      final userData = userSnap.data();
      final isDoctor = userData?['role'] == 'doctor';
      final prefsMap =
          userData?['notificationSettings'] as Map<String, dynamic>?;
      final settings = NotificationPreferences.fromMap(prefsMap,
          isDoctor: isDoctor, isWeb: kIsWeb);

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

      final tokens =
          _firestore.collection('user_tokens').doc(userId).collection('tokens');
      final previous =
          await tokens.where('deviceId', isEqualTo: deviceId).get();
      if (_tokenOwnerUserId != userId ||
          sessionVersion != _tokenSessionVersion) {
        return;
      }
      final batch = _firestore.batch();
      for (final old in previous.docs) {
        if (old.id != tokenHash) batch.delete(old.reference);
      }
      // Keep the existing server schema during the documented FID transition.
      batch.set(
          tokens.doc(tokenHash),
          {
            'fid': token,
            'registrationType': 'fid',
            'token': token,
            'tokenHash': tokenHash,
            'deviceId': deviceId,
            'platform': platform,
            'supportsLocalReminders': supportsLocalReminders,
            'onlinePushEnabled': settings.onlinePushEnabled,
            'appointmentReminderDelivery':
                effectiveAppointmentReminderDelivery.name,
            'doctorDailySummaryDelivery':
                effectiveDoctorDailySummaryDelivery.name,
            'timeZone': timeZone,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      debugPrint('Error inside _saveToken helper: $e');
    }
  }

  /// Remove FCM token when user logs out
  Future<void> removeTokenFromDatabase(String userId) async {
    if (EmulatorConfig.isEmulatorEnabled) return;
    final shouldInvalidateDeviceToken =
        _tokenOwnerUserId == null || _tokenOwnerUserId == userId;

    if (shouldInvalidateDeviceToken) {
      _tokenSessionVersion++;
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      _tokenOwnerUserId = null;
    }

    try {
      // Logout must not create a new registration just to remove its record.
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('uhc_device_id');
      if (deviceId != null) {
        final docs = await _firestore
            .collection('user_tokens')
            .doc(userId)
            .collection('tokens')
            .where('deviceId', isEqualTo: deviceId)
            .get();
        final batch = _firestore.batch();
        for (final doc in docs.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } else if (_registrationId != null) {
        final hash = sha256.convert(utf8.encode(_registrationId!)).toString();
        await _firestore
            .collection('user_tokens')
            .doc(userId)
            .collection('tokens')
            .doc(hash)
            .delete();
      }
    } catch (e) {
      debugPrint('Failed to delete FCM token document for $userId: $e');
    }

    if (!shouldInvalidateDeviceToken) return;

    try {
      await _messaging.unregister();
      _registrationId = null;
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
    if (EmulatorConfig.isEmulatorEnabled) return;
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
    if (EmulatorConfig.isEmulatorEnabled) return;
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
    if (kIsWeb || EmulatorConfig.isEmulatorEnabled) return;
    try {
      FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
    } catch (_) {
      // Ignore Crashlytics secondary failures.
    }
  }
}
