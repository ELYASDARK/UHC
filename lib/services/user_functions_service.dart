import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Service for calling user-related Cloud Functions
class UserFunctionsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Create a new user account (admin, student, or staff)
  Future<Map<String, dynamic>> createUserAccount({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? studentId,
    String? staffId,
    String? photoUrl,
  }) async {
    return _call('createUserAccount', {
      'email': email,
      'password': password,
      'fullName': fullName,
      'role': role,
      'phoneNumber': phoneNumber,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'studentId': studentId,
      'staffId': staffId,
      'photoUrl': photoUrl,
    });
  }

  /// Activate/deactivate a non-admin user.
  Future<Map<String, dynamic>> setUserActiveStatus({
    required String targetUid,
    required bool isActive,
  }) async {
    return _call('setUserActiveStatus', {
      'targetUid': targetUid,
      'isActive': isActive,
    });
  }

  /// Change non-admin user role between student/staff.
  Future<Map<String, dynamic>> changeUserRoleByAdmin({
    required String targetUid,
    required String newRole,
  }) async {
    return _call('changeUserRoleByAdmin', {
      'targetUid': targetUid,
      'newRole': newRole,
    });
  }

  /// Update profile-safe fields for a target user through Cloud Functions.
  Future<Map<String, dynamic>> updateUserProfileByAdmin({
    required String targetUid,
    String? fullName,
    String? phoneNumber,
    String? photoUrl,
    DateTime? dateOfBirth,
    String? studentId,
    String? staffId,
  }) async {
    return _call('updateUserProfileByAdmin', {
      'targetUid': targetUid,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'studentId': studentId,
      'staffId': staffId,
    });
  }

  /// Unlink Google provider from a target non-admin user.
  Future<Map<String, dynamic>> unlinkGoogleProvider({
    required String targetUid,
  }) async {
    return _call('unlinkGoogleProviderByAdmin', {
      'targetUid': targetUid,
    });
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
