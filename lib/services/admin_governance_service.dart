import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Service for Super Admin governance callable functions.
/// All methods call server-side Cloud Functions that enforce superAdmin-only access.
class AdminGovernanceService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ─── Admin Account Management ─────────────────────────

  /// Create a new admin account. Super Admin only.
  Future<Map<String, dynamic>> createAdminAccount({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    DateTime? dateOfBirth,
    String? photoUrl,
  }) async {
    return _call('createAdminAccount', {
      'email': email,
      'password': password,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'photoUrl': photoUrl,
    });
  }

  /// Change an admin's role (promote/demote). Super Admin only.
  Future<Map<String, dynamic>> changeAdminRole({
    required String targetUid,
    required String newRole,
  }) async {
    return _call('changeAdminRole', {
      'targetUid': targetUid,
      'newRole': newRole,
    });
  }

  /// Activate or deactivate an admin. Super Admin only.
  Future<Map<String, dynamic>> setAdminActiveStatus({
    required String targetUid,
    required bool isActive,
  }) async {
    return _call('setAdminActiveStatus', {
      'targetUid': targetUid,
      'isActive': isActive,
    });
  }

  /// Reset an admin's password. Super Admin only.
  Future<Map<String, dynamic>> resetAdminPassword({
    required String targetUid,
    required String newPassword,
  }) async {
    return _call('resetAdminPassword', {
      'targetUid': targetUid,
      'newPassword': newPassword,
    });
  }

  /// Delete an admin account. Super Admin only.
  Future<Map<String, dynamic>> deleteAdminAccount({
    required String targetUid,
  }) async {
    return _call('deleteAdminAccount', {'targetUid': targetUid});
  }

  /// Force sign-out a user by revoking sessions. Super Admin only.
  Future<Map<String, dynamic>> forceSignOutUser({
    required String targetUid,
  }) async {
    return _call('forceSignOutUser', {'targetUid': targetUid});
  }

  /// Set granular permissions on an admin account. Super Admin only.
  Future<Map<String, dynamic>> setAdminPermissions({
    required String targetUid,
    required Map<String, bool> permissions,
  }) async {
    return _call('setAdminPermissions', {
      'targetUid': targetUid,
      'permissions': permissions,
    });
  }

  // ─── Super Admin Slot Management ──────────────────────

  /// Assign a user to a Super Admin slot (primary/backup).
  Future<Map<String, dynamic>> assignSuperAdminSlot({
    required String targetUid,
    required String slotType, // 'primary' or 'backup'
  }) async {
    return _call('assignSuperAdminSlot', {
      'targetUid': targetUid,
      'slotType': slotType,
    });
  }

  /// Rotate a Super Admin slot: demote current holder, promote replacement.
  Future<Map<String, dynamic>> rotateSuperAdminSlot({
    required String slotType, // 'primary' or 'backup'
    required String replacementUid,
  }) async {
    return _call('rotateSuperAdminSlot', {
      'slotType': slotType,
      'replacementUid': replacementUid,
    });
  }

  // ─── Audit Logs ───────────────────────────────────────

  /// List admin audit logs with optional filtering. Super Admin only.
  Future<Map<String, dynamic>> listAdminAuditLogs({
    int? limit,
    String? targetUid,
    String? actorUid,
    String? action,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    return _call('listAdminAuditLogs', {
      if (limit != null) 'limit': limit,
      if (targetUid != null) 'targetUid': targetUid,
      if (actorUid != null) 'actorUid': actorUid,
      if (action != null) 'action': action,
      if (dateFrom != null) 'dateFrom': dateFrom.toIso8601String(),
      if (dateTo != null) 'dateTo': dateTo.toIso8601String(),
    });
  }

  // ─── Helper ───────────────────────────────────────────

  Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      final callable = _functions.httpsCallable(functionName);
      final result = await callable.call<Map<String, dynamic>>(data);
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
