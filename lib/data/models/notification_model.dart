import 'package:cloud_firestore/cloud_firestore.dart';

/// Notification types
enum NotificationType {
  appointmentReminder,
  appointmentConfirmation,
  appointmentCancellation,
  appointmentRescheduled,
  newMessage,
  systemUpdate,
  healthTip,
}

/// Reminder type for appointment notifications
enum ReminderType {
  oneWeek, // 1 week before appointment
  oneDay, // 1 day before appointment
  oneHour, // 1 hour before appointment
  immediate, // Immediate notification (confirmation, etc.)
}

/// Notification model
class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final NotificationType type;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;
  final String? appointmentId;
  final DateTime? scheduledFor; // When the notification should be shown
  final ReminderType? reminderType; // Type of reminder (1 week, 1 day, 1 hour)
  final bool isDelivered; // Whether the notification has been delivered

  NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.data,
    this.isRead = false,
    required this.createdAt,
    this.appointmentId,
    this.scheduledFor,
    this.reminderType,
    this.isDelivered = false,
  });

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: NotificationType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => NotificationType.systemUpdate,
      ),
      data: data['data'],
      isRead: data['isRead'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      appointmentId: data['appointmentId'],
      scheduledFor: (data['scheduledFor'] as Timestamp?)?.toDate(),
      reminderType: data['reminderType'] != null
          ? ReminderType.values.firstWhere(
              (r) => r.name == data['reminderType'],
              orElse: () => ReminderType.immediate,
            )
          : null,
      isDelivered: data['isDelivered'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'body': body,
      'type': type.name,
      'data': data,
      'isRead': isRead,
      'createdAt': Timestamp.fromDate(createdAt),
      'appointmentId': appointmentId,
      'scheduledFor': scheduledFor != null
          ? Timestamp.fromDate(scheduledFor!)
          : null,
      'reminderType': reminderType?.name,
      'isDelivered': isDelivered,
    };
  }

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? body,
    NotificationType? type,
    Map<String, dynamic>? data,
    bool? isRead,
    DateTime? createdAt,
    String? appointmentId,
    DateTime? scheduledFor,
    ReminderType? reminderType,
    bool? isDelivered,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      data: data ?? this.data,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      appointmentId: appointmentId ?? this.appointmentId,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      reminderType: reminderType ?? this.reminderType,
      isDelivered: isDelivered ?? this.isDelivered,
    );
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 7) {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
