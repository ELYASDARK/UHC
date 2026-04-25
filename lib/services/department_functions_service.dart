import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Service for calling Firebase Cloud Functions related to department management.
class DepartmentFunctionsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> createDepartment({
    required String key,
    required String name,
    required String description,
    required String iconName,
    required String colorHex,
    required Map<String, dynamic> workingHours,
  }) async {
    try {
      final callable = _functions.httpsCallable('createDepartment');
      final result = await callable.call<Map<String, dynamic>>({
        'key': key,
        'name': name,
        'description': description,
        'iconName': iconName,
        'colorHex': colorHex,
        'workingHours': workingHours,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error creating department: ${e.code} - ${e.message}');
      throw DepartmentFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to create department',
      );
    }
  }

  Future<Map<String, dynamic>> updateDepartment({
    required String departmentId,
    required String key,
    required String name,
    required String description,
    required String iconName,
    required String colorHex,
    required Map<String, dynamic> workingHours,
  }) async {
    try {
      final callable = _functions.httpsCallable('updateDepartment');
      final result = await callable.call<Map<String, dynamic>>({
        'departmentId': departmentId,
        'key': key,
        'name': name,
        'description': description,
        'iconName': iconName,
        'colorHex': colorHex,
        'workingHours': workingHours,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error updating department: ${e.code} - ${e.message}');
      throw DepartmentFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to update department',
      );
    }
  }

  Future<Map<String, dynamic>> setDepartmentActiveStatus({
    required String departmentId,
    required bool isActive,
  }) async {
    try {
      final callable = _functions.httpsCallable('setDepartmentActiveStatus');
      final result = await callable.call<Map<String, dynamic>>({
        'departmentId': departmentId,
        'isActive': isActive,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error setting department status: ${e.code} - ${e.message}');
      throw DepartmentFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to update department status',
      );
    }
  }

  Future<Map<String, dynamic>> deleteDepartment({
    required String departmentId,
  }) async {
    try {
      final callable = _functions.httpsCallable('deleteDepartment');
      final result = await callable.call<Map<String, dynamic>>({
        'departmentId': departmentId,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Error deleting department: ${e.code} - ${e.message}');
      throw DepartmentFunctionException(
        code: e.code,
        message: e.message ?? 'Failed to delete department',
      );
    }
  }
}

class DepartmentFunctionException implements Exception {
  final String code;
  final String message;

  DepartmentFunctionException({required this.code, required this.message});

  String get userMessage {
    switch (code) {
      case 'unauthenticated':
        return 'Please sign in to continue.';
      case 'permission-denied':
        return 'You do not have permission to perform this action.';
      case 'already-exists':
        return 'Department key already exists.';
      case 'not-found':
        return 'Department not found.';
      case 'invalid-argument':
        return message;
      default:
        return 'An error occurred. Please try again.';
    }
  }
}
