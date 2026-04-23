"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.listAdminAuditLogs = exports.rotateSuperAdminSlot = exports.assignSuperAdminSlot = exports.setAdminPermissions = exports.forceSignOutUser = exports.deleteAdminAccount = exports.resetAdminPassword = exports.setAdminActiveStatus = exports.changeAdminRole = exports.createAdminAccount = exports.sendTopicNotification = exports.onNotificationCreated = exports.createUserAccount = exports.resetDoctorPassword = exports.deleteDoctorAccount = exports.updateDoctorEmail = exports.createDoctorAccount = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();
// ─────────────────────────────────────────────────────────
// Shared Guards & Helpers
// ─────────────────────────────────────────────────────────
/** Throws if caller is not authenticated. Returns the uid. */
function requireAuth(context) {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to perform this action.');
    }
    return context.auth.uid;
}
/** Fetches the caller's user document. Throws if not found. */
async function getCallerUserDoc(uid) {
    const doc = await db.collection('users').doc(uid).get();
    if (!doc.exists) {
        throw new functions.https.HttpsError('not-found', 'Caller user document not found.');
    }
    return doc;
}
/** Returns true if user role is admin or superAdmin. */
function isAdminOrSuperAdmin(role) {
    return role === 'admin' || role === 'superAdmin';
}
/** Throws if caller is not admin or superAdmin. */
function requireAdminOrSuperAdmin(callerDoc) {
    var _a;
    const role = (_a = callerDoc.data()) === null || _a === void 0 ? void 0 : _a.role;
    if (!isAdminOrSuperAdmin(role)) {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can perform this action.');
    }
}
/** Throws if caller is not superAdmin. */
function requireSuperAdmin(callerDoc) {
    var _a;
    if (((_a = callerDoc.data()) === null || _a === void 0 ? void 0 : _a.role) !== 'superAdmin') {
        throw new functions.https.HttpsError('permission-denied', 'Only Super Admins can perform this action.');
    }
}
/** Throws if caller (admin) lacks the given permission. SuperAdmin bypasses. */
function requirePermission(callerDoc, permissionKey) {
    const data = callerDoc.data();
    if (!data)
        throw new functions.https.HttpsError('not-found', 'Caller data missing.');
    if (data.role === 'superAdmin')
        return; // bypass
    if (data.role !== 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can perform this action.');
    }
    const perms = data.adminPermissions;
    // Legacy admins without permissions object get full access
    if (!perms)
        return;
    if (!perms[permissionKey]) {
        throw new functions.https.HttpsError('permission-denied', `Missing permission: ${permissionKey}`);
    }
}
/** Writes an entry to admin_audit_logs collection. */
async function writeAdminAuditLog(params) {
    await db.collection('admin_audit_logs').add(Object.assign(Object.assign({}, params), { createdAt: admin.firestore.Timestamp.now() }));
}
/**
 * Cloud Function to create a doctor account
 * This creates both the Firebase Auth user and the Firestore documents
 */
exports.createDoctorAccount = functions.https.onCall(async (request) => {
    const data = request.data;
    // Auth + permission check
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'doctors.manage');
    // Validate required fields
    if (!data.email || !data.password || !data.name || !data.specialization) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: email, password, name, specialization');
    }
    // Validate password strength
    if (data.password.length < 6) {
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters long');
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
    }
    catch (error) {
        console.error('Error creating doctor account:', error);
        // Handle specific Firebase Auth errors
        if (error && typeof error === 'object' && 'code' in error) {
            const firebaseError = error;
            if (firebaseError.code === 'auth/email-already-exists') {
                throw new functions.https.HttpsError('already-exists', 'A user with this email already exists.');
            }
            if (firebaseError.code === 'auth/invalid-email') {
                throw new functions.https.HttpsError('invalid-argument', 'The email address is invalid.');
            }
            if (firebaseError.code === 'auth/weak-password') {
                throw new functions.https.HttpsError('invalid-argument', 'The password is too weak.');
            }
        }
        throw new functions.https.HttpsError('internal', 'Failed to create doctor account. Please try again.');
    }
});
/**
 * Cloud Function to update a doctor's auth email
 */
exports.updateDoctorEmail = functions.https.onCall(async (request) => {
    var _a;
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to perform this action.');
    }
    // Verify caller is admin
    const callerDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!callerDoc.exists || !isAdminOrSuperAdmin((_a = callerDoc.data()) === null || _a === void 0 ? void 0 : _a.role)) {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can update doctor accounts.');
    }
    try {
        // Get doctor document to find userId
        const doctorDoc = await db.collection('doctors').doc(data.doctorId).get();
        if (!doctorDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }
        const doctorData = doctorDoc.data();
        const userId = doctorData === null || doctorData === void 0 ? void 0 : doctorData.userId;
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
    }
    catch (error) {
        console.error('Error updating doctor email:', error);
        throw new functions.https.HttpsError('internal', 'Failed to update doctor email.');
    }
});
/**
 * Cloud Function to delete a doctor account
 */
exports.deleteDoctorAccount = functions.https.onCall(async (request) => {
    var _a;
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to perform this action.');
    }
    // Verify caller is admin
    const callerDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!callerDoc.exists || !isAdminOrSuperAdmin((_a = callerDoc.data()) === null || _a === void 0 ? void 0 : _a.role)) {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can delete doctor accounts.');
    }
    try {
        // Get doctor document to find userId
        const doctorDoc = await db.collection('doctors').doc(data.doctorId).get();
        if (!doctorDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }
        const doctorData = doctorDoc.data();
        const userId = doctorData === null || doctorData === void 0 ? void 0 : doctorData.userId;
        // Delete Firebase Auth user if exists
        if (userId && !userId.startsWith('sample_')) {
            try {
                await auth.deleteUser(userId);
            }
            catch (authError) {
                console.log('Auth user may not exist:', authError);
            }
            // Delete user document
            await db.collection('users').doc(userId).delete();
        }
        // Delete doctor document
        await db.collection('doctors').doc(data.doctorId).delete();
        return { success: true, message: 'Doctor account deleted successfully' };
    }
    catch (error) {
        console.error('Error deleting doctor account:', error);
        throw new functions.https.HttpsError('internal', 'Failed to delete doctor account.');
    }
});
/**
 * Cloud Function to reset a doctor's password
 */
exports.resetDoctorPassword = functions.https.onCall(async (request) => {
    var _a;
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to perform this action.');
    }
    // Verify caller is admin
    const callerDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!callerDoc.exists || !isAdminOrSuperAdmin((_a = callerDoc.data()) === null || _a === void 0 ? void 0 : _a.role)) {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can reset doctor passwords.');
    }
    if (!data.newPassword || data.newPassword.length < 6) {
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters long.');
    }
    try {
        // Get doctor document to find userId
        const doctorDoc = await db.collection('doctors').doc(data.doctorId).get();
        if (!doctorDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }
        const doctorData = doctorDoc.data();
        const userId = doctorData === null || doctorData === void 0 ? void 0 : doctorData.userId;
        if (!userId || userId.startsWith('sample_')) {
            throw new functions.https.HttpsError('failed-precondition', 'This doctor does not have an associated auth account.');
        }
        // Update password
        await auth.updateUser(userId, { password: data.newPassword });
        return { success: true, message: 'Password reset successfully' };
    }
    catch (error) {
        console.error('Error resetting doctor password:', error);
        throw new functions.https.HttpsError('internal', 'Failed to reset doctor password.');
    }
});
/**
 * Cloud Function to create a user account (student or staff only).
 * Admin accounts must be created via createAdminAccount (Super Admin only).
 */
exports.createUserAccount = functions.https.onCall(async (request) => {
    const data = request.data;
    // Auth + permission check
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireAdminOrSuperAdmin(callerDoc);
    // Validate required fields
    if (!data.email || !data.password || !data.fullName || !data.role) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: email, password, fullName, role');
    }
    // Only student/staff allowed — admin creation uses createAdminAccount
    if (!['student', 'staff'].includes(data.role)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid role. Must be student or staff. Use createAdminAccount for admin accounts.');
    }
    // Validate password strength
    if (data.password.length < 6) {
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters long');
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
    }
    catch (error) {
        console.error('Error creating user account:', error);
        // Handle specific Firebase Auth errors
        if (error && typeof error === 'object' && 'code' in error) {
            const firebaseError = error;
            if (firebaseError.code === 'auth/email-already-exists') {
                throw new functions.https.HttpsError('already-exists', 'A user with this email already exists.');
            }
            if (firebaseError.code === 'auth/invalid-email') {
                throw new functions.https.HttpsError('invalid-argument', 'The email address is invalid.');
            }
            if (firebaseError.code === 'auth/weak-password') {
                throw new functions.https.HttpsError('invalid-argument', 'The password is too weak.');
            }
        }
        throw new functions.https.HttpsError('internal', 'Failed to create user account. Please try again.');
    }
});
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
exports.onNotificationCreated = functions.firestore
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
    const userId = notification.userId;
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
        if (!tokenDoc.exists || !(tokenData === null || tokenData === void 0 ? void 0 : tokenData.token)) {
            console.log(`No FCM token found for user ${userId}, skipping push.`);
            // Still mark as delivered so the in-app notification list shows it
            await snap.ref.update({ isDelivered: true });
            return;
        }
        const fcmToken = tokenData.token;
        // Build the FCM message
        const message = {
            token: fcmToken,
            notification: {
                title: notification.title || 'UHC Notification',
                body: notification.body || '',
            },
            data: Object.assign(Object.assign({ notificationId: notificationId, type: notification.type || 'systemUpdate' }, (notification.appointmentId && { appointmentId: notification.appointmentId })), (notification.data && Object.fromEntries(Object.entries(notification.data).map(([k, v]) => [k, String(v)])))),
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
    }
    catch (error) {
        console.error(`Error sending FCM for notification ${notificationId}:`, error);
        // If the token is invalid/expired, clean it up
        if (error && typeof error === 'object' && 'code' in error) {
            const fcmError = error;
            if (fcmError.code === 'messaging/invalid-registration-token' ||
                fcmError.code === 'messaging/registration-token-not-registered') {
                console.log(`Removing stale FCM token for user ${userId}`);
                await db.collection('user_tokens').doc(userId).delete().catch(() => { });
            }
        }
        // Still mark as delivered so it shows in the in-app list
        await snap.ref.update({ isDelivered: true });
    }
});
/**
 * Callable Cloud Function for admins to send notifications to FCM topics
 * (e.g. "announcements", "department_cardiology").
 */
exports.sendTopicNotification = functions.https.onCall(async (request) => {
    var _a;
    const data = request.data;
    const context = request;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'You must be logged in to perform this action.');
    }
    // Verify caller is admin
    const callerDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!callerDoc.exists || !isAdminOrSuperAdmin((_a = callerDoc.data()) === null || _a === void 0 ? void 0 : _a.role)) {
        throw new functions.https.HttpsError('permission-denied', 'Only admins can send topic notifications.');
    }
    if (!data.topic || !data.title || !data.body) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: topic, title, body');
    }
    try {
        const message = {
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
    }
    catch (error) {
        console.error('Error sending topic notification:', error);
        throw new functions.https.HttpsError('internal', 'Failed to send topic notification.');
    }
});
// ─────────────────────────────────────────────────────────
// Super Admin Governance Functions
// ─────────────────────────────────────────────────────────
/**
 * Create an admin account. Super Admin only.
 */
exports.createAdminAccount = functions.https.onCall(async (request) => {
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
            isActive: true, adminPermissions: null, // full access by default
            notificationSettings: { email: true, push: true, sms: false },
            language: 'en', createdAt: now, updatedAt: now,
            bloodType: null, allergies: null, studentId: null, staffId: null,
        });
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: callerDoc.data().role,
            actorName: callerDoc.data().fullName,
            targetUid: userRecord.uid, targetName: data.fullName,
            targetRoleAfter: 'admin', action: 'admin.create',
        });
        return { success: true, userId: userRecord.uid, message: 'Admin account created successfully' };
    }
    catch (error) {
        if (error && typeof error === 'object' && 'code' in error) {
            const e = error;
            if (e.code === 'auth/email-already-exists')
                throw new functions.https.HttpsError('already-exists', 'A user with this email already exists.');
        }
        throw new functions.https.HttpsError('internal', 'Failed to create admin account.');
    }
});
/**
 * Change an admin user's role. Super Admin only.
 */
exports.changeAdminRole = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { targetUid, newRole } = request.data;
    if (!targetUid || !newRole)
        throw new functions.https.HttpsError('invalid-argument', 'Missing targetUid or newRole.');
    if (!['admin', 'student', 'staff'].includes(newRole))
        throw new functions.https.HttpsError('invalid-argument', 'Invalid role. Cannot assign doctor or superAdmin via this function.');
    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists)
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    const targetData = targetDoc.data();
    const oldRole = targetData.role;
    if (oldRole === 'superAdmin')
        throw new functions.https.HttpsError('failed-precondition', 'Cannot change a Super Admin role via this function.');
    await db.collection('users').doc(targetUid).update({ role: newRole, updatedAt: admin.firestore.Timestamp.now() });
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid, targetName: targetData.fullName,
        targetRoleBefore: oldRole, targetRoleAfter: newRole,
        action: oldRole === 'admin' ? 'admin.demote' : 'admin.promote',
    });
    return { success: true, message: `Role changed from ${oldRole} to ${newRole}` };
});
/**
 * Activate or deactivate an admin. Super Admin only.
 */
exports.setAdminActiveStatus = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { targetUid, isActive } = request.data;
    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists)
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    const targetRole = targetDoc.data().role;
    if (targetRole !== 'admin')
        throw new functions.https.HttpsError('failed-precondition', 'This function can only target admin accounts.');
    await db.collection('users').doc(targetUid).update({ isActive, updatedAt: admin.firestore.Timestamp.now() });
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid, targetName: targetDoc.data().fullName,
        action: isActive ? 'admin.activate' : 'admin.deactivate',
    });
    return { success: true, message: isActive ? 'Admin activated' : 'Admin deactivated' };
});
/**
 * Reset an admin's password. Super Admin only.
 */
exports.resetAdminPassword = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { targetUid, newPassword } = request.data;
    if (!newPassword || newPassword.length < 6)
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists)
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    if (targetDoc.data().role !== 'admin')
        throw new functions.https.HttpsError('failed-precondition', 'This function can only target admin accounts.');
    await auth.updateUser(targetUid, { password: newPassword });
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid, targetName: targetDoc.data().fullName,
        action: 'admin.passwordReset',
    });
    return { success: true, message: 'Password reset successfully' };
});
/**
 * Delete an admin account. Super Admin only.
 */
exports.deleteAdminAccount = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { targetUid } = request.data;
    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists)
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    const targetData = targetDoc.data();
    if (targetData.role !== 'admin')
        throw new functions.https.HttpsError('failed-precondition', 'This function can only target admin accounts.');
    try {
        await auth.deleteUser(targetUid);
    }
    catch (e) {
        console.log('Auth user may not exist:', e);
    }
    await db.collection('users').doc(targetUid).delete();
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid, targetName: targetData.fullName,
        targetRoleBefore: targetData.role, action: 'admin.delete',
    });
    return { success: true, message: 'Admin account deleted successfully' };
});
/**
 * Force sign-out a user by revoking refresh tokens. Super Admin only.
 */
exports.forceSignOutUser = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { targetUid } = request.data;
    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists)
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    await auth.revokeRefreshTokens(targetUid);
    // Also remove FCM token to stop push notifications
    await db.collection('user_tokens').doc(targetUid).delete().catch(() => { });
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid, targetName: targetDoc.data().fullName,
        action: 'admin.forceSignOut',
    });
    return { success: true, message: 'User sessions revoked' };
});
/**
 * Set admin permissions. Super Admin only.
 */
exports.setAdminPermissions = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { targetUid, permissions } = request.data;
    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists)
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    if (targetDoc.data().role !== 'admin')
        throw new functions.https.HttpsError('failed-precondition', 'Permissions can only be set on admin accounts.');
    const oldPerms = targetDoc.data().adminPermissions || {};
    await db.collection('users').doc(targetUid).update({
        adminPermissions: permissions,
        updatedAt: admin.firestore.Timestamp.now(),
    });
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid, targetName: targetDoc.data().fullName,
        action: 'admin.permissionsUpdate',
        before: oldPerms,
        after: permissions,
    });
    return { success: true, message: 'Permissions updated' };
});
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
exports.assignSuperAdminSlot = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { targetUid, slotType } = request.data;
    if (!['primary', 'backup'].includes(slotType))
        throw new functions.https.HttpsError('invalid-argument', 'slotType must be primary or backup.');
    const result = await db.runTransaction(async (tx) => {
        // Read current super admins
        const superAdminsSnap = await tx.get(db.collection('users').where('role', '==', 'superAdmin'));
        const currentSlots = superAdminsSnap.docs.map(d => ({
            uid: d.id, slotType: d.data().superAdminType,
        }));
        // Check if this slot is already occupied by someone else
        const existingSlotHolder = currentSlots.find(s => s.slotType === slotType);
        if (existingSlotHolder && existingSlotHolder.uid !== targetUid) {
            throw new functions.https.HttpsError('failed-precondition', `The ${slotType} slot is already occupied. Use rotateSuperAdminSlot to replace.`);
        }
        // Check max 2
        const otherSuperAdmins = currentSlots.filter(s => s.uid !== targetUid);
        if (otherSuperAdmins.length >= 2) {
            throw new functions.https.HttpsError('failed-precondition', 'Maximum 2 Super Admin slots reached.');
        }
        // Read target
        const targetRef = db.collection('users').doc(targetUid);
        const targetSnap = await tx.get(targetRef);
        if (!targetSnap.exists)
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        const oldRole = targetSnap.data().role;
        // Block existing superAdmins from switching slots (would orphan the other slot)
        if (oldRole === 'superAdmin') {
            const currentSlotType = targetSnap.data().superAdminType;
            if (currentSlotType && currentSlotType !== slotType) {
                throw new functions.https.HttpsError('failed-precondition', `Target already holds the ${currentSlotType} slot. Use rotateSuperAdminSlot to replace.`);
            }
        }
        tx.update(targetRef, {
            role: 'superAdmin', superAdminType: slotType,
            updatedAt: admin.firestore.Timestamp.now(),
        });
        return { oldRole, targetName: targetSnap.data().fullName };
    });
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid, targetName: result.targetName,
        targetRoleBefore: result.oldRole, targetRoleAfter: 'superAdmin',
        action: 'superAdmin.slotAssign',
        after: { slotType },
    });
    return { success: true, message: `Assigned ${slotType} Super Admin slot` };
});
/**
 * Rotate a Super Admin slot: demote the current holder and promote the replacement.
 * Runs inside a transaction to ensure atomicity.
 * Super Admin only.
 */
exports.rotateSuperAdminSlot = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { slotType, replacementUid } = request.data;
    if (!['primary', 'backup'].includes(slotType))
        throw new functions.https.HttpsError('invalid-argument', 'slotType must be primary or backup.');
    const result = await db.runTransaction(async (tx) => {
        // Find current holder of this slot
        const slotSnap = await tx.get(db.collection('users')
            .where('role', '==', 'superAdmin')
            .where('superAdminType', '==', slotType));
        if (slotSnap.empty)
            throw new functions.https.HttpsError('not-found', `No current ${slotType} Super Admin found.`);
        const currentHolder = slotSnap.docs[0];
        const currentHolderUid = currentHolder.id;
        if (currentHolderUid === replacementUid)
            throw new functions.https.HttpsError('failed-precondition', 'Replacement is already the slot holder.');
        // Read replacement
        const replacementRef = db.collection('users').doc(replacementUid);
        const replacementSnap = await tx.get(replacementRef);
        if (!replacementSnap.exists)
            throw new functions.https.HttpsError('not-found', 'Replacement user not found.');
        // Block if replacement already holds the OTHER super admin slot
        if (replacementSnap.data().role === 'superAdmin') {
            throw new functions.https.HttpsError('failed-precondition', 'Replacement already holds a Super Admin slot. Demote them first.');
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
            promotedName: replacementSnap.data().fullName,
            promotedOldRole: replacementSnap.data().role,
        };
    });
    // Log both actions
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid: result.demotedUid, targetName: result.demotedName,
        targetRoleBefore: 'superAdmin', targetRoleAfter: 'admin',
        action: 'superAdmin.slotRotate', metadata: { slotType, direction: 'demote' },
    });
    await writeAdminAuditLog({
        actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
        targetUid: replacementUid, targetName: result.promotedName,
        targetRoleBefore: result.promotedOldRole, targetRoleAfter: 'superAdmin',
        action: 'superAdmin.slotRotate', metadata: { slotType, direction: 'promote' },
    });
    return { success: true, message: `Rotated ${slotType} Super Admin slot` };
});
// ─────────────────────────────────────────────────────────
// Audit Log Query
// ─────────────────────────────────────────────────────────
/**
 * List admin audit logs with optional filtering. Super Admin only.
 */
exports.listAdminAuditLogs = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requireSuperAdmin(callerDoc);
    const { limit: queryLimit, targetUid, action } = request.data || {};
    let query = db.collection('admin_audit_logs')
        .orderBy('createdAt', 'desc');
    if (targetUid)
        query = query.where('targetUid', '==', targetUid);
    if (action)
        query = query.where('action', '==', action);
    query = query.limit(Math.min(queryLimit || 50, 200));
    const snap = await query.get();
    const logs = snap.docs.map(doc => {
        var _a, _b, _c;
        return (Object.assign(Object.assign({ id: doc.id }, doc.data()), { createdAt: ((_c = (_b = (_a = doc.data().createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString()) || null }));
    });
    return { success: true, logs };
});
//# sourceMappingURL=index.js.map