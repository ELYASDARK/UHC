import 'package:cloud_firestore/cloud_firestore.dart';

/// User roles in the system
enum UserRole { student, staff, doctor, admin }

/// User model representing students, staff, doctors, and admins
class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? photoUrl;
  final String? phoneNumber;
  final DateTime? dateOfBirth;
  final String? bloodType;
  final String? allergies;
  final UserRole role;
  final String? studentId;
  final String? staffId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final Map<String, dynamic>? notificationSettings;
  final String language;
  final String? googleEmail;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.photoUrl,
    this.phoneNumber,
    this.dateOfBirth,
    this.bloodType,
    this.allergies,
    this.role = UserRole.student,
    this.studentId,
    this.staffId,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.notificationSettings,
    this.language = 'en',
    this.googleEmail,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      email: data['email'] ?? '',
      fullName: data['fullName'] ?? '',
      photoUrl: data['photoUrl'],
      phoneNumber: data['phoneNumber'],
      dateOfBirth: data['dateOfBirth'] != null
          ? (data['dateOfBirth'] as Timestamp).toDate()
          : null,
      bloodType: data['bloodType'],
      allergies: data['allergies'],
      role: UserRole.values.firstWhere(
        (r) => r.name == data['role'],
        orElse: () => UserRole.student,
      ),
      studentId: data['studentId'],
      staffId: data['staffId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] ?? true,
      notificationSettings: data['notificationSettings'],
      language: data['language'] ?? 'en',
      googleEmail: data['googleEmail'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'fullName': fullName,
      'photoUrl': photoUrl,
      'phoneNumber': phoneNumber,
      'dateOfBirth':
          dateOfBirth != null ? Timestamp.fromDate(dateOfBirth!) : null,
      'bloodType': bloodType,
      'allergies': allergies,
      'role': role.name,
      'studentId': studentId,
      'staffId': staffId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isActive': isActive,
      'notificationSettings': notificationSettings,
      'language': language,
      'googleEmail': googleEmail,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    String? photoUrl,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? bloodType,
    String? allergies,
    UserRole? role,
    String? studentId,
    String? staffId,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    Map<String, dynamic>? notificationSettings,
    String? language,
    String? googleEmail,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      bloodType: bloodType ?? this.bloodType,
      allergies: allergies ?? this.allergies,
      role: role ?? this.role,
      studentId: studentId ?? this.studentId,
      staffId: staffId ?? this.staffId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      notificationSettings: notificationSettings ?? this.notificationSettings,
      language: language ?? this.language,
      googleEmail: googleEmail ?? this.googleEmail,
    );
  }

  bool get isDoctor => role == UserRole.doctor;
  bool get isAdmin => role == UserRole.admin;
  bool get isStaff => role == UserRole.staff;
  bool get isStudent => role == UserRole.student;

  String get displayRole {
    switch (role) {
      case UserRole.student:
        return 'Student';
      case UserRole.staff:
        return 'Staff';
      case UserRole.doctor:
        return 'Doctor';
      case UserRole.admin:
        return 'Admin';
    }
  }
}
