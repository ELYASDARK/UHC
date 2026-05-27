import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_permissions_model.dart';

/// User roles in the system
enum UserRole { student, staff, doctor, admin, superAdmin }

/// Super Admin slot type (exactly 2 super admins: 1 primary + 1 backup)
enum SuperAdminType { primary, backup }

/// User model representing students, staff, doctors, admins, and super admins
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
  final String themeMode;
  final String? googleEmail;
  final bool requiresInitialPasswordChange;

  /// Only set when role == superAdmin
  final SuperAdminType? superAdminType;

  /// Granular permissions for admin users (ignored for superAdmin — full access)
  final AdminPermissions? adminPermissions;

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
    this.themeMode = 'system',
    this.googleEmail,
    this.requiresInitialPasswordChange = false,
    this.superAdminType,
    this.adminPermissions,
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
      themeMode: data['themeMode'] ?? 'system',
      googleEmail: data['googleEmail'],
      requiresInitialPasswordChange:
          data['requiresInitialPasswordChange'] ?? false,
      superAdminType: data['superAdminType'] != null
          ? SuperAdminType.values.firstWhere(
              (t) => t.name == data['superAdminType'],
              orElse: () => SuperAdminType.primary,
            )
          : null,
      adminPermissions: data['adminPermissions'] != null
          ? AdminPermissions.fromMap(
              data['adminPermissions'] as Map<String, dynamic>)
          : null,
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
      'themeMode': themeMode,
      'googleEmail': googleEmail,
      'requiresInitialPasswordChange': requiresInitialPasswordChange,
      'superAdminType': superAdminType?.name,
      'adminPermissions': adminPermissions?.toMap(),
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
    String? themeMode,
    String? googleEmail,
    bool? requiresInitialPasswordChange,
    SuperAdminType? superAdminType,
    AdminPermissions? adminPermissions,
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
      themeMode: themeMode ?? this.themeMode,
      googleEmail: googleEmail ?? this.googleEmail,
      requiresInitialPasswordChange:
          requiresInitialPasswordChange ?? this.requiresInitialPasswordChange,
      superAdminType: superAdminType ?? this.superAdminType,
      adminPermissions: adminPermissions ?? this.adminPermissions,
    );
  }

  bool get isDoctor => role == UserRole.doctor;
  bool get isAdmin => role == UserRole.admin;
  bool get isStaff => role == UserRole.staff;
  bool get isStudent => role == UserRole.student;
  bool get isSuperAdmin => role == UserRole.superAdmin;

  /// Returns true if user is admin or superAdmin (for shared admin features)
  bool get isAdminOrSuperAdmin =>
      role == UserRole.admin || role == UserRole.superAdmin;

  /// Check if this admin user has a specific permission.
  /// Super Admins always return true (bypass all checks).
  bool hasPermission(String permissionKey) {
    if (isSuperAdmin) return true;
    if (!isAdmin) return false;
    // Firestore rules require explicit adminPermissions for admin access.
    if (adminPermissions == null) return false;
    return adminPermissions!.getByKey(permissionKey);
  }

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
      case UserRole.superAdmin:
        return 'Super Admin';
    }
  }
}
