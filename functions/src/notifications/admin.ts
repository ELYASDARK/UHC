import * as functions from 'firebase-functions';
import { randomUUID } from 'crypto';

import { admin, db } from '../firebase';
import { getCallerUserDoc, requireAuth, requirePermission } from '../shared/auth';
import { writeAdminAuditLog } from '../shared/audit';
import { errorMessage, toHttpsError } from '../shared/errors';
import { trustedNotificationPayloadWithId } from './core';

interface TopicNotificationData {
    topic: string;
    title: string;
    body: string;
    data?: Record<string, string>;
}

const ADMIN_NOTIFICATION_TARGET_TYPES = [
    'singlePatient',
    'singleDoctor',
    'allPatients',
    'allDoctors',
    'patientsAndDoctors',
] as const;

type AdminNotificationTargetType = typeof ADMIN_NOTIFICATION_TARGET_TYPES[number];

interface SendAdminNotificationData {
    targetType?: string;
    targetUserId?: string;
    title?: string;
    body?: string;
    requestId?: string;
}

interface AdminNotificationPreviewData {
    targetType?: string;
    targetUserId?: string;
}

interface SearchAdminNotificationRecipientsData {
    targetType?: string;
    query?: string;
    limit?: number;
}

export interface AdminNotificationRecipient {
    uid: string;
    name: string;
    role: 'student' | 'staff' | 'doctor' | 'admin' | 'superAdmin';
    email?: string;
    subtitle?: string;
}

const ADMIN_NOTIFICATION_MAX_RECIPIENTS = 500;
const ADMIN_NOTIFICATION_COOLDOWN_MS = 60 * 1000;
const ADMIN_NOTIFICATION_BATCH_SIZE = 450;
export const ADMIN_NOTIFICATION_SEARCH_SCAN_LIMIT = 2000;

function isAdminNotificationTargetType(value: unknown): value is AdminNotificationTargetType {
    return typeof value === 'string' &&
        (ADMIN_NOTIFICATION_TARGET_TYPES as readonly string[]).includes(value);
}

function adminNotificationTargetLabel(targetType: AdminNotificationTargetType): string {
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

function normalizeSearchText(value: unknown): string {
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

function requireTargetUserId(value: unknown, label: string): string {
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `${label} must be a string.`
        );
    }
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 128 || trimmed.includes('/')) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `${label} is invalid.`
        );
    }
    return trimmed;
}

function sanitizeAdminNotificationRequestId(value: unknown): string {
    if (value === undefined || value === null || value === '') {
        return randomUUID();
    }
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'requestId must be a string.'
        );
    }
    const trimmed = value.trim();
    if (!/^[A-Za-z0-9_-]{8,80}$/.test(trimmed)) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'requestId is invalid.'
        );
    }
    return trimmed;
}

function requireTrimmedText(
    value: unknown,
    field: 'title' | 'body',
    maxLength: number
): string {
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `${field} must be a string.`
        );
    }

    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > maxLength) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `${field} must be between 1 and ${maxLength} characters.`
        );
    }
    return trimmed;
}

function recipientFromUserDoc(
    doc: FirebaseFirestore.DocumentSnapshot
): AdminNotificationRecipient | null {
    const data = doc.data();
    if (!data || data.isActive !== true) return null;
    const role = data.role;
    if (role !== 'student' && role !== 'staff' && role !== 'doctor') return null;
    return {
        uid: doc.id,
        name: (data.fullName as string | undefined) || (data.email as string | undefined) || doc.id,
        role,
        email: data.email as string | undefined,
        subtitle: role === 'student'
            ? (data.studentId as string | undefined)
            : role === 'staff'
                ? (data.staffId as string | undefined)
                : (data.email as string | undefined),
    };
}

function doctorRecipientFromDocs(
    doctorDoc: FirebaseFirestore.QueryDocumentSnapshot,
    userDoc: FirebaseFirestore.DocumentSnapshot | undefined
): AdminNotificationRecipient | null {
    const doctor = doctorDoc.data();
    const user = userDoc?.data();
    const userId = doctor.userId as string | undefined;
    if (!userId || doctor.isActive !== true || !user || user.isActive !== true) {
        return null;
    }
    if (user.role !== 'doctor') {
        return null;
    }

    return {
        uid: userId,
        name: (doctor.name as string | undefined) ||
            (user.fullName as string | undefined) ||
            (doctor.email as string | undefined) ||
            (user.email as string | undefined) ||
            userId,
        role: 'doctor',
        email: (doctor.email as string | undefined) || (user.email as string | undefined),
        subtitle: (doctor.specialization as string | undefined) ||
            (doctor.department as string | undefined) ||
            (user.email as string | undefined),
    };
}

async function requireActivePatientRecipient(
    targetUserId: string | undefined
): Promise<AdminNotificationRecipient> {
    const uid = requireTargetUserId(targetUserId, 'targetUserId');

    const doc = await db.collection('users').doc(uid).get();
    const recipient = recipientFromUserDoc(doc);
    if (!recipient || (recipient.role !== 'student' && recipient.role !== 'staff')) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Target user must be an active student or staff patient.'
        );
    }
    return recipient;
}

async function hasActiveDoctorRecord(userId: string): Promise<boolean> {
    const doctorSnap = await db.collection('doctors')
        .where('userId', '==', userId)
        .limit(10)
        .get();
    return doctorSnap.docs.some((doc) => doc.data().isActive === true);
}

async function requireActiveDoctorRecipient(
    targetUserId: string | undefined
): Promise<AdminNotificationRecipient> {
    const uid = requireTargetUserId(targetUserId, 'targetUserId');

    const doc = await db.collection('users').doc(uid).get();
    const recipient = recipientFromUserDoc(doc);
    if (!recipient || recipient.role !== 'doctor') {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Target user must be an active doctor.'
        );
    }

    if (!(await hasActiveDoctorRecord(uid))) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Target doctor record must be active.'
        );
    }
    return recipient;
}

function enforceAdminNotificationCap(count: number): void {
    if (count > ADMIN_NOTIFICATION_MAX_RECIPIENTS) {
        throw new functions.https.HttpsError(
            'resource-exhausted',
            `Admin notifications are capped at ${ADMIN_NOTIFICATION_MAX_RECIPIENTS} recipients in v1.`
        );
    }
}

async function getActivePatientRecipients(): Promise<AdminNotificationRecipient[]> {
    const snap = await db.collection('users')
        .where('isActive', '==', true)
        .limit(ADMIN_NOTIFICATION_SEARCH_SCAN_LIMIT)
        .get();
    const recipients = snap.docs
        .map((doc) => recipientFromUserDoc(doc))
        .filter((recipient): recipient is AdminNotificationRecipient =>
            recipient !== null && (recipient.role === 'student' || recipient.role === 'staff')
        );
    enforceAdminNotificationCap(recipients.length);
    return recipients;
}

async function getActiveDoctorRecipients(): Promise<AdminNotificationRecipient[]> {
    const doctorSnap = await db.collection('doctors')
        .where('isActive', '==', true)
        .limit(ADMIN_NOTIFICATION_MAX_RECIPIENTS + 1)
        .get();
    enforceAdminNotificationCap(doctorSnap.docs.length);

    const userIds = Array.from(new Set(
        doctorSnap.docs
            .map((doc) => doc.data().userId as string | undefined)
            .filter((userId): userId is string => !!userId)
    ));
    enforceAdminNotificationCap(userIds.length);

    if (userIds.length === 0) return [];

    const userDocs = await db.getAll(
        ...userIds.map((userId) => db.collection('users').doc(userId))
    );
    const usersById = new Map(userDocs.map((doc) => [doc.id, doc]));

    const recipients = doctorSnap.docs
        .map((doc) => {
            const userId = doc.data().userId as string | undefined;
            return userId ? doctorRecipientFromDocs(doc, usersById.get(userId)) : null;
        })
        .filter((recipient): recipient is AdminNotificationRecipient =>
            recipient !== null && recipient.role === 'doctor'
        );
    enforceAdminNotificationCap(recipients.length);
    return recipients;
}

async function getAdminNotificationRecipients(
    targetType: AdminNotificationTargetType,
    targetUserId?: string
): Promise<AdminNotificationRecipient[]> {
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
            const byUid = new Map<string, AdminNotificationRecipient>();
            [...patients, ...doctors].forEach((recipient) => byUid.set(recipient.uid, recipient));
            enforceAdminNotificationCap(byUid.size);
            return Array.from(byUid.values());
        }
    }
}

function assertAdminNotificationTarget(data: AdminNotificationPreviewData): AdminNotificationTargetType {
    if (!isAdminNotificationTargetType(data.targetType)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid targetType.');
    }
    if (data.targetType === 'singlePatient' || data.targetType === 'singleDoctor') {
        requireTargetUserId(data.targetUserId, 'targetUserId');
    }
    return data.targetType;
}

function matchesRecipientQuery(
    recipient: AdminNotificationRecipient,
    query: string
): boolean {
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

async function reserveAdminNotificationSend(
    callerUid: string,
    requestId: string
): Promise<string> {
    const sendId = `${callerUid}_${requestId}`;
    const sendRef = db.collection('admin_notification_sends').doc(sendId);
    const rateRef = db.collection('admin_notification_rate_limits').doc(callerUid);

    await db.runTransaction(async (transaction) => {
        const [sendDoc, rateDoc] = await Promise.all([
            transaction.get(sendRef),
            transaction.get(rateRef),
        ]);
        if (sendDoc.exists) {
            const status = sendDoc.data()?.status;
            throw new functions.https.HttpsError(
                'already-exists',
                `This notification request was already ${status || 'submitted'}.`
            );
        }

        const lastSentAt = rateDoc.data()?.lastSentAt as FirebaseFirestore.Timestamp | undefined;
        if (lastSentAt) {
            const elapsedMs = Date.now() - lastSentAt.toDate().getTime();
            if (elapsedMs < ADMIN_NOTIFICATION_COOLDOWN_MS) {
                throw new functions.https.HttpsError(
                    'resource-exhausted',
                    'Please wait before sending another notification.'
                );
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

async function markAdminNotificationSend(
    sendId: string,
    status: 'completed' | 'failed',
    metadata: Record<string, unknown>
): Promise<void> {
    await db.collection('admin_notification_sends').doc(sendId).set({
        status,
        ...metadata,
        updatedAt: admin.firestore.Timestamp.now(),
    }, { merge: true });
}

async function createAdminNotificationDocs(params: {
    sendId: string;
    callerUid: string;
    recipients: AdminNotificationRecipient[];
    targetType: AdminNotificationTargetType;
    title: string;
    body: string;
    notificationIds: string[];
}): Promise<string[]> {
    for (let i = 0; i < params.recipients.length; i += ADMIN_NOTIFICATION_BATCH_SIZE) {
        const batch = db.batch();
        const chunk = params.recipients.slice(i, i + ADMIN_NOTIFICATION_BATCH_SIZE);
        const chunkIds: string[] = [];
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


export const searchAdminNotificationRecipients = functions.https.onCall(
    async (request: functions.https.CallableRequest<SearchAdminNotificationRecipientsData>) => {
        try {
            const callerUid = requireAuth(request);
            const callerDoc = await getCallerUserDoc(callerUid);
            requirePermission(callerDoc, 'notifications.send');

            const data = request.data || {};
            const targetType = data.targetType;
            if (targetType !== 'singlePatient' && targetType !== 'singleDoctor') {
                throw new functions.https.HttpsError(
                    'invalid-argument',
                    'Recipient search is only available for singlePatient and singleDoctor.'
                );
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
        } catch (error) {
            console.error('searchAdminNotificationRecipients failed:', error);
            throw toHttpsError(error, 'Failed to search notification recipients.');
        }
    }
);

/**
 * Preview trusted recipient count before confirmation.
 */
export const previewAdminNotificationRecipients = functions.https.onCall(
    async (request: functions.https.CallableRequest<AdminNotificationPreviewData>) => {
        try {
            const callerUid = requireAuth(request);
            const callerDoc = await getCallerUserDoc(callerUid);
            requirePermission(callerDoc, 'notifications.send');

            const data = request.data || {};
            const targetType = assertAdminNotificationTarget(data);
            const recipients = await getAdminNotificationRecipients(
                targetType,
                data.targetUserId
            );
            return {
                success: true,
                targetLabel: adminNotificationTargetLabel(targetType),
                recipientCount: recipients.length,
            };
        } catch (error) {
            console.error('previewAdminNotificationRecipients failed:', error);
            throw toHttpsError(error, 'Failed to count notification recipients.');
        }
    }
);

/**
 * Callable Cloud Function for admins to send trusted in-app and push notifications.
 */
export const sendAdminNotification = functions.https.onCall(
    async (request: functions.https.CallableRequest<SendAdminNotificationData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'notifications.send');

        const data = request.data;
        const targetType = assertAdminNotificationTarget(data);
        const title = requireTrimmedText(data.title, 'title', 80);
        const body = requireTrimmedText(data.body, 'body', 500);
        const requestId = sanitizeAdminNotificationRequestId(data.requestId);
        const recipients = await getAdminNotificationRecipients(
            targetType,
            data.targetUserId
        );

        if (recipients.length === 0) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'No active recipients matched this target.'
            );
        }
        enforceAdminNotificationCap(recipients.length);

        const callerData = callerDoc.data()!;
        const sendId = await reserveAdminNotificationSend(callerUid, requestId);
        const baseAudit = {
            actorUid: callerUid,
            actorRole: callerData.role as string,
            actorName: callerData.fullName as string | undefined,
            targetUid: data.targetUserId || targetType,
            targetName: adminNotificationTargetLabel(targetType),
        };

        await writeAdminAuditLog({
            ...baseAudit,
            action: 'notifications.send.attempt',
            metadata: {
                sendId,
                targetType,
                recipientCount: recipients.length,
                titlePreview: title.slice(0, 80),
                bodyLength: body.length,
            },
        });

        let notificationIds: string[] = [];
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
        } catch (error) {
            await markAdminNotificationSend(sendId, 'failed', {
                targetType,
                recipientCount: recipients.length,
                createdCount: notificationIds.length,
                errorMessage: errorMessage(error).slice(0, 240),
            }).catch(() => { });
            await writeAdminAuditLog({
                ...baseAudit,
                action: 'notifications.send.failed',
                metadata: {
                    sendId,
                    targetType,
                    recipientCount: recipients.length,
                    createdCount: notificationIds.length,
                    errorMessage: errorMessage(error).slice(0, 240),
                },
            }).catch(() => { });
            throw toHttpsError(error, 'Failed to create notification records.');
        }

        await markAdminNotificationSend(sendId, 'completed', {
            targetType,
            recipientCount: recipients.length,
            createdCount: notificationIds.length,
        });

        await writeAdminAuditLog({
            ...baseAudit,
            action: 'notifications.send',
            metadata: {
                sendId,
                targetType,
                recipientCount: recipients.length,
                createdCount: notificationIds.length,
                titlePreview: title.slice(0, 80),
                bodyLength: body.length,
            },
        });

        return {
            success: true,
            targetLabel: adminNotificationTargetLabel(targetType),
            recipientCount: recipients.length,
            notificationIds,
            message: 'Notification queued for delivery.',
        };
    }
);

/**
 * Callable Cloud Function for admins to send notifications to FCM topics
 * (e.g. "announcements", "department_cardiology").
 */
export const sendTopicNotification = functions.https.onCall(
    async (request: functions.https.CallableRequest<TopicNotificationData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'notifications.send');

        await writeAdminAuditLog({
            actorUid: callerUid,
            actorRole: callerDoc.data()!.role as string,
            actorName: callerDoc.data()!.fullName as string | undefined,
            targetUid: 'topic',
            targetName: 'Legacy topic notification',
            action: 'notifications.topicSend.blocked',
            metadata: {
                reason: 'deprecated_unaudited_topic_send',
            },
        }).catch(() => { });

        throw new functions.https.HttpsError(
            'failed-precondition',
            'Topic notifications are disabled. Use sendAdminNotification so notifications are audited and visible in-app.'
        );
    }
);
