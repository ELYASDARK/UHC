import * as functions from 'firebase-functions';

import { admin, auth, db } from './firebase';
import {
    getCallerUserDoc,
    requireAuth,
    requirePermission,
    revokeSessionsAndClearFcm,
} from './shared/auth';
import { MIN_PASSWORD_ERROR_LONG, MIN_PASSWORD_LENGTH } from './shared/errors';

interface CreateDoctorData {
    email: string;
    password: string;
    name: string;
    specialization: string;
    department: string;
    bio?: string;
    experienceYears?: number;
    consultationFee?: number;
    photoUrl?: string;
    phoneNumber?: string;
    qualifications?: string[];
    weeklySchedule?: Record<string, unknown[]>;
    dateOfBirth?: string; // ISO date string
}

/**
 * Cloud Function to create a doctor account
 * This creates both the Firebase Auth user and the Firestore documents
 */
export const createDoctorAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<CreateDoctorData>) => {
        const data = request.data;

        // Auth + permission check
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');

        // Validate required fields
        if (!data.email || !data.password || !data.name || !data.specialization) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Missing required fields: email, password, name, specialization'
            );
        }

        // Validate password strength
        if (data.password.length < MIN_PASSWORD_LENGTH) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                MIN_PASSWORD_ERROR_LONG
            );
        }

        try {
            // Create Firebase Auth user
            const userRecord = await auth.createUser({
                email: data.email,
                password: data.password,
                displayName: `Dr. ${data.name}`,
                emailVerified: false,
            });

            const now = admin.firestore.Timestamp.now();

            // Create user document with doctor role
            await db.collection('users').doc(userRecord.uid).set({
                email: data.email,
                fullName: data.name,
                photoUrl: data.photoUrl || null,
                phoneNumber: data.phoneNumber || null,
                dateOfBirth: data.dateOfBirth ? admin.firestore.Timestamp.fromDate(new Date(data.dateOfBirth)) : null,
                bloodType: null,
                allergies: null,
                role: 'doctor',
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
                requiresInitialPasswordChange: true,
                initialPasswordChangedAt: null,
            });

            // Use provided schedule or default to empty arrays
            const defaultSchedule = {
                monday: [],
                tuesday: [],
                wednesday: [],
                thursday: [],
                friday: [],
                saturday: [],
                sunday: [],
            };

            // Create doctor document
            const doctorDoc = await db.collection('doctors').add({
                userId: userRecord.uid,
                email: data.email,
                name: data.name,
                photoUrl: data.photoUrl || null,
                phoneNumber: data.phoneNumber || null,
                department: data.department || 'generalMedicine',
                specialization: data.specialization,
                bio: data.bio || '',
                experienceYears: data.experienceYears || 0,
                consultationFee: data.consultationFee || 0,
                qualifications: data.qualifications || [],
                isAvailable: true,
                isActive: true,
                weeklySchedule: data.weeklySchedule || defaultSchedule,
                createdAt: now,
                updatedAt: now,
            });

            return {
                success: true,
                userId: userRecord.uid,
                doctorId: doctorDoc.id,
                message: 'Doctor account created successfully',
            };
        } catch (error: unknown) {
            console.error('Error creating doctor account:', error);

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
                'Failed to create doctor account. Please try again.'
            );
        }
    }
);

/**
 * Cloud Function to update a doctor's auth email
 */
export const updateDoctorEmail = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ doctorId: string; newEmail: string }>) => {
        const data = request.data;

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');

        try {
            // Get doctor document to find userId
            const doctorDoc = await db.collection('doctors').doc(data.doctorId).get();
            if (!doctorDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Doctor not found.');
            }

            const doctorData = doctorDoc.data();
            const userId = doctorData?.userId;

            if (userId) {
                // Update Firebase Auth email
                await auth.updateUser(userId, { email: data.newEmail });

                // Update user document
                await db.collection('users').doc(userId).update({
                    email: data.newEmail,
                    updatedAt: admin.firestore.Timestamp.now(),
                });
            }

            // Update doctor document
            await db.collection('doctors').doc(data.doctorId).update({
                email: data.newEmail,
                updatedAt: admin.firestore.Timestamp.now(),
            });

            return { success: true, message: 'Email updated successfully' };
        } catch (error) {
            console.error('Error updating doctor email:', error);
            throw new functions.https.HttpsError(
                'internal',
                'Failed to update doctor email.'
            );
        }
    }
);

/**
 * Cloud Function to delete a doctor account
 */
export const deleteDoctorAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ doctorId: string }>) => {
        const data = request.data;

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');

        try {
            // Get doctor document to find userId
            const doctorDoc = await db.collection('doctors').doc(data.doctorId).get();
            if (!doctorDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Doctor not found.');
            }

            const doctorData = doctorDoc.data();
            const userId = doctorData?.userId;

            // Delete Firebase Auth user if exists
            if (userId && !userId.startsWith('sample_')) {
                try {
                    await auth.deleteUser(userId);
                } catch (authError) {
                    console.log('Auth user may not exist:', authError);
                }

                // Delete user document
                await db.collection('users').doc(userId).delete();
            }

            // Delete doctor document
            await db.collection('doctors').doc(data.doctorId).delete();

            return { success: true, message: 'Doctor account deleted successfully' };
        } catch (error) {
            console.error('Error deleting doctor account:', error);
            throw new functions.https.HttpsError(
                'internal',
                'Failed to delete doctor account.'
            );
        }
    }
);

/**
 * Cloud Function to reset a doctor's password
 */
export const resetDoctorPassword = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ doctorId: string; newPassword: string }>) => {
        const data = request.data;

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');

        if (!data.newPassword || data.newPassword.length < MIN_PASSWORD_LENGTH) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                MIN_PASSWORD_ERROR_LONG
            );
        }

        try {
            // Get doctor document to find userId
            const doctorDoc = await db.collection('doctors').doc(data.doctorId).get();
            if (!doctorDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Doctor not found.');
            }

            const doctorData = doctorDoc.data();
            const userId = doctorData?.userId;

            if (!userId || userId.startsWith('sample_')) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'This doctor does not have an associated auth account.'
                );
            }

            // Update password and require the doctor to replace it on next login.
            await auth.updateUser(userId, { password: data.newPassword });
            await db.collection('users').doc(userId).update({
                requiresInitialPasswordChange: true,
                initialPasswordChangedAt: admin.firestore.FieldValue.delete(),
                updatedAt: admin.firestore.Timestamp.now(),
            });

            return { success: true, message: 'Password reset successfully' };
        } catch (error) {
            console.error('Error resetting doctor password:', error);
            throw new functions.https.HttpsError(
                'internal',
                'Failed to reset doctor password.'
            );
        }
    }
);

interface UpdateDoctorProfileData {
    doctorId: string;
    name?: string;
    specialization?: string;
    department?: string;
    bio?: string | null;
    photoUrl?: string | null;
    experienceYears?: number;
    consultationFee?: number;
    qualifications?: string[];
    dailyNotificationTime?: string;
    isActive?: boolean;
}

/**
 * Cloud Function to update doctor profile-safe fields.
 */
export const updateDoctorProfile = functions.https.onCall(
    async (request: functions.https.CallableRequest<UpdateDoctorProfileData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');

        if (!data.doctorId) {
            throw new functions.https.HttpsError('invalid-argument', 'doctorId is required.');
        }

        const doctorRef = db.collection('doctors').doc(data.doctorId);
        const doctorSnap = await doctorRef.get();
        if (!doctorSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }

        const updates: Record<string, unknown> = {
            updatedAt: admin.firestore.Timestamp.now(),
        };
        if (data.name !== undefined) updates.name = data.name.trim();
        if (data.specialization !== undefined) updates.specialization = data.specialization.trim();
        if (data.department !== undefined) updates.department = data.department;
        if (data.bio !== undefined) updates.bio = data.bio ?? '';
        if (data.photoUrl !== undefined) updates.photoUrl = data.photoUrl;
        if (data.experienceYears !== undefined) updates.experienceYears = data.experienceYears;
        if (data.consultationFee !== undefined) updates.consultationFee = data.consultationFee;
        if (data.qualifications !== undefined) updates.qualifications = data.qualifications;
        if (data.dailyNotificationTime !== undefined) {
            updates.dailyNotificationTime = data.dailyNotificationTime;
        }
        if (data.isActive !== undefined) updates.isActive = data.isActive;

        await doctorRef.update(updates);

        return { success: true, message: 'Doctor profile updated successfully' };
    }
);

interface SetDoctorActiveStatusData {
    doctorId: string;
    isActive: boolean;
}

/**
 * Cloud Function to activate/deactivate a doctor record.
 */
export const setDoctorActiveStatus = functions.https.onCall(
    async (request: functions.https.CallableRequest<SetDoctorActiveStatusData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');

        if (!data.doctorId || typeof data.isActive !== 'boolean') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'doctorId and isActive are required.'
            );
        }

        const doctorRef = db.collection('doctors').doc(data.doctorId);
        const doctorSnap = await doctorRef.get();
        if (!doctorSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }

        await doctorRef.update({
            isActive: data.isActive,
            updatedAt: admin.firestore.Timestamp.now(),
        });

        const doctorUserId = doctorSnap.data()?.userId as string | undefined;
        if (!data.isActive && doctorUserId) {
            await db.collection('users').doc(doctorUserId).update({
                isActive: false,
                updatedAt: admin.firestore.Timestamp.now(),
            }).catch(() => { });
            await revokeSessionsAndClearFcm(doctorUserId);
        }

        return {
            success: true,
            message: data.isActive ? 'Doctor activated successfully' : 'Doctor deactivated successfully',
        };
    }
);

interface UpdateDoctorScheduleData {
    doctorId: string;
    weeklySchedule: Record<string, unknown[]>;
}

/**
 * Cloud Function to update a doctor's weekly schedule.
 */
export const updateDoctorSchedule = functions.https.onCall(
    async (request: functions.https.CallableRequest<UpdateDoctorScheduleData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');

        if (!data.doctorId || !data.weeklySchedule || typeof data.weeklySchedule !== 'object') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'doctorId and weeklySchedule are required.'
            );
        }

        const doctorRef = db.collection('doctors').doc(data.doctorId);
        const doctorSnap = await doctorRef.get();
        if (!doctorSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }

        await doctorRef.update({
            weeklySchedule: data.weeklySchedule,
            updatedAt: admin.firestore.Timestamp.now(),
        });

        return { success: true, message: 'Schedule updated successfully' };
    }
);

