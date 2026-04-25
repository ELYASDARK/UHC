import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Service for calling Firebase Cloud Functions related to doctor management
class DoctorFunctionsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Create a new doctor account
  ///
  /// This creates:
  /// 1. Firebase Auth user with the doctor role
  /// 2. User document in Firestore with role='doctor'
  /// 3. Doctor document in Firestore linked to the user
  Future<Map<String, dynamic>> createDoctorAccount({
    required String email,
    required String password,
    required String name,
    required String specialization,
    required String department,
    String? bio,
    int? experienceYears,
    double? consultationFee,
    String? photoUrl,
    String? phoneNumber,
    List<String>? qualifications,
    Map<String, dynamic>? weeklySchedule,
    DateTime? dateOfBirth,
    String? dailyNotificationTime,
  }) async {
    try {
      final callable = _functions.httpsCallable('createDoctorAccount');
      final result = await callable.call<Map<String, dynamic>>({
        'email': email,
        'password': password,
        'name': name,
        'specialization': specialization,
        'department': department,
        'bio': bio,
        'experienceYears': experienceYears,
        'consultationFee': consultationFee,
        'photoUrl': photoUrl,
        'phoneNumber': phoneNumber,
        'qualifications': qualifications ?? [],
        'weeklySchedule': weeklySchedule,
        'dateOfBirth': dateOfBirth?.toIso8601String(),
        'dailyNotificationTime': dailyNotificationTime ?? '21:00',
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error creating doctor account: ${e.code} - ${e.message}');
      throw DoctorFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to create doctor account',
      );
    } catch (e) {
      debugPrint('Unexpected error creating doctor account: $e');
      throw DoctorFunctionException(
        code: 'unknown',
        message: 'An unexpected error occurred',
      );
    }
  }

  /// Update a doctor's email address
  Future<Map<String, dynamic>> updateDoctorEmail({
    required String doctorId,
    required String newEmail,
  }) async {
    try {
      final callable = _functions.httpsCallable('updateDoctorEmail');
      final result = await callable.call<Map<String, dynamic>>({
        'doctorId': doctorId,
        'newEmail': newEmail,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error updating doctor email: ${e.code} - ${e.message}');
      throw DoctorFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to update doctor email',
      );
    }
  }

  /// Delete a doctor account (auth user, user doc, and doctor doc)
  Future<Map<String, dynamic>> deleteDoctorAccount({
    required String doctorId,
  }) async {
    try {
      final callable = _functions.httpsCallable('deleteDoctorAccount');
      final result = await callable.call<Map<String, dynamic>>({
        'doctorId': doctorId,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error deleting doctor account: ${e.code} - ${e.message}');
      throw DoctorFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to delete doctor account',
      );
    }
  }

  /// Reset a doctor's password
  Future<Map<String, dynamic>> resetDoctorPassword({
    required String doctorId,
    required String newPassword,
  }) async {
    try {
      final callable = _functions.httpsCallable('resetDoctorPassword');
      final result = await callable.call<Map<String, dynamic>>({
        'doctorId': doctorId,
        'newPassword': newPassword,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error resetting doctor password: ${e.code} - ${e.message}');
      throw DoctorFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to reset doctor password',
      );
    }
  }

  /// Update a doctor's profile-safe fields.
  Future<Map<String, dynamic>> updateDoctorProfile({
    required String doctorId,
    String? name,
    String? specialization,
    String? department,
    String? bio,
    String? photoUrl,
    int? experienceYears,
    double? consultationFee,
    List<String>? qualifications,
    String? dailyNotificationTime,
    bool? isActive,
  }) async {
    try {
      final callable = _functions.httpsCallable('updateDoctorProfile');
      final result = await callable.call<Map<String, dynamic>>({
        'doctorId': doctorId,
        if (name != null) 'name': name,
        if (specialization != null) 'specialization': specialization,
        if (department != null) 'department': department,
        if (bio != null) 'bio': bio,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (experienceYears != null) 'experienceYears': experienceYears,
        if (consultationFee != null) 'consultationFee': consultationFee,
        if (qualifications != null) 'qualifications': qualifications,
        if (dailyNotificationTime != null)
          'dailyNotificationTime': dailyNotificationTime,
        if (isActive != null) 'isActive': isActive,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error updating doctor profile: ${e.code} - ${e.message}');
      throw DoctorFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to update doctor profile',
      );
    }
  }

  /// Activate/deactivate a doctor.
  Future<Map<String, dynamic>> setDoctorActiveStatus({
    required String doctorId,
    required bool isActive,
  }) async {
    try {
      final callable = _functions.httpsCallable('setDoctorActiveStatus');
      final result = await callable.call<Map<String, dynamic>>({
        'doctorId': doctorId,
        'isActive': isActive,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error updating doctor status: ${e.code} - ${e.message}');
      throw DoctorFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to update doctor status',
      );
    }
  }

  /// Update a doctor's weekly schedule.
  Future<Map<String, dynamic>> updateDoctorSchedule({
    required String doctorId,
    required Map<String, dynamic> weeklySchedule,
  }) async {
    try {
      final callable = _functions.httpsCallable('updateDoctorSchedule');
      final result = await callable.call<Map<String, dynamic>>({
        'doctorId': doctorId,
        'weeklySchedule': weeklySchedule,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error updating doctor schedule: ${e.code} - ${e.message}');
      throw DoctorFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to update doctor schedule',
      );
    }
  }
}

/// Exception for doctor function errors
class DoctorFunctionException implements Exception {
  final String code;
  final String message;

  DoctorFunctionException({required this.code, required this.message});

  @override
  String toString() => 'DoctorFunctionException: [$code] $message';

  /// Get user-friendly error message
  String get userMessage {
    switch (code) {
      case 'unauthenticated':
        return 'Please sign in to continue.';
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'already-exists':
        return 'An account with this email already exists.';
      case 'invalid-argument':
        return message;
      case 'not-found':
        return 'Doctor not found.';
      case 'failed-precondition':
        return message;
      default:
        return 'An error occurred. Please try again.';
    }
  }
}
