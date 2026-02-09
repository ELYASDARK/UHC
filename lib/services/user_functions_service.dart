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
    try {
      final callable = _functions.httpsCallable('createUserAccount');
      final result = await callable.call<Map<String, dynamic>>({
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

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Firebase Functions Error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error creating user account: $e');
      rethrow;
    }
  }
}
