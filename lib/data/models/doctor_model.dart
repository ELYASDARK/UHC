import 'package:cloud_firestore/cloud_firestore.dart';

/// Department types in the health center (kept for backward compatibility)
/// New departments should be added directly to Firebase
enum Department { generalMedicine, dentistry, psychology, pharmacy, cardiology }

/// Doctor model
class DoctorModel {
  final String id;
  final String userId;
  final String name;
  final String email;
  final String? photoUrl;
  final String departmentId; // Changed to String for dynamic departments
  final String specialization;
  final String? bio;
  final int experienceYears;
  final List<String> qualifications;
  final bool isAvailable;
  final bool isActive; // Admin-controlled activation status
  final String? availabilityRequestStatus;
  final String? pendingAvailabilityRequestId;
  final String? availabilityRequestReason;
  final DateTime? availabilityRequestedAt;
  final Map<String, List<TimeSlot>> weeklySchedule;
  final String dailyNotificationTime; // HH:mm format
  final DateTime createdAt;
  final DateTime updatedAt;

  DoctorModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.email,
    this.photoUrl,
    required this.departmentId,
    required this.specialization,
    this.bio,
    this.experienceYears = 0,
    this.qualifications = const [],
    this.isAvailable = true,
    this.isActive = true,
    this.availabilityRequestStatus,
    this.pendingAvailabilityRequestId,
    this.availabilityRequestReason,
    this.availabilityRequestedAt,
    this.weeklySchedule = const {},
    this.dailyNotificationTime = '21:00',
    required this.createdAt,
    required this.updatedAt,
  });

  /// For backward compatibility with enum-based code
  Department get department {
    switch (departmentId.toLowerCase()) {
      case 'generalmedicine':
        return Department.generalMedicine;
      case 'dentistry':
        return Department.dentistry;
      case 'psychology':
        return Department.psychology;
      case 'pharmacy':
        return Department.pharmacy;
      case 'cardiology':
        return Department.cardiology;
      default:
        return Department.generalMedicine;
    }
  }

  factory DoctorModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse weekly schedule
    Map<String, List<TimeSlot>> schedule = {};
    if (data['weeklySchedule'] != null) {
      final scheduleData = data['weeklySchedule'] as Map<String, dynamic>;
      scheduleData.forEach((day, slots) {
        schedule[day] =
            (slots as List).map((s) => TimeSlot.fromMap(s)).toList();
      });
    }

    return DoctorModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      departmentId: data['department'] ?? 'generalMedicine',
      specialization: data['specialization'] ?? '',
      bio: data['bio'],
      experienceYears: data['experienceYears'] ?? 0,
      qualifications: List<String>.from(data['qualifications'] ?? []),
      isAvailable: data['isAvailable'] ?? true,
      isActive: data['isActive'] ?? true,
      availabilityRequestStatus: data['availabilityRequestStatus'],
      pendingAvailabilityRequestId: data['pendingAvailabilityRequestId'],
      availabilityRequestReason: data['availabilityRequestReason'],
      availabilityRequestedAt:
          (data['availabilityRequestedAt'] as Timestamp?)?.toDate(),
      weeklySchedule: schedule,
      dailyNotificationTime: data['dailyNotificationTime'] ?? '21:00',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    Map<String, dynamic> scheduleMap = {};
    weeklySchedule.forEach((day, slots) {
      scheduleMap[day] = slots.map((s) => s.toMap()).toList();
    });

    return {
      'userId': userId,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'department': departmentId,
      'specialization': specialization,
      'bio': bio,
      'experienceYears': experienceYears,
      'qualifications': qualifications,
      'isAvailable': isAvailable,
      'isActive': isActive,
      'availabilityRequestStatus': availabilityRequestStatus,
      'pendingAvailabilityRequestId': pendingAvailabilityRequestId,
      'availabilityRequestReason': availabilityRequestReason,
      'availabilityRequestedAt': availabilityRequestedAt != null
          ? Timestamp.fromDate(availabilityRequestedAt!)
          : null,
      'weeklySchedule': scheduleMap,
      'dailyNotificationTime': dailyNotificationTime,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  DoctorModel copyWith({
    String? id,
    String? userId,
    String? name,
    String? email,
    String? photoUrl,
    String? departmentId,
    String? specialization,
    String? bio,
    int? experienceYears,
    List<String>? qualifications,
    bool? isAvailable,
    bool? isActive,
    String? availabilityRequestStatus,
    String? pendingAvailabilityRequestId,
    String? availabilityRequestReason,
    DateTime? availabilityRequestedAt,
    Map<String, List<TimeSlot>>? weeklySchedule,
    String? dailyNotificationTime,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DoctorModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      departmentId: departmentId ?? this.departmentId,
      specialization: specialization ?? this.specialization,
      bio: bio ?? this.bio,
      experienceYears: experienceYears ?? this.experienceYears,
      qualifications: qualifications ?? this.qualifications,
      isAvailable: isAvailable ?? this.isAvailable,
      isActive: isActive ?? this.isActive,
      availabilityRequestStatus:
          availabilityRequestStatus ?? this.availabilityRequestStatus,
      pendingAvailabilityRequestId:
          pendingAvailabilityRequestId ?? this.pendingAvailabilityRequestId,
      availabilityRequestReason:
          availabilityRequestReason ?? this.availabilityRequestReason,
      availabilityRequestedAt:
          availabilityRequestedAt ?? this.availabilityRequestedAt,
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      dailyNotificationTime:
          dailyNotificationTime ?? this.dailyNotificationTime,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get department display name (for backward compatibility)
  String get departmentName {
    // Convert camelCase to Title Case with spaces
    final words = departmentId.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)}',
    );
    return words[0].toUpperCase() + words.substring(1);
  }

  String get experienceDisplay =>
      '$experienceYears ${experienceYears == 1 ? 'year' : 'years'}';

  bool get hasPendingAvailabilityRequest =>
      availabilityRequestStatus == 'pending' &&
      pendingAvailabilityRequestId != null &&
      pendingAvailabilityRequestId!.isNotEmpty;

  /// Canonical lowercase weekday names matching backend schedule keys.
  static const List<String> canonicalWeekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// Returns the day of the week as a lowercase string (e.g. 'monday', 'tuesday').
  static String dayOfWeekName(DateTime date) {
    return canonicalWeekdays[date.weekday - 1];
  }

  /// Whether the doctor can currently accept appointment bookings.
  bool get canBook => isActive && isAvailable;

  /// Whether the doctor has any active, valid weekly schedule slots configured.
  /// Strictly checks canonical weekdays only; ignores non-canonical or malformed keys.
  bool get hasActiveSchedule {
    if (!canBook) return false;
    for (final day in canonicalWeekdays) {
      List<TimeSlot>? slots = weeklySchedule[day];
      if (slots == null || slots.isEmpty) {
        for (final entry in weeklySchedule.entries) {
          if (entry.key.toLowerCase() == day) {
            slots = entry.value;
            break;
          }
        }
      }
      if (slots != null) {
        for (final slot in slots) {
          if (slot.isValid) return true;
        }
      }
    }
    return false;
  }

  /// Returns valid, active weekly schedule time slots for the given [date].
  /// Never fabricates fallback slots; returns an empty list if doctor is
  /// unavailable/inactive, has no schedule, or the day has no valid slots.
  List<TimeSlot> getAvailableSlots(DateTime date) {
    if (!canBook) return const [];

    final dayName = dayOfWeekName(date);
    List<TimeSlot>? slots = weeklySchedule[dayName];
    if (slots == null || slots.isEmpty) {
      for (final entry in weeklySchedule.entries) {
        if (entry.key.toLowerCase() == dayName) {
          slots = entry.value;
          break;
        }
      }
    }

    if (slots == null || slots.isEmpty) return const [];

    return slots.where((slot) => slot.isValid).toList();
  }
}

/// Time slot model for doctor schedules
class TimeSlot {
  final String startTime;
  final String endTime;
  final bool isAvailable;

  TimeSlot({
    required this.startTime,
    required this.endTime,
    this.isAvailable = true,
  });

  factory TimeSlot.fromMap(Map<String, dynamic> map) {
    return TimeSlot(
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'] ?? '',
      isAvailable: map['isAvailable'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startTime': startTime,
      'endTime': endTime,
      'isAvailable': isAvailable,
    };
  }

  String get display => startTime;

  /// Full display with range (for detailed views)
  String get fullDisplay => '$startTime - $endTime';

  /// Matches canonical 2-digit 24-hour time HH:mm (00:00 - 23:59)
  /// Group 1: hour (00-23)
  /// Group 2: minute (00-59)
  static final RegExp _timeRegex = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  /// Parse time in canonical 2-digit HH:mm format to minutes from midnight (0..1439), or null if malformed.
  static int? parseMinutes(String time) {
    final match = _timeRegex.firstMatch(time);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Whether this slot is available and has valid, non-malformed start and end times
  /// where end time is strictly after start time.
  bool get isValid {
    if (!isAvailable) return false;
    final startMin = parseMinutes(startTime);
    final endMin = parseMinutes(endTime);
    if (startMin == null || endMin == null) return false;
    return endMin > startMin;
  }
}
