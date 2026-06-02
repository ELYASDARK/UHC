import * as functions from 'firebase-functions';

import { auth, db } from '../firebase';

/** Throws if caller is not authenticated. Returns the uid. */
export function requireAuth(context: { auth?: { uid: string } }): string {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'You must be logged in to perform this action.'
        );
    }
    return context.auth.uid;
}

/** Fetches the caller's user document. Throws if not found. */
export async function getCallerUserDoc(uid: string): Promise<FirebaseFirestore.DocumentSnapshot> {
    const doc = await db.collection('users').doc(uid).get();
    if (!doc.exists) {
        throw new functions.https.HttpsError('not-found', 'Caller user document not found.');
    }
    if (doc.data()?.isActive !== true) {
        throw new functions.https.HttpsError('permission-denied', 'Your account is inactive.');
    }
    const authUser = await auth.getUser(uid);
    const hasGoogleProvider = authUser.providerData.some((provider) => provider.providerId === 'google.com');
    if (!hasGoogleProvider) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Link your Google account before accessing UHC services.'
        );
    }
    return doc;
}

/** Throws if caller is not superAdmin. */
export function requireSuperAdmin(callerDoc: FirebaseFirestore.DocumentSnapshot): void {
    if (callerDoc.data()?.role !== 'superAdmin') {
        throw new functions.https.HttpsError('permission-denied', 'Only Super Admins can perform this action.');
    }
}

/** Throws if caller (admin) lacks the given permission. SuperAdmin bypasses. */
export function requirePermission(callerDoc: FirebaseFirestore.DocumentSnapshot, permissionKey: string): void {
    const data = callerDoc.data();
    if (!data) throw new functions.https.HttpsError('not-found', 'Caller data missing.');
    if (data.role === 'superAdmin') return; // bypass
    if (data.role !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can perform this action.');
    }
    const perms = data.adminPermissions as Record<string, unknown> | undefined;
    if (!perms) {
        throw new functions.https.HttpsError('permission-denied', `Missing permission: ${permissionKey}`);
    }
    if (perms[permissionKey] !== true) {
        throw new functions.https.HttpsError('permission-denied', `Missing permission: ${permissionKey}`);
    }
}

export async function revokeSessionsAndClearFcm(uid: string): Promise<void> {
    try {
        await auth.revokeRefreshTokens(uid);
    } catch (error) {
        if ((error as { code?: string })?.code !== 'auth/user-not-found') {
            throw error;
        }
    }
    await clearUserFcmTokens(uid);
}

export async function clearUserFcmTokens(uid: string): Promise<void> {
    const parentRef = db.collection('user_tokens').doc(uid);
    const tokensSnap = await parentRef.collection('tokens').get();
    for (let i = 0; i < tokensSnap.docs.length; i += 500) {
        const batch = db.batch();
        tokensSnap.docs.slice(i, i + 500).forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
    }
    await parentRef.delete().catch(() => { });
}


export const READ_ONLY_ADMIN_PERMISSIONS: Record<string, boolean> = {
    'users.view': true,
    'users.manageNonAdmin': false,
    'doctors.view': true,
    'doctors.manage': false,
    'departments.view': true,
    'departments.manage': false,
    'appointments.view': false,
    'appointments.manage': false,
    'analytics.view': true,
    'reports.view': true,
    'reports.export': false,
    'notifications.send': false,
};

const ADMIN_PERMISSION_KEYS = Object.keys(READ_ONLY_ADMIN_PERMISSIONS);

export function sanitizeAdminPermissions(
    permissions: unknown
): Record<string, boolean> {
    if (!permissions || typeof permissions !== 'object' || Array.isArray(permissions)) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Missing or invalid permissions.'
        );
    }

    const raw = permissions as Record<string, unknown>;
    const unknownKeys = Object.keys(raw).filter((key) => !ADMIN_PERMISSION_KEYS.includes(key));
    if (unknownKeys.length > 0) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `Unknown permission key: ${unknownKeys[0]}`
        );
    }

    const sanitized: Record<string, boolean> = {};
    for (const key of ADMIN_PERMISSION_KEYS) {
        const value = raw[key];
        if (typeof value !== 'boolean') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                `Permission ${key} must be true or false.`
            );
        }
        sanitized[key] = value;
    }
    return sanitized;
}
