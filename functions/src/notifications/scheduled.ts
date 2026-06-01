import * as functions from 'firebase-functions';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { admin, db } from '../firebase';
import {
    appointmentExactTime,
    availabilityDateParts,
    baghdadStartOfToday,
    firestoreDateToDate,
    formatDateForNotification,
    isAdminWithAppointmentAccess,
} from '../shared/appointmentHelpers';
import { getCallerUserDoc, requireAuth } from '../shared/auth';
import {
    createTrustedNotification,
    getUserNotificationSettings,
    trustedNotificationPayload,
} from './core';
import { deliverNotificationPush } from './delivery';

export const deliverScheduledNotifications = onSchedule(
    {
        schedule: 'every 5 minutes',
        timeZone: 'Asia/Baghdad',
        retryCount: 0,
    },
    async () => {
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
            await Promise.all(
                fcmSnap.docs.map((doc) => deliverNotificationPush(doc, doc.id))
            );
        }

        const legacyScheduledSnap = await db.collection('notifications')
            .where('isDelivered', '==', false)
            .where('scheduledFor', '<=', now)
            .orderBy('scheduledFor', 'asc')
            .limit(100)
            .get();

        const legacyScheduledDocs = legacyScheduledSnap.docs.filter((doc) => {
            const data = doc.data();
            return data.deliveryChannel === undefined;
        });

        if (legacyScheduledDocs.length > 0) {
            console.log(`Delivering ${legacyScheduledDocs.length} legacy scheduled notification(s).`);
            await Promise.all(
                legacyScheduledDocs.map((doc) => deliverNotificationPush(doc, doc.id))
            );
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
    }
);

export const resyncUserNotificationSchedules = functions.https.onCall(
    async (request: functions.https.CallableRequest<{ userId?: string }>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const callerData = callerDoc.data()!;

        let targetUid = callerUid;
        if (request.data && request.data.userId) {
            const requestedUid = request.data.userId;
            if (requestedUid !== callerUid) {
                if (!isAdminWithAppointmentAccess(callerData)) {
                    throw new functions.https.HttpsError(
                        'permission-denied',
                        'You do not have permission to resync schedules for other users.'
                    );
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
        const appts: any[] = [];
        for (const doc of appointmentsSnap.docs) {
            const appt = doc.data();
            const date = firestoreDateToDate(appt.appointmentDate);
            if (!date) continue;
            const exactTime = appointmentExactTime(date, appt.timeSlot);
            const formattedDate = formatDateForNotification(exactTime);

            const reminders = [
                { reminderType: 'oneWeek', scheduledFor: new Date(exactTime.getTime() - 7 * 24 * 60 * 60 * 1000), title: 'Appointment in 1 Week' },
                { reminderType: 'oneDay', scheduledFor: new Date(exactTime.getTime() - 24 * 60 * 60 * 1000), title: 'Appointment Tomorrow' },
                { reminderType: 'oneHour', scheduledFor: new Date(exactTime.getTime() - 60 * 60 * 1000), title: 'Appointment in 1 Hour' },
            ];

            const apptReminders: Record<string, string | null> = {
                oneWeek: null,
                oneDay: null,
                oneHour: null,
            };

            if (settings.appointmentReminders.enabled) {
                for (const reminder of reminders) {
                    const isSwitchOn =
                        (reminder.reminderType === 'oneWeek' && settings.appointmentReminders.oneWeek) ||
                        (reminder.reminderType === 'oneDay' && settings.appointmentReminders.oneDay) ||
                        (reminder.reminderType === 'oneHour' && settings.appointmentReminders.oneHour);

                    if (!isSwitchOn) continue;

                    const reminderTime = reminder.scheduledFor;
                    const isFuture = reminderTime.getTime() > Date.now();
                    if (!isFuture) continue;

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
                        deliveryChannel: 'fcm',
                        pushStatus: 'pending',
                        isDelivered: false,
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
    }
);

export const sendDoctorDailyReports = onSchedule(
    {
        schedule: 'every 5 minutes',
        timeZone: 'Asia/Baghdad',
        retryCount: 0,
    },
    async () => {
        const now = new Date();

        // Calculate minutes since midnight in Baghdad
        const parts = new Intl.DateTimeFormat('en-US', {
            timeZone: 'Asia/Baghdad',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
        }).formatToParts(now);
        const currentHour = parseInt(parts.find(p => p.type === 'hour')?.value || '0', 10);
        const currentMinute = parseInt(parts.find(p => p.type === 'minute')?.value || '0', 10);
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
            if (!doctorUserId) continue;

            try {
                const settings = await getUserNotificationSettings(doctorUserId);
                if (!settings.doctorDailySummary.enabled) continue;

                const summaryTime = settings.doctorDailySummary.time || '21:00';
                const [timeHourStr, timeMinuteStr] = summaryTime.split(':');
                const timeHour = parseInt(timeHourStr || '0', 10);
                const timeMinute = parseInt(timeMinuteStr || '0', 10);
                const summaryMinutes = timeHour * 60 + timeMinute;

                const diff = (nowMinutes - summaryMinutes + 1440) % 1440;
                const isTimeMatched = diff >= 0 && diff < 5;
                if (!isTimeMatched) continue;

                // Get tomorrow's active appointments fresh from Firestore
                const appointmentsSnap = await db.collection('appointments')
                    .where('doctorId', '==', doc.id)
                    .where('status', 'in', ['pending', 'confirmed'])
                    .where('appointmentDate', '>=', admin.firestore.Timestamp.fromDate(tomorrowStart))
                    .where('appointmentDate', '<', admin.firestore.Timestamp.fromDate(tomorrowEnd))
                    .get();

                const appointmentCount = appointmentsSnap.size;
                const docId = `doctor_daily_${doctorUserId}_${tomorrowDateKey}`;
                const existingSummary = await db.collection('notifications').doc(docId).get();
                if (existingSummary.exists) {
                    console.log(`Daily summary already exists for doctor ${doctorUserId} on ${tomorrowDateKey}, skipping.`);
                    continue;
                }

                await createTrustedNotification({
                    userId: doctorUserId,
                    title: "Tomorrow's UHC Schedule",
                    body: `You have ${appointmentCount} appointment${appointmentCount === 1 ? '' : 's'} tomorrow. Open UHC for the full report.`,
                    type: 'dailySummary',
                    data: {
                        appointmentCount,
                        date: tomorrowDateKey,
                    },
                    deliveryChannel: 'fcm',
                    pushStatus: 'pending',
                    isDelivered: false,
                    isVisible: true,
                }, docId);

                console.log(`Daily summary created for doctor ${doctorUserId} with count ${appointmentCount}.`);
            } catch (err) {
                console.error(`Failed to process daily report for doctor ${doctorUserId}:`, err);
            }
        }
    }
);
