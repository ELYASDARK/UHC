import 'package:cloud_firestore/cloud_firestore.dart';

/// Actions that can be logged in the admin audit log
enum AuditAction {
  adminCreate,
  adminDemote,
  adminPromote,
  adminActivate,
  adminDeactivate,
  adminPasswordReset,
  adminDelete,
  adminForceSignOut,
  adminPermissionsUpdate,
  superAdminSlotAssign,
  superAdminSlotRotate,
}

/// Extension to convert AuditAction to/from Firestore string
extension AuditActionExtension on AuditAction {
  String get value {
    switch (this) {
      case AuditAction.adminCreate:
        return 'admin.create';
      case AuditAction.adminDemote:
        return 'admin.demote';
      case AuditAction.adminPromote:
        return 'admin.promote';
      case AuditAction.adminActivate:
        return 'admin.activate';
      case AuditAction.adminDeactivate:
        return 'admin.deactivate';
      case AuditAction.adminPasswordReset:
        return 'admin.passwordReset';
      case AuditAction.adminDelete:
        return 'admin.delete';
      case AuditAction.adminForceSignOut:
        return 'admin.forceSignOut';
      case AuditAction.adminPermissionsUpdate:
        return 'admin.permissionsUpdate';
      case AuditAction.superAdminSlotAssign:
        return 'superAdmin.slotAssign';
      case AuditAction.superAdminSlotRotate:
        return 'superAdmin.slotRotate';
    }
  }

  static AuditAction fromString(String value) {
    switch (value) {
      case 'admin.create':
        return AuditAction.adminCreate;
      case 'admin.demote':
        return AuditAction.adminDemote;
      case 'admin.promote':
        return AuditAction.adminPromote;
      case 'admin.activate':
        return AuditAction.adminActivate;
      case 'admin.deactivate':
        return AuditAction.adminDeactivate;
      case 'admin.passwordReset':
        return AuditAction.adminPasswordReset;
      case 'admin.delete':
        return AuditAction.adminDelete;
      case 'admin.forceSignOut':
        return AuditAction.adminForceSignOut;
      case 'admin.permissionsUpdate':
        return AuditAction.adminPermissionsUpdate;
      case 'superAdmin.slotAssign':
        return AuditAction.superAdminSlotAssign;
      case 'superAdmin.slotRotate':
        return AuditAction.superAdminSlotRotate;
      default:
        return AuditAction.adminCreate;
    }
  }
}

/// Represents a single admin audit log entry
class AdminAuditLog {
  final String id;
  final String actorUid;
  final String actorRole;
  final String? actorName;
  final String targetUid;
  final String? targetRoleBefore;
  final String? targetRoleAfter;
  final String? targetName;
  final AuditAction action;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const AdminAuditLog({
    required this.id,
    required this.actorUid,
    required this.actorRole,
    this.actorName,
    required this.targetUid,
    this.targetRoleBefore,
    this.targetRoleAfter,
    this.targetName,
    required this.action,
    this.before,
    this.after,
    this.metadata,
    required this.createdAt,
  });

  factory AdminAuditLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdminAuditLog(
      id: doc.id,
      actorUid: data['actorUid'] ?? '',
      actorRole: data['actorRole'] ?? '',
      actorName: data['actorName'],
      targetUid: data['targetUid'] ?? '',
      targetRoleBefore: data['targetRoleBefore'],
      targetRoleAfter: data['targetRoleAfter'],
      targetName: data['targetName'],
      action: AuditActionExtension.fromString(data['action'] ?? ''),
      before: data['before'] as Map<String, dynamic>?,
      after: data['after'] as Map<String, dynamic>?,
      metadata: data['metadata'] as Map<String, dynamic>?,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'actorUid': actorUid,
      'actorRole': actorRole,
      'actorName': actorName,
      'targetUid': targetUid,
      'targetRoleBefore': targetRoleBefore,
      'targetRoleAfter': targetRoleAfter,
      'targetName': targetName,
      'action': action.value,
      'before': before,
      'after': after,
      'metadata': metadata,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Human-readable description of the audit action
  String get actionDescription {
    switch (action) {
      case AuditAction.adminCreate:
        return 'Created admin account';
      case AuditAction.adminDemote:
        return 'Demoted admin';
      case AuditAction.adminPromote:
        return 'Promoted to admin';
      case AuditAction.adminActivate:
        return 'Activated admin account';
      case AuditAction.adminDeactivate:
        return 'Deactivated admin account';
      case AuditAction.adminPasswordReset:
        return 'Reset admin password';
      case AuditAction.adminDelete:
        return 'Deleted admin account';
      case AuditAction.adminForceSignOut:
        return 'Forced sign-out';
      case AuditAction.adminPermissionsUpdate:
        return 'Updated admin permissions';
      case AuditAction.superAdminSlotAssign:
        return 'Assigned Super Admin slot';
      case AuditAction.superAdminSlotRotate:
        return 'Rotated Super Admin slot';
    }
  }
}
