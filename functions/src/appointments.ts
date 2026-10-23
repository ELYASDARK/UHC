import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import * as functions from 'firebase-functions';
import { randomUUID } from 'crypto';

import { db } from './firebase';
import {
    ACTIVE_APPOINTMENT_STATUSES,
    APPOINTMENT_STATUSES,
    appointmentDateKey,
    appointmentExactTime,
    appointmentExactUtcTime,
    canMutateAppointment,
    firestoreDateToDate,
    formatDateForNotification,
    lockAppointmentSlot,
    parseAppointmentDate,
    releaseAppointmentSlot,
} from './shared/appointmentHelpers';
import { getCallerUserDoc, requireAuth } from './shared/auth';
import {
    createAppointmentNotifications,
    createAppointmentStatusNotification,
    createTrustedNotification,
    deleteAppointmentNotifications,
} from './notifications/core';

import { CreateAppointmentData, consumeAssistantOffer, isUnscheduledEmergencyRequest, prepareBookingRequest, resolveBookingRequest } from './appointments/bookingRequest';
import { readBookingDoctor, readDoctorSlotReservation, writeDoctorSlotReservation } from './appointments/slotReservation';
export { CreateAppointmentData } from './appointments/bookingRequest';
export { getDoctorDayAvailability, GetDoctorDayAvailabilityData, GetDoctorDayAvailabilityResult, AvailableSlotInfo } from './appointments/doctorDayAvailability';

interface AppointmentMutationData {
    appointmentId: string;
}

export interface CreateAppointmentResult {
    success: true;
    appointmentId: string;
    bookingReference: string;
    qrCode: string;
    isExisting?: boolean;
}

interface RescheduleAppointmentData extends AppointmentMutationData {
    appointmentDate: string;
    timeSlot: string;
    reason?: string | null;
}

interface CancelAppointmentData extends AppointmentMutationData {
    reason?: string | null;
    statusUpdatedBy?: string | null;
}

interface UpdateAppointmentStatusData extends AppointmentMutationData {
    status: string;
    statusUpdatedBy?: string | null;
}

interface UpdateMedicalNotesData extends AppointmentMutationData {
    notes: string;
}

interface ConfirmAppointmentCheckInData extends AppointmentMutationData {
    qrCode: string;
}

function assertFutureAppointmentTime(appointmentDate: Date, timeSlot: string): void {
    const exactTime = appointmentExactTime(appointmentDate, timeSlot);
    if (exactTime.getTime() <= Date.now()) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Appointment time must be in the future.'
        );
    }
}

function validateCheckInWindow(appointmentData: FirebaseFirestore.DocumentData): Date {
    const appointmentDate = firestoreDateToDate(appointmentData.appointmentDate);
    if (!appointmentDate || typeof appointmentData.timeSlot !== 'string') {
        throw new functions.https.HttpsError('failed-precondition', 'Appointment time is unavailable.');
    }
    const exactTime = appointmentExactTime(appointmentDate, appointmentData.timeSlot);
    const now = Date.now();
    const windowStart = exactTime.getTime() - 5 * 60 * 1000;
    const windowEnd = exactTime.getTime() + 10 * 60 * 1000;
    if (now < windowStart || now > windowEnd) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Appointment can only be confirmed during the QR check-in window.'
        );
    }
    return appointmentDate;
}

async function handlePostBookingNotifications(params: {
    appointmentId: string;
    bookingReference: string;
    patientId: string;
    doctorName: string;
    appointmentDate: Date | null;
    timeSlot: string;
    isExisting?: boolean;
}): Promise<void> {
    if (params.isExisting || !params.appointmentDate) {
        return;
    }

    try {
        await createAppointmentNotifications({
            userId: params.patientId,
            appointmentId: params.appointmentId,
            doctorName: params.doctorName,
            appointmentDate: params.appointmentDate,
            timeSlot: params.timeSlot,
        });
    } catch (notifErr: unknown) {
        const errMessage = notifErr instanceof Error ? notifErr.message : String(notifErr);
        // Safe logging: never log patient identifiers
        console.error(JSON.stringify({
            event: 'post_commit_notification_failed',
            appointmentId: params.appointmentId,
            bookingReference: params.bookingReference,
            error: errMessage,
        }));

        try {
            await db.collection('appointments').doc(params.appointmentId).update({
                notificationDeliveryError: true,
                notificationDeliveryErrorAt: Timestamp.now(),
            });
        } catch {
            // Non-blocking
        }
    }
}

export async function createAppointmentCore(
    callerUid: string,
    callerData: FirebaseFirestore.DocumentData,
    data: CreateAppointmentData
): Promise<CreateAppointmentResult> {
    const booking = prepareBookingRequest(callerUid, data);
    const { idempotencyDocId, payloadHash } = booking;
    const now = Timestamp.now();

    const ref = db.collection('appointments').doc();
    const bookingReference = (data.bookingReference || ref.id.substring(0, 8)).toUpperCase();
    const qrCode = `UHC_APPOINTMENT:${ref.id}:${randomUUID()}`;

    const txResult = await db.runTransaction(async (transaction) => {
        // Lost-response retries must resolve before reading a consumed offer or checking current availability.
        if (idempotencyDocId) {
            const idempotencyRef = db.collection('appointment_idempotency').doc(idempotencyDocId);
            const idempotencySnap = await transaction.get(idempotencyRef);
            if (idempotencySnap.exists) {
                const existing = idempotencySnap.data()!;
                if (booking.kind === 'direct' && existing.payloadHash && existing.payloadHash !== payloadHash) {
                    throw new functions.https.HttpsError(
                        'already-exists',
                        'Idempotency key has already been used with a different request payload.'
                    );
                }
                return {
                    isExisting: true,
                    appointmentId: existing.appointmentId as string,
                    bookingReference: existing.bookingReference as string,
                    qrCode: existing.qrCode as string,
                    appointmentDate: null as Date | null,
                    trustedDoctorName: '',
                    timeSlot: '',
                };
            }
        }

        const resolved = await resolveBookingRequest(transaction, db, { booking, patientId: callerUid, now: now.toDate() });
        const isEmergencyRequest = isUnscheduledEmergencyRequest(resolved);
        const emergencyDoctor = isEmergencyRequest && resolved.doctorId
            ? await readBookingDoctor(transaction, {
                firestore: db, doctorId: resolved.doctorId, fallbackDoctorName: resolved.doctorName,
            }) : null;
        // Emergency requests have no scheduled slot to reserve, even with a preferred doctor.
        const reservation = !isEmergencyRequest && resolved.doctorId ? await readDoctorSlotReservation(transaction, {
            firestore: db,
            doctorId: resolved.doctorId,
            appointmentId: ref.id,
            appointmentDate: resolved.appointmentDate,
            timeSlot: resolved.timeSlot,
            fallbackDoctorName: resolved.doctorName,
        }) : null;
        if (!reservation && !isEmergencyRequest) {
            throw new functions.https.HttpsError('invalid-argument', 'doctorId is required for scheduled appointments.');
        }
        const bookingDoctor = reservation || emergencyDoctor;
        const resolvedDoctorId = resolved.doctorId;
        const resolvedDoctorName = bookingDoctor?.doctorName || resolved.doctorName;
        const resolvedDepartment = bookingDoctor?.department || resolved.department;
        const resolvedDate = resolved.appointmentDate;
        const finalCanonicalSlot = reservation?.slot.canonicalSlot || resolved.timeSlot;
        const doctorUserId = bookingDoctor?.doctorUserId;

        // Offer, receipt, access and booking writes share the transaction with the slot reservation.
        if (reservation) writeDoctorSlotReservation(transaction, reservation, { appointmentId: ref.id, status: 'pending', now });

        transaction.set(ref, {
            id: ref.id,
            bookingReference,
            patientId: callerUid,
            patientName: callerData.fullName || '',
            patientEmail: callerData.email || '',
            doctorId: resolvedDoctorId || '',
            doctorName: resolvedDoctorName,
            department: resolvedDepartment,
            appointmentDate: Timestamp.fromDate(resolvedDate),
            timeSlot: finalCanonicalSlot,
            type: resolved.type,
            status: 'pending',
            notes: resolved.notes,
            medicalNotes: null,
            qrCode,
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

        if (idempotencyDocId) {
            const idempotencyRef = db.collection('appointment_idempotency').doc(idempotencyDocId);
            transaction.set(idempotencyRef, {
                patientId: callerUid,
                idempotencyKey: idempotencyDocId,
                payloadHash,
                appointmentId: ref.id,
                bookingReference,
                qrCode,
                createdAt: now,
            });
        }

        if (doctorUserId && resolvedDoctorId) {
            const accessRef = db.collection('doctor_patient_access').doc(doctorUserId)
                .collection('patients').doc(callerUid);
            transaction.set(accessRef, {
                doctorUserId,
                doctorId: resolvedDoctorId,
                patientId: callerUid,
                appointmentId: ref.id,
                updatedAt: now,
            }, { merge: true });
        }

        if (resolved.offerConsumption) consumeAssistantOffer(transaction, resolved.offerConsumption, now);

        return {
            isExisting: false,
            appointmentId: ref.id,
            bookingReference,
            qrCode,
            appointmentDate: resolvedDate,
            trustedDoctorName: resolvedDoctorName,
            timeSlot: finalCanonicalSlot,
        };
    });

    if (txResult.isExisting) {
        return {
            success: true,
            appointmentId: txResult.appointmentId,
            bookingReference: txResult.bookingReference,
            qrCode: txResult.qrCode,
            isExisting: true,
        };
    }

    await handlePostBookingNotifications({
        appointmentId: txResult.appointmentId,
        bookingReference: txResult.bookingReference,
        patientId: callerUid,
        doctorName: txResult.trustedDoctorName,
        appointmentDate: txResult.appointmentDate,
        timeSlot: txResult.timeSlot,
        isExisting: txResult.isExisting,
    });

    return {
        success: true,
        appointmentId: txResult.appointmentId,
        bookingReference: txResult.bookingReference,
        qrCode: txResult.qrCode,
    };
}

export const createAppointment = functions.https.onCall(
    async (request: functions.https.CallableRequest<CreateAppointmentData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const callerData = callerDoc.data()!;
        return createAppointmentCore(callerUid, callerData, request.data);
    }
);

export const rescheduleAppointment = functions.https.onCall(
    async (request: functions.https.CallableRequest<RescheduleAppointmentData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const { appointmentId, appointmentDate, timeSlot, reason } = request.data;
        if (!appointmentId || !appointmentDate || !timeSlot) {
            throw new functions.https.HttpsError('invalid-argument', 'Missing required reschedule fields.');
        }
        const ref = db.collection('appointments').doc(appointmentId);
        const snap = await ref.get();
        if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        const appointment = snap.data()!;
        if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowPatient: true, allowDoctor: true, allowAdmin: true })) {
            throw new functions.https.HttpsError('permission-denied', 'You cannot reschedule this appointment.');
        }
        if (!ACTIVE_APPOINTMENT_STATUSES.includes(appointment.status)) {
            throw new functions.https.HttpsError('failed-precondition', 'Only active appointments can be rescheduled.');
        }

        const parsedDate = parseAppointmentDate(appointmentDate);
        assertFutureAppointmentTime(parsedDate, timeSlot);

        await db.runTransaction(async (transaction) => {
            const transactionSnap = await transaction.get(ref);
            if (!transactionSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Appointment not found.');
            }
            const currentAppointment = transactionSnap.data()!;
            if (!ACTIVE_APPOINTMENT_STATUSES.includes(currentAppointment.status)) {
                throw new functions.https.HttpsError('failed-precondition', 'Only active appointments can be rescheduled.');
            }

            const currentApptDate = firestoreDateToDate(currentAppointment.appointmentDate);
            if (['student', 'staff'].includes(callerDoc.data()?.role) && currentApptDate && currentAppointment.timeSlot) {
                const currentApptDateKey = appointmentDateKey(currentApptDate);
                const currentExactUtc = appointmentExactUtcTime(currentApptDateKey, currentAppointment.timeSlot);
                const diffMs = currentExactUtc.getTime() - Date.now();
                const minNoticeMs = 24 * 60 * 60 * 1000;
                if (diffMs < minNoticeMs) {
                    throw new functions.https.HttpsError(
                        'failed-precondition',
                        'Appointments cannot be rescheduled within 24 hours of the appointment time.'
                    );
                }
            }

            const doctorId = currentAppointment.doctorId;
            if (!doctorId) {
                throw new functions.https.HttpsError('failed-precondition', 'Appointment has no assigned doctor.');
            }

            const reservation = await readDoctorSlotReservation(transaction, {
                firestore: db,
                doctorId,
                appointmentId,
                appointmentDate: parsedDate,
                timeSlot,
                fallbackDoctorName: currentAppointment.doctorName || 'Doctor',
                previousAppointment: currentAppointment,
            });
            const now = Timestamp.now();
            writeDoctorSlotReservation(transaction, reservation, { appointmentId, status: currentAppointment.status, now });

            transaction.update(ref, {
                appointmentDate: Timestamp.fromDate(parsedDate),
                timeSlot: reservation.slot.canonicalSlot,
                rescheduleReason: reason || null,
                updatedAt: Timestamp.now(),
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
    }
);

export const cancelAppointment = functions.https.onCall(
    async (request: functions.https.CallableRequest<CancelAppointmentData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const { appointmentId, reason, statusUpdatedBy } = request.data;
        if (!appointmentId) throw new functions.https.HttpsError('invalid-argument', 'appointmentId is required.');

        const ref = db.collection('appointments').doc(appointmentId);
        const snap = await ref.get();
        if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        const appointment = snap.data()!;
        if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowPatient: true, allowDoctor: true, allowAdmin: true })) {
            throw new functions.https.HttpsError('permission-denied', 'You cannot cancel this appointment.');
        }

        await db.runTransaction(async (transaction) => {
            const transactionSnap = await transaction.get(ref);
            if (!transactionSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Appointment not found.');
            }
            const currentAppointment = transactionSnap.data()!;
            await releaseAppointmentSlot(transaction, appointmentId, currentAppointment);
            transaction.update(ref, {
                status: 'cancelled',
                cancelReason: reason || null,
                statusUpdatedBy: statusUpdatedBy || callerUid,
                updatedAt: Timestamp.now(),
            });
        });
        await deleteAppointmentNotifications(appointmentId);
        const date = appointment.appointmentDate?.toDate?.() as Date | undefined;
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
    }
);

export const updateAppointmentStatus = functions.https.onCall(
    async (request: functions.https.CallableRequest<UpdateAppointmentStatusData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const { appointmentId, status, statusUpdatedBy } = request.data;
        if (!appointmentId || !APPOINTMENT_STATUSES.includes(status)) {
            throw new functions.https.HttpsError('invalid-argument', 'Missing or invalid appointment status.');
        }
        const ref = db.collection('appointments').doc(appointmentId);
        const snap = await ref.get();
        if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        const appointment = snap.data()!;
        if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowDoctor: true, allowAdmin: true })) {
            throw new functions.https.HttpsError('permission-denied', 'You cannot update this appointment status.');
        }
        if (status === 'confirmed') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Use QR check-in confirmation to confirm appointments.'
            );
        }
        if (status === 'pending' && appointment.status !== 'pending') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Reactivating a non-pending appointment to pending is not supported.'
            );
        }
        if (status === 'completed' && appointment.status !== 'confirmed') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Only confirmed appointments can be completed.'
            );
        }
        if (status === 'noShow' && appointment.status !== 'pending') {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Only pending appointments can be marked no-show.'
            );
        }
        let previousStatus = appointment.status as string | undefined;
        let updatedAppointment: FirebaseFirestore.DocumentData = appointment;
        await db.runTransaction(async (transaction) => {
            const transactionSnap = await transaction.get(ref);
            if (!transactionSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Appointment not found.');
            }
            const currentAppointment = transactionSnap.data()!;
            previousStatus = currentAppointment.status as string | undefined;
            if (status === 'pending' && currentAppointment.status !== 'pending') {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'Reactivating a non-pending appointment to pending is not supported.'
                );
            }
            if (status === 'completed' && currentAppointment.status !== 'confirmed') {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'Only confirmed appointments can be completed.'
                );
            }
            if (status === 'noShow' && currentAppointment.status !== 'pending') {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'Only pending appointments can be marked no-show.'
                );
            }
            updatedAppointment = { ...currentAppointment, status };
            const appointmentDateForLock = firestoreDateToDate(currentAppointment.appointmentDate);
            if (
                ACTIVE_APPOINTMENT_STATUSES.includes(status) &&
                currentAppointment.doctorId &&
                appointmentDateForLock &&
                currentAppointment.timeSlot
            ) {
                await lockAppointmentSlot(transaction, {
                    doctorId: currentAppointment.doctorId,
                    appointmentDate: appointmentDateForLock,
                    timeSlot: currentAppointment.timeSlot,
                    appointmentId,
                    status,
                    excludeAppointmentId: appointmentId,
                });
            } else {
                await releaseAppointmentSlot(transaction, appointmentId, currentAppointment);
            }

            transaction.update(ref, {
                status,
                statusUpdatedBy: statusUpdatedBy || callerUid,
                updatedAt: Timestamp.now(),
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
    }
);

export const confirmAppointmentCheckIn = functions.https.onCall(
    async (request: functions.https.CallableRequest<ConfirmAppointmentCheckInData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const { appointmentId, qrCode } = request.data;
        if (!appointmentId || typeof qrCode !== 'string' || !qrCode.trim()) {
            throw new functions.https.HttpsError('invalid-argument', 'appointmentId and qrCode are required.');
        }

        const ref = db.collection('appointments').doc(appointmentId);
        const confirmedAppointment = await db.runTransaction(async (transaction) => {
            const snap = await transaction.get(ref);
            if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Appointment not found.');
            const appointment = snap.data()!;
            if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowDoctor: true })) {
                throw new functions.https.HttpsError('permission-denied', 'You cannot confirm this appointment.');
            }
            if (appointment.status !== 'pending') {
                throw new functions.https.HttpsError('failed-precondition', 'Only pending appointments can be confirmed.');
            }
            if (appointment.qrCode !== qrCode.trim()) {
                throw new functions.https.HttpsError('permission-denied', 'QR code does not match this appointment.');
            }
            const appointmentDate = validateCheckInWindow(appointment);
            await lockAppointmentSlot(transaction, {
                doctorId: appointment.doctorId,
                appointmentDate,
                timeSlot: appointment.timeSlot,
                appointmentId,
                excludeAppointmentId: appointmentId,
                status: 'confirmed',
            });
            const changes = {
                status: 'confirmed',
                isCheckedIn: true,
                checkedInAt: Timestamp.now(),
                statusUpdatedBy: callerUid,
                updatedAt: Timestamp.now(),
            };
            transaction.update(ref, changes);
            return { ...appointment, ...changes };
        });
        await createAppointmentStatusNotification({
            appointmentId,
            appointment: confirmedAppointment,
            status: 'confirmed',
        });
        return { success: true };
    }
);

export const updateMedicalNotes = functions.https.onCall(
    async (request: functions.https.CallableRequest<UpdateMedicalNotesData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const { appointmentId, notes } = request.data;
        if (!appointmentId || typeof notes !== 'string') {
            throw new functions.https.HttpsError('invalid-argument', 'appointmentId and notes are required.');
        }
        const ref = db.collection('appointments').doc(appointmentId);
        const snap = await ref.get();
        if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        const appointment = snap.data()!;
        if (!await canMutateAppointment(callerUid, callerDoc, appointment, { allowDoctor: true, allowAdmin: true })) {
            throw new functions.https.HttpsError('permission-denied', 'You cannot update medical notes for this appointment.');
        }
        await ref.update({
            medicalNotes: notes,
            medicalNotesUpdatedAt: Timestamp.now(),
            updatedAt: Timestamp.now(),
        });
        return { success: true };
    }
);

export const incrementQrScanFailures = functions.https.onCall(
    async (request: functions.https.CallableRequest<AppointmentMutationData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const { appointmentId } = request.data;
        if (!appointmentId) throw new functions.https.HttpsError('invalid-argument', 'appointmentId is required.');
        const ref = db.collection('appointments').doc(appointmentId);
        const snap = await ref.get();
        if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        if (!await canMutateAppointment(callerUid, callerDoc, snap.data()!, { allowDoctor: true })) {
            throw new functions.https.HttpsError('permission-denied', 'You cannot update QR failures for this appointment.');
        }
        await ref.update({
            qrScanFailures: FieldValue.increment(1),
            updatedAt: Timestamp.now(),
        });
        return { success: true };
    }
);

export const deleteAppointment = functions.https.onCall(
    async (request: functions.https.CallableRequest<AppointmentMutationData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const { appointmentId } = request.data;
        if (!appointmentId) throw new functions.https.HttpsError('invalid-argument', 'appointmentId is required.');
        const ref = db.collection('appointments').doc(appointmentId);
        const snap = await ref.get();
        if (!snap.exists) throw new functions.https.HttpsError('not-found', 'Appointment not found.');
        if (!await canMutateAppointment(callerUid, callerDoc, snap.data()!, { allowAdmin: true })) {
            throw new functions.https.HttpsError('permission-denied', 'Only authorized admins can delete appointments.');
        }
        await db.runTransaction(async (transaction) => {
            const transactionSnap = await transaction.get(ref);
            if (!transactionSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Appointment not found.');
            }
            await releaseAppointmentSlot(transaction, appointmentId, transactionSnap.data()!);
            transaction.delete(ref);
        });
        await deleteAppointmentNotifications(appointmentId);
        return { success: true };
    }
);
