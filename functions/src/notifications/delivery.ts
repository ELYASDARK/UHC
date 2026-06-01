import * as functions from 'firebase-functions';

import { admin, db, messaging } from '../firebase';
import { clearUserFcmTokens } from '../shared/auth';
import { errorMessage } from '../shared/errors';
import {
    DEFAULT_DOCTOR_SETTINGS,
    DEFAULT_PATIENT_SETTINGS,
    getUserNotificationSettings,
    NotificationSettingsV2,
    UserDeviceToken,
} from './core';

const MAX_PUSH_DELIVERY_ATTEMPTS = 3;

function scheduledForDate(notification: FirebaseFirestore.DocumentData): Date | null {
    const scheduledFor = notification.scheduledFor;
    if (!scheduledFor) return null;
    if (typeof scheduledFor.toDate === 'function') {
        return scheduledFor.toDate();
    }
    const parsed = new Date(scheduledFor);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function fcmErrorCode(error: unknown): string | null {
    if (!error || typeof error !== 'object' || !('code' in error)) return null;
    const code = (error as { code?: unknown }).code;
    return typeof code === 'string' ? code : null;
}

function isTerminalFcmError(error: unknown): boolean {
    const code = fcmErrorCode(error);
    return code === 'messaging/invalid-registration-token' ||
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-argument' ||
        code === 'messaging/mismatched-credential';
}

function shouldSendPushToToken(
    notification: FirebaseFirestore.DocumentData,
    settings: NotificationSettingsV2,
    token: UserDeviceToken
): boolean {
    if (token.onlinePushEnabled === false) return false;
    if ((notification.deliveryChannel || 'fcm') !== 'fcm') return false;

    if (notification.type === 'appointmentReminder') {
        const reminderType = notification.reminderType;
        const isReminderEnabled = settings.appointmentReminders.enabled && (
            (reminderType === 'oneWeek' && settings.appointmentReminders.oneWeek) ||
            (reminderType === 'oneDay' && settings.appointmentReminders.oneDay) ||
            (reminderType === 'oneHour' && settings.appointmentReminders.oneHour)
        );
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

function isKnownTokenPlatform(value: unknown): value is UserDeviceToken['platform'] {
    return value === 'android' ||
        value === 'ios' ||
        value === 'web' ||
        value === 'macos' ||
        value === 'windows' ||
        value === 'linux' ||
        value === 'unknown';
}

function tokenSupportsLocalByPlatform(platform: UserDeviceToken['platform']): boolean {
    return platform === 'android' || platform === 'ios';
}

function normalizeTokenDelivery(
    value: unknown,
    platform: UserDeviceToken['platform'],
    accountDelivery: 'fcm' | 'local'
): 'fcm' | 'local' {
    if (value === 'fcm' || value === 'local') return value;
    if (platform === 'web') return 'fcm';
    if (tokenSupportsLocalByPlatform(platform) && accountDelivery === 'local') {
        return 'local';
    }
    return 'fcm';
}

function normalizeUserDeviceToken(
    data: FirebaseFirestore.DocumentData,
    settings: NotificationSettingsV2,
    fallbackTokenHash: string
): UserDeviceToken | null {
    if (!data || typeof data.token !== 'string' || data.token.length === 0) {
        return null;
    }

    const rawPlatform = data.platform;
    const platform = isKnownTokenPlatform(rawPlatform) ? rawPlatform : 'unknown';
    const supportsLocalReminders = typeof data.supportsLocalReminders === 'boolean'
        ? data.supportsLocalReminders
        : tokenSupportsLocalByPlatform(platform);

    return {
        token: data.token,
        tokenHash: typeof data.tokenHash === 'string' && data.tokenHash.length > 0
            ? data.tokenHash
            : fallbackTokenHash,
        platform,
        supportsLocalReminders,
        onlinePushEnabled: data.onlinePushEnabled !== undefined ? !!data.onlinePushEnabled : true,
        appointmentReminderDelivery: normalizeTokenDelivery(
            data.appointmentReminderDelivery,
            platform,
            settings.appointmentReminders.delivery
        ),
        doctorDailySummaryDelivery: normalizeTokenDelivery(
            data.doctorDailySummaryDelivery,
            platform,
            settings.doctorDailySummary.delivery
        ),
        timeZone: typeof data.timeZone === 'string' ? data.timeZone : null,
        appVersion: typeof data.appVersion === 'string' ? data.appVersion : null,
        deviceId: typeof data.deviceId === 'string' ? data.deviceId : null,
        createdAt: data.createdAt || admin.firestore.Timestamp.now(),
        updatedAt: data.updatedAt || admin.firestore.Timestamp.now(),
        lastSeenAt: data.lastSeenAt || admin.firestore.Timestamp.now(),
    };
}



export async function deliverNotificationPush(
    snap: FirebaseFirestore.DocumentSnapshot,
    notificationId: string
): Promise<void> {
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

    const userId: string = notification.userId;
    if (!userId) {
        console.log(`Notification ${notificationId} has no userId, skipping push.`);
        return;
    }

    let settings: NotificationSettingsV2;
    try {
        settings = await getUserNotificationSettings(userId);
    } catch (err) {
        console.error(`Error loading settings for user ${userId}, using defaults:`, err);
        const userDoc = await db.collection('users').doc(userId).get();
        const role = userDoc.exists ? (userDoc.data()?.role || 'student') : 'student';
        settings = role === 'doctor' ? DEFAULT_DOCTOR_SETTINGS : DEFAULT_PATIENT_SETTINGS;
    }

    try {
        const tokensList: UserDeviceToken[] = [];
        const subcollectionSnap = await db.collection('user_tokens')
            .doc(userId)
            .collection('tokens')
            .get();

        if (!subcollectionSnap.empty) {
            subcollectionSnap.docs.forEach((doc) => {
                const token = normalizeUserDeviceToken(doc.data(), settings, doc.id);
                if (token) {
                    tokensList.push(token);
                }
            });
        } else {
            const legacyDoc = await db.collection('user_tokens').doc(userId).get();
            const legacyData = legacyDoc.data();
            if (legacyDoc.exists && legacyData?.token) {
                const token = normalizeUserDeviceToken({
                    ...legacyData,
                    tokenHash: 'legacy',
                    platform: legacyData.platform || 'android',
                }, settings, 'legacy');
                if (token) {
                    tokensList.push(token);
                }
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

        const multicastMessage: admin.messaging.MulticastMessage = {
            tokens: eligibleTokens.map(t => t.token),
            notification: {
                title: notification.title || 'UHC Notification',
                body: notification.body || '',
            },
            data: {
                notificationId,
                type: notification.type || 'systemUpdate',
                ...(notification.appointmentId && { appointmentId: notification.appointmentId }),
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

        const response = await messaging.sendEachForMulticast(multicastMessage);

        let successCount = 0;
        let failureCount = 0;

        for (let idx = 0; idx < response.responses.length; idx++) {
            const res = response.responses[idx];
            const tokenObj = eligibleTokens[idx];
            if (res.success) {
                successCount++;
            } else {
                failureCount++;
                const error = res.error;
                console.error(`FCM send failed for token ${tokenObj.token.slice(0, 10)}...:`, error);

                if (error && isTerminalFcmError(error)) {
                    console.log(`Removing stale FCM token for user ${userId}: ${tokenObj.tokenHash}`);
                    if (tokenObj.tokenHash === 'legacy') {
                        await db.collection('user_tokens').doc(userId).delete().catch(() => {});
                    } else {
                        await db.collection('user_tokens')
                            .doc(userId)
                            .collection('tokens')
                            .doc(tokenObj.tokenHash)
                            .delete()
                            .catch(() => {});
                    }
                }
            }
        }

        const attempts = Number(notification.deliveryAttempts || 0) + 1;
        const allFailedRetryable = successCount === 0 && failureCount > 0 && response.responses.every(r => r.error && !isTerminalFcmError(r.error));

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
                            (response.responses.some(r => r.error && isTerminalFcmError(r.error)) ? 'failed_terminal' : 'failed_retry_exhausted'));

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
    } catch (error: unknown) {
        console.error(`Error sending FCM for notification ${notificationId}:`, error);

        const code = fcmErrorCode(error);
        const attempts = Number(notification.deliveryAttempts || 0) + 1;
        const terminal = isTerminalFcmError(error);

        if (
            code === 'messaging/invalid-registration-token' ||
            code === 'messaging/registration-token-not-registered'
        ) {
            console.log(`Removing stale FCM token for user ${userId}`);
            await clearUserFcmTokens(userId);
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
