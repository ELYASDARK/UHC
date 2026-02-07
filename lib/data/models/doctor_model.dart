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
  final List<String> languages;
  final bool isAvailable;
  final Map<String, List<TimeSlot>> weeklySchedule;
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
    this.languages = const ['English'],
    this.isAvailable = true,
    this.weeklySchedule = const {},
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
        schedule[day] = (slots as List)
            .map((s) => TimeSlot.fromMap(s))
            .toList();
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
      languages: List<String>.from(data['languages'] ?? ['English']),
      isAvailable: data['isAvailable'] ?? true,
      weeklySchedule: schedule,
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
      'languages': languages,
      'isAvailable': isAvailable,
      'weeklySchedule': scheduleMap,
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
    List<String>? languages,
    bool? isAvailable,
    Map<String, List<TimeSlot>>? weeklySchedule,
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
      languages: languages ?? this.languages,
      isAvailable: isAvailable ?? this.isAvailable,
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
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
}
