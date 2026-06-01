"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendDoctorDailyReports = exports.resyncUserNotificationSchedules = exports.listAdminAuditLogs = exports.rotateSuperAdminSlot = exports.assignSuperAdminSlot = exports.setAdminPermissions = exports.forceSignOutUser = exports.deleteAdminAccount = exports.resetAdminPassword = exports.setAdminActiveStatus = exports.changeAdminRole = exports.createAdminAccount = exports.sendTopicNotification = exports.sendAdminNotification = exports.previewAdminNotificationRecipients = exports.searchAdminNotificationRecipients = exports.reviewDoctorAvailabilityRequest = exports.setDoctorAvailabilityByAdmin = exports.setDoctorAvailability = exports.requestDoctorUnavailable = exports.deliverScheduledNotifications = exports.onNotificationCreated = exports.deleteUserAccount = exports.updateUserProfileByAdmin = exports.unlinkGoogleProviderByAdmin = exports.changeUserRoleByAdmin = exports.setUserActiveStatus = exports.bootstrapSelfUserDocument = exports.deleteDepartment = exports.setDepartmentActiveStatus = exports.updateDepartment = exports.createDepartment = exports.updateDoctorSchedule = exports.setDoctorActiveStatus = exports.updateDoctorProfile = exports.createUserAccount = exports.completeInitialPasswordChange = exports.resetDoctorPassword = exports.deleteDoctorAccount = exports.updateDoctorEmail = exports.createDoctorAccount = exports.deleteAppointment = exports.incrementQrScanFailures = exports.updateMedicalNotes = exports.updateAppointmentStatus = exports.cancelAppointment = exports.rescheduleAppointment = exports.createAppointment = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const crypto_1 = require("crypto");
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
    var _a;
    const doc = await db.collection('users').doc(uid).get();
    if (!doc.exists) {
        throw new functions.https.HttpsError('not-found', 'Caller user document not found.');
    }
    if (((_a = doc.data()) === null || _a === void 0 ? void 0 : _a.isActive) !== true) {
        throw new functions.https.HttpsError('permission-denied', 'Your account is inactive.');
    }
    return doc;
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
    if (!perms) {
        throw new functions.https.HttpsError('permission-denied', `Missing permission: ${permissionKey}`);
    }
    if (perms[permissionKey] !== true) {
        throw new functions.https.HttpsError('permission-denied', `Missing permission: ${permissionKey}`);
    }
}
async function revokeSessionsAndClearFcm(uid) {
    try {
        await auth.revokeRefreshTokens(uid);
    }
    catch (error) {
        if ((error === null || error === void 0 ? void 0 : error.code) !== 'auth/user-not-found') {
            throw error;
        }
    }
    await db.collection('user_tokens').doc(uid).delete().catch(() => { });
}
/** Writes an entry to admin_audit_logs collection. */
async function writeAdminAuditLog(params) {
    const payload = Object.assign(Object.assign({}, params), { createdAt: admin.firestore.Timestamp.now() });
    // Firestore rejects undefined values; strip optional undefined fields.
    const sanitized = Object.fromEntries(Object.entries(payload).filter(([, value]) => value !== undefined));
    await db.collection('admin_audit_logs').add(sanitized);
}
/** Convert unknown runtime errors to consistent callable HttpsError responses. */
function toHttpsError(error, fallbackMessage) {
    if (error instanceof functions.https.HttpsError) {
        return error;
    }
    const maybe = error;
    const code = maybe === null || maybe === void 0 ? void 0 : maybe.code;
    if (code === 'auth/user-not-found') {
        return new functions.https.HttpsError('not-found', 'Target auth user not found.');
    }
    if (code === 'auth/invalid-password' || code === 'auth/weak-password') {
        return new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR);
    }
    const message = (maybe === null || maybe === void 0 ? void 0 : maybe.message) || fallbackMessage;
    return new functions.https.HttpsError('internal', message);
}
const READ_ONLY_ADMIN_PERMISSIONS = {
    'users.view': true,
    'users.manageNonAdmin': false,
    'doctors.view': true,
    'doctors.manage': false,
    'departments.view': true,
    'departments.manage': false,
    'appointments.view': true,
    'appointments.manage': false,
    'analytics.view': true,
    'reports.view': true,
    'reports.export': false,
    'notifications.send': false,
};
const ADMIN_PERMISSION_KEYS = Object.keys(READ_ONLY_ADMIN_PERMISSIONS);
function sanitizeAdminPermissions(permissions) {
    if (!permissions || typeof permissions !== 'object' || Array.isArray(permissions)) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing or invalid permissions.');
    }
    const raw = permissions;
    const unknownKeys = Object.keys(raw).filter((key) => !ADMIN_PERMISSION_KEYS.includes(key));
    if (unknownKeys.length > 0) {
        throw new functions.https.HttpsError('invalid-argument', `Unknown permission key: ${unknownKeys[0]}`);
    }
    const sanitized = {};
    for (const key of ADMIN_PERMISSION_KEYS) {
        const value = raw[key];
        if (typeof value !== 'boolean') {
            throw new functions.https.HttpsError('invalid-argument', `Permission ${key} must be true or false.`);
        }
        sanitized[key] = value;
    }
    return sanitized;
}
const APPOINTMENT_STATUSES = ['pending', 'confirmed', 'completed', 'cancelled', 'noShow'];
const APPOINTMENT_TYPES = ['regularCheckup', 'followUp', 'consultation', 'emergency'];
const ACTIVE_APPOINTMENT_STATUSES = ['pending', 'confirmed'];
const MIN_PASSWORD_LENGTH = 8;
const MIN_PASSWORD_ERROR = `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
const MIN_PASSWORD_ERROR_LONG = `Password must be at least ${MIN_PASSWORD_LENGTH} characters long.`;
const PROFILE_IMAGE_MAX_BYTES = 5 * 1024 * 1024;
const PROFILE_IMAGE_EXTENSIONS = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
};
async function uploadProfilePhoto(uid, upload, folder = 'user_photos') {
    if (!upload)
        return undefined;
    if (typeof upload.base64 !== 'string' || typeof upload.contentType !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid profile photo upload.');
    }
    const expectedExtension = PROFILE_IMAGE_EXTENSIONS[upload.contentType];
    if (!expectedExtension) {
        throw new functions.https.HttpsError('invalid-argument', 'Profile photo must be a JPEG, PNG, or WebP image.');
    }
    const buffer = Buffer.from(upload.base64, 'base64');
    if (buffer.length === 0 || buffer.length > PROFILE_IMAGE_MAX_BYTES) {
        throw new functions.https.HttpsError('invalid-argument', 'Profile photo must be less than 5 MB.');
    }
    const requestedExtension = (upload.extension || expectedExtension)
        .toLowerCase()
        .replace(/^\./, '');
    const extension = requestedExtension === expectedExtension ||
        (expectedExtension === 'jpg' && requestedExtension === 'jpeg')
        ? expectedExtension
        : expectedExtension;
    const bucket = admin.storage().bucket();
    const token = (0, crypto_1.randomUUID)();
    const file = bucket.file(`${folder}/${uid}.${extension}`);
    await file.save(buffer, {
        resumable: false,
        metadata: {
            contentType: upload.contentType,
            cacheControl: 'public, max-age=31536000',
            metadata: {
                firebaseStorageDownloadTokens: token,
            },
        },
    });
    return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(file.name)}?alt=media&token=${token}`;
}
async function deleteProfilePhotos(uid, folder = 'user_photos') {
    const bucket = admin.storage().bucket();
    await Promise.all(['jpg', 'jpeg', 'png', 'webp'].map((extension) => bucket
        .file(`${folder}/${uid}.${extension}`)
        .delete({ ignoreNotFound: true })
        .catch((error) => {
        console.warn(`Failed to delete profile photo ${uid}.${extension}:`, error);
    })));
}
function appointmentDateKey(appointmentDate) {
    const year = appointmentDate.getFullYear();
    const month = String(appointmentDate.getMonth() + 1).padStart(2, '0');
    const day = String(appointmentDate.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}
function slotLockComponent(value) {
    return encodeURIComponent(value.trim());
}
function appointmentSlotLockRef(doctorId, appointmentDate, timeSlot) {
    return db.collection('appointment_slot_locks').doc(`${slotLockComponent(doctorId)}_${appointmentDateKey(appointmentDate)}_${slotLockComponent(timeSlot)}`);
}
function firestoreDateToDate(value) {
    if (value instanceof Date)
        return value;
    if (value && typeof value.toDate === 'function') {
        return value.toDate();
    }
    return null;
}
async function lockAppointmentSlot(transaction, params) {
    var _a, _b;
    const slotRef = appointmentSlotLockRef(params.doctorId, params.appointmentDate, params.timeSlot);
    const slotLockSnap = await transaction.get(slotRef);
    const lockedAppointmentId = (_a = slotLockSnap.data()) === null || _a === void 0 ? void 0 : _a.appointmentId;
    const lockedStatus = (_b = slotLockSnap.data()) === null || _b === void 0 ? void 0 : _b.status;
    if (slotLockSnap.exists &&
        lockedAppointmentId !== params.excludeAppointmentId &&
        ACTIVE_APPOINTMENT_STATUSES.includes(lockedStatus || 'pending')) {
        throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
    }
    transaction.set(slotRef, {
        appointmentId: params.appointmentId,
        doctorId: params.doctorId,
        appointmentDateKey: appointmentDateKey(params.appointmentDate),
        timeSlot: params.timeSlot,
        status: params.status,
        updatedAt: admin.firestore.Timestamp.now(),
    });
    return slotRef;
}
function releaseAppointmentSlot(transaction, appointmentId, appointmentData) {
    const appointmentDate = firestoreDateToDate(appointmentData.appointmentDate);
    if (!appointmentData.doctorId || !appointmentDate || !appointmentData.timeSlot)
        return;
    const slotRef = appointmentSlotLockRef(appointmentData.doctorId, appointmentDate, appointmentData.timeSlot);
    transaction.delete(slotRef);
}
function parseAppointmentDate(value) {
    const parsed = new Date(value);
    if (!value || Number.isNaN(parsed.getTime())) {
        throw new functions.https.HttpsError('invalid-argument', 'appointmentDate must be a valid ISO date string.');
    }
    return parsed;
}
function appointmentExactTime(date, timeSlot) {
    const startTime = timeSlot.split(' - ')[0] || '00:00';
    const [hourRaw, minuteRaw] = startTime.split(':');
    const hour = Number.parseInt(hourRaw || '0', 10);
    const minute = Number.parseInt(minuteRaw || '0', 10);
    // Extracted components in UTC to be completely timezone-agnostic.
    const year = date.getUTCFullYear();
    const month = date.getUTCMonth();
    const day = date.getUTCDate();
    // Construct local Date inside a UTC representation.
    const utcDate = new Date(Date.UTC(year, month, day, Number.isNaN(hour) ? 0 : hour, Number.isNaN(minute) ? 0 : minute));
    // Shift from Baghdad (UTC+3) to UTC time by subtracting 3 hours.
    return new Date(utcDate.getTime() - 3 * 60 * 60 * 1000);
}
function formatDateForNotification(date) {
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}
function isAdminWithAppointmentMutationAccess(data) {
    if (data.role === 'superAdmin')
        return true;
    if (data.role !== 'admin')
        return false;
    const perms = data.adminPermissions;
    return (perms === null || perms === void 0 ? void 0 : perms['appointments.manage']) === true;
}
async function getDoctorForUser(uid) {
    const snap = await db.collection('doctors')
        .where('userId', '==', uid)
        .where('isActive', '==', true)
        .limit(1)
        .get();
    return snap.empty ? null : snap.docs[0];
}
async function canMutateAppointment(callerUid, callerDoc, appointmentData, options) {
    const callerData = callerDoc.data();
    if (options.allowPatient && appointmentData.patientId === callerUid)
        return true;
    if (options.allowAdmin && isAdminWithAppointmentMutationAccess(callerData))
        return true;
    if (options.allowDoctor && callerData.role === 'doctor') {
        const doctorDoc = await getDoctorForUser(callerUid);
        return (doctorDoc === null || doctorDoc === void 0 ? void 0 : doctorDoc.id) === appointmentData.doctorId;
    }
    return false;
}
const DEFAULT_PATIENT_SETTINGS = {
    version: 2,
    onlinePushEnabled: true,
    appointmentStatusAlerts: {
        enabled: true,
        locked: true,
    },
    adminAnnouncements: {
        enabled: true,
    },
    appointmentReminders: {
        enabled: true,
        delivery: 'fcm',
        oneWeek: true,
        oneDay: true,
        oneHour: true,
    },
    doctorDailySummary: {
        enabled: false,
        delivery: 'fcm',
        time: '21:00',
    },
    email: false,
};
const DEFAULT_DOCTOR_SETTINGS = {
    version: 2,
    onlinePushEnabled: true,
    appointmentStatusAlerts: {
        enabled: true,
        locked: true,
    },
    adminAnnouncements: {
        enabled: true,
    },
    appointmentReminders: {
        enabled: false,
        delivery: 'fcm',
        oneWeek: false,
        oneDay: false,
        oneHour: false,
    },
    doctorDailySummary: {
        enabled: true,
        delivery: 'fcm',
        time: '21:00',
    },
    email: false,
};
async function getUserNotificationSettings(uid) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) {
        return DEFAULT_PATIENT_SETTINGS;
    }
    const userData = userDoc.data() || {};
    const role = userData.role || 'student';
    const isDoctor = role === 'doctor';
    const defaults = isDoctor ? DEFAULT_DOCTOR_SETTINGS : DEFAULT_PATIENT_SETTINGS;
    const oldSettings = userData.notificationSettings || {};
    const getBoolValue = (keys, defaultVal) => {
        for (const key of keys) {
            if (oldSettings[key] !== undefined)
                return !!oldSettings[key];
            if (userData[key] !== undefined)
                return !!userData[key];
        }
        return defaultVal;
    };
    const getStringValue = (keys, defaultVal) => {
        for (const key of keys) {
            if (oldSettings[key] !== undefined)
                return String(oldSettings[key]);
            if (userData[key] !== undefined)
                return String(userData[key]);
        }
        return defaultVal;
    };
    if (oldSettings.version === 2) {
        return {
            version: 2,
            onlinePushEnabled: oldSettings.onlinePushEnabled !== undefined ? !!oldSettings.onlinePushEnabled : defaults.onlinePushEnabled,
            appointmentStatusAlerts: {
                enabled: true,
                locked: true,
            },
            adminAnnouncements: {
                enabled: ((_a = oldSettings.adminAnnouncements) === null || _a === void 0 ? void 0 : _a.enabled) !== undefined ? !!oldSettings.adminAnnouncements.enabled : defaults.adminAnnouncements.enabled,
            },
            appointmentReminders: {
                enabled: ((_b = oldSettings.appointmentReminders) === null || _b === void 0 ? void 0 : _b.enabled) !== undefined ? !!oldSettings.appointmentReminders.enabled : defaults.appointmentReminders.enabled,
                delivery: ((_c = oldSettings.appointmentReminders) === null || _c === void 0 ? void 0 : _c.delivery) === 'local' ? 'local' : 'fcm',
                oneWeek: ((_d = oldSettings.appointmentReminders) === null || _d === void 0 ? void 0 : _d.oneWeek) !== undefined ? !!oldSettings.appointmentReminders.oneWeek : defaults.appointmentReminders.oneWeek,
                oneDay: ((_e = oldSettings.appointmentReminders) === null || _e === void 0 ? void 0 : _e.oneDay) !== undefined ? !!oldSettings.appointmentReminders.oneDay : defaults.appointmentReminders.oneDay,
                oneHour: ((_f = oldSettings.appointmentReminders) === null || _f === void 0 ? void 0 : _f.oneHour) !== undefined ? !!oldSettings.appointmentReminders.oneHour : defaults.appointmentReminders.oneHour,
            },
            doctorDailySummary: {
                enabled: ((_g = oldSettings.doctorDailySummary) === null || _g === void 0 ? void 0 : _g.enabled) !== undefined ? !!oldSettings.doctorDailySummary.enabled : defaults.doctorDailySummary.enabled,
                delivery: ((_h = oldSettings.doctorDailySummary) === null || _h === void 0 ? void 0 : _h.delivery) === 'local' ? 'local' : 'fcm',
                time: ((_j = oldSettings.doctorDailySummary) === null || _j === void 0 ? void 0 : _j.time) || defaults.doctorDailySummary.time,
            },
            email: oldSettings.email !== undefined ? !!oldSettings.email : defaults.email,
        };
    }
    const onlinePushEnabled = getBoolValue(['push', 'settings_push_notifications'], defaults.onlinePushEnabled);
    const email = getBoolValue(['email', 'email_notifications', 'settings_email_notifications'], defaults.email);
    const appointmentRemindersEnabled = getBoolValue(['notif_appointment_reminders'], defaults.appointmentReminders.enabled);
    const oneWeek = getBoolValue(['notif_reminder_1w'], defaults.appointmentReminders.oneWeek);
    const oneDay = getBoolValue(['notif_reminder_24h'], defaults.appointmentReminders.oneDay);
    const oneHour = getBoolValue(['notif_reminder_1h'], defaults.appointmentReminders.oneHour);
    const doctorDailySummaryEnabled = getBoolValue(['notif_daily_summary'], defaults.doctorDailySummary.enabled);
    const doctorDailySummaryTime = getStringValue(['notif_daily_summary_time'], defaults.doctorDailySummary.time);
    const migratedSettings = {
        version: 2,
        onlinePushEnabled,
        appointmentStatusAlerts: {
            enabled: true,
            locked: true,
        },
        adminAnnouncements: {
            enabled: true,
        },
        appointmentReminders: {
            enabled: appointmentRemindersEnabled,
            delivery: 'fcm',
            oneWeek,
            oneDay,
            oneHour,
        },
        doctorDailySummary: {
            enabled: doctorDailySummaryEnabled,
            delivery: 'fcm',
            time: doctorDailySummaryTime,
        },
        email,
    };
    await db.collection('users').doc(uid).update({
        notificationSettings: migratedSettings,
        updatedAt: admin.firestore.Timestamp.now(),
    });
    return migratedSettings;
}
function trustedNotificationPayload(id, params) {
    const now = new Date();
    const scheduledTime = params.scheduledFor;
    const isFuture = scheduledTime && scheduledTime > now;
    const deliveryChannel = params.deliveryChannel || 'fcm';
    const isVisible = params.isVisible !== undefined ? params.isVisible : !isFuture;
    return {
        id,
        userId: params.userId,
        title: params.title,
        body: params.body,
        type: params.type,
        data: params.data || null,
        isRead: false,
        createdAt: admin.firestore.Timestamp.now(),
        appointmentId: params.appointmentId || null,
        scheduledFor: scheduledTime ? admin.firestore.Timestamp.fromDate(scheduledTime) : null,
        reminderType: params.reminderType || null,
        createdByBackend: true,
        settingsVersion: 2,
        deliveryChannel,
        pushStatus: params.pushStatus || (deliveryChannel === 'inAppOnly' ? 'skipped_local_device_mode' : 'pending'),
        isDelivered: params.isDelivered !== undefined ? params.isDelivered : (deliveryChannel === 'inAppOnly'),
        isVisible,
        visibleAt: isVisible ? admin.firestore.Timestamp.now() : null,
        deliveredAt: null,
        pushAttemptedAt: null,
        deliveryAttempts: 0,
        deliveredTokenCount: 0,
        skippedTokenCount: 0,
        failedTokenCount: 0,
    };
}
async function createTrustedNotification(params, docId) {
    const id = docId || db.collection('notifications').doc().id;
    const ref = db.collection('notifications').doc(id);
    await ref.set(trustedNotificationPayload(id, params));
    return id;
}
function trustedNotificationPayloadWithId(id, params) {
    return trustedNotificationPayload(id, params);
}
async function deleteAppointmentNotifications(appointmentId) {
    const snap = await db.collection('notifications')
        .where('appointmentId', '==', appointmentId)
        .limit(500)
        .get();
    if (snap.empty)
        return;
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
}
async function createAppointmentNotifications(params) {
    const settings = await getUserNotificationSettings(params.userId);
    const exactTime = appointmentExactTime(params.appointmentDate, params.timeSlot);
    const formattedDate = formatDateForNotification(exactTime);
    if (params.includeConfirmation !== false) {
        await createTrustedNotification({
            userId: params.userId,
            title: 'Booking Confirmed',
            body: `Your appointment with Dr. ${params.doctorName} on ${formattedDate} at ${params.timeSlot} has been confirmed.`,
            type: 'appointmentConfirmation',
            data: { appointmentId: params.appointmentId },
            appointmentId: params.appointmentId,
            reminderType: 'immediate',
        }, `appointment_${params.appointmentId}_confirmation`);
    }
    if (!settings.appointmentReminders.enabled) {
        return;
    }
    const reminders = [
        { reminderType: 'oneWeek', scheduledFor: new Date(exactTime.getTime() - 7 * 24 * 60 * 60 * 1000), title: 'Appointment in 1 Week' },
        { reminderType: 'oneDay', scheduledFor: new Date(exactTime.getTime() - 24 * 60 * 60 * 1000), title: 'Appointment Tomorrow' },
        { reminderType: 'oneHour', scheduledFor: new Date(exactTime.getTime() - 60 * 60 * 1000), title: 'Appointment in 1 Hour' },
    ];
    const now = new Date();
    const deliveryChannel = settings.appointmentReminders.delivery === 'local' ? 'inAppOnly' : 'fcm';
    const isDelivered = (deliveryChannel === 'inAppOnly');
    const pushStatus = isDelivered ? 'skipped_local_device_mode' : 'pending';
    for (const reminder of reminders) {
        const isSwitchOn = (reminder.reminderType === 'oneWeek' && settings.appointmentReminders.oneWeek) ||
            (reminder.reminderType === 'oneDay' && settings.appointmentReminders.oneDay) ||
            (reminder.reminderType === 'oneHour' && settings.appointmentReminders.oneHour);
        if (!isSwitchOn)
            continue;
        if (reminder.scheduledFor <= now)
            continue;
        await createTrustedNotification({
            userId: params.userId,
            title: reminder.title,
            body: `Reminder: Your appointment with Dr. ${params.doctorName} is on ${formattedDate} at ${params.timeSlot}.`,
            type: 'appointmentReminder',
            data: { appointmentId: params.appointmentId, reminderType: reminder.reminderType },
            appointmentId: params.appointmentId,
            scheduledFor: reminder.scheduledFor,
            reminderType: reminder.reminderType,
            deliveryChannel,
            pushStatus,
            isDelivered,
            isVisible: false,
        }, `appointment_${params.appointmentId}_${reminder.reminderType}`);
    }
}
async function createAppointmentStatusNotification(params) {
    const patientId = params.appointment.patientId;
    if (!patientId)
        return;
    const doctorName = params.appointment.doctorName || 'your doctor';
    const appointmentDate = firestoreDateToDate(params.appointment.appointmentDate);
    const timeSlot = params.appointment.timeSlot;
    const when = appointmentDate
        ? `${formatDateForNotification(appointmentDate)}${timeSlot ? ` at ${timeSlot}` : ''}`
        : null;
    const withDoctor = `with Dr. ${doctorName}`;
    const suffix = when ? ` ${withDoctor} on ${when}` : ` ${withDoctor}`;
    const notificationByStatus = {
        confirmed: {
            title: 'Appointment Confirmed',
            body: `Your appointment${suffix} has been confirmed.`,
            type: 'appointmentConfirmation',
        },
        completed: {
            title: 'Appointment Completed',
            body: `Your appointment${suffix} has been marked as completed.`,
            type: 'appointmentCompleted',
        },
        noShow: {
            title: 'Appointment Marked No-Show',
            body: `Your appointment${suffix} has been marked as no-show. Please contact the health center if you need help rebooking.`,
            type: 'appointmentNoShow',
        },
    };
    const notification = notificationByStatus[params.status];
    if (!notification)
        return;
    await createTrustedNotification({
        userId: patientId,
        title: notification.title,
        body: notification.body,
        type: notification.type,
        data: { appointmentId: params.appointmentId, status: params.status },
        appointmentId: params.appointmentId,
        reminderType: 'immediate',
    }, `appointment_${params.appointmentId}_${params.status}`);
}
exports.createAppointment = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const callerData = callerDoc.data();
    const data = request.data;
    if (data.patientId !== callerUid) {
        throw new functions.https.HttpsError('permission-denied', 'You can only create appointments for yourself.');
    }
    if (!data.department || !data.appointmentDate || !data.timeSlot) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required appointment fields.');
    }
    const type = data.type || 'regularCheckup';
    if (!APPOINTMENT_TYPES.includes(type)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid appointment type.');
    }
    const appointmentDate = parseAppointmentDate(data.appointmentDate);
    const now = admin.firestore.Timestamp.now();
    let doctorUserId;
    const ref = db.collection('appointments').doc();
    const bookingReference = (data.bookingReference || ref.id.substring(0, 8)).toUpperCase();
    let trustedDoctorName = 'Any Available';
    let trustedDepartment = data.department;
    await db.runTransaction(async (transaction) => {
        if (data.doctorId) {
            const doctorRef = db.collection('doctors').doc(data.doctorId);
            const doctorDoc = await transaction.get(doctorRef);
            const doctorData = doctorDoc.data();
            if (!doctorDoc.exists || (doctorData === null || doctorData === void 0 ? void 0 : doctorData.isActive) !== true || (doctorData === null || doctorData === void 0 ? void 0 : doctorData.isAvailable) !== true) {
                throw new functions.https.HttpsError('failed-precondition', 'Selected doctor is unavailable.');
            }
            doctorUserId = doctorData.userId;
            trustedDoctorName = typeof doctorData.name === 'string' && doctorData.name.trim()
                ? doctorData.name.trim()
                : 'your doctor';
            trustedDepartment = typeof doctorData.department === 'string' && doctorData.department.trim()
                ? doctorData.department.trim()
                : data.department;
            await lockAppointmentSlot(transaction, {
                doctorId: data.doctorId,
                appointmentDate,
                timeSlot: data.timeSlot,
                appointmentId: ref.id,
                status: 'pending',
            });
        }
        else if (type !== 'emergency') {
            throw new functions.https.HttpsError('invalid-argument', 'doctorId is required for non-emergency appointments.');
        }
        transaction.set(ref, {
            id: ref.id,
            bookingReference,
            patientId: callerUid,
            patientName: callerData.fullName || '',
            patientEmail: callerData.email || '',
            doctorId: data.doctorId || '',
            doctorName: trustedDoctorName,
            department: trustedDepartment,
            appointmentDate: admin.firestore.Timestamp.fromDate(appointmentDate),
            timeSlot: data.timeSlot,
            type,
            status: 'pending',
            notes: data.notes || null,
            medicalNotes: null,
            qrCode: null,
            isCheckedIn: false,
            checkedInAt: null,
            createdAt: now,
            updatedAt: now,
            cancelReason: null,
            rescheduleReason: null,
            reminderSent24h: false,
            reminderSent1h: false,
            medicalNotesUpdatedAt: null,
            statusUpdatedBy: null,
            qrScanFailures: 0,
        });
        if (doctorUserId) {
            const accessRef = db.collection('doctor_patient_access').doc(doctorUserId)
                .collection('patients').doc(callerUid);
            transaction.set(accessRef, {
                doctorUserId,
                doctorId: data.doctorId,
                patientId: callerUid,
                appointmentId: ref.id,
                updatedAt: now,
            }, { merge: true });
        }
    });
    await createAppointmentNotifications({
        userId: callerUid,
        appointmentId: ref.id,
        doctorName: trustedDoctorName,
        appointmentDate,
        timeSlot: data.timeSlot,
    });
    return { success: true, appointmentId: ref.id, bookingReference };
});
exports.rescheduleAppointment = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const { appointmentId, appointmentDate, timeSlot, reason } = request.data;
    if (!appointmentId || !appointmentDate || !timeSlot) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required reschedule fields.');
    }
    const ref = db.collection('appointments').doc(appointmentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new functions.https.HttpsError('not-found', 'Appointment not found.');
    const appointment = snap.data();
    if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowPatient: true, allowDoctor: true, allowAdmin: true })) {
        throw new functions.https.HttpsError('permission-denied', 'You cannot reschedule this appointment.');
    }
    if (!ACTIVE_APPOINTMENT_STATUSES.includes(appointment.status)) {
        throw new functions.https.HttpsError('failed-precondition', 'Only active appointments can be rescheduled.');
    }
    const parsedDate = parseAppointmentDate(appointmentDate);
    await db.runTransaction(async (transaction) => {
        const transactionSnap = await transaction.get(ref);
        if (!transactionSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        }
        const currentAppointment = transactionSnap.data();
        if (!ACTIVE_APPOINTMENT_STATUSES.includes(currentAppointment.status)) {
            throw new functions.https.HttpsError('failed-precondition', 'Only active appointments can be rescheduled.');
        }
        let newSlotRef = null;
        if (currentAppointment.doctorId) {
            newSlotRef = await lockAppointmentSlot(transaction, {
                doctorId: currentAppointment.doctorId,
                appointmentDate: parsedDate,
                timeSlot,
                appointmentId,
                status: currentAppointment.status,
                excludeAppointmentId: appointmentId,
            });
        }
        const currentDate = firestoreDateToDate(currentAppointment.appointmentDate);
        if (currentAppointment.doctorId && currentDate && currentAppointment.timeSlot) {
            const currentSlotRef = appointmentSlotLockRef(currentAppointment.doctorId, currentDate, currentAppointment.timeSlot);
            if (!newSlotRef || currentSlotRef.path !== newSlotRef.path) {
                transaction.delete(currentSlotRef);
            }
        }
        transaction.update(ref, {
            appointmentDate: admin.firestore.Timestamp.fromDate(parsedDate),
            timeSlot,
            rescheduleReason: reason || null,
            updatedAt: admin.firestore.Timestamp.now(),
            statusUpdatedBy: callerUid,
        });
    });
    await deleteAppointmentNotifications(appointmentId);
    await createTrustedNotification({
        userId: appointment.patientId,
        title: 'Appointment Rescheduled',
        body: `Your appointment with Dr. ${appointment.doctorName || 'your doctor'} has been rescheduled to ${formatDateForNotification(parsedDate)} at ${timeSlot}.`,
        type: 'appointmentRescheduled',
        data: { appointmentId },
        appointmentId,
        reminderType: 'immediate',
    });
    await createAppointmentNotifications({
        userId: appointment.patientId,
        appointmentId,
        doctorName: appointment.doctorName || 'your doctor',
        appointmentDate: parsedDate,
        timeSlot,
        includeConfirmation: false,
    });
    return { success: true };
});
exports.cancelAppointment = functions.https.onCall(async (request) => {
    var _a, _b;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const { appointmentId, reason, statusUpdatedBy } = request.data;
    if (!appointmentId)
        throw new functions.https.HttpsError('invalid-argument', 'appointmentId is required.');
    const ref = db.collection('appointments').doc(appointmentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new functions.https.HttpsError('not-found', 'Appointment not found.');
    const appointment = snap.data();
    if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowPatient: true, allowDoctor: true, allowAdmin: true })) {
        throw new functions.https.HttpsError('permission-denied', 'You cannot cancel this appointment.');
    }
    await db.runTransaction(async (transaction) => {
        const transactionSnap = await transaction.get(ref);
        if (!transactionSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        }
        const currentAppointment = transactionSnap.data();
        releaseAppointmentSlot(transaction, appointmentId, currentAppointment);
        transaction.update(ref, {
            status: 'cancelled',
            cancelReason: reason || null,
            statusUpdatedBy: statusUpdatedBy || callerUid,
            updatedAt: admin.firestore.Timestamp.now(),
        });
    });
    await deleteAppointmentNotifications(appointmentId);
    const date = (_b = (_a = appointment.appointmentDate) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a);
    await createTrustedNotification({
        userId: appointment.patientId,
        title: 'Appointment Cancelled',
        body: `Your appointment with Dr. ${appointment.doctorName || 'your doctor'}${date ? ` on ${formatDateForNotification(date)}` : ''} has been cancelled.${reason ? ` Reason: ${reason}` : ''}`,
        type: 'appointmentCancellation',
        data: { appointmentId },
        appointmentId,
        reminderType: 'immediate',
    });
    return { success: true };
});
exports.updateAppointmentStatus = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const { appointmentId, status, statusUpdatedBy } = request.data;
    if (!appointmentId || !APPOINTMENT_STATUSES.includes(status)) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing or invalid appointment status.');
    }
    const ref = db.collection('appointments').doc(appointmentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new functions.https.HttpsError('not-found', 'Appointment not found.');
    const appointment = snap.data();
    if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowDoctor: true, allowAdmin: true })) {
        throw new functions.https.HttpsError('permission-denied', 'You cannot update this appointment status.');
    }
    let previousStatus = appointment.status;
    let updatedAppointment = appointment;
    await db.runTransaction(async (transaction) => {
        const transactionSnap = await transaction.get(ref);
        if (!transactionSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        }
        const currentAppointment = transactionSnap.data();
        previousStatus = currentAppointment.status;
        updatedAppointment = Object.assign(Object.assign({}, currentAppointment), { status });
        const appointmentDateForLock = firestoreDateToDate(currentAppointment.appointmentDate);
        if (ACTIVE_APPOINTMENT_STATUSES.includes(status) &&
            currentAppointment.doctorId &&
            appointmentDateForLock &&
            currentAppointment.timeSlot) {
            await lockAppointmentSlot(transaction, {
                doctorId: currentAppointment.doctorId,
                appointmentDate: appointmentDateForLock,
                timeSlot: currentAppointment.timeSlot,
                appointmentId,
                status,
                excludeAppointmentId: appointmentId,
            });
        }
        else {
            releaseAppointmentSlot(transaction, appointmentId, currentAppointment);
        }
        transaction.update(ref, {
            status,
            statusUpdatedBy: statusUpdatedBy || callerUid,
            updatedAt: admin.firestore.Timestamp.now(),
        });
    });
    if (previousStatus !== status) {
        if (status === 'completed' || status === 'noShow') {
            await deleteAppointmentNotifications(appointmentId);
        }
        await createAppointmentStatusNotification({
            appointmentId,
            appointment: updatedAppointment,
            status,
        });
    }
    return { success: true };
});
exports.updateMedicalNotes = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const { appointmentId, notes } = request.data;
    if (!appointmentId || typeof notes !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'appointmentId and notes are required.');
    }
    const ref = db.collection('appointments').doc(appointmentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new functions.https.HttpsError('not-found', 'Appointment not found.');
    const appointment = snap.data();
    if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowDoctor: true, allowAdmin: true })) {
        throw new functions.https.HttpsError('permission-denied', 'You cannot update medical notes for this appointment.');
    }
    await ref.update({
        medicalNotes: notes,
        medicalNotesUpdatedAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
    });
    return { success: true };
});
exports.incrementQrScanFailures = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const { appointmentId } = request.data;
    if (!appointmentId)
        throw new functions.https.HttpsError('invalid-argument', 'appointmentId is required.');
    const ref = db.collection('appointments').doc(appointmentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new functions.https.HttpsError('not-found', 'Appointment not found.');
    if (!await canMutateAppointment(callerUid, callerDoc, snap.data(), { allowDoctor: true })) {
        throw new functions.https.HttpsError('permission-denied', 'You cannot update QR failures for this appointment.');
    }
    await ref.update({
        qrScanFailures: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.Timestamp.now(),
    });
    return { success: true };
});
exports.deleteAppointment = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const { appointmentId } = request.data;
    if (!appointmentId)
        throw new functions.https.HttpsError('invalid-argument', 'appointmentId is required.');
    const ref = db.collection('appointments').doc(appointmentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new functions.https.HttpsError('not-found', 'Appointment not found.');
    if (!await canMutateAppointment(callerUid, callerDoc, snap.data(), { allowAdmin: true })) {
        throw new functions.https.HttpsError('permission-denied', 'Only authorized admins can delete appointments.');
    }
    await db.runTransaction(async (transaction) => {
        const transactionSnap = await transaction.get(ref);
        if (!transactionSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        }
        releaseAppointmentSlot(transaction, appointmentId, transactionSnap.data());
        transaction.delete(ref);
    });
    await deleteAppointmentNotifications(appointmentId);
    return { success: true };
});
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
    if (data.password.length < MIN_PASSWORD_LENGTH) {
        throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR_LONG);
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
    const data = request.data;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'doctors.manage');
    if (!data.newPassword || data.newPassword.length < MIN_PASSWORD_LENGTH) {
        throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR_LONG);
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
        // Update password and require the doctor to replace it on next login.
        await auth.updateUser(userId, { password: data.newPassword });
        await db.collection('users').doc(userId).update({
            requiresInitialPasswordChange: true,
            initialPasswordChangedAt: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.Timestamp.now(),
        });
        return { success: true, message: 'Password reset successfully' };
    }
    catch (error) {
        console.error('Error resetting doctor password:', error);
        throw new functions.https.HttpsError('internal', 'Failed to reset doctor password.');
    }
});
/**
 * Clear the one-time first-login password change gate after the signed-in
 * client successfully replaces their admin-issued temporary password.
 */
exports.completeInitialPasswordChange = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const data = request.data;
    if (!data.newPassword || data.newPassword.length < MIN_PASSWORD_LENGTH) {
        throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR_LONG);
    }
    const userRef = db.collection('users').doc(callerUid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User profile not found.');
    }
    const userData = userDoc.data();
    if (userData.isActive !== true) {
        throw new functions.https.HttpsError('permission-denied', 'Your account is inactive.');
    }
    const role = userData.role;
    if (!['doctor', 'student', 'staff'].includes(role !== null && role !== void 0 ? role : '')) {
        throw new functions.https.HttpsError('failed-precondition', 'Initial password change is only available for doctor and patient accounts.');
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
    requirePermission(callerDoc, 'users.manageNonAdmin');
    // Validate required fields
    if (!data.email || !data.password || !data.fullName || !data.role) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields: email, password, fullName, role');
    }
    // Only student/staff allowed — admin creation uses createAdminAccount
    if (!['student', 'staff'].includes(data.role)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid role. Must be student or staff. Use createAdminAccount for admin accounts.');
    }
    // Validate password strength
    if (data.password.length < MIN_PASSWORD_LENGTH) {
        throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR_LONG);
    }
    let createdUid = null;
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
        const uploadedPhotoUrl = await uploadProfilePhoto(userRecord.uid, data.photoUpload);
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
    }
    catch (error) {
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
/**
 * Cloud Function to update doctor profile-safe fields.
 */
exports.updateDoctorProfile = functions.https.onCall(async (request) => {
    var _a;
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
    const updates = {
        updatedAt: admin.firestore.Timestamp.now(),
    };
    if (data.name !== undefined)
        updates.name = data.name.trim();
    if (data.specialization !== undefined)
        updates.specialization = data.specialization.trim();
    if (data.department !== undefined)
        updates.department = data.department;
    if (data.bio !== undefined)
        updates.bio = (_a = data.bio) !== null && _a !== void 0 ? _a : '';
    if (data.photoUrl !== undefined)
        updates.photoUrl = data.photoUrl;
    if (data.experienceYears !== undefined)
        updates.experienceYears = data.experienceYears;
    if (data.consultationFee !== undefined)
        updates.consultationFee = data.consultationFee;
    if (data.qualifications !== undefined)
        updates.qualifications = data.qualifications;
    if (data.dailyNotificationTime !== undefined) {
        updates.dailyNotificationTime = data.dailyNotificationTime;
    }
    if (data.isActive !== undefined)
        updates.isActive = data.isActive;
    await doctorRef.update(updates);
    return { success: true, message: 'Doctor profile updated successfully' };
});
/**
 * Cloud Function to activate/deactivate a doctor record.
 */
exports.setDoctorActiveStatus = functions.https.onCall(async (request) => {
    var _a;
    const data = request.data;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'doctors.manage');
    if (!data.doctorId || typeof data.isActive !== 'boolean') {
        throw new functions.https.HttpsError('invalid-argument', 'doctorId and isActive are required.');
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
    const doctorUserId = (_a = doctorSnap.data()) === null || _a === void 0 ? void 0 : _a.userId;
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
});
/**
 * Cloud Function to update a doctor's weekly schedule.
 */
exports.updateDoctorSchedule = functions.https.onCall(async (request) => {
    const data = request.data;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'doctors.manage');
    if (!data.doctorId || !data.weeklySchedule || typeof data.weeklySchedule !== 'object') {
        throw new functions.https.HttpsError('invalid-argument', 'doctorId and weeklySchedule are required.');
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
});
/**
 * Cloud Function to create a department document.
 */
exports.createDepartment = functions.https.onCall(async (request) => {
    var _a, _b, _c;
    const data = request.data;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'departments.manage');
    if (!data.key || !data.name || !data.workingHours) {
        throw new functions.https.HttpsError('invalid-argument', 'key, name, and workingHours are required.');
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
        description: (_a = data.description) !== null && _a !== void 0 ? _a : '',
        iconName: (_b = data.iconName) !== null && _b !== void 0 ? _b : 'medical_services',
        colorHex: (_c = data.colorHex) !== null && _c !== void 0 ? _c : '#2196F3',
        workingHours: data.workingHours,
        isActive: true,
        doctorCount: 0,
        createdAt: now,
        updatedAt: now,
    });
    return { success: true, departmentId: ref.id, message: 'Department created successfully' };
});
/**
 * Cloud Function to update department fields.
 */
exports.updateDepartment = functions.https.onCall(async (request) => {
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
    const updates = {
        updatedAt: admin.firestore.Timestamp.now(),
    };
    if (data.key !== undefined)
        updates.key = data.key;
    if (data.name !== undefined)
        updates.name = data.name;
    if (data.description !== undefined)
        updates.description = data.description;
    if (data.iconName !== undefined)
        updates.iconName = data.iconName;
    if (data.colorHex !== undefined)
        updates.colorHex = data.colorHex;
    if (data.workingHours !== undefined)
        updates.workingHours = data.workingHours;
    await ref.update(updates);
    return { success: true, message: 'Department updated successfully' };
});
/**
 * Cloud Function to activate/deactivate a department.
 */
exports.setDepartmentActiveStatus = functions.https.onCall(async (request) => {
    const data = request.data;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'departments.manage');
    if (!data.departmentId || typeof data.isActive !== 'boolean') {
        throw new functions.https.HttpsError('invalid-argument', 'departmentId and isActive are required.');
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
});
/**
 * Cloud Function to delete a department.
 */
exports.deleteDepartment = functions.https.onCall(async (request) => {
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
});
/**
 * Create the caller's own user document after self-registration.
 * This keeps users/{userId} create blocked in Firestore rules while
 * preserving the existing registerWithEmail UX.
 */
exports.bootstrapSelfUserDocument = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const data = request.data;
    if (!(data === null || data === void 0 ? void 0 : data.fullName) || !data.fullName.trim()) {
        throw new functions.https.HttpsError('invalid-argument', 'fullName is required.');
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
});
/**
 * Activate/deactivate a non-admin user.
 * Admin requires users.manageNonAdmin permission.
 * Super Admin bypasses permission checks.
 */
exports.setUserActiveStatus = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'users.manageNonAdmin');
    const { targetUid, isActive } = request.data;
    if (!targetUid || typeof isActive !== 'boolean') {
        throw new functions.https.HttpsError('invalid-argument', 'Missing or invalid targetUid/isActive.');
    }
    const callerRole = callerDoc.data().role;
    const targetDoc = await db.collection('users').doc(targetUid).get();
    if (!targetDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    }
    const targetRole = targetDoc.data().role;
    if (targetRole === 'superAdmin') {
        throw new functions.https.HttpsError('failed-precondition', 'Cannot modify Super Admin status via this function.');
    }
    if (targetRole === 'admin') {
        throw new functions.https.HttpsError('failed-precondition', 'Use setAdminActiveStatus for admin accounts.');
    }
    if (callerRole === 'admin' && targetRole === 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Admins cannot modify admin accounts.');
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
});
/**
 * Change role between student/staff for non-admin targets.
 * Admin requires users.manageNonAdmin permission.
 * Super Admin bypasses permission checks, but cannot use this for admin/superAdmin.
 */
exports.changeUserRoleByAdmin = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'users.manageNonAdmin');
    const { targetUid, newRole } = request.data;
    if (!targetUid || !newRole) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing targetUid or newRole.');
    }
    if (!['student', 'staff'].includes(newRole)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid role. Only student/staff are allowed here.');
    }
    const callerRole = callerDoc.data().role;
    const targetRef = db.collection('users').doc(targetUid);
    const targetDoc = await targetRef.get();
    if (!targetDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    }
    const targetData = targetDoc.data();
    const oldRole = targetData.role;
    if (oldRole === 'superAdmin' || oldRole === 'admin') {
        throw new functions.https.HttpsError('failed-precondition', 'Cannot change admin/superAdmin roles via this function.');
    }
    if (callerRole === 'admin' && (oldRole === 'admin' || oldRole === 'superAdmin')) {
        throw new functions.https.HttpsError('permission-denied', 'Admins cannot modify admin/superAdmin accounts.');
    }
    if (oldRole === newRole) {
        return {
            success: true,
            message: 'Role already set.',
        };
    }
    const updates = {
        role: newRole,
        updatedAt: admin.firestore.Timestamp.now(),
        studentId: newRole === 'student' ? targetUid : null,
        staffId: newRole === 'staff' ? targetUid : null,
    };
    await targetRef.update(updates);
    await writeAdminAuditLog({
        actorUid: callerUid,
        actorRole: callerRole,
        actorName: callerDoc.data().fullName,
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
});
/**
 * Unlink Google sign-in provider from a non-admin user.
 * Admin requires users.manageNonAdmin permission.
 * Super Admin bypasses permission checks.
 */
exports.unlinkGoogleProviderByAdmin = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'users.manageNonAdmin');
    const { targetUid } = request.data;
    if (!targetUid) {
        throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
    }
    const callerData = callerDoc.data();
    const callerRole = callerData.role;
    const targetRef = db.collection('users').doc(targetUid);
    const targetDoc = await targetRef.get();
    if (!targetDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    }
    const targetData = targetDoc.data();
    const targetRole = targetData.role;
    if (targetRole === 'superAdmin') {
        throw new functions.https.HttpsError('failed-precondition', 'Cannot unlink Google for Super Admin accounts via this function.');
    }
    if (targetRole === 'admin') {
        throw new functions.https.HttpsError('failed-precondition', 'Use governance flow for admin account provider management.');
    }
    if (callerRole === 'admin' && (targetRole === 'admin' || targetRole === 'superAdmin')) {
        throw new functions.https.HttpsError('permission-denied', 'Admins cannot modify admin/superAdmin accounts.');
    }
    const authUser = await auth.getUser(targetUid);
    const providerIds = new Set(authUser.providerData.map((p) => p.providerId));
    if (!providerIds.has('google.com')) {
        throw new functions.https.HttpsError('failed-precondition', 'Target user does not have Google linked.');
    }
    if (!providerIds.has('password')) {
        throw new functions.https.HttpsError('failed-precondition', 'Cannot unlink Google: user has no email/password sign-in linked.');
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
});
/**
 * Update profile-safe fields for a target user via server-side enforcement.
 * Admins can manage non-admin users only.
 * Super Admins can manage all users, including super admins.
 */
exports.updateUserProfileByAdmin = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'users.manageNonAdmin');
    const data = request.data;
    if (!(data === null || data === void 0 ? void 0 : data.targetUid)) {
        throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
    }
    const callerRole = callerDoc.data().role;
    const targetRef = db.collection('users').doc(data.targetUid);
    const targetDoc = await targetRef.get();
    if (!targetDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    }
    const targetRole = targetDoc.data().role;
    if (targetRole === 'superAdmin' && callerRole !== 'superAdmin') {
        throw new functions.https.HttpsError('permission-denied', 'Only Super Admin can edit Super Admin profile.');
    }
    if (callerRole === 'admin' && targetRole === 'admin') {
        throw new functions.https.HttpsError('permission-denied', 'Admins cannot edit admin accounts.');
    }
    const updates = {
        updatedAt: admin.firestore.Timestamp.now(),
    };
    if (data.fullName !== undefined) {
        const trimmed = data.fullName.trim();
        if (!trimmed) {
            throw new functions.https.HttpsError('invalid-argument', 'fullName cannot be empty.');
        }
        updates.fullName = trimmed;
    }
    if (data.phoneNumber !== undefined)
        updates.phoneNumber = data.phoneNumber;
    if (data.photoUpload !== undefined && data.photoUpload !== null) {
        updates.photoUrl = await uploadProfilePhoto(data.targetUid, data.photoUpload);
    }
    else if (data.photoUrl !== undefined) {
        updates.photoUrl = data.photoUrl;
    }
    if (data.studentId !== undefined)
        updates.studentId = data.studentId;
    if (data.staffId !== undefined)
        updates.staffId = data.staffId;
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
});
/**
 * Delete a student or staff account from User Management.
 * Admin accounts use deleteAdminAccount, doctors use deleteDoctorAccount.
 */
exports.deleteUserAccount = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'users.manageNonAdmin');
    const data = request.data;
    if (!(data === null || data === void 0 ? void 0 : data.targetUid)) {
        throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
    }
    if (data.targetUid === callerUid) {
        throw new functions.https.HttpsError('failed-precondition', 'You cannot delete your own account from User Management.');
    }
    const callerRole = callerDoc.data().role;
    const targetRef = db.collection('users').doc(data.targetUid);
    const targetDoc = await targetRef.get();
    if (!targetDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Target user not found.');
    }
    const targetData = targetDoc.data();
    const targetRole = targetData.role;
    if (targetRole === 'superAdmin') {
        throw new functions.https.HttpsError('permission-denied', 'Super Admin accounts cannot be deleted from User Management.');
    }
    if (targetRole === 'admin') {
        throw new functions.https.HttpsError('failed-precondition', 'Admin accounts must be deleted from Super Admin controls.');
    }
    if (targetRole === 'doctor') {
        throw new functions.https.HttpsError('failed-precondition', 'Doctor accounts must be deleted from Doctor Management.');
    }
    if (callerRole !== 'superAdmin' && targetRole !== 'student' && targetRole !== 'staff') {
        throw new functions.https.HttpsError('permission-denied', 'Admins can delete student and staff accounts only.');
    }
    try {
        await revokeSessionsAndClearFcm(data.targetUid);
        await auth.deleteUser(data.targetUid).catch((error) => {
            if ((error === null || error === void 0 ? void 0 : error.code) !== 'auth/user-not-found') {
                throw error;
            }
        });
        await deleteProfilePhotos(data.targetUid);
        await targetRef.delete();
        return {
            success: true,
            message: 'User account deleted successfully.',
        };
    }
    catch (error) {
        console.error('Error deleting user account:', error);
        throw toHttpsError(error, 'Failed to delete user account.');
    }
});
// ─────────────────────────────────────────────────────────
// FCM Push Notification Functions
// ─────────────────────────────────────────────────────────
const messaging = admin.messaging();
const MAX_PUSH_DELIVERY_ATTEMPTS = 3;
function scheduledForDate(notification) {
    const scheduledFor = notification.scheduledFor;
    if (!scheduledFor)
        return null;
    if (typeof scheduledFor.toDate === 'function') {
        return scheduledFor.toDate();
    }
    const parsed = new Date(scheduledFor);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
}
function fcmErrorCode(error) {
    if (!error || typeof error !== 'object' || !('code' in error))
        return null;
    const code = error.code;
    return typeof code === 'string' ? code : null;
}
function isTerminalFcmError(error) {
    const code = fcmErrorCode(error);
    return code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-argument' ||
        code === 'messaging/mismatched-credential';
}
function shouldSendPushToToken(notification, settings, token) {
    if (settings.onlinePushEnabled === false)
        return false;
    if (token.onlinePushEnabled === false)
        return false;
    if (notification.deliveryChannel !== 'fcm')
        return false;
    if (notification.type === 'appointmentReminder') {
        const reminderType = notification.reminderType;
        const isReminderEnabled = settings.appointmentReminders.enabled && ((reminderType === 'oneWeek' && settings.appointmentReminders.oneWeek) ||
            (reminderType === 'oneDay' && settings.appointmentReminders.oneDay) ||
            (reminderType === 'oneHour' && settings.appointmentReminders.oneHour));
        return isReminderEnabled && token.appointmentReminderDelivery === 'fcm';
    }
    if (notification.type === 'dailySummary') {
        return settings.doctorDailySummary.enabled && token.doctorDailySummaryDelivery === 'fcm';
    }
    if (notification.type === 'adminAnnouncement') {
        return settings.adminAnnouncements.enabled;
    }
    return true;
}
function errorMessage(error) {
    if (error instanceof Error)
        return error.message;
    if (error && typeof error === 'object' && 'message' in error) {
        const message = error.message;
        if (typeof message === 'string')
            return message;
    }
    return String(error);
}
async function deliverNotificationPush(snap, notificationId) {
    var _a;
    const notification = snap.data();
    if (!notification) {
        console.log(`Notification ${notificationId} is empty, skipping push.`);
        return;
    }
    if (notification.createdByBackend !== true) {
        console.log(`Notification ${notificationId} was not backend-created, skipping push delivery.`);
        return;
    }
    if (notification.isDelivered === true) {
        console.log(`Notification ${notificationId} already delivered, skipping push.`);
        return;
    }
    const userId = notification.userId;
    if (!userId) {
        console.log(`Notification ${notificationId} has no userId, skipping push.`);
        return;
    }
    let settings;
    try {
        settings = await getUserNotificationSettings(userId);
    }
    catch (err) {
        console.error(`Error loading settings for user ${userId}, using defaults:`, err);
        const userDoc = await db.collection('users').doc(userId).get();
        const role = userDoc.exists ? (((_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.role) || 'student') : 'student';
        settings = role === 'doctor' ? DEFAULT_DOCTOR_SETTINGS : DEFAULT_PATIENT_SETTINGS;
    }
    try {
        const tokensList = [];
        const subcollectionSnap = await db.collection('user_tokens')
            .doc(userId)
            .collection('tokens')
            .get();
        if (!subcollectionSnap.empty) {
            subcollectionSnap.docs.forEach((doc) => {
                tokensList.push(doc.data());
            });
        }
        else {
            const legacyDoc = await db.collection('user_tokens').doc(userId).get();
            const legacyData = legacyDoc.data();
            if (legacyDoc.exists && (legacyData === null || legacyData === void 0 ? void 0 : legacyData.token)) {
                tokensList.push({
                    token: legacyData.token,
                    tokenHash: 'legacy',
                    platform: 'android',
                    supportsLocalReminders: true,
                    onlinePushEnabled: legacyData.onlinePushEnabled !== undefined ? !!legacyData.onlinePushEnabled : true,
                    appointmentReminderDelivery: 'fcm',
                    doctorDailySummaryDelivery: 'fcm',
                    timeZone: legacyData.timeZone || null,
                    createdAt: admin.firestore.Timestamp.now(),
                    updatedAt: admin.firestore.Timestamp.now(),
                    lastSeenAt: admin.firestore.Timestamp.now(),
                });
            }
        }
        if (tokensList.length === 0) {
            console.log(`No FCM token found for user ${userId}, skipping push.`);
            await snap.ref.update({
                isDelivered: true,
                deliveredAt: admin.firestore.Timestamp.now(),
                pushStatus: 'skipped_no_token',
                pushAttemptedAt: admin.firestore.Timestamp.now(),
                isVisible: true,
                visibleAt: admin.firestore.Timestamp.now(),
                deliveredTokenCount: 0,
                skippedTokenCount: 0,
                failedTokenCount: 0,
            });
            return;
        }
        const eligibleTokens = tokensList.filter(t => shouldSendPushToToken(notification, settings, t));
        const skippedTokens = tokensList.filter(t => !shouldSendPushToToken(notification, settings, t));
        if (eligibleTokens.length === 0) {
            console.log(`No push-eligible token found for user ${userId}, skipping push.`);
            await snap.ref.update({
                isDelivered: true,
                deliveredAt: admin.firestore.Timestamp.now(),
                pushStatus: 'skipped_no_eligible_token',
                pushAttemptedAt: admin.firestore.Timestamp.now(),
                isVisible: true,
                visibleAt: admin.firestore.Timestamp.now(),
                deliveredTokenCount: 0,
                skippedTokenCount: skippedTokens.length,
                failedTokenCount: 0,
            });
            return;
        }
        const multicastMessage = {
            tokens: eligibleTokens.map(t => t.token),
            notification: {
                title: notification.title || 'UHC Notification',
                body: notification.body || '',
            },
            data: Object.assign(Object.assign({ notificationId, type: notification.type || 'systemUpdate' }, (notification.appointmentId && { appointmentId: notification.appointmentId })), (notification.data && Object.fromEntries(Object.entries(notification.data).map(([k, v]) => [k, String(v)])))),
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
        const response = await messaging.sendEachForMulticast(multicastMessage);
        let successCount = 0;
        let failureCount = 0;
        for (let idx = 0; idx < response.responses.length; idx++) {
            const res = response.responses[idx];
            const tokenObj = eligibleTokens[idx];
            if (res.success) {
                successCount++;
            }
            else {
                failureCount++;
                const error = res.error;
                console.error(`FCM send failed for token ${tokenObj.token.slice(0, 10)}...:`, error);
                if (error && isTerminal稳定Error(error)) {
                    console.log(`Removing stale FCM token for user ${userId}: ${tokenObj.tokenHash}`);
                    if (tokenObj.tokenHash === 'legacy') {
                        await db.collection('user_tokens').doc(userId).delete().catch(() => { });
                    }
                    else {
                        await db.collection('user_tokens')
                            .doc(userId)
                            .collection('tokens')
                            .doc(tokenObj.tokenHash)
                            .delete()
                            .catch(() => { });
                    }
                }
            }
        }
        const attempts = Number(notification.deliveryAttempts || 0) + 1;
        const allFailedRetryable = successCount === 0 && failureCount > 0 && response.responses.every(r => r.error && !isTerminal稳定Error(r.error));
        if (allFailedRetryable && attempts < MAX_PUSH_DELIVERY_ATTEMPTS) {
            await snap.ref.update({
                isDelivered: false,
                scheduledFor: admin.firestore.Timestamp.now(),
                deliveryAttempts: attempts,
                pushStatus: 'retryable_error',
                pushAttemptedAt: admin.firestore.Timestamp.now(),
                deliveredTokenCount: 0,
                skippedTokenCount: skippedTokens.length,
                failedTokenCount: failureCount,
            });
            return;
        }
        const finalStatus = successCount === eligibleTokens.length ? 'sent' : // pushStatus: 'sent'
            (successCount > 0 ? 'sent_partial' :
                (response.responses.some(r => r.error && isTerminal稳定Error(r.error)) ? 'failed_terminal' : 'failed_retry_exhausted'));
        await snap.ref.update({
            isDelivered: true,
            deliveredAt: admin.firestore.Timestamp.now(),
            deliveryAttempts: attempts,
            pushStatus: finalStatus,
            pushAttemptedAt: admin.firestore.Timestamp.now(),
            isVisible: true,
            visibleAt: admin.firestore.Timestamp.now(),
            deliveredTokenCount: successCount,
            skippedTokenCount: skippedTokens.length,
            failedTokenCount: failureCount,
        });
    }
    catch (error) {
        console.error(`Error sending FCM for notification ${notificationId}:`, error);
        const code = fcmErrorCode(error);
        const attempts = Number(notification.deliveryAttempts || 0) + 1;
        const terminal = isTerminal稳定Error(error);
        if (code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered') {
            console.log(`Removing stale FCM token for user ${userId}`);
            await db.collection('user_tokens').doc(userId).delete().catch(() => { });
        }
        if (!terminal && attempts < MAX_PUSH_DELIVERY_ATTEMPTS) {
            await snap.ref.update({
                isDelivered: false,
                scheduledFor: admin.firestore.Timestamp.now(),
                deliveryAttempts: attempts,
                pushStatus: 'retryable_error',
                pushAttemptedAt: admin.firestore.Timestamp.now(),
                pushErrorCode: code || 'unknown',
                pushErrorMessage: errorMessage(error).slice(0, 240),
            });
            return;
        }
        await snap.ref.update({
            isDelivered: true,
            deliveredAt: admin.firestore.Timestamp.now(),
            deliveryAttempts: attempts,
            pushStatus: terminal ? 'failed_terminal' : 'failed_retry_exhausted',
            pushAttemptedAt: admin.firestore.Timestamp.now(),
            pushErrorCode: code || 'unknown',
            pushErrorMessage: errorMessage(error).slice(0, 240),
            isVisible: true,
            visibleAt: admin.firestore.Timestamp.now(),
        });
    }
}
// Helper mapping to uniform name isTerminal稳定Error
const isTerminal稳定Error = isTerminalTransientOrTerminal;
function isTerminalTransientOrTerminal(error) {
    return isTerminal稳定ErrorOriginal(error);
}
const isTerminal稳定ErrorOriginal = isTerminal稳定ErrorActual;
function isTerminal稳定ErrorActual(error) {
    return isTerminal稳定ErrorOriginalOriginal(error);
}
const isTerminal稳定ErrorOriginalOriginal = isTerminalFcmError;
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
    if (notification.createdByBackend !== true) {
        console.log(`Notification ${notificationId} was not backend-created, skipping push delivery.`);
        return;
    }
    const scheduledTime = scheduledForDate(notification);
    if (scheduledTime && scheduledTime > new Date()) {
        console.log(`Notification ${notificationId} is scheduled for the future, scheduled worker will deliver it.`);
        return;
    }
    await deliverNotificationPush(snap, notificationId);
});
exports.deliverScheduledNotifications = (0, scheduler_1.onSchedule)({
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Baghdad',
    retryCount: 0,
}, async () => {
    const now = admin.firestore.Timestamp.now();
    // Query 1: FCM scheduled notifications
    const fcmSnap = await db.collection('notifications')
        .where('isDelivered', '==', false)
        .where('deliveryChannel', '==', 'fcm')
        .where('scheduledFor', '<=', now)
        .orderBy('scheduledFor', 'asc')
        .limit(100)
        .get();
    if (!fcmSnap.empty) {
        console.log(`Delivering ${fcmSnap.docs.length} scheduled FCM notification(s).`);
        await Promise.all(fcmSnap.docs.map((doc) => deliverNotificationPush(doc, doc.id)));
    }
    // Query 2: Local/In-app only scheduled notifications that need to be made visible
    const inAppSnap = await db.collection('notifications')
        .where('isVisible', '==', false)
        .where('deliveryChannel', '==', 'inAppOnly')
        .where('scheduledFor', '<=', now)
        .orderBy('scheduledFor', 'asc')
        .limit(100)
        .get();
    if (!inAppSnap.empty) {
        console.log(`Making ${inAppSnap.docs.length} in-app-only notification(s) visible.`);
        const batch = db.batch();
        inAppSnap.docs.forEach((doc) => {
            batch.update(doc.ref, {
                isVisible: true,
                visibleAt: admin.firestore.Timestamp.now(),
            });
        });
        await batch.commit();
    }
});
const DOCTOR_AVAILABILITY_MONTHLY_LIMIT = 2;
const DOCTOR_AVAILABILITY_ADMIN_NOTIFICATION_LIMIT = 450;
const DOCTOR_AVAILABILITY_APPOINTMENT_BATCH_SIZE = 200;
const DOCTOR_AVAILABILITY_TIME_ZONE = 'Asia/Baghdad';
const ADMIN_NOTIFICATION_TARGET_TYPES = [
    'singlePatient',
    'singleDoctor',
    'allPatients',
    'allDoctors',
    'patientsAndDoctors',
];
const ADMIN_NOTIFICATION_MAX_RECIPIENTS = 500;
const ADMIN_NOTIFICATION_COOLDOWN_MS = 60 * 1000;
const ADMIN_NOTIFICATION_BATCH_SIZE = 450;
const ADMIN_NOTIFICATION_SEARCH_SCAN_LIMIT = 2000;
function isAdminNotificationTargetType(value) {
    return typeof value === 'string' &&
        ADMIN_NOTIFICATION_TARGET_TYPES.includes(value);
}
function adminNotificationTargetLabel(targetType) {
    switch (targetType) {
        case 'singlePatient':
            return 'Single patient';
        case 'singleDoctor':
            return 'Single doctor';
        case 'allPatients':
            return 'All active patients';
        case 'allDoctors':
            return 'All active doctors';
        case 'patientsAndDoctors':
            return 'All active patients and doctors';
    }
}
function normalizeSearchText(value) {
    return String(value || '')
        .normalize('NFKD')
        .replace(/[\u0300-\u036f\u064b-\u065f\u0670\u0640]/g, '')
        .replace(/[أإآٱ]/g, 'ا')
        .replace(/[ىئ]/g, 'ي')
        .replace(/ی/g, 'ي')
        .replace(/ك/g, 'ک')
        .replace(/ة/g, 'ه')
        .replace(/ؤ/g, 'و')
        .trim()
        .toLocaleLowerCase();
}
function requireTargetUserId(value, label) {
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', `${label} must be a string.`);
    }
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 128 || trimmed.includes('/')) {
        throw new functions.https.HttpsError('invalid-argument', `${label} is invalid.`);
    }
    return trimmed;
}
function sanitizeAdminNotificationRequestId(value) {
    if (value === undefined || value === null || value === '') {
        return (0, crypto_1.randomUUID)();
    }
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'requestId must be a string.');
    }
    const trimmed = value.trim();
    if (!/^[A-Za-z0-9_-]{8,80}$/.test(trimmed)) {
        throw new functions.https.HttpsError('invalid-argument', 'requestId is invalid.');
    }
    return trimmed;
}
function requireTrimmedText(value, field, maxLength) {
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', `${field} must be a string.`);
    }
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > maxLength) {
        throw new functions.https.HttpsError('invalid-argument', `${field} must be between 1 and ${maxLength} characters.`);
    }
    return trimmed;
}
function recipientFromUserDoc(doc) {
    const data = doc.data();
    if (!data || data.isActive !== true)
        return null;
    const role = data.role;
    if (role !== 'student' && role !== 'staff' && role !== 'doctor')
        return null;
    return {
        uid: doc.id,
        name: data.fullName || data.email || doc.id,
        role,
        email: data.email,
        subtitle: role === 'student'
            ? data.studentId
            : role === 'staff'
                ? data.staffId
                : data.email,
    };
}
function doctorRecipientFromDocs(doctorDoc, userDoc) {
    const doctor = doctorDoc.data();
    const user = userDoc === null || userDoc === void 0 ? void 0 : userDoc.data();
    const userId = doctor.userId;
    if (!userId || doctor.isActive !== true || !user || user.isActive !== true) {
        return null;
    }
    if (user.role !== 'doctor') {
        return null;
    }
    return {
        uid: userId,
        name: doctor.name ||
            user.fullName ||
            doctor.email ||
            user.email ||
            userId,
        role: 'doctor',
        email: doctor.email || user.email,
        subtitle: doctor.specialization ||
            doctor.department ||
            user.email,
    };
}
async function requireActivePatientRecipient(targetUserId) {
    const uid = requireTargetUserId(targetUserId, 'targetUserId');
    const doc = await db.collection('users').doc(uid).get();
    const recipient = recipientFromUserDoc(doc);
    if (!recipient || (recipient.role !== 'student' && recipient.role !== 'staff')) {
        throw new functions.https.HttpsError('failed-precondition', 'Target user must be an active student or staff patient.');
    }
    return recipient;
}
async function hasActiveDoctorRecord(userId) {
    const doctorSnap = await db.collection('doctors')
        .where('userId', '==', userId)
        .limit(10)
        .get();
    return doctorSnap.docs.some((doc) => doc.data().isActive === true);
}
async function requireActiveDoctorRecipient(targetUserId) {
    const uid = requireTargetUserId(targetUserId, 'targetUserId');
    const doc = await db.collection('users').doc(uid).get();
    const recipient = recipientFromUserDoc(doc);
    if (!recipient || recipient.role !== 'doctor') {
        throw new functions.https.HttpsError('failed-precondition', 'Target user must be an active doctor.');
    }
    if (!(await hasActiveDoctorRecord(uid))) {
        throw new functions.https.HttpsError('failed-precondition', 'Target doctor record must be active.');
    }
    return recipient;
}
function enforceAdminNotificationCap(count) {
    if (count > ADMIN_NOTIFICATION_MAX_RECIPIENTS) {
        throw new functions.https.HttpsError('resource-exhausted', `Admin notifications are capped at ${ADMIN_NOTIFICATION_MAX_RECIPIENTS} recipients in v1.`);
    }
}
async function getActivePatientRecipients() {
    const snap = await db.collection('users')
        .where('isActive', '==', true)
        .limit(ADMIN_NOTIFICATION_SEARCH_SCAN_LIMIT)
        .get();
    const recipients = snap.docs
        .map((doc) => recipientFromUserDoc(doc))
        .filter((recipient) => recipient !== null && (recipient.role === 'student' || recipient.role === 'staff'));
    enforceAdminNotificationCap(recipients.length);
    return recipients;
}
async function getActiveDoctorRecipients() {
    const doctorSnap = await db.collection('doctors')
        .where('isActive', '==', true)
        .limit(ADMIN_NOTIFICATION_MAX_RECIPIENTS + 1)
        .get();
    enforceAdminNotificationCap(doctorSnap.docs.length);
    const userIds = Array.from(new Set(doctorSnap.docs
        .map((doc) => doc.data().userId)
        .filter((userId) => !!userId)));
    enforceAdminNotificationCap(userIds.length);
    if (userIds.length === 0)
        return [];
    const userDocs = await db.getAll(...userIds.map((userId) => db.collection('users').doc(userId)));
    const usersById = new Map(userDocs.map((doc) => [doc.id, doc]));
    const recipients = doctorSnap.docs
        .map((doc) => {
        const userId = doc.data().userId;
        return userId ? doctorRecipientFromDocs(doc, usersById.get(userId)) : null;
    })
        .filter((recipient) => recipient !== null && recipient.role === 'doctor');
    enforceAdminNotificationCap(recipients.length);
    return recipients;
}
async function getAdminNotificationRecipients(targetType, targetUserId) {
    switch (targetType) {
        case 'singlePatient':
            return [await requireActivePatientRecipient(targetUserId)];
        case 'singleDoctor':
            return [await requireActiveDoctorRecipient(targetUserId)];
        case 'allPatients':
            return getActivePatientRecipients();
        case 'allDoctors':
            return getActiveDoctorRecipients();
        case 'patientsAndDoctors': {
            const [patients, doctors] = await Promise.all([
                getActivePatientRecipients(),
                getActiveDoctorRecipients(),
            ]);
            const byUid = new Map();
            [...patients, ...doctors].forEach((recipient) => byUid.set(recipient.uid, recipient));
            enforceAdminNotificationCap(byUid.size);
            return Array.from(byUid.values());
        }
    }
}
function assertAdminNotificationTarget(data) {
    if (!isAdminNotificationTargetType(data.targetType)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid targetType.');
    }
    if (data.targetType === 'singlePatient' || data.targetType === 'singleDoctor') {
        requireTargetUserId(data.targetUserId, 'targetUserId');
    }
    return data.targetType;
}
function matchesRecipientQuery(recipient, query) {
    const haystack = [
        recipient.name,
        recipient.email,
        recipient.subtitle,
        recipient.role,
        recipient.role === 'doctor' ? 'doctor dr دكتور دکتۆر پزیشک' : null,
        recipient.role === 'student' ? 'patient student طالب قوتابی خوێندکار' : null,
        recipient.role === 'staff' ? 'patient staff موظف ستاف کارمەند' : null,
    ].map((value) => normalizeSearchText(value)).join(' ');
    return haystack.includes(query);
}
async function reserveAdminNotificationSend(callerUid, requestId) {
    const sendId = `${callerUid}_${requestId}`;
    const sendRef = db.collection('admin_notification_sends').doc(sendId);
    const rateRef = db.collection('admin_notification_rate_limits').doc(callerUid);
    await db.runTransaction(async (transaction) => {
        var _a, _b;
        const [sendDoc, rateDoc] = await Promise.all([
            transaction.get(sendRef),
            transaction.get(rateRef),
        ]);
        if (sendDoc.exists) {
            const status = (_a = sendDoc.data()) === null || _a === void 0 ? void 0 : _a.status;
            throw new functions.https.HttpsError('already-exists', `This notification request was already ${status || 'submitted'}.`);
        }
        const lastSentAt = (_b = rateDoc.data()) === null || _b === void 0 ? void 0 : _b.lastSentAt;
        if (lastSentAt) {
            const elapsedMs = Date.now() - lastSentAt.toDate().getTime();
            if (elapsedMs < ADMIN_NOTIFICATION_COOLDOWN_MS) {
                throw new functions.https.HttpsError('resource-exhausted', 'Please wait before sending another notification.');
            }
        }
        const now = admin.firestore.Timestamp.now();
        transaction.create(sendRef, {
            id: sendId,
            callerUid,
            requestId,
            status: 'reserved',
            createdAt: now,
            updatedAt: now,
        });
        transaction.set(rateRef, {
            lastSentAt: now,
            updatedAt: now,
        }, { merge: true });
    });
    return sendId;
}
async function markAdminNotificationSend(sendId, status, metadata) {
    await db.collection('admin_notification_sends').doc(sendId).set(Object.assign(Object.assign({ status }, metadata), { updatedAt: admin.firestore.Timestamp.now() }), { merge: true });
}
async function createAdminNotificationDocs(params) {
    for (let i = 0; i < params.recipients.length; i += ADMIN_NOTIFICATION_BATCH_SIZE) {
        const batch = db.batch();
        const chunk = params.recipients.slice(i, i + ADMIN_NOTIFICATION_BATCH_SIZE);
        const chunkIds = [];
        for (const recipient of chunk) {
            const notificationId = `admin_${params.sendId}_${encodeURIComponent(recipient.uid)}`;
            const ref = db.collection('notifications').doc(notificationId);
            chunkIds.push(notificationId);
            batch.set(ref, trustedNotificationPayloadWithId(notificationId, {
                userId: recipient.uid,
                title: params.title,
                body: params.body,
                type: 'adminAnnouncement',
                data: {
                    targetType: params.targetType,
                    sentBy: params.callerUid,
                    sendId: params.sendId,
                },
                reminderType: 'immediate',
            }));
        }
        await batch.commit();
        params.notificationIds.push(...chunkIds);
    }
    return params.notificationIds;
}
function availabilityDateParts(date) {
    const formatted = new Intl.DateTimeFormat('en-CA', {
        timeZone: DOCTOR_AVAILABILITY_TIME_ZONE,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    }).format(date);
    const match = formatted.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) {
        return {
            year: Number(match[1]),
            month: Number(match[2]),
            day: Number(match[3]),
        };
    }
    const fallback = new Date(date.getTime() + 3 * 60 * 60 * 1000);
    return {
        year: fallback.getUTCFullYear(),
        month: fallback.getUTCMonth() + 1,
        day: fallback.getUTCDate(),
    };
}
function availabilityMonthKey(date = new Date()) {
    const parts = availabilityDateParts(date);
    return `${parts.year}-${String(parts.month).padStart(2, '0')}`;
}
function baghdadStartOfToday(date = new Date()) {
    const parts = availabilityDateParts(date);
    return new Date(Date.UTC(parts.year, parts.month - 1, parts.day, -3, 0, 0, 0));
}
function doctorAvailabilityUsageRef(doctorId, monthKey) {
    return db.collection('doctor_availability_usage').doc(`${doctorId}_${monthKey}`);
}
function sanitizeAvailabilityReason(value) {
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError('invalid-argument', 'Please add a short note for the admin.');
    }
    const trimmed = value.trim();
    if (trimmed.length < 3 || trimmed.length > 280) {
        throw new functions.https.HttpsError('invalid-argument', 'The note must be between 3 and 280 characters.');
    }
    return trimmed;
}
function requireAvailabilityRequestId(value) {
    return requireTargetUserId(value, 'requestId');
}
function parseAvailabilityDecision(value) {
    if (value === 'approved' || value === 'rejected')
        return value;
    throw new functions.https.HttpsError('invalid-argument', 'decision must be approved or rejected.');
}
function clearPendingAvailabilityFields() {
    return {
        availabilityRequestStatus: admin.firestore.FieldValue.delete(),
        pendingAvailabilityRequestId: admin.firestore.FieldValue.delete(),
        availabilityRequestReason: admin.firestore.FieldValue.delete(),
        availabilityRequestedAt: admin.firestore.FieldValue.delete(),
    };
}
async function getDoctorManagingAdminRecipients() {
    const snap = await db.collection('users')
        .where('isActive', '==', true)
        .limit(ADMIN_NOTIFICATION_SEARCH_SCAN_LIMIT)
        .get();
    return snap.docs
        .map((doc) => {
        const data = doc.data();
        const role = data.role;
        const permissions = data.adminPermissions;
        const canManageDoctors = role === 'superAdmin' ||
            (role === 'admin' && (permissions === null || permissions === void 0 ? void 0 : permissions['doctors.manage']) === true);
        if (!canManageDoctors)
            return null;
        const recipientRole = role === 'superAdmin' ? 'superAdmin' : 'admin';
        return {
            uid: doc.id,
            name: data.fullName ||
                data.email ||
                doc.id,
            role: recipientRole,
            email: data.email,
            subtitle: role === 'superAdmin' ? 'Super Admin' : 'Doctor management',
        };
    })
        .filter((recipient) => recipient !== null);
}
function setDoctorAvailabilityAdminNotifications(transaction, params) {
    if (params.recipients.length > DOCTOR_AVAILABILITY_ADMIN_NOTIFICATION_LIMIT) {
        throw new functions.https.HttpsError('resource-exhausted', 'Too many doctor-managing admins to notify.');
    }
    const notificationIds = [];
    for (const recipient of params.recipients) {
        const notificationId = `doctor_availability_${params.requestId}_${encodeURIComponent(recipient.uid)}`;
        notificationIds.push(notificationId);
        transaction.set(db.collection('notifications').doc(notificationId), trustedNotificationPayloadWithId(notificationId, {
            userId: recipient.uid,
            title: 'Action required: doctor availability',
            body: `Dr. ${params.doctorName} requested to become unavailable. Note: ${params.reason}`,
            type: 'doctorAvailabilityRequest',
            data: {
                category: 'doctorAvailabilityRequest',
                priority: 'high',
                availabilityRequestId: params.requestId,
                doctorId: params.doctorId,
                doctorUserId: params.doctorUserId,
                doctorName: params.doctorName,
                specialization: params.specialization || '',
                reason: params.reason,
                status: 'pending',
                monthKey: params.monthKey,
                monthlyLimit: DOCTOR_AVAILABILITY_MONTHLY_LIMIT,
            },
            reminderType: 'immediate',
        }));
    }
    return notificationIds;
}
async function updateDoctorAvailabilityAdminNotifications(params) {
    const title = params.status === 'approved'
        ? 'Doctor availability approved'
        : 'Doctor availability rejected';
    const body = params.status === 'approved'
        ? `Dr. ${params.doctorName} is now unavailable.`
        : `Dr. ${params.doctorName}'s unavailable request was rejected.`;
    for (const notificationId of params.notificationIds) {
        await db.collection('notifications').doc(notificationId).update({
            title,
            body,
            'data.status': params.status,
            'data.reviewedBy': params.reviewerUid,
            'data.reviewedByName': params.reviewerName || null,
            'data.reviewedAt': admin.firestore.Timestamp.now(),
        }).catch((error) => {
            console.warn(`Failed to update admin notification ${notificationId}:`, error);
        });
    }
}
async function cancelActiveAppointmentsForUnavailableDoctor(params) {
    const start = admin.firestore.Timestamp.fromDate(baghdadStartOfToday());
    const appointmentIds = [];
    let cancelledCount = 0;
    while (true) {
        const snap = await db.collection('appointments')
            .where('doctorId', '==', params.doctorId)
            .where('status', 'in', ACTIVE_APPOINTMENT_STATUSES)
            .where('appointmentDate', '>=', start)
            .orderBy('appointmentDate', 'asc')
            .limit(DOCTOR_AVAILABILITY_APPOINTMENT_BATCH_SIZE)
            .get();
        if (snap.empty)
            break;
        const batch = db.batch();
        const notifications = [];
        for (const doc of snap.docs) {
            const appointment = doc.data();
            const appointmentDate = firestoreDateToDate(appointment.appointmentDate);
            const timeSlot = appointment.timeSlot || '';
            batch.update(doc.ref, {
                status: 'cancelled',
                cancelReason: 'Doctor unavailable. Please cancel or reschedule with another available time.',
                statusUpdatedBy: params.reviewedByUid,
                cancellationSource: 'doctorAvailabilityApproved',
                availabilityRequestId: params.requestId,
                updatedAt: admin.firestore.Timestamp.now(),
            });
            if (appointmentDate && timeSlot) {
                batch.delete(appointmentSlotLockRef(params.doctorId, appointmentDate, timeSlot));
            }
            notifications.push({
                appointmentId: doc.id,
                patientId: appointment.patientId,
                doctorName: appointment.doctorName ||
                    params.doctorName ||
                    'your doctor',
                appointmentDate,
                timeSlot,
            });
            appointmentIds.push(doc.id);
        }
        await batch.commit();
        for (const notification of notifications) {
            if (!notification.patientId)
                continue;
            await deleteAppointmentNotifications(notification.appointmentId);
            await createTrustedNotification({
                userId: notification.patientId,
                title: 'Appointment Cancelled',
                body: `Your appointment with Dr. ${notification.doctorName}${notification.appointmentDate ? ` on ${formatDateForNotification(notification.appointmentDate)}` : ''}${notification.timeSlot ? ` at ${notification.timeSlot}` : ''} has been cancelled because the doctor is unavailable. Please book another available time.`,
                type: 'appointmentCancellation',
                data: {
                    appointmentId: notification.appointmentId,
                    availabilityRequestId: params.requestId,
                    cancellationSource: 'doctorAvailabilityApproved',
                },
                appointmentId: notification.appointmentId,
                reminderType: 'immediate',
            });
        }
        cancelledCount += snap.size;
        if (snap.size < DOCTOR_AVAILABILITY_APPOINTMENT_BATCH_SIZE)
            break;
    }
    return { cancelledCount, appointmentIds };
}
/**
 * Doctor requests admin approval before becoming unavailable.
 */
exports.requestDoctorUnavailable = functions.https.onCall(async (request) => {
    var _a;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const callerData = callerDoc.data();
    if (callerData.role !== 'doctor') {
        throw new functions.https.HttpsError('permission-denied', 'Only doctors can request unavailable status.');
    }
    const reason = sanitizeAvailabilityReason((_a = request.data) === null || _a === void 0 ? void 0 : _a.reason);
    const doctorDoc = await getDoctorForUser(callerUid);
    if (!doctorDoc) {
        throw new functions.https.HttpsError('not-found', 'Doctor profile not found.');
    }
    const recipients = await getDoctorManagingAdminRecipients();
    if (recipients.length === 0) {
        throw new functions.https.HttpsError('failed-precondition', 'No doctor-managing admin is available to review this request.');
    }
    const requestRef = db.collection('doctor_availability_requests').doc();
    const monthKey = availabilityMonthKey();
    let approvedCount = 0;
    let notificationIds = [];
    await db.runTransaction(async (transaction) => {
        var _a;
        const [doctorSnap, usageSnap] = await Promise.all([
            transaction.get(doctorDoc.ref),
            transaction.get(doctorAvailabilityUsageRef(doctorDoc.id, monthKey)),
        ]);
        if (!doctorSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor profile not found.');
        }
        const doctorData = doctorSnap.data();
        if (doctorData.isActive !== true) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor account is inactive.');
        }
        if (doctorData.isAvailable === false) {
            throw new functions.https.HttpsError('failed-precondition', 'You are already unavailable.');
        }
        if (doctorData.availabilityRequestStatus === 'pending') {
            throw new functions.https.HttpsError('already-exists', 'You already have an unavailable request waiting for admin review.');
        }
        approvedCount = Number(((_a = usageSnap.data()) === null || _a === void 0 ? void 0 : _a.approvedCount) || 0);
        if (approvedCount >= DOCTOR_AVAILABILITY_MONTHLY_LIMIT) {
            throw new functions.https.HttpsError('resource-exhausted', `You can become unavailable only ${DOCTOR_AVAILABILITY_MONTHLY_LIMIT} times per month.`);
        }
        const now = admin.firestore.Timestamp.now();
        const doctorName = doctorData.name ||
            callerData.fullName ||
            'Doctor';
        notificationIds = setDoctorAvailabilityAdminNotifications(transaction, {
            requestId: requestRef.id,
            recipients,
            doctorId: doctorDoc.id,
            doctorUserId: callerUid,
            doctorName,
            specialization: doctorData.specialization,
            reason,
            monthKey,
        });
        transaction.set(requestRef, {
            id: requestRef.id,
            doctorId: doctorDoc.id,
            doctorUserId: callerUid,
            doctorName,
            specialization: doctorData.specialization || '',
            reason,
            status: 'pending',
            monthKey,
            monthlyLimit: DOCTOR_AVAILABILITY_MONTHLY_LIMIT,
            approvedCountAtRequest: approvedCount,
            adminNotificationIds: notificationIds,
            createdAt: now,
            updatedAt: now,
        });
        transaction.update(doctorDoc.ref, {
            availabilityRequestStatus: 'pending',
            pendingAvailabilityRequestId: requestRef.id,
            availabilityRequestReason: reason,
            availabilityRequestedAt: now,
            updatedAt: now,
        });
    });
    return {
        success: true,
        requestId: requestRef.id,
        status: 'pending',
        monthlyLimit: DOCTOR_AVAILABILITY_MONTHLY_LIMIT,
        usedThisMonth: approvedCount,
        remainingThisMonth: DOCTOR_AVAILABILITY_MONTHLY_LIMIT - approvedCount,
        adminNotificationIds: notificationIds,
    };
});
/**
 * Doctor can return to available immediately. Becoming unavailable requires approval.
 */
exports.setDoctorAvailability = functions.https.onCall(async (request) => {
    var _a, _b;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    if (((_a = callerDoc.data()) === null || _a === void 0 ? void 0 : _a.role) !== 'doctor') {
        throw new functions.https.HttpsError('permission-denied', 'Only doctors can update their own availability.');
    }
    if (((_b = request.data) === null || _b === void 0 ? void 0 : _b.isAvailable) !== true) {
        throw new functions.https.HttpsError('failed-precondition', 'Submit an unavailable request for admin approval.');
    }
    const doctorDoc = await getDoctorForUser(callerUid);
    if (!doctorDoc) {
        throw new functions.https.HttpsError('not-found', 'Doctor profile not found.');
    }
    const doctorData = doctorDoc.data();
    if (doctorData.availabilityRequestStatus === 'pending') {
        throw new functions.https.HttpsError('failed-precondition', 'Your unavailable request is still waiting for admin review.');
    }
    await doctorDoc.ref.update(Object.assign(Object.assign({ isAvailable: true }, clearPendingAvailabilityFields()), { updatedAt: admin.firestore.Timestamp.now() }));
    return { success: true, isAvailable: true };
});
/**
 * Admins with doctor management permission can set a doctor's live availability.
 */
exports.setDoctorAvailabilityByAdmin = functions.https.onCall(async (request) => {
    var _a, _b;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'doctors.manage');
    const callerData = callerDoc.data();
    const doctorId = requireTargetUserId((_a = request.data) === null || _a === void 0 ? void 0 : _a.doctorId, 'doctorId');
    if (typeof ((_b = request.data) === null || _b === void 0 ? void 0 : _b.isAvailable) !== 'boolean') {
        throw new functions.https.HttpsError('invalid-argument', 'doctorId and isAvailable are required.');
    }
    const isAvailable = request.data.isAvailable;
    const doctorRef = db.collection('doctors').doc(doctorId);
    const context = await db.runTransaction(async (transaction) => {
        var _a, _b;
        const doctorSnap = await transaction.get(doctorRef);
        if (!doctorSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }
        const doctorData = doctorSnap.data();
        const doctorUserId = doctorData.userId;
        if (!doctorUserId) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor is not linked to a login account.');
        }
        const doctorName = doctorData.name || 'Doctor';
        const now = admin.firestore.Timestamp.now();
        const pendingRequestId = typeof doctorData.pendingAvailabilityRequestId === 'string'
            ? doctorData.pendingAvailabilityRequestId
            : undefined;
        let pendingDecision;
        let pendingNotificationIds = [];
        let monthKey;
        if (pendingRequestId) {
            const requestRef = db.collection('doctor_availability_requests').doc(pendingRequestId);
            const requestSnap = await transaction.get(requestRef);
            if (requestSnap.exists && ((_a = requestSnap.data()) === null || _a === void 0 ? void 0 : _a.status) === 'pending') {
                const requestData = requestSnap.data();
                pendingDecision = isAvailable ? 'rejected' : 'approved';
                monthKey = String(requestData.monthKey || availabilityMonthKey());
                pendingNotificationIds = Array.isArray(requestData.adminNotificationIds)
                    ? requestData.adminNotificationIds.map((id) => String(id))
                    : [];
                if (pendingDecision === 'approved') {
                    const usageRef = doctorAvailabilityUsageRef(doctorId, monthKey);
                    const usageSnap = await transaction.get(usageRef);
                    const approvedCount = Number(((_b = usageSnap.data()) === null || _b === void 0 ? void 0 : _b.approvedCount) || 0);
                    if (approvedCount >= DOCTOR_AVAILABILITY_MONTHLY_LIMIT) {
                        throw new functions.https.HttpsError('resource-exhausted', `This doctor has already used ${DOCTOR_AVAILABILITY_MONTHLY_LIMIT} unavailable approvals this month.`);
                    }
                    transaction.set(usageRef, {
                        doctorId,
                        doctorUserId,
                        monthKey,
                        approvedCount: approvedCount + 1,
                        updatedAt: now,
                    }, { merge: true });
                }
                transaction.update(requestRef, {
                    status: pendingDecision,
                    reviewedAt: now,
                    reviewedBy: callerUid,
                    reviewedByName: callerData.fullName || null,
                    updatedAt: now,
                });
            }
        }
        const updates = Object.assign(Object.assign({ isAvailable }, clearPendingAvailabilityFields()), { availabilityUpdatedByAdminAt: now, availabilityUpdatedByAdminUid: callerUid, updatedAt: now });
        if (!isAvailable) {
            updates.lastUnavailableApprovedAt = now;
            updates.lastAvailabilityRequestId = pendingRequestId || null;
            updates.lastAvailabilityRequestReason = pendingRequestId
                ? (doctorData.availabilityRequestReason || 'Admin marked unavailable')
                : 'Admin marked unavailable';
            if (monthKey)
                updates.availabilityUsageMonth = monthKey;
        }
        transaction.update(doctorRef, updates);
        return {
            doctorUserId,
            doctorName,
            pendingRequestId,
            pendingDecision,
            pendingNotificationIds,
            monthKey,
        };
    });
    let cancelledAppointments = 0;
    let cancellationError = null;
    if (!isAvailable) {
        try {
            const cancellation = await cancelActiveAppointmentsForUnavailableDoctor({
                doctorId,
                reviewedByUid: callerUid,
                doctorName: context.doctorName,
                requestId: context.pendingRequestId || `admin_manual_${doctorId}_${Date.now()}`,
            });
            cancelledAppointments = cancellation.cancelledCount;
        }
        catch (error) {
            cancellationError = errorMessage(error).slice(0, 240);
            console.error('Failed to cancel appointments for admin availability change:', error);
        }
    }
    if (context.pendingDecision) {
        await updateDoctorAvailabilityAdminNotifications({
            notificationIds: context.pendingNotificationIds,
            status: context.pendingDecision,
            doctorName: context.doctorName,
            reviewerUid: callerUid,
            reviewerName: callerData.fullName,
        });
    }
    await createTrustedNotification({
        userId: context.doctorUserId,
        title: 'Availability updated by admin',
        body: isAvailable
            ? 'Admin marked you available.'
            : 'Admin marked you unavailable.',
        type: 'doctorAvailabilityDecision',
        data: {
            status: isAvailable ? 'available' : 'unavailable',
            source: 'adminDoctorManagement',
            doctorId,
            availabilityRequestId: context.pendingRequestId || '',
            cancelledAppointments,
        },
        reminderType: 'immediate',
    });
    await writeAdminAuditLog({
        actorUid: callerUid,
        actorRole: callerData.role,
        actorName: callerData.fullName,
        targetUid: context.doctorUserId,
        targetName: context.doctorName,
        targetRoleBefore: 'doctor',
        targetRoleAfter: 'doctor',
        action: isAvailable
            ? 'doctorAvailability.adminSetAvailable'
            : 'doctorAvailability.adminSetUnavailable',
        metadata: {
            doctorId,
            pendingRequestId: context.pendingRequestId || null,
            pendingDecision: context.pendingDecision || null,
            cancelledAppointments,
            cancellationError,
        },
    });
    return {
        success: true,
        isAvailable,
        cancelledAppointments,
        cancellationError,
    };
});
/**
 * Admin approval or rejection for doctor unavailable requests.
 */
exports.reviewDoctorAvailabilityRequest = functions.https.onCall(async (request) => {
    var _a, _b;
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'doctors.manage');
    const callerData = callerDoc.data();
    const requestId = requireAvailabilityRequestId((_a = request.data) === null || _a === void 0 ? void 0 : _a.requestId);
    const decision = parseAvailabilityDecision((_b = request.data) === null || _b === void 0 ? void 0 : _b.decision);
    const requestRef = db.collection('doctor_availability_requests').doc(requestId);
    const reviewContext = await db.runTransaction(async (transaction) => {
        var _a;
        const requestSnap = await transaction.get(requestRef);
        if (!requestSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Availability request not found.');
        }
        const requestData = requestSnap.data();
        if (requestData.status !== 'pending') {
            throw new functions.https.HttpsError('failed-precondition', 'This availability request has already been reviewed.');
        }
        const doctorId = requireTargetUserId(requestData.doctorId, 'doctorId');
        const doctorUserId = requireTargetUserId(requestData.doctorUserId, 'doctorUserId');
        const monthKey = String(requestData.monthKey || availabilityMonthKey());
        const doctorRef = db.collection('doctors').doc(doctorId);
        const usageRef = doctorAvailabilityUsageRef(doctorId, monthKey);
        const [doctorSnap, usageSnap] = await Promise.all([
            transaction.get(doctorRef),
            decision === 'approved' ? transaction.get(usageRef) : Promise.resolve(null),
        ]);
        if (!doctorSnap.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor profile not found.');
        }
        const doctorData = doctorSnap.data();
        if (doctorData.userId !== doctorUserId || doctorData.isActive !== true) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor profile is no longer active.');
        }
        const approvedCount = usageSnap
            ? Number(((_a = usageSnap.data()) === null || _a === void 0 ? void 0 : _a.approvedCount) || 0)
            : 0;
        if (decision === 'approved' && approvedCount >= DOCTOR_AVAILABILITY_MONTHLY_LIMIT) {
            throw new functions.https.HttpsError('resource-exhausted', `This doctor has already used ${DOCTOR_AVAILABILITY_MONTHLY_LIMIT} unavailable approvals this month.`);
        }
        const now = admin.firestore.Timestamp.now();
        const doctorName = requestData.doctorName ||
            doctorData.name ||
            'Doctor';
        const reason = String(requestData.reason || '');
        const notificationIds = Array.isArray(requestData.adminNotificationIds)
            ? requestData.adminNotificationIds.map((id) => String(id))
            : [];
        if (decision === 'approved') {
            transaction.update(doctorRef, Object.assign(Object.assign({ isAvailable: false, lastUnavailableApprovedAt: now, lastAvailabilityRequestId: requestId, lastAvailabilityRequestReason: reason, availabilityUsageMonth: monthKey }, clearPendingAvailabilityFields()), { updatedAt: now }));
            transaction.set(usageRef, {
                doctorId,
                doctorUserId,
                monthKey,
                approvedCount: approvedCount + 1,
                updatedAt: now,
            }, { merge: true });
        }
        else {
            transaction.update(doctorRef, Object.assign(Object.assign({}, clearPendingAvailabilityFields()), { updatedAt: now }));
        }
        transaction.update(requestRef, {
            status: decision,
            reviewedAt: now,
            reviewedBy: callerUid,
            reviewedByName: callerData.fullName || null,
            updatedAt: now,
        });
        return {
            doctorId,
            doctorUserId,
            doctorName,
            reason,
            monthKey,
            notificationIds,
        };
    });
    let cancelledAppointments = 0;
    let cancellationError = null;
    if (decision === 'approved') {
        try {
            const cancellation = await cancelActiveAppointmentsForUnavailableDoctor({
                doctorId: reviewContext.doctorId,
                reviewedByUid: callerUid,
                doctorName: reviewContext.doctorName,
                requestId,
            });
            cancelledAppointments = cancellation.cancelledCount;
            await requestRef.update({
                cancelledAppointmentIds: cancellation.appointmentIds,
                cancelledAppointments,
                cancellationProcessedAt: admin.firestore.Timestamp.now(),
            });
        }
        catch (error) {
            cancellationError = errorMessage(error).slice(0, 240);
            console.error('Failed to cancel appointments for availability approval:', error);
            await requestRef.update({
                cancellationError,
                cancellationProcessedAt: admin.firestore.Timestamp.now(),
            }).catch(() => { });
        }
    }
    await updateDoctorAvailabilityAdminNotifications({
        notificationIds: reviewContext.notificationIds,
        status: decision,
        doctorName: reviewContext.doctorName,
        reviewerUid: callerUid,
        reviewerName: callerData.fullName,
    });
    await createTrustedNotification({
        userId: reviewContext.doctorUserId,
        title: decision === 'approved'
            ? 'Availability request approved'
            : 'Availability request rejected',
        body: decision === 'approved'
            ? 'Your request was approved. You are now unavailable.'
            : 'Your request was rejected',
        type: 'doctorAvailabilityDecision',
        data: {
            availabilityRequestId: requestId,
            status: decision,
            cancelledAppointments,
        },
        reminderType: 'immediate',
    });
    await writeAdminAuditLog({
        actorUid: callerUid,
        actorRole: callerData.role,
        actorName: callerData.fullName,
        targetUid: reviewContext.doctorUserId,
        targetName: reviewContext.doctorName,
        targetRoleBefore: 'doctor',
        targetRoleAfter: 'doctor',
        action: `doctorAvailability.${decision}`,
        metadata: {
            requestId,
            doctorId: reviewContext.doctorId,
            monthKey: reviewContext.monthKey,
            cancelledAppointments,
            cancellationError,
        },
    });
    return {
        success: true,
        status: decision,
        cancelledAppointments,
        cancellationError,
    };
});
/**
 * Search valid single-send recipients without granting broad user-list access.
 */
exports.searchAdminNotificationRecipients = functions.https.onCall(async (request) => {
    try {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'notifications.send');
        const data = request.data || {};
        const targetType = data.targetType;
        if (targetType !== 'singlePatient' && targetType !== 'singleDoctor') {
            throw new functions.https.HttpsError('invalid-argument', 'Recipient search is only available for singlePatient and singleDoctor.');
        }
        const query = normalizeSearchText(data.query);
        const limit = Math.min(Math.max(Number(data.limit) || 10, 1), 20);
        if (query.length < 2) {
            return { success: true, recipients: [] };
        }
        if (targetType === 'singlePatient') {
            const recipients = (await getActivePatientRecipients())
                .filter((recipient) => matchesRecipientQuery(recipient, query))
                .slice(0, limit);
            return { success: true, recipients };
        }
        const recipients = (await getActiveDoctorRecipients())
            .filter((recipient) => matchesRecipientQuery(recipient, query))
            .slice(0, limit);
        return { success: true, recipients };
    }
    catch (error) {
        console.error('searchAdminNotificationRecipients failed:', error);
        throw toHttpsError(error, 'Failed to search notification recipients.');
    }
});
/**
 * Preview trusted recipient count before confirmation.
 */
exports.previewAdminNotificationRecipients = functions.https.onCall(async (request) => {
    try {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'notifications.send');
        const data = request.data || {};
        const targetType = assertAdminNotificationTarget(data);
        const recipients = await getAdminNotificationRecipients(targetType, data.targetUserId);
        return {
            success: true,
            targetLabel: adminNotificationTargetLabel(targetType),
            recipientCount: recipients.length,
        };
    }
    catch (error) {
        console.error('previewAdminNotificationRecipients failed:', error);
        throw toHttpsError(error, 'Failed to count notification recipients.');
    }
});
/**
 * Callable Cloud Function for admins to send trusted in-app and push notifications.
 */
exports.sendAdminNotification = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'notifications.send');
    const data = request.data;
    const targetType = assertAdminNotificationTarget(data);
    const title = requireTrimmedText(data.title, 'title', 80);
    const body = requireTrimmedText(data.body, 'body', 500);
    const requestId = sanitizeAdminNotificationRequestId(data.requestId);
    const recipients = await getAdminNotificationRecipients(targetType, data.targetUserId);
    if (recipients.length === 0) {
        throw new functions.https.HttpsError('failed-precondition', 'No active recipients matched this target.');
    }
    enforceAdminNotificationCap(recipients.length);
    const callerData = callerDoc.data();
    const sendId = await reserveAdminNotificationSend(callerUid, requestId);
    const baseAudit = {
        actorUid: callerUid,
        actorRole: callerData.role,
        actorName: callerData.fullName,
        targetUid: data.targetUserId || targetType,
        targetName: adminNotificationTargetLabel(targetType),
    };
    await writeAdminAuditLog(Object.assign(Object.assign({}, baseAudit), { action: 'notifications.send.attempt', metadata: {
            sendId,
            targetType,
            recipientCount: recipients.length,
            titlePreview: title.slice(0, 80),
            bodyLength: body.length,
        } }));
    let notificationIds = [];
    try {
        notificationIds = await createAdminNotificationDocs({
            sendId,
            callerUid,
            recipients,
            targetType,
            title,
            body,
            notificationIds,
        });
    }
    catch (error) {
        await markAdminNotificationSend(sendId, 'failed', {
            targetType,
            recipientCount: recipients.length,
            createdCount: notificationIds.length,
            errorMessage: errorMessage(error).slice(0, 240),
        }).catch(() => { });
        await writeAdminAuditLog(Object.assign(Object.assign({}, baseAudit), { action: 'notifications.send.failed', metadata: {
                sendId,
                targetType,
                recipientCount: recipients.length,
                createdCount: notificationIds.length,
                errorMessage: errorMessage(error).slice(0, 240),
            } })).catch(() => { });
        throw toHttpsError(error, 'Failed to create notification records.');
    }
    await markAdminNotificationSend(sendId, 'completed', {
        targetType,
        recipientCount: recipients.length,
        createdCount: notificationIds.length,
    });
    await writeAdminAuditLog(Object.assign(Object.assign({}, baseAudit), { action: 'notifications.send', metadata: {
            sendId,
            targetType,
            recipientCount: recipients.length,
            createdCount: notificationIds.length,
            titlePreview: title.slice(0, 80),
            bodyLength: body.length,
        } }));
    return {
        success: true,
        targetLabel: adminNotificationTargetLabel(targetType),
        recipientCount: recipients.length,
        notificationIds,
        message: 'Notification queued for delivery.',
    };
});
/**
 * Callable Cloud Function for admins to send notifications to FCM topics
 * (e.g. "announcements", "department_cardiology").
 */
exports.sendTopicNotification = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    requirePermission(callerDoc, 'notifications.send');
    await writeAdminAuditLog({
        actorUid: callerUid,
        actorRole: callerDoc.data().role,
        actorName: callerDoc.data().fullName,
        targetUid: 'topic',
        targetName: 'Legacy topic notification',
        action: 'notifications.topicSend.blocked',
        metadata: {
            reason: 'deprecated_unaudited_topic_send',
        },
    }).catch(() => { });
    throw new functions.https.HttpsError('failed-precondition', 'Topic notifications are disabled. Use sendAdminNotification so notifications are audited and visible in-app.');
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
    if (data.password.length < MIN_PASSWORD_LENGTH) {
        throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR);
    }
    let createdUid = null;
    try {
        const userRecord = await auth.createUser({
            email: data.email, password: data.password,
            displayName: data.fullName, emailVerified: false,
        });
        createdUid = userRecord.uid;
        const now = admin.firestore.Timestamp.now();
        const uploadedPhotoUrl = await uploadProfilePhoto(userRecord.uid, data.photoUpload);
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
            actorUid: callerUid, actorRole: callerDoc.data().role,
            actorName: callerDoc.data().fullName,
            targetUid: userRecord.uid, targetName: data.fullName,
            targetRoleAfter: 'admin', action: 'admin.create',
        });
        return { success: true, userId: userRecord.uid, message: 'Admin account created successfully' };
    }
    catch (error) {
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
    try {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { targetUid, isActive } = request.data;
        if (!targetUid || typeof isActive !== 'boolean') {
            throw new functions.https.HttpsError('invalid-argument', 'Missing or invalid targetUid/isActive.');
        }
        const targetDoc = await db.collection('users').doc(targetUid).get();
        if (!targetDoc.exists)
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        const targetRole = targetDoc.data().role;
        if (targetRole !== 'admin')
            throw new functions.https.HttpsError('failed-precondition', 'This function can only target admin accounts.');
        await db.collection('users').doc(targetUid).update({ isActive, updatedAt: admin.firestore.Timestamp.now() });
        if (!isActive) {
            await revokeSessionsAndClearFcm(targetUid);
        }
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
            targetUid, targetName: targetDoc.data().fullName,
            action: isActive ? 'admin.activate' : 'admin.deactivate',
        });
        return { success: true, message: isActive ? 'Admin activated' : 'Admin deactivated' };
    }
    catch (error) {
        console.error('setAdminActiveStatus failed:', error);
        throw toHttpsError(error, 'Failed to update admin active status.');
    }
});
/**
 * Reset an admin's password. Super Admin only.
 */
exports.resetAdminPassword = functions.https.onCall(async (request) => {
    try {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { targetUid, newPassword } = request.data;
        if (!targetUid || !newPassword || newPassword.length < MIN_PASSWORD_LENGTH)
            throw new functions.https.HttpsError('invalid-argument', MIN_PASSWORD_ERROR);
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
    }
    catch (error) {
        console.error('resetAdminPassword failed:', error);
        throw toHttpsError(error, 'Failed to reset admin password.');
    }
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
    await deleteProfilePhotos(targetUid);
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
    try {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { targetUid } = request.data;
        if (!targetUid) {
            throw new functions.https.HttpsError('invalid-argument', 'targetUid is required.');
        }
        const targetDoc = await db.collection('users').doc(targetUid).get();
        if (!targetDoc.exists)
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        let authUserFound = true;
        try {
            await auth.revokeRefreshTokens(targetUid);
        }
        catch (error) {
            const code = error === null || error === void 0 ? void 0 : error.code;
            if (code === 'auth/user-not-found') {
                authUserFound = false;
            }
            else {
                throw error;
            }
        }
        // Also remove FCM token to stop push notifications
        await db.collection('user_tokens').doc(targetUid).delete().catch(() => { });
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
            targetUid, targetName: targetDoc.data().fullName,
            action: 'admin.forceSignOut',
            metadata: { authUserFound },
        });
        return {
            success: true,
            message: authUserFound
                ? 'User sessions revoked'
                : 'Auth user not found; local tokens were cleared.',
        };
    }
    catch (error) {
        console.error('forceSignOutUser failed:', error);
        throw toHttpsError(error, 'Failed to force sign out user.');
    }
});
/**
 * Set admin permissions. Super Admin only.
 */
exports.setAdminPermissions = functions.https.onCall(async (request) => {
    try {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const data = request.data || {};
        const { permissions } = data;
        const targetUid = requireTargetUserId(data.targetUid, 'targetUid');
        if (!targetUid || !permissions || typeof permissions !== 'object') {
            throw new functions.https.HttpsError('invalid-argument', 'Missing or invalid targetUid/permissions.');
        }
        const sanitizedPermissions = sanitizeAdminPermissions(permissions);
        const targetDoc = await db.collection('users').doc(targetUid).get();
        if (!targetDoc.exists)
            throw new functions.https.HttpsError('not-found', 'Target user not found.');
        if (targetDoc.data().role !== 'admin')
            throw new functions.https.HttpsError('failed-precondition', 'Permissions can only be set on admin accounts.');
        const oldPerms = targetDoc.data().adminPermissions || {};
        await db.collection('users').doc(targetUid).update({
            adminPermissions: sanitizedPermissions,
            updatedAt: admin.firestore.Timestamp.now(),
        });
        await writeAdminAuditLog({
            actorUid: callerUid, actorRole: 'superAdmin', actorName: callerDoc.data().fullName,
            targetUid, targetName: targetDoc.data().fullName,
            action: 'admin.permissionsUpdate',
            before: oldPerms,
            after: sanitizedPermissions,
        });
        return { success: true, message: 'Permissions updated' };
    }
    catch (error) {
        console.error('setAdminPermissions failed:', error);
        throw toHttpsError(error, 'Failed to update admin permissions.');
    }
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
    var _a, _b;
    try {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requireSuperAdmin(callerDoc);
        const { limit: queryLimit, targetUid, actorUid, action, dateFrom, dateTo, } = request.data || {};
        let dateFromValue = null;
        let dateToValue = null;
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
        let query = db.collection('admin_audit_logs');
        const indexedFilters = [
            { field: 'targetUid', value: targetUid },
            { field: 'actorUid', value: actorUid },
            { field: 'action', value: action },
        ].filter((filter) => Boolean(filter.value));
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
        const filteredDocs = [];
        let scannedDocs = 0;
        let lastDoc = null;
        while (filteredDocs.length <= requestedLimit && scannedDocs < maxScannedDocs) {
            const remainingScanBudget = maxScannedDocs - scannedDocs;
            let pageQuery = query.limit(Math.min(pageSize, remainingScanBudget));
            if (lastDoc) {
                pageQuery = pageQuery.startAfter(lastDoc);
            }
            const snap = await pageQuery.get();
            if (snap.empty)
                break;
            scannedDocs += snap.docs.length;
            lastDoc = snap.docs[snap.docs.length - 1];
            for (const doc of snap.docs) {
                const data = doc.data();
                if (targetUid && data.targetUid !== targetUid)
                    continue;
                if (actorUid && data.actorUid !== actorUid)
                    continue;
                if (action && data.action !== action)
                    continue;
                const createdAtDate = (_b = (_a = data.createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a);
                if (dateFromValue && (!createdAtDate || createdAtDate < dateFromValue))
                    continue;
                if (dateToValue && (!createdAtDate || createdAtDate > dateToValue))
                    continue;
                filteredDocs.push(doc);
                if (filteredDocs.length > requestedLimit)
                    break;
            }
            if (snap.docs.length < Math.min(pageSize, remainingScanBudget))
                break;
        }
        const visibleDocs = filteredDocs.slice(0, requestedLimit);
        const logs = visibleDocs.map(doc => {
            var _a, _b, _c;
            return (Object.assign(Object.assign({ id: doc.id }, doc.data()), { createdAt: ((_c = (_b = (_a = doc.data().createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString()) || null }));
        });
        return {
            success: true,
            logs,
            hasMore: filteredDocs.length > requestedLimit || scannedDocs >= maxScannedDocs,
            scanned: scannedDocs,
            scanLimit: maxScannedDocs,
        };
    }
    catch (error) {
        console.error('listAdminAuditLogs failed:', error);
        throw toHttpsError(error, 'Failed to load admin audit logs.');
    }
});
exports.resyncUserNotificationSchedules = functions.https.onCall(async (request) => {
    const callerUid = requireAuth(request);
    const callerDoc = await getCallerUserDoc(callerUid);
    const callerData = callerDoc.data();
    let targetUid = callerUid;
    if (request.data && request.data.userId) {
        const requestedUid = request.data.userId;
        if (requestedUid !== callerUid) {
            if (callerData.role !== 'admin' && callerData.role !== 'superAdmin') {
                throw new functions.https.HttpsError('permission-denied', 'You do not have permission to resync schedules for other users.');
            }
            targetUid = requestedUid;
        }
    }
    const settings = await getUserNotificationSettings(targetUid);
    // Find future active appointments for the user
    const now = admin.firestore.Timestamp.now();
    const appointmentsSnap = await db.collection('appointments')
        .where('patientId', '==', targetUid)
        .where('status', 'in', ['pending', 'confirmed'])
        .where('appointmentDate', '>=', now)
        .get();
    // Delete future appointmentReminder docs for that user
    const notificationsSnap = await db.collection('notifications')
        .where('userId', '==', targetUid)
        .where('type', '==', 'appointmentReminder')
        .where('scheduledFor', '>', now)
        .get();
    if (!notificationsSnap.empty) {
        const batch = db.batch();
        notificationsSnap.docs.forEach((doc) => batch.delete(doc.ref));
        await batch.commit();
    }
    // Recreate future reminder docs using current settings
    const appts = [];
    for (const doc of appointmentsSnap.docs) {
        const appt = doc.data();
        const date = firestoreDateToDate(appt.appointmentDate);
        if (!date)
            continue;
        const exactTime = appointmentExactTime(date, appt.timeSlot);
        const formattedDate = formatDateForNotification(exactTime);
        const reminders = [
            { reminderType: 'oneWeek', scheduledFor: new Date(exactTime.getTime() - 7 * 24 * 60 * 60 * 1000), title: 'Appointment in 1 Week' },
            { reminderType: 'oneDay', scheduledFor: new Date(exactTime.getTime() - 24 * 60 * 60 * 1000), title: 'Appointment Tomorrow' },
            { reminderType: 'oneHour', scheduledFor: new Date(exactTime.getTime() - 60 * 60 * 1000), title: 'Appointment in 1 Hour' },
        ];
        const apptReminders = {
            oneWeek: null,
            oneDay: null,
            oneHour: null,
        };
        if (settings.appointmentReminders.enabled) {
            const deliveryChannel = settings.appointmentReminders.delivery === 'local' ? 'inAppOnly' : 'fcm';
            const isDelivered = (deliveryChannel === 'inAppOnly');
            const pushStatus = isDelivered ? 'skipped_local_device_mode' : 'pending';
            for (const reminder of reminders) {
                const isSwitchOn = (reminder.reminderType === 'oneWeek' && settings.appointmentReminders.oneWeek) ||
                    (reminder.reminderType === 'oneDay' && settings.appointmentReminders.oneDay) ||
                    (reminder.reminderType === 'oneHour' && settings.appointmentReminders.oneHour);
                if (!isSwitchOn)
                    continue;
                const reminderTime = reminder.scheduledFor;
                const isFuture = reminderTime.getTime() > Date.now();
                if (!isFuture)
                    continue;
                apptReminders[reminder.reminderType] = reminderTime.toISOString();
                const reminderId = `appointment_${appt.id}_${reminder.reminderType}`;
                const reminderRef = db.collection('notifications').doc(reminderId);
                await reminderRef.set(trustedNotificationPayload(reminderId, {
                    userId: targetUid,
                    title: reminder.title,
                    body: `Reminder: Your appointment with Dr. ${appt.doctorName} is on ${formattedDate} at ${appt.timeSlot}.`,
                    type: 'appointmentReminder',
                    data: { appointmentId: appt.id, reminderType: reminder.reminderType },
                    appointmentId: appt.id,
                    scheduledFor: reminderTime,
                    reminderType: reminder.reminderType,
                    deliveryChannel,
                    pushStatus,
                    isDelivered,
                    isVisible: false,
                }));
            }
        }
        appts.push({
            appointmentId: appt.id,
            doctorName: appt.doctorName,
            appointmentTime: exactTime.toISOString(),
            timeSlot: appt.timeSlot,
            reminders: apptReminders,
        });
    }
    const localScheduleRequired = settings.appointmentReminders.enabled && settings.appointmentReminders.delivery === 'local';
    return {
        success: true,
        localScheduleRequired,
        appointments: appts,
    };
});
exports.sendDoctorDailyReports = (0, scheduler_1.onSchedule)({
    schedule: 'every 5 minutes',
    timeZone: 'Asia/Baghdad',
    retryCount: 0,
}, async () => {
    var _a, _b;
    const now = new Date();
    // Calculate minutes since midnight in Baghdad
    const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: 'Asia/Baghdad',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    }).formatToParts(now);
    const currentHour = parseInt(((_a = parts.find(p => p.type === 'hour')) === null || _a === void 0 ? void 0 : _a.value) || '0', 10);
    const currentMinute = parseInt(((_b = parts.find(p => p.type === 'minute')) === null || _b === void 0 ? void 0 : _b.value) || '0', 10);
    const nowMinutes = currentHour * 60 + currentMinute;
    // Find active doctors
    const doctorsSnap = await db.collection('doctors')
        .where('isActive', '==', true)
        .get();
    if (doctorsSnap.empty) {
        console.log('No active doctors found for daily reports.');
        return;
    }
    const baghdadToday = baghdadStartOfToday(now);
    const tomorrowStart = new Date(baghdadToday.getTime() + 24 * 60 * 60 * 1000);
    const tomorrowEnd = new Date(tomorrowStart.getTime() + 24 * 60 * 60 * 1000);
    const tomorrowParts = availabilityDateParts(tomorrowStart);
    const tomorrowDateKey = `${tomorrowParts.year}-${String(tomorrowParts.month).padStart(2, '0')}-${String(tomorrowParts.day).padStart(2, '0')}`;
    for (const doc of doctorsSnap.docs) {
        const doctorData = doc.data();
        const doctorUserId = doctorData.userId;
        if (!doctorUserId)
            continue;
        try {
            const settings = await getUserNotificationSettings(doctorUserId);
            if (!settings.doctorDailySummary.enabled)
                continue;
            const summaryTime = settings.doctorDailySummary.time || '21:00';
            const [timeHourStr, timeMinuteStr] = summaryTime.split(':');
            const timeHour = parseInt(timeHourStr || '0', 10);
            const timeMinute = parseInt(timeMinuteStr || '0', 10);
            const summaryMinutes = timeHour * 60 + timeMinute;
            const diff = (nowMinutes - summaryMinutes + 1440) % 1440;
            const isTimeMatched = diff >= 0 && diff < 5;
            if (!isTimeMatched)
                continue;
            // Get tomorrow's active appointments fresh from Firestore
            const appointmentsSnap = await db.collection('appointments')
                .where('doctorId', '==', doc.id)
                .where('status', 'in', ['pending', 'confirmed'])
                .where('appointmentDate', '>=', admin.firestore.Timestamp.fromDate(tomorrowStart))
                .where('appointmentDate', '<', admin.firestore.Timestamp.fromDate(tomorrowEnd))
                .get();
            const appointmentCount = appointmentsSnap.size;
            const docId = `doctor_daily_${doctorUserId}_${tomorrowDateKey}`;
            const deliveryChannel = settings.doctorDailySummary.delivery === 'local' ? 'inAppOnly' : 'fcm';
            const isDelivered = (deliveryChannel === 'inAppOnly');
            const pushStatus = isDelivered ? 'skipped_local_device_mode' : 'pending';
            await createTrustedNotification({
                userId: doctorUserId,
                title: "Tomorrow's UHC Schedule",
                body: `You have ${appointmentCount} appointment${appointmentCount === 1 ? '' : 's'} tomorrow. Open UHC for the full report.`,
                type: 'dailySummary',
                data: {
                    appointmentCount,
                    date: tomorrowDateKey,
                },
                deliveryChannel,
                pushStatus,
                isDelivered,
                isVisible: true,
            }, docId);
            console.log(`Daily summary created for doctor ${doctorUserId} with count ${appointmentCount}.`);
        }
        catch (err) {
            console.error(`Failed to process daily report for doctor ${doctorUserId}:`, err);
        }
    }
});
//# sourceMappingURL=index.js.map