import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

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
        const context = request;

        // Check if the caller is authenticated and is an admin
        if (!context.auth) {
            throw new functions.https.HttpsError(
                'unauthenticated',
                'You must be logged in to perform this action.'
            );
        }

        // Verify caller is admin
        const callerDoc = await db.collection('users').doc(context.auth.uid).get();
        if (!callerDoc.exists || callerDoc.data()?.role !== 'admin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only admins can create doctor accounts.'
            );
        }

        // Validate required fields
        if (!data.email || !data.password || !data.name || !data.specialization) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Missing required fields: email, password, name, specialization'
            );
        }

        // Validate password strength
        if (data.password.length < 6) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Password must be at least 6 characters long'
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
        const context = request;

        if (!context.auth) {
            throw new functions.https.HttpsError(
                'unauthenticated',
                'You must be logged in to perform this action.'
            );
        }

        // Verify caller is admin
        const callerDoc = await db.collection('users').doc(context.auth.uid).get();
        if (!callerDoc.exists || callerDoc.data()?.role !== 'admin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only admins can update doctor accounts.'
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
        const context = request;

        if (!context.auth) {
            throw new functions.https.HttpsError(
                'unauthenticated',
                'You must be logged in to perform this action.'
            );
        }

        // Verify caller is admin
        const callerDoc = await db.collection('users').doc(context.auth.uid).get();
        if (!callerDoc.exists || callerDoc.data()?.role !== 'admin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only admins can delete doctor accounts.'
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
        const context = request;

        if (!context.auth) {
            throw new functions.https.HttpsError(
                'unauthenticated',
                'You must be logged in to perform this action.'
            );
        }

        // Verify caller is admin
        const callerDoc = await db.collection('users').doc(context.auth.uid).get();
        if (!callerDoc.exists || callerDoc.data()?.role !== 'admin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only admins can reset doctor passwords.'
            );
        }

        if (!data.newPassword || data.newPassword.length < 6) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Password must be at least 6 characters long.'
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

            // Update password
            await auth.updateUser(userId, { password: data.newPassword });

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

interface CreateUserData {
    email: string;
    password: string;
    fullName: string;
    role: 'admin' | 'student' | 'staff';
    phoneNumber?: string;
    dateOfBirth?: string; // ISO date string
    studentId?: string;
    staffId?: string;
    photoUrl?: string;
}

/**
 * Cloud Function to create a user account (admin, student, or staff)
 * This creates both the Firebase Auth user and the Firestore user document
 */
export const createUserAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<CreateUserData>) => {
        const data = request.data;
        const context = request;

        // Check if the caller is authenticated and is an admin
        if (!context.auth) {
            throw new functions.https.HttpsError(
                'unauthenticated',
                'You must be logged in to perform this action.'
            );
        }

        // Verify caller is admin
        const callerDoc = await db.collection('users').doc(context.auth.uid).get();
        if (!callerDoc.exists || callerDoc.data()?.role !== 'admin') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only admins can create user accounts.'
            );
        }

        // Validate required fields
        if (!data.email || !data.password || !data.fullName || !data.role) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Missing required fields: email, password, fullName, role'
            );
        }

        // Validate role (prevent creating doctors through this function)
        if (!['admin', 'student', 'staff'].includes(data.role)) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Invalid role. Must be admin, student, or staff.'
            );
        }

        // Validate password strength
        if (data.password.length < 6) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Password must be at least 6 characters long'
            );
        }

        try {
            // Create Firebase Auth user
            const userRecord = await auth.createUser({
                email: data.email,
                password: data.password,
                displayName: data.fullName,
                emailVerified: false,
            });

            const now = admin.firestore.Timestamp.now();

            // Create user document
            await db.collection('users').doc(userRecord.uid).set({
                email: data.email,
                fullName: data.fullName,
                role: data.role,
                phoneNumber: data.phoneNumber || null,
                photoUrl: data.photoUrl || null,
                dateOfBirth: data.dateOfBirth ? admin.firestore.Timestamp.fromDate(new Date(data.dateOfBirth)) : null,
                studentId: data.studentId || null,
                staffId: data.staffId || null,
                isActive: true,
                language: 'en',
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
