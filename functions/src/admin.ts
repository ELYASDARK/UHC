import * as functions from 'firebase-functions';

import { admin, auth, db } from './firebase';
import { writeAdminAuditLog } from './shared/audit';
import {
    clearUserFcmTokens,
    getCallerUserDoc,
    READ_ONLY_ADMIN_PERMISSIONS,
    requireAuth,
    requireSuperAdmin,
    revokeSessionsAndClearFcm,
    sanitizeAdminPermissions,
} from './shared/auth';
import { MIN_PASSWORD_ERROR, MIN_PASSWORD_LENGTH, toHttpsError } from './shared/errors';
import {
    deleteProfilePhotos,
    ProfilePhotoUploadData,
    uploadProfilePhoto,
} from './shared/profilePhotos';
import { requireTargetUserId } from './shared/validation';

export const createAdminAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<{
        email: string; password: string; fullName: string;
        phoneNumber?: string; dateOfBirth?: string; photoUrl?: string;
        photoUpload?: ProfilePhotoUploadData;
    }>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const data = request.data;

        if (!data.email || !data.password || !data.fullName) {
            throw new functions.https.HttpsError('invalid-argument', 'Missing required fields.');
        }
        if (data.password.length < MIN_PASSWORD_LENGTH) {
            throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR);
        }

        let createdUid: string | null = null;
        try {
            const userRecord = await auth.createUser({
                email: data.email, password: data.password,
                displayName: data.fullName, emailVerified: false,
            });
            createdUid = userRecord.uid;
            const now = admin.firestore.Timestamp.now();
            const uploadedPhotoUrl = await uploadProfilePhoto(
                userRecord.uid,
                data.photoUpload
            );
            await db.collection('users').doc(userRecord.uid).set({
                email: data.email, fullName: data.fullName, role: 'admin',
                phoneNumber: data.phoneNumber || null, photoUrl: uploadedPhotoUrl || data.photoUrl || null,
                dateOfBirth: data.dateOfBirth ? admin.firestore.Timestamp.fromDate(new Date(data.dateOfBirth)) : null,
                isActive: true,
                adminPermissions: READ_ONLY_ADMIN_PERMISSIONS,
                notificationSettings: { email: true, push: true, sms: false },
                language: 'en', createdAt: now, updatedAt: now,
                bloodType: null, allergies: null, studentId: null, staffId: null,
            });
            await writeAdminAuditLog({
                actorUid: callerUid, actorRole: callerDoc.data()!.role,
                actorName: callerDoc.data()!.fullName,
                targetUid: userRecord.uid, targetName: data.fullName,
                targetRoleAfter: 'admin', action: 'admin.create',
            });
            return { success: true, userId: userRecord.uid, message: 'Admin account created successfully' };
        } catch (error: unknown) {
            if (createdUid) {
                await auth.deleteUser(createdUid).catch((cleanupError) => {
                    console.error('Failed to clean up created admin auth user:', cleanupError);
                });
                await deleteProfilePhotos(createdUid).catch((cleanupError) => {
                    console.error('Failed to clean up uploaded admin profile photo:', cleanupError);
                });
            }
            if (error instanceof functions.https.HttpsError) {
                throw error;
            }
            if (error && typeof error === 'object' && 'code' in error) {
                const e = error as { code: string };
                if (e.code === 'auth/email-already-exists')
                    throw new functions.https.HttpsError('already-exists', 'A user with this email already exists.');
            }
            throw new functions.https.HttpsError('internal', 'Failed to create admin account.');
        }
    }
);

/**
 * Change an admin user's role. Super Admin only.
 */
export const changeAdminRole = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ targetUid: string; newRole: string }>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { targetUid, newRole } = request.data;

        if (!targetUid || !newRole) throw new functions.https.HttpsError('invalid-argument', 'Missing targetUid or newRole.');
        if (!['admin', 'student', 'staff'].includes(newRole))
            throw new functions.https.HttpsError('invalid-argument', 'Invalid role. Cannot assign doctor or superAdmin via this function.');

        const targetDoc = await db.collection('users').doc(targetUid).get();
        if (!targetDoc.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');
        const targetData = targetDoc.data()!;
        const oldRole = targetData.role;

        if (oldRole === 'superAdmin')
            throw new functions.https.HttpsError('failed-precondition', 'Cannot change a Super Admin role via this function.');

        await db.collection('users').doc(targetUid).update({ role: newRole, updatedAt: admin.firestore.Timestamp.now() });
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
            targetUid, targetName: targetData.fullName,
            targetRoleBefore: oldRole, targetRoleAfter: newRole,
            action: oldRole === 'admin' ? 'admin.demote' : 'admin.promote',
        });
        return { success: true, message: `Role changed from ${oldRole} to ${newRole}` };
    }
);

/**
 * Activate or deactivate an admin. Super Admin only.
 */
export const setAdminActiveStatus = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ targetUid: string; isActive: boolean }>) => {
        try {
            const callerUid = requireAuth(request);
            const callerDoc = await getCallerUserDoc(callerUid);
            requireSuperAdmin(callerDoc);
            const { targetUid, isActive } = request.data;

            if (!targetUid || typeof isActive !== 'boolean') {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    'Missing or invalid targetUid/isActive.'
                );
            }

            const targetDoc = await db.collection('users').doc(targetUid).get();
            if (!targetDoc.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');
            const targetRole = targetDoc.data()!.role;
            if (targetRole !== 'admin')
                throw new functions.https.HttpsError('failed-precondition', 'This function can only target admin accounts.');

            await db.collection('users').doc(targetUid).update({ isActive, updatedAt: admin.firestore.Timestamp.now() });
            if (!isActive) {
                await revokeSessionsAndClearFcm(targetUid);
            }
            await writeAdminAuditLog({
                actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
                targetUid, targetName: targetDoc.data()!.fullName,
                action: isActive ? 'admin.activate' : 'admin.deactivate',
            });
            return { success: true, message: isActive ? 'Admin activated' : 'Admin deactivated' };
        } catch (error) {
            console.error('setAdminActiveStatus failed:', error);
            throw toHttpsError(error, 'Failed to update admin active status.');
        }
    }
);

/**
 * Reset an admin's password. Super Admin only.
 */
export const resetAdminPassword = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ targetUid: string; newPassword: string }>) => {
        try {
            const callerUid = requireAuth(request);
            const callerDoc = await getCallerUserDoc(callerUid);
            requireSuperAdmin(callerDoc);
            const { targetUid, newPassword } = request.data;

            if (!targetUid || !newPassword || newPassword.length < MIN_PASSWORD_LENGTH)
                throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR);
            const targetDoc = await db.collection('users').doc(targetUid).get();
            if (!targetDoc.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');
            if (targetDoc.data()!.role !== 'admin')
                throw new functions.https.HttpsError('failed-precondition', 'This function can only target admin accounts.');

            await auth.updateUser(targetUid, { password: newPassword });
            await writeAdminAuditLog({
                actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
                targetUid, targetName: targetDoc.data()!.fullName,
                action: 'admin.passwordReset',
            });
            return { success: true, message: 'Password reset successfully' };
        } catch (error) {
            console.error('resetAdminPassword failed:', error);
            throw toHttpsError(error, 'Failed to reset admin password.');
        }
    }
);

/**
 * Delete an admin account. Super Admin only.
 */
export const deleteAdminAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ targetUid: string }>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { targetUid } = request.data;

        const targetDoc = await db.collection('users').doc(targetUid).get();
        if (!targetDoc.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');
        const targetData = targetDoc.data()!;
        if (targetData.role !== 'admin')
            throw new functions.https.HttpsError('failed-precondition', 'This function can only target admin accounts.');

        try { await auth.deleteUser(targetUid); } catch (e) { console.log('Auth user may not exist:', e); }
        await deleteProfilePhotos(targetUid);
        await db.collection('users').doc(targetUid).delete();
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
            targetUid, targetName: targetData.fullName,
            targetRoleBefore: targetData.role, action: 'admin.delete',
        });
        return { success: true, message: 'Admin account deleted successfully' };
    }
);

/**
 * Force sign-out a user by revoking refresh tokens. Super Admin only.
 */
export const forceSignOutUser = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ targetUid: string }>) => {
        try {
            const callerUid = requireAuth(request);
            const callerDoc = await getCallerUserDoc(callerUid);
            requireSuperAdmin(callerDoc);
            const { targetUid } = request.data;

            if (!targetUid) {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    'targetUid is required.'
                );
            }

            const targetDoc = await db.collection('users').doc(targetUid).get();
            if (!targetDoc.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');

            let authUserFound = true;
            try {
                await auth.revokeRefreshTokens(targetUid);
            } catch (error) {
                const code = (error as { code?: string })?.code;
                if (code === 'auth/user-not-found') {
                    authUserFound = false;
                } else {
                    throw error;
                }
            }

            // Also remove FCM tokens to stop push notifications
            await clearUserFcmTokens(targetUid);
            await writeAdminAuditLog({
                actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
                targetUid, targetName: targetDoc.data()!.fullName,
                action: 'admin.forceSignOut',
                metadata: { authUserFound },
            });
            return {
                success: true,
                message: authUserFound
                    ? 'User sessions revoked'
                    : 'Auth user not found; local tokens were cleared.',
            };
        } catch (error) {
            console.error('forceSignOutUser failed:', error);
            throw toHttpsError(error, 'Failed to force sign out user.');
        }
    }
);

/**
 * Set admin permissions. Super Admin only.
 */
export const setAdminPermissions = functions.https.onCall(
    async (request: functions.https.CallableRequest<{
        targetUid: string;
        permissions: Record<string, boolean>;
    }>) => {
        try {
            const callerUid = requireAuth(request);
            const callerDoc = await getCallerUserDoc(callerUid);
            requireSuperAdmin(callerDoc);
            const data = request.data || {};
            const { permissions } = data;
            const targetUid = requireTargetUserId(data.targetUid, 'targetUid');

            if (!targetUid || !permissions || typeof permissions !== 'object') {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    'Missing or invalid targetUid/permissions.'
                );
            }
            const sanitizedPermissions = sanitizeAdminPermissions(permissions);

            const targetDoc = await db.collection('users').doc(targetUid).get();
            if (!targetDoc.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');
            if (targetDoc.data()!.role !== 'admin')
                throw new functions.https.HttpsError('failed-precondition', 'Permissions can only be set on admin accounts.');

            const oldPerms = targetDoc.data()!.adminPermissions || {};
            await db.collection('users').doc(targetUid).update({
                adminPermissions: sanitizedPermissions,
                updatedAt: admin.firestore.Timestamp.now(),
            });
            await writeAdminAuditLog({
                actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
                targetUid, targetName: targetDoc.data()!.fullName,
                action: 'admin.permissionsUpdate',
                before: oldPerms as Record<string, unknown>,
                after: sanitizedPermissions as Record<string, unknown>,
            });
            return { success: true, message: 'Permissions updated' };
        } catch (error) {
            console.error('setAdminPermissions failed:', error);
            throw toHttpsError(error, 'Failed to update admin permissions.');
        }
    }
);

// ─────────────────────────────────────────────────────────
// Super Admin Slot Management (strict two-account model)
// ─────────────────────────────────────────────────────────

/**
 * Assign a user to a Super Admin slot (primary or backup).
 * Runs inside a Firestore transaction to enforce constraints:
 * - Max 2 superAdmins total
 * - Exactly one primary, exactly one backup
 * Super Admin only.
 */
export const assignSuperAdminSlot = functions.https.onCall(
    async (request: functions.https.CallableRequest<{
        targetUid: string; slotType: 'primary' | 'backup';
    }>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { targetUid, slotType } = request.data;

        if (!['primary', 'backup'].includes(slotType))
            throw new functions.https.HttpsError('invalid-argument', 'slotType must be primary or backup.');

        const result = await db.runTransaction(async (tx) => {
            // Read current super admins
            const superAdminsSnap = await tx.get(
                db.collection('users').where('role', '==', 'superAdmin')
            );
            const currentSlots = superAdminsSnap.docs.map(d => ({
                uid: d.id, slotType: d.data().superAdminType as string,
            }));

            // Check if this slot is already occupied by someone else
            const existingSlotHolder = currentSlots.find(s => s.slotType === slotType);
            if (existingSlotHolder && existingSlotHolder.uid !== targetUid) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    `The ${slotType} slot is already occupied. Use rotateSuperAdminSlot to replace.`
                );
            }

            // Check max 2
            const otherSuperAdmins = currentSlots.filter(s => s.uid !== targetUid);
            if (otherSuperAdmins.length >= 2) {
                throw new functions.https.HttpsError('failed-precondition', 'Maximum 2 Super Admin slots reached.');
            }

            // Read target
            const targetRef = db.collection('users').doc(targetUid);
            const targetSnap = await tx.get(targetRef);
            if (!targetSnap.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');
            const oldRole = targetSnap.data()!.role;

            // Block existing superAdmins from switching slots (would orphan the other slot)
            if (oldRole === 'superAdmin') {
                const currentSlotType = targetSnap.data()!.superAdminType;
                if (currentSlotType && currentSlotType !== slotType) {
                    throw new functions.https.HttpsError(
                        'failed-precondition',
                        `Target already holds the ${currentSlotType} slot. Use rotateSuperAdminSlot to replace.`
                    );
                }
            }

            tx.update(targetRef, {
                role: 'superAdmin', superAdminType: slotType,
                updatedAt: admin.firestore.Timestamp.now(),
            });
            return { oldRole, targetName: targetSnap.data()!.fullName };
        });

        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
            targetUid, targetName: result.targetName,
            targetRoleBefore: result.oldRole, targetRoleAfter: 'superAdmin',
            action: 'superAdmin.slotAssign',
            after: { slotType } as Record<string, unknown>,
        });
        return { success: true, message: `Assigned ${slotType} Super Admin slot` };
    }
);

/**
 * Rotate a Super Admin slot: demote the current holder and promote the replacement.
 * Runs inside a transaction to ensure atomicity.
 * Super Admin only.
 */
export const rotateSuperAdminSlot = functions.https.onCall(
    async (request: functions.https.CallableRequest<{
        slotType: 'primary' | 'backup'; replacementUid: string;
    }>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { slotType, replacementUid } = request.data;

        if (!['primary', 'backup'].includes(slotType))
            throw new functions.https.HttpsError('invalid-argument', 'slotType must be primary or backup.');

        const result = await db.runTransaction(async (tx) => {
            // Find current holder of this slot
            const slotSnap = await tx.get(
                db.collection('users')
                    .where('role', '==', 'superAdmin')
                    .where('superAdminType', '==', slotType)
            );
            if (slotSnap.empty) throw new functions.https.HttpsError('not-found', `No current ${slotType} Super Admin found.`);

            const currentHolder = slotSnap.docs[0];
            const currentHolderUid = currentHolder.id;

            if (currentHolderUid === replacementUid)
                throw new functions.https.HttpsError('failed-precondition', 'Replacement is already the slot holder.');

            // Read replacement
            const replacementRef = db.collection('users').doc(replacementUid);
            const replacementSnap = await tx.get(replacementRef);
            if (!replacementSnap.exists) throw new functions.https.HttpsError('not-found', 'Replacement user not found.');

            // Block if replacement already holds the OTHER super admin slot
            if (replacementSnap.data()!.role === 'superAdmin') {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'Replacement already holds a Super Admin slot. Demote them first.'
                );
            }

            // Demote current holder to admin
            tx.update(db.collection('users').doc(currentHolderUid), {
                role: 'admin', superAdminType: admin.firestore.FieldValue.delete(),
                updatedAt: admin.firestore.Timestamp.now(),
            });
            // Promote replacement
            tx.update(replacementRef, {
                role: 'superAdmin', superAdminType: slotType,
                updatedAt: admin.firestore.Timestamp.now(),
            });
            return {
                demotedName: currentHolder.data().fullName,
                demotedUid: currentHolderUid,
                promotedName: replacementSnap.data()!.fullName,
                promotedOldRole: replacementSnap.data()!.role,
            };
        });

        // Log both actions
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
            targetUid: result.demotedUid, targetName: result.demotedName,
            targetRoleBefore: 'superAdmin', targetRoleAfter: 'admin',
            action: 'superAdmin.slotRotate', metadata: { slotType, direction: 'demote' },
        });
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
            targetUid: replacementUid, targetName: result.promotedName,
            targetRoleBefore: result.promotedOldRole, targetRoleAfter: 'superAdmin',
            action: 'superAdmin.slotRotate', metadata: { slotType, direction: 'promote' },
        });
        return { success: true, message: `Rotated ${slotType} Super Admin slot` };
    }
);

// ─────────────────────────────────────────────────────────
// Audit Log Query
// ─────────────────────────────────────────────────────────

/**
 * List admin audit logs with optional filtering. Super Admin only.
 */
export const listAdminAuditLogs = functions.https.onCall(
    async (request: functions.https.CallableRequest<{
        limit?: number;
        targetUid?: string;
        actorUid?: string;
        action?: string;
        dateFrom?: string; // ISO date string
        dateTo?: string; // ISO date string
    }>) => {
        try {
            const callerUid = requireAuth(request);
            const callerDoc = await getCallerUserDoc(callerUid);
            requireSuperAdmin(callerDoc);
            const {
                limit: queryLimit,
                targetUid,
                actorUid,
                action,
                dateFrom,
                dateTo,
            } = request.data || {};

            let dateFromValue: Date | null = null;
            let dateToValue: Date | null = null;
            if (dateFrom) {
                const parsed = new Date(dateFrom);
                if (Number.isNaN(parsed.getTime())) {
                    throw new functions.https.HttpsError('invalid-argument', 'dateFrom must be a valid ISO date string.');
                }
                dateFromValue = parsed;
            }
            if (dateTo) {
                const parsed = new Date(dateTo);
                if (Number.isNaN(parsed.getTime())) {
                    throw new functions.https.HttpsError('invalid-argument', 'dateTo must be a valid ISO date string.');
                }
                dateToValue = parsed;
            }
            if (dateFromValue && dateToValue && dateFromValue > dateToValue) {
                throw new functions.https.HttpsError('invalid-argument', 'dateFrom cannot be later than dateTo.');
            }

            const requestedLimit = Math.min(Math.max(queryLimit || 100, 1), 500);
            const pageSize = Math.min(Math.max(requestedLimit * 2, 100), 500);
            const maxScannedDocs = 3000;
            let query: FirebaseFirestore.Query = db.collection('admin_audit_logs');

            const indexedFilters = [
                { field: 'targetUid', value: targetUid },
                { field: 'actorUid', value: actorUid },
                { field: 'action', value: action },
            ].filter((filter): filter is { field: string; value: string } => Boolean(filter.value));
            const primaryIndexedFilter = indexedFilters[0];
            if (primaryIndexedFilter) {
                query = query.where(primaryIndexedFilter.field, '==', primaryIndexedFilter.value);
            }
            if (dateFromValue) {
                query = query.where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dateFromValue));
            }
            if (dateToValue) {
                query = query.where('createdAt', '<=', admin.firestore.Timestamp.fromDate(dateToValue));
            }
            query = query.orderBy('createdAt', 'desc');

            const filteredDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
            let scannedDocs = 0;
            let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | null = null;
            while (filteredDocs.length <= requestedLimit && scannedDocs < maxScannedDocs) {
                const remainingScanBudget = maxScannedDocs - scannedDocs;
                let pageQuery = query.limit(Math.min(pageSize, remainingScanBudget));
                if (lastDoc) {
                    pageQuery = pageQuery.startAfter(lastDoc);
                }
                const snap = await pageQuery.get();
                if (snap.empty) break;
                scannedDocs += snap.docs.length;
                lastDoc = snap.docs[snap.docs.length - 1];

                for (const doc of snap.docs) {
                    const data = doc.data();
                    if (targetUid && data.targetUid !== targetUid) continue;
                    if (actorUid && data.actorUid !== actorUid) continue;
                    if (action && data.action !== action) continue;

                    const createdAtDate = data.createdAt?.toDate?.() as Date | undefined;
                    if (dateFromValue && (!createdAtDate || createdAtDate < dateFromValue)) continue;
                    if (dateToValue && (!createdAtDate || createdAtDate > dateToValue)) continue;
                    filteredDocs.push(doc);
                    if (filteredDocs.length > requestedLimit) break;
                }
                if (snap.docs.length < Math.min(pageSize, remainingScanBudget)) break;
            }

            const visibleDocs = filteredDocs.slice(0, requestedLimit);
            const logs = visibleDocs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
            }));
            return {
                success: true,
                logs,
                hasMore: filteredDocs.length > requestedLimit || scannedDocs >= maxScannedDocs,
                scanned: scannedDocs,
                scanLimit: maxScannedDocs,
            };
        } catch (error) {
            console.error('listAdminAuditLogs failed:', error);
            throw toHttpsError(error, 'Failed to load admin audit logs.');
        }
    }
);
