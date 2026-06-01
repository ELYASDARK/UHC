import * as functions from 'firebase-functions';

import { admin, db } from './firebase';
import { writeAdminAuditLog } from './shared/audit';
import {
    ACTIVE_APPOINTMENT_STATUSES,
    appointmentSlotLockRef,
    availabilityDateParts,
    baghdadStartOfToday,
    firestoreDateToDate,
    formatDateForNotification,
    getDoctorForUser,
} from './shared/appointmentHelpers';
import { getCallerUserDoc, requireAuth, requirePermission } from './shared/auth';
import { errorMessage } from './shared/errors';
import { requireTargetUserId } from './shared/validation';
import {
    createTrustedNotification,
    deleteAppointmentNotifications,
    trustedNotificationPayloadWithId,
} from './notifications/core';
import {
    ADMIN_NOTIFICATION_SEARCH_SCAN_LIMIT,
    AdminNotificationRecipient,
} from './notifications/admin';

interface RequestDoctorAvailabilityData {
    reason?: string;
}

interface ReviewDoctorAvailabilityRequestData {
    requestId?: string;
    decision?: string;
}

interface SetDoctorAvailabilityData {
    isAvailable?: boolean;
}

interface SetDoctorAvailabilityByAdminData {
    doctorId?: string;
    isAvailable?: boolean;
}

type DoctorAvailabilityRequestStatus = 'pending' | 'approved' | 'rejected';

interface DoctorAvailabilityReviewContext {
    doctorId: string;
    doctorUserId: string;
    doctorName: string;
    reason: string;
    monthKey: string;
    notificationIds: string[];
}

const DOCTOR_AVAILABILITY_MONTHLY_LIMIT = 2;
const DOCTOR_AVAILABILITY_ADMIN_NOTIFICATION_LIMIT = 450;
const DOCTOR_AVAILABILITY_APPOINTMENT_BATCH_SIZE = 200;

function availabilityMonthKey(date = new Date()): string {
    const parts = availabilityDateParts(date);
    return `${parts.year}-${String(parts.month).padStart(2, '0')}`;
}

function doctorAvailabilityUsageRef(
    doctorId: string,
    monthKey: string
): FirebaseFirestore.DocumentReference {
    return db.collection('doctor_availability_usage').doc(`${doctorId}_${monthKey}`);
}

function sanitizeAvailabilityReason(value: unknown): string {
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Please add a short note for the admin.'
        );
    }
    const trimmed = value.trim();
    if (trimmed.length < 3 || trimmed.length > 280) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'The note must be between 3 and 280 characters.'
        );
    }
    return trimmed;
}

function requireAvailabilityRequestId(value: unknown): string {
    return requireTargetUserId(value, 'requestId');
}

function parseAvailabilityDecision(value: unknown): Exclude<DoctorAvailabilityRequestStatus, 'pending'> {
    if (value === 'approved' || value === 'rejected') return value;
    throw new functions.https.HttpsError(
        'invalid-argument',
        'decision must be approved or rejected.'
    );
}

function clearPendingAvailabilityFields(): Record<string, unknown> {
    return {
        availabilityRequestStatus: admin.firestore.FieldValue.delete(),
        pendingAvailabilityRequestId: admin.firestore.FieldValue.delete(),
        availabilityRequestReason: admin.firestore.FieldValue.delete(),
        availabilityRequestedAt: admin.firestore.FieldValue.delete(),
    };
}

async function getDoctorManagingAdminRecipients(): Promise<AdminNotificationRecipient[]> {
    const snap = await db.collection('users')
        .where('isActive', '==', true)
        .limit(ADMIN_NOTIFICATION_SEARCH_SCAN_LIMIT)
        .get();

    return snap.docs
        .map((doc): AdminNotificationRecipient | null => {
            const data = doc.data();
            const role = data.role as string | undefined;
            const permissions = data.adminPermissions as Record<string, unknown> | undefined;
            const canManageDoctors = role === 'superAdmin' ||
                (role === 'admin' && permissions?.['doctors.manage'] === true);
            if (!canManageDoctors) return null;
            const recipientRole = role === 'superAdmin' ? 'superAdmin' : 'admin';
            return {
                uid: doc.id,
                name: (data.fullName as string | undefined) ||
                    (data.email as string | undefined) ||
                    doc.id,
                role: recipientRole,
                email: data.email as string | undefined,
                subtitle: role === 'superAdmin' ? 'Super Admin' : 'Doctor management',
            };
        })
        .filter((recipient): recipient is AdminNotificationRecipient => recipient !== null);
}

function setDoctorAvailabilityAdminNotifications(
    transaction: FirebaseFirestore.Transaction,
    params: {
        requestId: string;
        recipients: AdminNotificationRecipient[];
        doctorId: string;
        doctorUserId: string;
        doctorName: string;
        specialization?: string;
        reason: string;
        monthKey: string;
    }
): string[] {
    if (params.recipients.length > DOCTOR_AVAILABILITY_ADMIN_NOTIFICATION_LIMIT) {
        throw new functions.https.HttpsError(
            'resource-exhausted',
            'Too many doctor-managing admins to notify.'
        );
    }

    const notificationIds: string[] = [];
    for (const recipient of params.recipients) {
        const notificationId = `doctor_availability_${params.requestId}_${encodeURIComponent(recipient.uid)}`;
        notificationIds.push(notificationId);
        transaction.set(
            db.collection('notifications').doc(notificationId),
            trustedNotificationPayloadWithId(notificationId, {
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
            })
        );
    }
    return notificationIds;
}

async function updateDoctorAvailabilityAdminNotifications(params: {
    notificationIds: string[];
    status: Exclude<DoctorAvailabilityRequestStatus, 'pending'>;
    doctorName: string;
    reviewerUid: string;
    reviewerName?: string;
}): Promise<void> {
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

async function cancelActiveAppointmentsForUnavailableDoctor(params: {
    doctorId: string;
    reviewedByUid: string;
    doctorName: string;
    requestId: string;
}): Promise<{ cancelledCount: number; appointmentIds: string[] }> {
    const start = admin.firestore.Timestamp.fromDate(baghdadStartOfToday());
    const appointmentIds: string[] = [];
    let cancelledCount = 0;

    while (true) {
        const snap = await db.collection('appointments')
            .where('doctorId', '==', params.doctorId)
            .where('status', 'in', ACTIVE_APPOINTMENT_STATUSES)
            .where('appointmentDate', '>=', start)
            .orderBy('appointmentDate', 'asc')
            .limit(DOCTOR_AVAILABILITY_APPOINTMENT_BATCH_SIZE)
            .get();

        if (snap.empty) break;

        const batch = db.batch();
        const notifications: Array<{
            appointmentId: string;
            patientId: string;
            doctorName: string;
            appointmentDate: Date | null;
            timeSlot: string;
        }> = [];

        for (const doc of snap.docs) {
            const appointment = doc.data();
            const appointmentDate = firestoreDateToDate(appointment.appointmentDate);
            const timeSlot = (appointment.timeSlot as string | undefined) || '';
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
                patientId: appointment.patientId as string,
                doctorName: (appointment.doctorName as string | undefined) ||
                    params.doctorName ||
                    'your doctor',
                appointmentDate,
                timeSlot,
            });
            appointmentIds.push(doc.id);
        }

        await batch.commit();

        for (const notification of notifications) {
            if (!notification.patientId) continue;
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
        if (snap.size < DOCTOR_AVAILABILITY_APPOINTMENT_BATCH_SIZE) break;
    }

    return { cancelledCount, appointmentIds };
}

/**
 * Doctor requests admin approval before becoming unavailable.
 */
export const requestDoctorUnavailable = functions.https.onCall(
    async (request: functions.https.CallableRequest<RequestDoctorAvailabilityData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const callerData = callerDoc.data()!;
        if (callerData.role !== 'doctor') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only doctors can request unavailable status.'
            );
        }

        const reason = sanitizeAvailabilityReason(request.data?.reason);
        const doctorDoc = await getDoctorForUser(callerUid);
        if (!doctorDoc) {
            throw new functions.https.HttpsError('not-found', 'Doctor profile not found.');
        }

        const recipients = await getDoctorManagingAdminRecipients();
        if (recipients.length === 0) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'No doctor-managing admin is available to review this request.'
            );
        }

        const requestRef = db.collection('doctor_availability_requests').doc();
        const monthKey = availabilityMonthKey();
        let approvedCount = 0;
        let notificationIds: string[] = [];

        await db.runTransaction(async (transaction) => {
            const [doctorSnap, usageSnap] = await Promise.all([
                transaction.get(doctorDoc.ref),
                transaction.get(doctorAvailabilityUsageRef(doctorDoc.id, monthKey)),
            ]);

            if (!doctorSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Doctor profile not found.');
            }
            const doctorData = doctorSnap.data()!;
            if (doctorData.isActive !== true) {
                throw new functions.https.HttpsError('failed-precondition', 'Doctor account is inactive.');
            }
            if (doctorData.isAvailable === false) {
                throw new functions.https.HttpsError('failed-precondition', 'You are already unavailable.');
            }
            if (doctorData.availabilityRequestStatus === 'pending') {
                throw new functions.https.HttpsError(
                    'already-exists',
                    'You already have an unavailable request waiting for admin review.'
                );
            }

            approvedCount = Number(usageSnap.data()?.approvedCount || 0);
            if (approvedCount >= DOCTOR_AVAILABILITY_MONTHLY_LIMIT) {
                throw new functions.https.HttpsError(
                    'resource-exhausted',
                    `You can become unavailable only ${DOCTOR_AVAILABILITY_MONTHLY_LIMIT} times per month.`
                );
            }

            const now = admin.firestore.Timestamp.now();
            const doctorName = (doctorData.name as string | undefined) ||
                (callerData.fullName as string | undefined) ||
                'Doctor';
            notificationIds = setDoctorAvailabilityAdminNotifications(transaction, {
                requestId: requestRef.id,
                recipients,
                doctorId: doctorDoc.id,
                doctorUserId: callerUid,
                doctorName,
                specialization: doctorData.specialization as string | undefined,
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
    }
);

/**
 * Doctor can return to available immediately. Becoming unavailable requires approval.
 */
export const setDoctorAvailability = functions.https.onCall(
    async (request: functions.https.CallableRequest<SetDoctorAvailabilityData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        if (callerDoc.data()?.role !== 'doctor') {
            throw new functions.https.HttpsError(
                'permission-denied',
                'Only doctors can update their own availability.'
            );
        }
        if (request.data?.isAvailable !== true) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Submit an unavailable request for admin approval.'
            );
        }

        const doctorDoc = await getDoctorForUser(callerUid);
        if (!doctorDoc) {
            throw new functions.https.HttpsError('not-found', 'Doctor profile not found.');
        }
        const doctorData = doctorDoc.data()!;
        if (doctorData.availabilityRequestStatus === 'pending') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Your unavailable request is still waiting for admin review.'
            );
        }

        await doctorDoc.ref.update({
            isAvailable: true,
            ...clearPendingAvailabilityFields(),
            updatedAt: admin.firestore.Timestamp.now(),
        });

        return { success: true, isAvailable: true };
    }
);

/**
 * Admins with doctor management permission can set a doctor's live availability.
 */
export const setDoctorAvailabilityByAdmin = functions.https.onCall(
    async (request: functions.https.CallableRequest<SetDoctorAvailabilityByAdminData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');
        const callerData = callerDoc.data()!;

        const doctorId = requireTargetUserId(request.data?.doctorId, 'doctorId');
        if (typeof request.data?.isAvailable !== 'boolean') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'doctorId and isAvailable are required.'
            );
        }
        const isAvailable = request.data.isAvailable;
        const doctorRef = db.collection('doctors').doc(doctorId);

        const context = await db.runTransaction(async (transaction): Promise<{
            doctorUserId: string;
            doctorName: string;
            pendingRequestId?: string;
            pendingDecision?: Exclude<DoctorAvailabilityRequestStatus, 'pending'>;
            pendingNotificationIds: string[];
            monthKey?: string;
        }> => {
            const doctorSnap = await transaction.get(doctorRef);
            if (!doctorSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Doctor not found.');
            }

            const doctorData = doctorSnap.data()!;
            const doctorUserId = doctorData.userId as string | undefined;
            if (!doctorUserId) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'Doctor is not linked to a login account.'
                );
            }
            const doctorName = (doctorData.name as string | undefined) || 'Doctor';
            const now = admin.firestore.Timestamp.now();
            const pendingRequestId = typeof doctorData.pendingAvailabilityRequestId === 'string'
                ? doctorData.pendingAvailabilityRequestId
                : undefined;
            let pendingDecision: Exclude<DoctorAvailabilityRequestStatus, 'pending'> | undefined;
            let pendingNotificationIds: string[] = [];
            let monthKey: string | undefined;

            if (pendingRequestId) {
                const requestRef = db.collection('doctor_availability_requests').doc(pendingRequestId);
                const requestSnap = await transaction.get(requestRef);
                if (requestSnap.exists && requestSnap.data()?.status === 'pending') {
                    const requestData = requestSnap.data()!;
                    pendingDecision = isAvailable ? 'rejected' : 'approved';
                    monthKey = String(requestData.monthKey || availabilityMonthKey());
                    pendingNotificationIds = Array.isArray(requestData.adminNotificationIds)
                        ? requestData.adminNotificationIds.map((id) => String(id))
                        : [];

                    if (pendingDecision === 'approved') {
                        const usageRef = doctorAvailabilityUsageRef(doctorId, monthKey);
                        const usageSnap = await transaction.get(usageRef);
                        const approvedCount = Number(usageSnap.data()?.approvedCount || 0);
                        if (approvedCount >= DOCTOR_AVAILABILITY_MONTHLY_LIMIT) {
                            throw new functions.https.HttpsError(
                                'resource-exhausted',
                                `This doctor has already used ${DOCTOR_AVAILABILITY_MONTHLY_LIMIT} unavailable approvals this month.`
                            );
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

            const updates: Record<string, unknown> = {
                isAvailable,
                ...clearPendingAvailabilityFields(),
                availabilityUpdatedByAdminAt: now,
                availabilityUpdatedByAdminUid: callerUid,
                updatedAt: now,
            };
            if (!isAvailable) {
                updates.lastUnavailableApprovedAt = now;
                updates.lastAvailabilityRequestId = pendingRequestId || null;
                updates.lastAvailabilityRequestReason = pendingRequestId
                    ? (doctorData.availabilityRequestReason || 'Admin marked unavailable')
                    : 'Admin marked unavailable';
                if (monthKey) updates.availabilityUsageMonth = monthKey;
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
        let cancellationError: string | null = null;
        if (!isAvailable) {
            try {
                const cancellation = await cancelActiveAppointmentsForUnavailableDoctor({
                    doctorId,
                    reviewedByUid: callerUid,
                    doctorName: context.doctorName,
                    requestId: context.pendingRequestId || `admin_manual_${doctorId}_${Date.now()}`,
                });
                cancelledAppointments = cancellation.cancelledCount;
            } catch (error) {
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
                reviewerName: callerData.fullName as string | undefined,
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
            actorRole: callerData.role as string,
            actorName: callerData.fullName as string | undefined,
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
    }
);

/**
 * Admin approval or rejection for doctor unavailable requests.
 */
export const reviewDoctorAvailabilityRequest = functions.https.onCall(
    async (request: functions.https.CallableRequest<ReviewDoctorAvailabilityRequestData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'doctors.manage');
        const callerData = callerDoc.data()!;
        const requestId = requireAvailabilityRequestId(request.data?.requestId);
        const decision = parseAvailabilityDecision(request.data?.decision);
        const requestRef = db.collection('doctor_availability_requests').doc(requestId);

        const reviewContext = await db.runTransaction(async (transaction): Promise<DoctorAvailabilityReviewContext> => {
            const requestSnap = await transaction.get(requestRef);
            if (!requestSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Availability request not found.');
            }

            const requestData = requestSnap.data()!;
            if (requestData.status !== 'pending') {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'This availability request has already been reviewed.'
                );
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
            const doctorData = doctorSnap.data()!;
            if (doctorData.userId !== doctorUserId || doctorData.isActive !== true) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'Doctor profile is no longer active.'
                );
            }

            const approvedCount = usageSnap
                ? Number(usageSnap.data()?.approvedCount || 0)
                : 0;
            if (decision === 'approved' && approvedCount >= DOCTOR_AVAILABILITY_MONTHLY_LIMIT) {
                throw new functions.https.HttpsError(
                    'resource-exhausted',
                    `This doctor has already used ${DOCTOR_AVAILABILITY_MONTHLY_LIMIT} unavailable approvals this month.`
                );
            }

            const now = admin.firestore.Timestamp.now();
            const doctorName = (requestData.doctorName as string | undefined) ||
                (doctorData.name as string | undefined) ||
                'Doctor';
            const reason = String(requestData.reason || '');
            const notificationIds = Array.isArray(requestData.adminNotificationIds)
                ? requestData.adminNotificationIds.map((id) => String(id))
                : [];

            if (decision === 'approved') {
                transaction.update(doctorRef, {
                    isAvailable: false,
                    lastUnavailableApprovedAt: now,
                    lastAvailabilityRequestId: requestId,
                    lastAvailabilityRequestReason: reason,
                    availabilityUsageMonth: monthKey,
                    ...clearPendingAvailabilityFields(),
                    updatedAt: now,
                });
                transaction.set(usageRef, {
                    doctorId,
                    doctorUserId,
                    monthKey,
                    approvedCount: approvedCount + 1,
                    updatedAt: now,
                }, { merge: true });
            } else {
                transaction.update(doctorRef, {
                    ...clearPendingAvailabilityFields(),
                    updatedAt: now,
                });
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
        let cancellationError: string | null = null;
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
            } catch (error) {
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
            reviewerName: callerData.fullName as string | undefined,
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
            actorRole: callerData.role as string,
            actorName: callerData.fullName as string | undefined,
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
    }
);
