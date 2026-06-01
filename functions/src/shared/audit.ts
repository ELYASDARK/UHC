import { admin, db } from '../firebase';

export async function writeAdminAuditLog(params: {
    actorUid: string;
    actorRole: string;
    actorName?: string;
    targetUid: string;
    targetName?: string;
    targetRoleBefore?: string;
    targetRoleAfter?: string;
    action: string;
    before?: Record<string, unknown>;
    after?: Record<string, unknown>;
    metadata?: Record<string, unknown>;
}): Promise<void> {
    const payload = {
        ...params,
        createdAt: admin.firestore.Timestamp.now(),
    };

    // Firestore rejects undefined values; strip optional undefined fields.
    const sanitized = Object.fromEntries(
        Object.entries(payload).filter(([, value]) => value !== undefined)
    );

    await db.collection('admin_audit_logs').add(sanitized);
}

