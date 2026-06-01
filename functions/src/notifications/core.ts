import { admin, db } from '../firebase';
import {
    appointmentExactTime,
    firestoreDateToDate,
    formatDateForNotification,
} from '../shared/appointmentHelpers';

export interface NotificationSettingsV2 {
    version: number;
    onlinePushEnabled: boolean;
    appointmentStatusAlerts: {
        enabled: boolean;
        locked: boolean;
    };
    adminAnnouncements: {
        enabled: boolean;
    };
    appointmentReminders: {
        enabled: boolean;
        delivery: 'fcm' | 'local';
        oneWeek: boolean;
        oneDay: boolean;
        oneHour: boolean;
    };
    doctorDailySummary: {
        enabled: boolean;
        delivery: 'fcm' | 'local';
        time: string;
    };
    email: boolean;
}

export interface UserDeviceToken {
    token: string;
    tokenHash: string;
    platform: 'android' | 'ios' | 'web' | 'macos' | 'windows' | 'linux' | 'unknown';
    supportsLocalReminders: boolean;
    onlinePushEnabled: boolean;
    appointmentReminderDelivery: 'fcm' | 'local';
    doctorDailySummaryDelivery: 'fcm' | 'local';
    timeZone: string | null;
    appVersion?: string | null;
    deviceId?: string | null;
    createdAt: any;
    updatedAt: any;
    lastSeenAt: any;
}

export const DEFAULT_PATIENT_SETTINGS: NotificationSettingsV2 = {
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

export const DEFAULT_DOCTOR_SETTINGS: NotificationSettingsV2 = {
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

export async function getUserNotificationSettings(uid: string): Promise<NotificationSettingsV2> {
    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) {
        return DEFAULT_PATIENT_SETTINGS;
    }
    const userData = userDoc.data() || {};
    const role = userData.role || 'student';
    const isDoctor = role === 'doctor';
    const defaults = isDoctor ? DEFAULT_DOCTOR_SETTINGS : DEFAULT_PATIENT_SETTINGS;

    const oldSettings = userData.notificationSettings || {};

    const getBoolValue = (keys: string[], defaultVal: boolean): boolean => {
        for (const key of keys) {
            if (oldSettings[key] !== undefined) return !!oldSettings[key];
            if (userData[key] !== undefined) return !!userData[key];
        }
        return defaultVal;
    };

    const getStringValue = (keys: string[], defaultVal: string): string => {
        for (const key of keys) {
            if (oldSettings[key] !== undefined) return String(oldSettings[key]);
            if (userData[key] !== undefined) return String(userData[key]);
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
                enabled: oldSettings.adminAnnouncements?.enabled !== undefined ? !!oldSettings.adminAnnouncements.enabled : defaults.adminAnnouncements.enabled,
            },
            appointmentReminders: {
                enabled: oldSettings.appointmentReminders?.enabled !== undefined ? !!oldSettings.appointmentReminders.enabled : defaults.appointmentReminders.enabled,
                delivery: oldSettings.appointmentReminders?.delivery === 'local' ? 'local' : 'fcm',
                oneWeek: oldSettings.appointmentReminders?.oneWeek !== undefined ? !!oldSettings.appointmentReminders.oneWeek : defaults.appointmentReminders.oneWeek,
                oneDay: oldSettings.appointmentReminders?.oneDay !== undefined ? !!oldSettings.appointmentReminders.oneDay : defaults.appointmentReminders.oneDay,
                oneHour: oldSettings.appointmentReminders?.oneHour !== undefined ? !!oldSettings.appointmentReminders.oneHour : defaults.appointmentReminders.oneHour,
            },
            doctorDailySummary: {
                enabled: oldSettings.doctorDailySummary?.enabled !== undefined ? !!oldSettings.doctorDailySummary.enabled : defaults.doctorDailySummary.enabled,
                delivery: oldSettings.doctorDailySummary?.delivery === 'local' ? 'local' : 'fcm',
                time: oldSettings.doctorDailySummary?.time || defaults.doctorDailySummary.time,
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

    const migratedSettings: NotificationSettingsV2 = {
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

export function trustedNotificationPayload(id: string, params: {
    userId: string;
    title: string;
    body: string;
    type: string;
    data?: Record<string, unknown>;
    appointmentId?: string;
    scheduledFor?: Date | null;
    reminderType?: string | null;
    isDelivered?: boolean;
    deliveryChannel?: 'fcm' | 'inAppOnly';
    pushStatus?: string;
    isVisible?: boolean;
}): Record<string, unknown> {
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

export async function createTrustedNotification(params: {
    userId: string;
    title: string;
    body: string;
    type: string;
    data?: Record<string, unknown>;
    appointmentId?: string;
    scheduledFor?: Date | null;
    reminderType?: string | null;
    isDelivered?: boolean;
    deliveryChannel?: 'fcm' | 'inAppOnly';
    pushStatus?: string;
    isVisible?: boolean;
}, docId?: string): Promise<string> {
    const id = docId || db.collection('notifications').doc().id;
    const ref = db.collection('notifications').doc(id);
    await ref.set(trustedNotificationPayload(id, params));
    return id;
}

export function trustedNotificationPayloadWithId(
    id: string,
    params: {
        userId: string;
        title: string;
        body: string;
        type: string;
        data?: Record<string, unknown>;
        appointmentId?: string;
        scheduledFor?: Date | null;
        reminderType?: string | null;
        isDelivered?: boolean;
        deliveryChannel?: 'fcm' | 'inAppOnly';
        pushStatus?: string;
        isVisible?: boolean;
    }
): Record<string, unknown> {
    return trustedNotificationPayload(id, params);
}

export async function deleteAppointmentNotifications(appointmentId: string): Promise<void> {
    const snap = await db.collection('notifications')
        .where('appointmentId', '==', appointmentId)
        .limit(500)
        .get();
    if (snap.empty) return;
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
}

export async function createAppointmentNotifications(params: {
    userId: string;
    appointmentId: string;
    doctorName: string;
    appointmentDate: Date;
    timeSlot: string;
    includeConfirmation?: boolean;
}): Promise<void> {
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
    for (const reminder of reminders) {
        const isSwitchOn =
            (reminder.reminderType === 'oneWeek' && settings.appointmentReminders.oneWeek) ||
            (reminder.reminderType === 'oneDay' && settings.appointmentReminders.oneDay) ||
            (reminder.reminderType === 'oneHour' && settings.appointmentReminders.oneHour);

        if (!isSwitchOn) continue;
        if (reminder.scheduledFor <= now) continue;

        await createTrustedNotification({
            userId: params.userId,
            title: reminder.title,
            body: `Reminder: Your appointment with Dr. ${params.doctorName} is on ${formattedDate} at ${params.timeSlot}.`,
            type: 'appointmentReminder',
            data: { appointmentId: params.appointmentId, reminderType: reminder.reminderType },
            appointmentId: params.appointmentId,
            scheduledFor: reminder.scheduledFor,
            reminderType: reminder.reminderType,
            deliveryChannel: 'fcm',
            pushStatus: 'pending',
            isDelivered: false,
            isVisible: false,
        }, `appointment_${params.appointmentId}_${reminder.reminderType}`);
    }
}

export async function createAppointmentStatusNotification(params: {
    appointmentId: string;
    appointment: FirebaseFirestore.DocumentData;
    status: string;
}): Promise<void> {
    const patientId = params.appointment.patientId as string | undefined;
    if (!patientId) return;

    const doctorName = params.appointment.doctorName || 'your doctor';
    const appointmentDate = firestoreDateToDate(params.appointment.appointmentDate);
    const timeSlot = params.appointment.timeSlot as string | undefined;
    const when = appointmentDate
        ? `${formatDateForNotification(appointmentDate)}${timeSlot ? ` at ${timeSlot}` : ''}`
        : null;
    const withDoctor = `with Dr. ${doctorName}`;
    const suffix = when ? ` ${withDoctor} on ${when}` : ` ${withDoctor}`;

    const notificationByStatus: Record<string, { title: string; body: string; type: string }> = {
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
    if (!notification) return;

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

