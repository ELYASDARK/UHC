import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum AdminNotificationTargetType {
  singlePatient,
  singleDoctor,
  allPatients,
  allDoctors,
  patientsAndDoctors,
}

extension AdminNotificationTargetTypeX on AdminNotificationTargetType {
  String get label {
    switch (this) {
      case AdminNotificationTargetType.singlePatient:
        return 'Single patient';
      case AdminNotificationTargetType.singleDoctor:
        return 'Single doctor';
      case AdminNotificationTargetType.allPatients:
        return 'All active patients';
      case AdminNotificationTargetType.allDoctors:
        return 'All active doctors';
      case AdminNotificationTargetType.patientsAndDoctors:
        return 'Patients and doctors';
    }
  }

  String get description {
    switch (this) {
      case AdminNotificationTargetType.singlePatient:
        return 'Choose one active student or staff member.';
      case AdminNotificationTargetType.singleDoctor:
        return 'Choose one active doctor account.';
      case AdminNotificationTargetType.allPatients:
        return 'Active students and staff only.';
      case AdminNotificationTargetType.allDoctors:
        return 'Active doctors only.';
      case AdminNotificationTargetType.patientsAndDoctors:
        return 'Active students, staff, and doctors.';
    }
  }

  bool get requiresRecipient =>
      this == AdminNotificationTargetType.singlePatient ||
      this == AdminNotificationTargetType.singleDoctor;
}

class AdminNotificationRecipient {
  final String uid;
  final String name;
  final String role;
  final String? email;
  final String? subtitle;

  const AdminNotificationRecipient({
    required this.uid,
    required this.name,
    required this.role,
    this.email,
    this.subtitle,
  });

  factory AdminNotificationRecipient.fromMap(Map<String, dynamic> data) {
    return AdminNotificationRecipient(
      uid: data['uid']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Unknown',
      role: data['role']?.toString() ?? '',
      email: data['email']?.toString(),
      subtitle: data['subtitle']?.toString(),
    );
  }
}

class AdminNotificationPreview {
  final String targetLabel;
  final int recipientCount;

  const AdminNotificationPreview({
    required this.targetLabel,
    required this.recipientCount,
  });

  factory AdminNotificationPreview.fromMap(Map<String, dynamic> data) {
    return AdminNotificationPreview(
      targetLabel: data['targetLabel']?.toString() ?? '',
      recipientCount: (data['recipientCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminNotificationSendResult {
  final String targetLabel;
  final int recipientCount;
  final List<String> notificationIds;
  final String message;

  const AdminNotificationSendResult({
    required this.targetLabel,
    required this.recipientCount,
    required this.notificationIds,
    required this.message,
  });

  factory AdminNotificationSendResult.fromMap(Map<String, dynamic> data) {
    final rawIds = data['notificationIds'];
    return AdminNotificationSendResult(
      targetLabel: data['targetLabel']?.toString() ?? '',
      recipientCount: (data['recipientCount'] as num?)?.toInt() ?? 0,
      notificationIds: rawIds is List
          ? rawIds.map((id) => id.toString()).toList(growable: false)
          : const [],
      message: data['message']?.toString() ?? 'Notification sent.',
    );
  }
}

class AdminNotificationService {
  static const _uuid = Uuid();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<List<AdminNotificationRecipient>> searchRecipients({
    required AdminNotificationTargetType targetType,
    required String query,
  }) async {
    final data = await _call('searchAdminNotificationRecipients', {
      'targetType': targetType.name,
      'query': query,
      'limit': 12,
    });
    final rawRecipients = data['recipients'];
    if (rawRecipients is! List) return const [];
    return rawRecipients
        .whereType<Map>()
        .map((item) => AdminNotificationRecipient.fromMap(
              Map<String, dynamic>.from(item),
            ))
        .where((recipient) => recipient.uid.isNotEmpty)
        .toList(growable: false);
  }

  Future<AdminNotificationPreview> previewRecipients({
    required AdminNotificationTargetType targetType,
    String? targetUserId,
  }) async {
    final data = await _call('previewAdminNotificationRecipients', {
      'targetType': targetType.name,
      if (targetUserId != null) 'targetUserId': targetUserId,
    });
    return AdminNotificationPreview.fromMap(data);
  }

  Future<AdminNotificationSendResult> sendNotification({
    required AdminNotificationTargetType targetType,
    String? targetUserId,
    required String title,
    required String body,
  }) async {
    final data = await _call('sendAdminNotification', {
      'targetType': targetType.name,
      if (targetUserId != null) 'targetUserId': targetUserId,
      'title': title,
      'body': body,
      'requestId': _uuid.v4(),
    });
    return AdminNotificationSendResult.fromMap(data);
  }

  Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    try {
      final callable = _functions.httpsCallable(functionName);
      final result = await callable.call<Map<String, dynamic>>(payload);
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[$functionName] Firebase Functions Error: ${e.code} - ${e.message}',
      );
      rethrow;
    } catch (e) {
      debugPrint('[$functionName] Error: $e');
      rethrow;
    }
  }
}
