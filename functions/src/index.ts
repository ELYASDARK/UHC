import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

// ─────────────────────────────────────────────────────────
// Shared Guards & Helpers
// ─────────────────────────────────────────────────────────

/** Throws if caller is not authenticated. Returns the uid. */
function requireAuth(context: { auth?: { uid: string } }): string {
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'You must be logged in to perform this action.'
        );
    }
    return context.auth.uid;
}

/** Fetches the caller's user document. Throws if not found. */
async function getCallerUserDoc(uid: string): Promise<FirebaseFirestore.DocumentSnapshot> {
    const doc = await db.collection('users').doc(uid).get();
    if (!doc.exists) {
        throw new functions.https.HttpsError('not-found', 'Caller user document not found.');
    }
    return doc;
}

/** Throws if caller is not superAdmin. */
function requireSuperAdmin(callerDoc: FirebaseFirestore.DocumentSnapshot): void {
    if (callerDoc.data()?.role !== 'superAdmin') {
        throw new functions.https.HttpsError('permission-denied', 'Only Super Admins can perform this action.');
    }
}

/** Throws if caller (admin) lacks the given permission. SuperAdmin bypasses. */
function requirePermission(callerDoc: FirebaseFirestore.DocumentSnapshot, permissionKey: string): void {
    const data = callerDoc.data();
    if (!data) throw new functions.https.HttpsError('not-found', 'Caller data missing.');
    if (data.role === 'superAdmin') return; // bypass
    if (data.role !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can perform this action.');
    }
    const perms = data.adminPermissions as Record<string, boolean> | undefined;
    // Legacy admins without permissions object get full access
    if (!perms) return;
    if (!perms[permissionKey]) {
        throw new functions.https.HttpsError('permission-denied', `Missing permission: ${permissionKey}`);
    }
}

/** Writes an entry to admin_audit_logs collection. */
async function writeAdminAuditLog(params: {
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

/** Convert unknown runtime errors to consistent callable HttpsError responses. */
function toHttpsError(
    error: unknown,
    fallbackMessage: string
): functions.https.HttpsError {
    if (error instanceof functions.https.HttpsError) {
        return error;
    }

    const maybe = error as { code?: string; message?: string } | undefined;
    const code = maybe?.code;

    if (code === 'auth/user-not-found') {
        return new functions.https.HttpsError(
            'not-found',
            'Target auth user not found.'
        );
    }
    if (code === 'auth/invalid-password' || code === 'auth/weak-password') {
        return new functions.https.HttpsError(
            'invalid-argument',
            'Password must be at least 6 characters.'
        );
    }

    const message = maybe?.message || fallbackMessage;
    return new functions.https.HttpsError('internal', message);
}

const READ_ONLY_ADMIN_PERMISSIONS: Record<string, boolean> = {
    'users.view': true,
    'users.manageNonAdmin': false,
    'doctors.view': true,
    'doctors.manage': false,
    'departments.view': true,
    'departments.manage': false,
    'analytics.view': true,
    'reports.view': true,
    'reports.export': false,
    'notifications.send': false,
};

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
    role: 'student' | 'staff';
    phoneNumber?: string;
    dateOfBirth?: string; // ISO date string
    studentId?: string;
    staffId?: string;
    photoUrl?: string;
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
                notificationSettings: {
                    email: true,
                    push: true,
                    sms: false,
                },
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

interface CreateDepartmentData {
    key: string;
    name: string;
    description?: string;
    iconName?: string;
    colorHex?: string;
    workingHours: Record<string, unknown>;
}

/**
 * Cloud Function to create a department document.
 */
export const createDepartment = functions.https.onCall(
    async (request: functions.https.CallableRequest<CreateDepartmentData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.key || !data.name || !data.workingHours) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'key, name, and workingHours are required.'
            );
        }

        const existing = await db.collection('departments')
            .where('key', '==', data.key)
            .limit(1)
            .get();
        if (!existing.empty) {
            throw new functions.https.HttpsError('already-exists', 'Department key already exists.');
        }

        const now = admin.firestore.Timestamp.now();
        const ref = await db.collection('departments').add({
            key: data.key,
            name: data.name,
            description: data.description ?? '',
            iconName: data.iconName ?? 'medical_services',
            colorHex: data.colorHex ?? '#2196F3',
            workingHours: data.workingHours,
            isActive: true,
            doctorCount: 0,
            createdAt: now,
            updatedAt: now,
        });

        return { success: true, departmentId: ref.id, message: 'Department created successfully' };
    }
);

interface UpdateDepartmentData {
    departmentId: string;
    key?: string;
    name?: string;
    description?: string;
    iconName?: string;
    colorHex?: string;
    workingHours?: Record<string, unknown>;
}

/**
 * Cloud Function to update department fields.
 */
export const updateDepartment = functions.https.onCall(
    async (request: functions.https.CallableRequest<UpdateDepartmentData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.departmentId) {
            throw new functions.https.HttpsError('invalid-argument', 'departmentId is required.');
        }

        const ref = db.collection('departments').doc(data.departmentId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new functions.https.HttpsError('not-found', 'Department not found.');
        }

        const updates: Record<string, unknown> = {
            updatedAt: admin.firestore.Timestamp.now(),
        };
        if (data.key !== undefined) updates.key = data.key;
        if (data.name !== undefined) updates.name = data.name;
        if (data.description !== undefined) updates.description = data.description;
        if (data.iconName !== undefined) updates.iconName = data.iconName;
        if (data.colorHex !== undefined) updates.colorHex = data.colorHex;
        if (data.workingHours !== undefined) updates.workingHours = data.workingHours;

        await ref.update(updates);
        return { success: true, message: 'Department updated successfully' };
    }
);

interface SetDepartmentActiveStatusData {
    departmentId: string;
    isActive: boolean;
}

/**
 * Cloud Function to activate/deactivate a department.
 */
export const setDepartmentActiveStatus = functions.https.onCall(
    async (request: functions.https.CallableRequest<SetDepartmentActiveStatusData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.departmentId || typeof data.isActive !== 'boolean') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'departmentId and isActive are required.'
            );
        }

        const ref = db.collection('departments').doc(data.departmentId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new functions.https.HttpsError('not-found', 'Department not found.');
        }

        await ref.update({
            isActive: data.isActive,
            updatedAt: admin.firestore.Timestamp.now(),
        });

        return {
            success: true,
            message: data.isActive
                ? 'Department activated successfully'
                : 'Department deactivated successfully',
        };
    }
);

interface DeleteDepartmentData {
    departmentId: string;
}

/**
 * Cloud Function to delete a department.
 */
export const deleteDepartment = functions.https.onCall(
    async (request: functions.https.CallableRequest<DeleteDepartmentData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.departmentId) {
            throw new functions.https.HttpsError('invalid-argument', 'departmentId is required.');
        }

        const ref = db.collection('departments').doc(data.departmentId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new functions.https.HttpsError('not-found', 'Department not found.');
        }

        await ref.delete();
        return { success: true, message: 'Department deleted successfully' };
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
        if (data.photoUrl !== undefined) updates.photoUrl = data.photoUrl;
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

// ─────────────────────────────────────────────────────────
// FCM Push Notification Functions
// ─────────────────────────────────────────────────────────

const messaging = admin.messaging();

/**
 * Firestore trigger: whenever a new notification document is created,
 * look up the target user's FCM token and send a push notification.
 *
 * Expected document shape (from NotificationModel.toFirestore):
 *   userId, title, body, type, data, isRead, createdAt,
 *   appointmentId, scheduledFor, reminderType, isDelivered
 */
export const onNotificationCreated = functions.firestore
    .onDocumentCreated('notifications/{notificationId}', async (event) => {
        const snap = event.data;
        if (!snap) {
            console.log('No snapshot in event, skipping.');
            return;
        }
        const notification = snap.data();
        const notificationId = event.params.notificationId;

        if (!notification) {
            console.log('Empty notification document, skipping.');
            return;
        }

        const userId: string = notification.userId;
        if (!userId) {
            console.log('No userId on notification, skipping.');
            return;
        }

        // If scheduledFor is in the future, skip sending now.
        // A scheduled Cloud Task or cron job should handle future delivery.
        if (notification.scheduledFor) {
            const scheduledTime = notification.scheduledFor.toDate
                ? notification.scheduledFor.toDate()
                : new Date(notification.scheduledFor);
            if (scheduledTime > new Date()) {
                console.log(`Notification ${notificationId} is scheduled for the future, skipping immediate send.`);
                return;
            }
        }

        try {
            // Look up the user's FCM token from user_tokens collection
            const tokenDoc = await db.collection('user_tokens').doc(userId).get();
            const tokenData = tokenDoc.data();

            if (!tokenDoc.exists || !tokenData?.token) {
                console.log(`No FCM token found for user ${userId}, skipping push.`);
                // Still mark as delivered so the in-app notification list shows it
                await snap.ref.update({ isDelivered: true });
                return;
            }

            const fcmToken: string = tokenData.token;

            // Build the FCM message
            const message: admin.messaging.Message = {
                token: fcmToken,
                notification: {
                    title: notification.title || 'UHC Notification',
                    body: notification.body || '',
                },
                data: {
                    notificationId: notificationId,
                    type: notification.type || 'systemUpdate',
                    ...(notification.appointmentId && { appointmentId: notification.appointmentId }),
                    // Flatten extra data fields for FCM (values must be strings)
                    ...(notification.data && Object.fromEntries(
                        Object.entries(notification.data).map(([k, v]) => [k, String(v)])
                    )),
                },
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'uhc_notifications',
                        priority: 'high',
                        sound: 'default',
                    },
                },
                apns: {
                    payload: {
                        aps: {
                            alert: {
                                title: notification.title || 'UHC Notification',
                                body: notification.body || '',
                            },
                            sound: 'default',
                            badge: 1,
                        },
                    },
                },
            };

            await messaging.send(message);
            console.log(`FCM sent to user ${userId} for notification ${notificationId}`);

            // Mark the notification as delivered in Firestore
            await snap.ref.update({ isDelivered: true });
        } catch (error: unknown) {
            console.error(`Error sending FCM for notification ${notificationId}:`, error);

            // If the token is invalid/expired, clean it up
            if (error && typeof error === 'object' && 'code' in error) {
                const fcmError = error as { code: string };
                if (
                    fcmError.code === 'messaging/invalid-registration-token' ||
                    fcmError.code === 'messaging/registration-token-not-registered'
                ) {
                    console.log(`Removing stale FCM token for user ${userId}`);
                    await db.collection('user_tokens').doc(userId).delete().catch(() => { });
                }
            }

            // Still mark as delivered so it shows in the in-app list
            await snap.ref.update({ isDelivered: true });
        }
    });

interface TopicNotificationData {
    topic: string;
    title: string;
    body: string;
    data?: Record<string, string>;
}

/**
 * Callable Cloud Function for admins to send notifications to FCM topics
 * (e.g. "announcements", "department_cardiology").
 */
export const sendTopicNotification = functions.https.onCall(
    async (request: functions.https.CallableRequest<TopicNotificationData>) => {
        const data = request.data;

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'notifications.send');

        if (!data.topic || !data.title || !data.body) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'Missing required fields: topic, title, body'
            );
        }

        try {
            const message: admin.messaging.Message = {
                topic: data.topic,
                notification: {
                    title: data.title,
                    body: data.body,
                },
                data: data.data || {},
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'uhc_notifications',
                        sound: 'default',
                    },
                },
                apns: {
                    payload: {
                        aps: {
                            sound: 'default',
                        },
                    },
                },
            };

            const messageId = await messaging.send(message);
            console.log(`Topic notification sent to "${data.topic}", messageId: ${messageId}`);

            return {
                success: true,
                messageId,
                message: `Notification sent to topic "${data.topic}" successfully`,
            };
        } catch (error) {
            console.error('Error sending topic notification:', error);
            throw new functions.https.HttpsError(
                'internal',
                'Failed to send topic notification.'
            );
        }
    }
);

// ─────────────────────────────────────────────────────────
// Super Admin Governance Functions
// ─────────────────────────────────────────────────────────

/**
 * Create an admin account. Super Admin only.
 */
export const createAdminAccount = functions.https.onCall(
    async (request: functions.https.CallableRequest<{
        email: string; password: string; fullName: string;
        phoneNumber?: string; dateOfBirth?: string; photoUrl?: string;
    }>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const data = request.data;

        if (!data.email || !data.password || !data.fullName) {
            throw new functions.https.HttpsError('invalid-argument', 'Missing required fields.');
        }
        if (data.password.length < 6) {
            throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
        }

        try {
            const userRecord = await auth.createUser({
                email: data.email, password: data.password,
                displayName: data.fullName, emailVerified: false,
            });
            const now = admin.firestore.Timestamp.now();
            await db.collection('users').doc(userRecord.uid).set({
                email: data.email, fullName: data.fullName, role: 'admin',
                phoneNumber: data.phoneNumber || null, photoUrl: data.photoUrl || null,
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

            if (!targetUid || !newPassword || newPassword.length < 6)
                throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
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

            // Also remove FCM token to stop push notifications
            await db.collection('user_tokens').doc(targetUid).delete().catch(() => { });
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
            const { targetUid, permissions } = request.data;

            if (!targetUid || !permissions || typeof permissions !== 'object') {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    'Missing or invalid targetUid/permissions.'
                );
            }

            const targetDoc = await db.collection('users').doc(targetUid).get();
            if (!targetDoc.exists) throw new functions.https.HttpsError('not-found', 'Target user not found.');
            if (targetDoc.data()!.role !== 'admin')
                throw new functions.https.HttpsError('failed-precondition', 'Permissions can only be set on admin accounts.');

            const oldPerms = targetDoc.data()!.adminPermissions || {};
            await db.collection('users').doc(targetUid).update({
                adminPermissions: permissions,
                updatedAt: admin.firestore.Timestamp.now(),
            });
            await writeAdminAuditLog({
                actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data()!.fullName,
                targetUid, targetName: targetDoc.data()!.fullName,
                action: 'admin.permissionsUpdate',
                before: oldPerms as Record<string, unknown>,
                after: permissions as Record<string, unknown>,
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

            // Query only by createdAt desc to avoid composite index failures;
            // apply additional filters in memory.
            const snap = await db
                .collection('admin_audit_logs')
                .orderBy('createdAt', 'desc')
                .limit(Math.min(queryLimit || 100, 500))
                .get();

            const filteredDocs = snap.docs.filter((doc) => {
                const data = doc.data();
                if (targetUid && data.targetUid !== targetUid) return false;
                if (actorUid && data.actorUid !== actorUid) return false;
                if (action && data.action !== action) return false;

                const createdAtDate = data.createdAt?.toDate?.() as Date | undefined;
                if (dateFromValue && (!createdAtDate || createdAtDate < dateFromValue)) return false;
                if (dateToValue && (!createdAtDate || createdAtDate > dateToValue)) return false;
                return true;
            });

            const logs = filteredDocs.map(doc => ({
                id: doc.id,
                ...doc.data(),
                createdAt: doc.data().createdAt?.toDate?.()?.toISOString() || null,
            }));
            return { success: true, logs };
        } catch (error) {
            console.error('listAdminAuditLogs failed:', error);
            throw toHttpsError(error, 'Failed to load admin audit logs.');
        }
    }
);
