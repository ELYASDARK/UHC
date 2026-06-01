import * as functions from 'firebase-functions';

import { admin, auth, db } from './firebase';
import { writeAdminAuditLog } from './shared/audit';
import {
    getCallerUserDoc,
    requireAuth,
    requirePermission,
    revokeSessionsAndClearFcm,
} from './shared/auth';
import { MIN_PASSWORD_ERROR_LONG, MIN_PASSWORD_LENGTH, toHttpsError } from './shared/errors';
import {
    deleteProfilePhotos,
    ProfilePhotoUploadData,
    uploadProfilePhoto,
} from './shared/profilePhotos';

export const completeInitialPasswordChange = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ newPassword: string }>) => {
        const callerUid = requireAuth(request);
        const data = request.data;

        if (!data.newPassword || data.newPassword.length < MIN_PASSWORD_LENGTH) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                MIN_PASSWORD_ERROR_LONG
            );
        }

        const userRef = db.collection('users').doc(callerUid);
        const userDoc = await userRef.get();

        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User profile not found.');
        }

        const userData = userDoc.data()!;
        if (userData.isActive !== true) {
            throw new functions.https.HttpsError('permission-denied', 'Your account is inactive.');
        }

        const role = userData.role as string | undefined;
        if (!['doctor', 'student', 'staff'].includes(role ?? '')) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Initial password change is only available for doctor and patient accounts.'
            );
        }

        if (userData.requiresInitialPasswordChange !== true) {
            return { success: true, message: 'No initial password change required.' };
        }

        const now = admin.firestore.Timestamp.now();
        await userRef.update({
            requiresInitialPasswordChange: false,
            initialPasswordChangedAt: now,
            updatedAt: now,
        });

        return { success: true, message: 'Initial password change completed.' };
    }
);

interface CreateUserData {
    email: string;
    password: string;
    fullName: string;
    role: 'student' | 'staff';
    phoneNumber?: string;
    dateOfBirth?: string; // ISO date string
    studentId?: string;
    staffId?: string;
    photoUrl?: string;
    photoUpload?: ProfilePhotoUploadData;
}

/**
 * Cloud Function to create a user account (student or staff only).
 * Admin accounts must be created via createAdminAccount (Super Admin only).
 */
export const createUserAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<CreateUserData>) => {
        const data = request.data;

        // Auth + permission check
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'users.manageNonAdmin');

        // Validate required fields
        if (!data.email || !data.password || !data.fullName || !data.role) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Missing required fields: email, password, fullName, role'
            );
        }

        // Only student/staff allowed — admin creation uses createAdminAccount
        if (!['student', 'staff'].includes(data.role)) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Invalid role. Must be student or staff. Use createAdminAccount for admin accounts.'
            );
        }

        // Validate password strength
        if (data.password.length < MIN_PASSWORD_LENGTH) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                MIN_PASSWORD_ERROR_LONG
            );
        }

        let createdUid: string | null = null;
        try {
            // Create Firebase Auth user
            const userRecord = await auth.createUser({
                email: data.email,
                password: data.password,
                displayName: data.fullName,
                emailVerified: false,
            });
            createdUid = userRecord.uid;

            const now = admin.firestore.Timestamp.now();
            const uploadedPhotoUrl = await uploadProfilePhoto(
                userRecord.uid,
                data.photoUpload
            );

            // Create user document
            await db.collection('users').doc(userRecord.uid).set({
                email: data.email,
                fullName: data.fullName,
                role: data.role,
                phoneNumber: data.phoneNumber || null,
                photoUrl: uploadedPhotoUrl || data.photoUrl || null,
                dateOfBirth: data.dateOfBirth ? admin.firestore.Timestamp.fromDate(new Date(data.dateOfBirth)) : null,
                studentId: data.studentId || null,
                staffId: data.staffId || null,
                isActive: true,
                notificationSettings: {
                    email: true,
                    push: true,
                    sms: false,
                },
                language: 'en',
                requiresInitialPasswordChange: true,
                initialPasswordChangedAt: null,
                createdAt: now,
                updatedAt: now,
            });

            return {
                success: true,
                userId: userRecord.uid,
                message: `${data.role.charAt(0).toUpperCase() + data.role.slice(1)} account created successfully`,
            };
        } catch (error: unknown) {
            console.error('Error creating user account:', error);
            if (createdUid) {
                await auth.deleteUser(createdUid).catch((cleanupError) => {
                    console.error('Failed to clean up created auth user:', cleanupError);
                });
                await deleteProfilePhotos(createdUid).catch((cleanupError) => {
                    console.error('Failed to clean up uploaded profile photo:', cleanupError);
                });
            }
            if (error instanceof functions.https.HttpsError) {
                throw error;
            }

            // Handle specific Firebase Auth errors
            if (error && typeof error === 'object' && 'code' in error) {
                const firebaseError = error as { code: string; message?: string };
                if (firebaseError.code === 'auth/email-already-exists') {
                    throw new functions.https.HttpsError(
                        'already-exists',
                        'A user with this email already exists.'
                    );
                }
                if (firebaseError.code === 'auth/invalid-email') {
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'The email address is invalid.'
                    );
                }
                if (firebaseError.code === 'auth/weak-password') {
                    throw new functions.https.HttpsError(
                        'invalid-argument',
                        'The password is too weak.'
                    );
                }
            }

            throw new functions.https.HttpsError(
                'internal',
                'Failed to create user account. Please try again.'
            );
        }
    }
);

interface BootstrapSelfUserData {
    fullName: string;
    phoneNumber?: string;
    dateOfBirth?: string; // ISO date string
}

/**
 * Create the caller's own user document after self-registration.
 * This keeps users/{userId} create blocked in Firestore rules while
 * preserving the existing registerWithEmail UX.
 */
export const bootstrapSelfUserDocument = functions.https.onCall(
    async (request: functions.https.CallableRequest<BootstrapSelfUserData>) => {
        const callerUid = requireAuth(request);
        const data = request.data;

        if (!data?.fullName || !data.fullName.trim()) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'fullName is required.'
            );
        }

        const userRef = db.collection('users').doc(callerUid);
        const existingDoc = await userRef.get();
        if (existingDoc.exists) {
            return { success: true, message: 'User document already exists.' };
        }

        const authUser = await auth.getUser(callerUid);
        const now = admin.firestore.Timestamp.now();

        await userRef.set({
            email: authUser.email || '',
            fullName: data.fullName.trim(),
            photoUrl: authUser.photoURL || null,
            phoneNumber: data.phoneNumber || null,
            dateOfBirth: data.dateOfBirth
                ? admin.firestore.Timestamp.fromDate(new Date(data.dateOfBirth))
                : null,
            bloodType: null,
            allergies: null,
            role: 'student',
            studentId: null,
            staffId: null,
            createdAt: now,
            updatedAt: now,
            isActive: true,
            notificationSettings: {
                email: true,
                push: true,
                sms: false,
            },
            language: 'en',
            googleEmail: null,
        });

        return { success: true, message: 'User profile initialized successfully.' };
    }
);

interface SetUserActiveStatusData {
    targetUid: string;
    isActive: boolean;
}

/**
 * Activate/deactivate a non-admin user.
 * Admin requires users.manageNonAdmin permission.
 * Super Admin bypasses permission checks.
 */
export const setUserActiveStatus = functions.https.onCall(
    async (request: functions.https.CallableRequest<SetUserActiveStatusData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'users.manageNonAdmin');
        const { targetUid, isActive } = request.data;

        if (!targetUid || typeof isActive !== 'boolean') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Missing or invalid targetUid/isActive.'
            );
        }

        const callerRole = callerDoc.data()!.role;
        const targetDoc = await db.collection('users').doc(targetUid).get();
        if (!targetDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        }

        const targetRole = targetDoc.data()!.role;
        if (targetRole === 'superAdmin') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Cannot modify Super Admin status via this function.'
            );
        }
        if (targetRole === 'admin') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Use setAdminActiveStatus for admin accounts.'
            );
        }
        if (callerRole === 'admin' && targetRole === 'admin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Admins cannot modify admin accounts.'
            );
        }

        await db.collection('users').doc(targetUid).update({
            isActive,
            updatedAt: admin.firestore.Timestamp.now(),
        });
        if (!isActive) {
            await revokeSessionsAndClearFcm(targetUid);
        }

        return {
            success: true,
            message: isActive ? 'User activated successfully.' : 'User deactivated successfully.',
        };
    }
);

interface UnlinkGoogleProviderByAdminData {
    targetUid: string;
}

interface ChangeUserRoleByAdminData {
    targetUid: string;
    newRole: 'student' | 'staff';
}

/**
 * Change role between student/staff for non-admin targets.
 * Admin requires users.manageNonAdmin permission.
 * Super Admin bypasses permission checks, but cannot use this for admin/superAdmin.
 */
export const changeUserRoleByAdmin = functions.https.onCall(
    async (request: functions.https.CallableRequest<ChangeUserRoleByAdminData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'users.manageNonAdmin');

        const { targetUid, newRole } = request.data;
        if (!targetUid || !newRole) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Missing targetUid or newRole.',
            );
        }
        if (!['student', 'staff'].includes(newRole)) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Invalid role. Only student/staff are allowed here.',
            );
        }

        const callerRole = callerDoc.data()!.role;
        const targetRef = db.collection('users').doc(targetUid);
        const targetDoc = await targetRef.get();
        if (!targetDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        }
        const targetData = targetDoc.data()!;
        const oldRole = targetData.role as string;

        if (oldRole === 'superAdmin' || oldRole === 'admin') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Cannot change admin/superAdmin roles via this function.',
            );
        }
        if (callerRole === 'admin' && (oldRole === 'admin' || oldRole === 'superAdmin')) {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Admins cannot modify admin/superAdmin accounts.',
            );
        }

        if (oldRole === newRole) {
            return {
                success: true,
                message: 'Role already set.',
            };
        }

        const updates: Record<string, unknown> = {
            role: newRole,
            updatedAt: admin.firestore.Timestamp.now(),
            studentId: newRole === 'student' ? targetUid : null,
            staffId: newRole === 'staff' ? targetUid : null,
        };
        await targetRef.update(updates);

        await writeAdminAuditLog({
            actorUid: callerUid,
            actorRole: callerRole,
            actorName: callerDoc.data()!.fullName,
            targetUid,
            targetName: targetData.fullName,
            targetRoleBefore: oldRole,
            targetRoleAfter: newRole,
            action: oldRole === 'student' ? 'user.promoteToStaff' : 'user.demoteToStudent',
        });

        return {
            success: true,
            message: `Role changed from ${oldRole} to ${newRole}.`,
        };
    }
);

/**
 * Unlink Google sign-in provider from a non-admin user.
 * Admin requires users.manageNonAdmin permission.
 * Super Admin bypasses permission checks.
 */
export const unlinkGoogleProviderByAdmin = functions.https.onCall(
    async (request: functions.https.CallableRequest<UnlinkGoogleProviderByAdminData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'users.manageNonAdmin');
        const { targetUid } = request.data;

        if (!targetUid) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'targetUid is required.',
            );
        }

        const callerData = callerDoc.data()!;
        const callerRole = callerData.role;
        const targetRef = db.collection('users').doc(targetUid);
        const targetDoc = await targetRef.get();
        if (!targetDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        }

        const targetData = targetDoc.data()!;
        const targetRole = targetData.role;
        if (targetRole === 'superAdmin') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Cannot unlink Google for Super Admin accounts via this function.',
            );
        }
        if (targetRole === 'admin') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Use governance flow for admin account provider management.',
            );
        }
        if (callerRole === 'admin' && (targetRole === 'admin' || targetRole === 'superAdmin')) {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Admins cannot modify admin/superAdmin accounts.',
            );
        }

        const authUser = await auth.getUser(targetUid);
        const providerIds = new Set(authUser.providerData.map((p) => p.providerId));
        if (!providerIds.has('google.com')) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Target user does not have Google linked.',
            );
        }
        if (!providerIds.has('password')) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Cannot unlink Google: user has no email/password sign-in linked.',
            );
        }

        await auth.updateUser(targetUid, {
            providersToUnlink: ['google.com'],
        });

        await targetRef.update({
            googleEmail: null,
            updatedAt: admin.firestore.Timestamp.now(),
        });

        await writeAdminAuditLog({
            actorUid: callerUid,
            actorRole: callerRole,
            actorName: callerData.fullName,
            targetUid,
            targetName: targetData.fullName,
            targetRoleBefore: targetRole,
            targetRoleAfter: targetRole,
            action: 'user.googleUnlink',
        });

        return {
            success: true,
            message: 'Google provider unlinked successfully.',
        };
    }
);

interface UpdateUserProfileByAdminData {
    targetUid: string;
    fullName?: string;
    phoneNumber?: string | null;
    photoUrl?: string | null;
    photoUpload?: ProfilePhotoUploadData | null;
    dateOfBirth?: string | null; // ISO date string
    studentId?: string | null;
    staffId?: string | null;
}

/**
 * Update profile-safe fields for a target user via server-side enforcement.
 * Admins can manage non-admin users only.
 * Super Admins can manage all users, including super admins.
 */
export const updateUserProfileByAdmin = functions.https.onCall(
    async (request: functions.https.CallableRequest<UpdateUserProfileByAdminData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'users.manageNonAdmin');
        const data = request.data;

        if (!data?.targetUid) {
            throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
        }

        const callerRole = callerDoc.data()!.role;
        const targetRef = db.collection('users').doc(data.targetUid);
        const targetDoc = await targetRef.get();
        if (!targetDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        }

        const targetRole = targetDoc.data()!.role;
        if (targetRole === 'superAdmin' && callerRole !== 'superAdmin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only Super Admin can edit Super Admin profile.'
            );
        }
        if (callerRole === 'admin' && targetRole === 'admin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Admins cannot edit admin accounts.'
            );
        }

        const updates: Record<string, unknown> = {
            updatedAt: admin.firestore.Timestamp.now(),
        };

        if (data.fullName !== undefined) {
            const trimmed = data.fullName.trim();
            if (!trimmed) {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    'fullName cannot be empty.'
                );
            }
            updates.fullName = trimmed;
        }
        if (data.phoneNumber !== undefined) updates.phoneNumber = data.phoneNumber;
        if (data.photoUpload !== undefined && data.photoUpload !== null) {
            updates.photoUrl = await uploadProfilePhoto(data.targetUid, data.photoUpload);
        } else if (data.photoUrl !== undefined) {
            updates.photoUrl = data.photoUrl;
        }
        if (data.studentId !== undefined) updates.studentId = data.studentId;
        if (data.staffId !== undefined) updates.staffId = data.staffId;
        if (data.dateOfBirth !== undefined) {
            updates.dateOfBirth = data.dateOfBirth
                ? admin.firestore.Timestamp.fromDate(new Date(data.dateOfBirth))
                : null;
        }

        await targetRef.update(updates);

        return {
            success: true,
            message: 'User profile updated successfully.',
        };
    }
);

interface DeleteUserAccountData {
    targetUid: string;
}

/**
 * Delete a student or staff account from User Management.
 * Admin accounts use deleteAdminAccount, doctors use deleteDoctorAccount.
 */
export const deleteUserAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<DeleteUserAccountData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'users.manageNonAdmin');
        const data = request.data;

        if (!data?.targetUid) {
            throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
        }
        if (data.targetUid === callerUid) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'You cannot delete your own account from User Management.'
            );
        }

        const callerRole = callerDoc.data()!.role;
        const targetRef = db.collection('users').doc(data.targetUid);
        const targetDoc = await targetRef.get();
        if (!targetDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        }

        const targetData = targetDoc.data()!;
        const targetRole = targetData.role as string | undefined;
        if (targetRole === 'superAdmin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Super Admin accounts cannot be deleted from User Management.'
            );
        }
        if (targetRole === 'admin') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Admin accounts must be deleted from Super Admin controls.'
            );
        }
        if (targetRole === 'doctor') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Doctor accounts must be deleted from Doctor Management.'
            );
        }
        if (callerRole !== 'superAdmin' && targetRole !== 'student' && targetRole !== 'staff') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Admins can delete student and staff accounts only.'
            );
        }

        try {
            await revokeSessionsAndClearFcm(data.targetUid);
            await auth.deleteUser(data.targetUid).catch((error) => {
                if ((error as { code?: string })?.code !== 'auth/user-not-found') {
                    throw error;
                }
            });
            await deleteProfilePhotos(data.targetUid);
            await targetRef.delete();

            return {
                success: true,
                message: 'User account deleted successfully.',
            };
        } catch (error) {
            console.error('Error deleting user account:', error);
            throw toHttpsError(error, 'Failed to delete user account.');
        }
    }
);

// ─────────────────────────────────────────────────────────
