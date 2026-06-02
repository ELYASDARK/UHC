import * as functions from 'firebase-functions';
import { randomUUID } from 'crypto';

import { admin, db } from './firebase';
import {
    ACTIVE_APPOINTMENT_STATUSES,
    APPOINTMENT_STATUSES,
    APPOINTMENT_TYPES,
    appointmentSlotLockRef,
    appointmentExactTime,
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

interface AppointmentMutationData {
    appointmentId: string;
}

interface CreateAppointmentData {
    bookingReference?: string;
    patientId: string;
    doctorId?: string;
    doctorName?: string;
    department: string;
    appointmentDate: string;
    timeSlot: string;
    type?: string;
    notes?: string | null;
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

function assertConfirmWindow(appointmentData: FirebaseFirestore.DocumentData): void {
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
}

export const createAppointment = functions.https.onCall(
    async (request: functions.https.CallableRequest<CreateAppointmentData>) => {
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        const callerData = callerDoc.data()!;
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
        assertFutureAppointmentTime(appointmentDate, data.timeSlot);
        const now = admin.firestore.Timestamp.now();

        let doctorUserId: string | undefined;
        const ref = db.collection('appointments').doc();
        const bookingReference = (data.bookingReference || ref.id.substring(0, 8)).toUpperCase();
        const qrCode = `UHC_APPOINTMENT:${ref.id}:${randomUUID()}`;
        let trustedDoctorName = 'Any Available';
        let trustedDepartment = data.department;

        await db.runTransaction(async (transaction) => {
            if (data.doctorId) {
                const doctorRef = db.collection('doctors').doc(data.doctorId);
                const doctorDoc = await transaction.get(doctorRef);
                const doctorData = doctorDoc.data();
                if (!doctorDoc.exists || doctorData?.isActive !== true || doctorData?.isAvailable !== true) {
                    throw new functions.https.HttpsError('failed-precondition', 'Selected doctor is unavailable.');
                }

                doctorUserId = doctorData.userId as string | undefined;
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
            } else if (type !== 'emergency') {
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

        return { success: true, appointmentId: ref.id, bookingReference, qrCode };
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

            const currentDate = firestoreDateToDate(currentAppointment.appointmentDate);
            let currentSlotRef: FirebaseFirestore.DocumentReference | null = null;
            let currentSlotSnap: FirebaseFirestore.DocumentSnapshot | null = null;
            if (currentAppointment.doctorId && currentDate && currentAppointment.timeSlot) {
                currentSlotRef = appointmentSlotLockRef(
                    currentAppointment.doctorId,
                    currentDate,
                    currentAppointment.timeSlot
                );
                currentSlotSnap = await transaction.get(currentSlotRef);
            }

            let newSlotRef: FirebaseFirestore.DocumentReference | null = null;
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

            if (currentSlotRef) {
                if (!newSlotRef || currentSlotRef.path !== newSlotRef.path) {
                    if (currentSlotSnap?.data()?.appointmentId === appointmentId) {
                        transaction.delete(currentSlotRef);
                    }
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
                updatedAt: admin.firestore.Timestamp.now(),
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
        const snap = await ref.get();
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
        assertConfirmWindow(appointment);

        await ref.update({
            status: 'confirmed',
            isCheckedIn: true,
            checkedInAt: admin.firestore.Timestamp.now(),
            statusUpdatedBy: callerUid,
            updatedAt: admin.firestore.Timestamp.now(),
        });
        await createAppointmentStatusNotification({
            appointmentId,
            appointment: { ...appointment, status: 'confirmed' },
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
            medicalNotesUpdatedAt: admin.firestore.Timestamp.now(),
            updatedAt: admin.firestore.Timestamp.now(),
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
            qrScanFailures: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.Timestamp.now(),
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
