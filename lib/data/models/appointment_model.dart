import 'package:cloud_firestore/cloud_firestore.dart';

/// Appointment status
enum AppointmentStatus { pending, confirmed, completed, cancelled, noShow }

/// Appointment type
enum AppointmentType { regularCheckup, followUp, consultation, emergency }

/// Appointment model
class AppointmentModel {
  final String id;
  final String patientId;
  final String patientName;
  final String patientEmail;
  final String doctorId;
  final String doctorName;
  final String department;
  final DateTime appointmentDate;
  final String timeSlot;
  final AppointmentType type;
  final AppointmentStatus status;
  final String? notes;
  final String? medicalNotes;
  final String? qrCode;
  final bool isCheckedIn;
  final DateTime? checkedInAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? cancelReason;
  final String? rescheduleReason;
  final bool reminderSent24h;
  final bool reminderSent1h;

  AppointmentModel({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.patientEmail,
    required this.doctorId,
    required this.doctorName,
    required this.department,
    required this.appointmentDate,
    required this.timeSlot,
    this.type = AppointmentType.regularCheckup,
    this.status = AppointmentStatus.pending,
    this.notes,
    this.medicalNotes,
    this.qrCode,
    this.isCheckedIn = false,
    this.checkedInAt,
    required this.createdAt,
    required this.updatedAt,
    this.cancelReason,
    this.rescheduleReason,
    this.reminderSent24h = false,
    this.reminderSent1h = false,
  });

  factory AppointmentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppointmentModel(
      id: doc.id,
      patientId: data['patientId'] ?? '',
      patientName: data['patientName'] ?? '',
      patientEmail: data['patientEmail'] ?? '',
      doctorId: data['doctorId'] ?? '',
      doctorName: data['doctorName'] ?? '',
      department: data['department'] ?? '',
      appointmentDate: (data['appointmentDate'] as Timestamp).toDate(),
      timeSlot: data['timeSlot'] ?? '',
      type: AppointmentType.values.firstWhere(
        (t) => t.name == data['type'],
        orElse: () => AppointmentType.regularCheckup,
      ),
      status: AppointmentStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => AppointmentStatus.pending,
      ),
      notes: data['notes'],
      medicalNotes: data['medicalNotes'],
      qrCode: data['qrCode'],
      isCheckedIn: data['isCheckedIn'] ?? false,
      checkedInAt: data['checkedInAt'] != null
          ? (data['checkedInAt'] as Timestamp).toDate()
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      cancelReason: data['cancelReason'],
      rescheduleReason: data['rescheduleReason'],
      reminderSent24h: data['reminderSent24h'] ?? false,
      reminderSent1h: data['reminderSent1h'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'patientId': patientId,
      'patientName': patientName,
      'patientEmail': patientEmail,
      'doctorId': doctorId,
      'doctorName': doctorName,
      'department': department,
      'appointmentDate': Timestamp.fromDate(appointmentDate),
      'timeSlot': timeSlot,
      'type': type.name,
      'status': status.name,
      'notes': notes,
      'medicalNotes': medicalNotes,
      'qrCode': qrCode,
      'isCheckedIn': isCheckedIn,
      'checkedInAt': checkedInAt != null
          ? Timestamp.fromDate(checkedInAt!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'cancelReason': cancelReason,
      'rescheduleReason': rescheduleReason,
      'reminderSent24h': reminderSent24h,
      'reminderSent1h': reminderSent1h,
    };
  }

  AppointmentModel copyWith({
    String? id,
    String? patientId,
    String? patientName,
    String? patientEmail,
    String? doctorId,
    String? doctorName,
    String? department,
    DateTime? appointmentDate,
    String? timeSlot,
    AppointmentType? type,
    AppointmentStatus? status,
    String? notes,
    String? medicalNotes,
    String? qrCode,
    bool? isCheckedIn,
    DateTime? checkedInAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? cancelReason,
    String? rescheduleReason,
    bool? reminderSent24h,
    bool? reminderSent1h,
  }) {
    return AppointmentModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      patientName: patientName ?? this.patientName,
      patientEmail: patientEmail ?? this.patientEmail,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      department: department ?? this.department,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      timeSlot: timeSlot ?? this.timeSlot,
      type: type ?? this.type,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      medicalNotes: medicalNotes ?? this.medicalNotes,
      qrCode: qrCode ?? this.qrCode,
      isCheckedIn: isCheckedIn ?? this.isCheckedIn,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cancelReason: cancelReason ?? this.cancelReason,
      rescheduleReason: rescheduleReason ?? this.rescheduleReason,
      reminderSent24h: reminderSent24h ?? this.reminderSent24h,
      reminderSent1h: reminderSent1h ?? this.reminderSent1h,
    );
  }

  bool get isPending => status == AppointmentStatus.pending;
  bool get isConfirmed => status == AppointmentStatus.confirmed;
  bool get isCompleted => status == AppointmentStatus.completed;
  bool get isCancelled => status == AppointmentStatus.cancelled;
  bool get isUpcoming =>
      appointmentDate.isAfter(DateTime.now()) &&
      (status == AppointmentStatus.pending ||
          status == AppointmentStatus.confirmed);
  bool get isPast =>
      appointmentDate.isBefore(DateTime.now()) ||
      status == AppointmentStatus.completed ||
      status == AppointmentStatus.cancelled;

  String get statusDisplay {
    switch (status) {
      case AppointmentStatus.pending:
        return 'Pending';
      case AppointmentStatus.confirmed:
        return 'Confirmed';
      case AppointmentStatus.completed:
        return 'Completed';
      case AppointmentStatus.cancelled:
        return 'Cancelled';
      case AppointmentStatus.noShow:
        return 'No Show';
    }
  }

  String get typeDisplay {
    switch (type) {
      case AppointmentType.regularCheckup:
        return 'Regular Checkup';
      case AppointmentType.followUp:
        return 'Follow Up';
      case AppointmentType.consultation:
        return 'Consultation';
      case AppointmentType.emergency:
        return 'Emergency';
    }
  }

  /// Check if the appointment can be cancelled (24 hours before)
  bool get canCancel {
    if (isCancelled || isCompleted) return false;
    final hoursUntil = appointmentDate.difference(DateTime.now()).inHours;
    return hoursUntil >= 24;
  }

  /// Check if the appointment can be rescheduled (24 hours before)
  bool get canReschedule => canCancel;
}
