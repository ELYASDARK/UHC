import * as functions from 'firebase-functions';
import { createHash, randomUUID } from 'crypto';

import { admin, db } from './firebase';
import {
    ACTIVE_APPOINTMENT_STATUSES,
    APPOINTMENT_STATUSES,
    APPOINTMENT_TYPES,
    appointmentDateKey,
    appointmentDayCoordinationRef,
    appointmentExactTime,
    appointmentExactUtcTime,
    canMutateAppointment,
    canonicalAppointmentSlotLockRef,
    canonicalSlotStartTime,
    doesAppointmentOverlapSlot,
    firestoreDateToDate,
    formatDateForNotification,
    getDoctorDaySchedule,
    legacyAppointmentSlotLockRef,
    lockAppointmentSlot,
    parseAppointmentDate,
    releaseAppointmentSlot,
    resolveTrustedSlotFromSchedule,
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

export interface CreateAppointmentData {
    bookingReference?: string;
    patientId: string;
    doctorId?: string;
    doctorName?: string;
    department?: string;
    appointmentDate?: string;
    timeSlot?: string;
    type?: string;
    notes?: string | null;
    idempotencyKey?: string;
    offerId?: string;
    confirmed?: boolean;
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
                notificationDeliveryErrorAt: admin.firestore.Timestamp.now(),
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
    if (data.patientId !== callerUid) {
        throw new functions.https.HttpsError('permission-denied', 'You can only create appointments for yourself.');
    }

    const isAssistant = typeof data.offerId === 'string' && data.offerId.trim().length > 0;
    if (isAssistant && data.confirmed !== true) {
        throw new functions.https.HttpsError('invalid-argument', 'confirmed must be explicitly true.');
    }

    const offerId = isAssistant ? data.offerId!.trim() : undefined;
    const now = admin.firestore.Timestamp.now();
    const nowJs = now.toDate();

    let idempotencyDocId: string | undefined;
    let payloadHash: string;

    if (isAssistant) {
        if (typeof offerId !== 'string' || !offerId.trim() || offerId.trim().length > 128) {
            throw new functions.https.HttpsError('invalid-argument', 'offerId must be a non-empty string up to 128 characters.');
        }
        if (data.confirmed !== true) {
            throw new functions.https.HttpsError('invalid-argument', 'confirmed must be explicitly true.');
        }
        if (data.notes !== undefined && data.notes !== null) {
            if (typeof data.notes !== 'string' || data.notes.length > 1000) {
                throw new functions.https.HttpsError('invalid-argument', 'notes must be 1000 characters or fewer.');
            }
        }
        idempotencyDocId = 'asst_confirm_' + createHash('sha256').update(`${callerUid}:${offerId}`).digest('hex');
        payloadHash = createHash('sha256').update(`${callerUid}:${offerId}`).digest('hex');
    } else {
        if (!data.department || !data.appointmentDate || !data.timeSlot) {
            throw new functions.https.HttpsError('invalid-argument', 'Missing required appointment fields.');
        }
        if (typeof data.department !== 'string' || !data.department.trim() || data.department.trim().length > 128) {
            throw new functions.https.HttpsError('invalid-argument', 'department must be 1 to 128 characters.');
        }
        if (typeof data.appointmentDate !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(data.appointmentDate.trim()) || data.appointmentDate.trim().length > 32) {
            throw new functions.https.HttpsError('invalid-argument', 'appointmentDate must be a valid date string.');
        }
        if (typeof data.timeSlot !== 'string' || !data.timeSlot.trim() || data.timeSlot.trim().length > 64) {
            throw new functions.https.HttpsError('invalid-argument', 'timeSlot must be 1 to 64 characters.');
        }
        if (data.doctorId !== undefined && data.doctorId !== null) {
            if (typeof data.doctorId !== 'string' || !data.doctorId.trim() || data.doctorId.trim().length > 128) {
                throw new functions.https.HttpsError('invalid-argument', 'doctorId must be a string up to 128 characters.');
            }
        }
        if (data.bookingReference !== undefined && data.bookingReference !== null) {
            if (typeof data.bookingReference !== 'string' || data.bookingReference.trim().length > 64) {
                throw new functions.https.HttpsError('invalid-argument', 'bookingReference must be 64 characters or fewer.');
            }
        }
        const type = data.type || 'regularCheckup';
        if (!APPOINTMENT_TYPES.includes(type)) {
            throw new functions.https.HttpsError('invalid-argument', 'Invalid appointment type.');
        }
        if (typeof data.notes === 'string' && data.notes.length > 1000) {
            throw new functions.https.HttpsError('invalid-argument', 'notes must be 1000 characters or fewer.');
        }
        if (typeof data.idempotencyKey === 'string' && data.idempotencyKey.trim().length > 128) {
            throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey must be 128 characters or fewer.');
        }

        const normalizedIdempotencyKey = typeof data.idempotencyKey === 'string' && data.idempotencyKey.trim()
            ? data.idempotencyKey.trim()
            : (typeof data.bookingReference === 'string' && data.bookingReference.trim()
                ? `bref_${data.bookingReference.trim().toUpperCase()}`
                : undefined);

        if (normalizedIdempotencyKey) {
            idempotencyDocId = `${callerUid}_${encodeURIComponent(normalizedIdempotencyKey)}`;
        }

        payloadHash = createHash('sha256')
            .update(`${callerUid}:${data.doctorId || ''}:${data.department}:${data.appointmentDate}:${data.timeSlot}:${type}:${data.notes || ''}`)
            .digest('hex');
    }

    const ref = db.collection('appointments').doc();
    const bookingReference = (data.bookingReference || ref.id.substring(0, 8)).toUpperCase();
    const qrCode = `UHC_APPOINTMENT:${ref.id}:${randomUUID()}`;

    const txResult = await db.runTransaction(async (transaction) => {
        // 1. Existing receipt lookup PRECEDES all checks for lost-response retry
        if (idempotencyDocId) {
            const idempotencyRef = db.collection('appointment_idempotency').doc(idempotencyDocId);
            const idempotencySnap = await transaction.get(idempotencyRef);
            if (idempotencySnap.exists) {
                const existing = idempotencySnap.data()!;
                if (!isAssistant && existing.payloadHash && existing.payloadHash !== payloadHash) {
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

        // 2. Resolve booking inputs
        let resolvedDoctorId: string | undefined;
        let resolvedDoctorName = 'Any Available';
        let resolvedDepartment = isAssistant ? '' : data.department!;
        let resolvedDate: Date;
        let resolvedSlotStr: string;
        let resolvedType = isAssistant ? 'regularCheckup' : (data.type || 'regularCheckup');
        let resolvedNotes = typeof data.notes === 'string' ? data.notes.trim() : null;
        let chatRef: FirebaseFirestore.DocumentReference | null = null;
        let remainingOffers: any[] | null = null;
        let chatDoc: FirebaseFirestore.DocumentData | undefined;

        if (isAssistant) {
            chatRef = db.collection('assistant_chats').doc(callerUid);
            const chatSnap = await transaction.get(chatRef);
            if (!chatSnap.exists) {
                throw new functions.https.HttpsError('not-found', 'Appointment offer not found or has been cleared.');
            }
            chatDoc = chatSnap.data();

            const chatExpiresAtMs = chatDoc?.expiresAt?.toMillis ? chatDoc.expiresAt.toMillis() : 0;
            if (chatExpiresAtMs > 0 && chatExpiresAtMs <= nowJs.getTime()) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'Chat session has expired. Please request a new appointment.'
                );
            }

            const offers = (chatDoc?.offers || []) as any[];
            const matchedOffer = offers.find((o: any) => o.offerId === offerId);
            if (!matchedOffer) {
                throw new functions.https.HttpsError('not-found', 'Appointment offer not found or has been cleared.');
            }

            if (matchedOffer.isAvailable === false) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'This appointment offer is no longer available.'
                );
            }

            const expiresAtMs = new Date(matchedOffer.expiresAt).getTime();
            if (Number.isNaN(expiresAtMs) || expiresAtMs <= nowJs.getTime()) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'This appointment offer has expired. Please request a new appointment.'
                );
            }

            const exactUtc = appointmentExactUtcTime(matchedOffer.appointmentDate, matchedOffer.timeSlot);
            if (exactUtc.getTime() <= nowJs.getTime()) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    'This appointment slot is in the past.'
                );
            }

            resolvedDoctorId = matchedOffer.doctorId;
            resolvedDoctorName = matchedOffer.doctorName || 'Doctor';
            resolvedDepartment = matchedOffer.department;
            resolvedDate = parseAppointmentDate(matchedOffer.appointmentDate);
            resolvedSlotStr = matchedOffer.timeSlot;
            remainingOffers = offers.filter((o: any) => o.offerId !== offerId);
        } else {
            resolvedDoctorId = data.doctorId;
            resolvedDate = parseAppointmentDate(data.appointmentDate!);
            assertFutureAppointmentTime(resolvedDate, data.timeSlot!);
            resolvedSlotStr = data.timeSlot!;
        }

        let doctorUserId: string | undefined;
        let finalCanonicalSlot = resolvedSlotStr;
        let trustedSlotStart = canonicalSlotStartTime(resolvedSlotStr);
        let coordinationRef: FirebaseFirestore.DocumentReference | null = null;
        let canonicalSlotRef: FirebaseFirestore.DocumentReference | null = null;

        if (resolvedDoctorId) {
            const doctorRef = db.collection('doctors').doc(resolvedDoctorId);
            const doctorDoc = await transaction.get(doctorRef);
            const doctorData = doctorDoc.data();
            if (!doctorDoc.exists || doctorData?.isActive !== true || doctorData?.isAvailable !== true) {
                throw new functions.https.HttpsError('failed-precondition', 'Selected doctor is unavailable.');
            }

            // Require doctor to have an assigned active department (no fallback to caller department)
            const doctorDeptKey = doctorData.department as string | undefined;
            if (!doctorDeptKey) {
                throw new functions.https.HttpsError('failed-precondition', 'Doctor has no assigned department.');
            }
            const deptQuery = db.collection('departments')
                .where('key', '==', doctorDeptKey)
                .where('isActive', '==', true)
                .limit(1);
            const deptSnap = await transaction.get(deptQuery);
            if (deptSnap.empty) {
                throw new functions.https.HttpsError('failed-precondition', 'Selected doctor department is inactive.');
            }
            resolvedDepartment = doctorDeptKey;

            // Resolve trusted schedule duration and reject forged range ends
            const trustedSlot = resolveTrustedSlotFromSchedule(doctorData, resolvedDate, resolvedSlotStr);
            finalCanonicalSlot = trustedSlot.canonicalSlot;
            trustedSlotStart = trustedSlot.startTime;

            // Day coordination record serializes overlapping appointments with different start times
            coordinationRef = appointmentDayCoordinationRef(resolvedDoctorId, resolvedDate, db);
            await transaction.get(coordinationRef);

            // Check canonical slot lock AND legacy slot lock
            canonicalSlotRef = canonicalAppointmentSlotLockRef(resolvedDoctorId, resolvedDate, finalCanonicalSlot, db);
            const legacySlotRef = legacyAppointmentSlotLockRef(resolvedDoctorId, resolvedDate, finalCanonicalSlot, db);
            const [canonicalSnap, legacySnap] = await Promise.all([
                transaction.get(canonicalSlotRef),
                transaction.get(legacySlotRef),
            ]);

            for (const snap of [canonicalSnap, legacySnap]) {
                if (snap.exists) {
                    const lockStatus = snap.data()?.status as string | undefined;
                    if (ACTIVE_APPOINTMENT_STATUSES.includes(lockStatus || 'pending')) {
                        throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
                    }
                }
            }

            // Check active appointments on that day for schedule overlap
            const dateKey = appointmentDateKey(resolvedDate);
            const [year, month, day] = dateKey.split('-').map(Number);
            const startOfDayUtc = Date.UTC(year, month - 1, day, -3, 0, 0, 0);
            const endOfDayUtc = Date.UTC(year, month - 1, day, 20, 59, 59, 999);
            const startOfDay = admin.firestore.Timestamp.fromMillis(startOfDayUtc);
            const endOfDay = admin.firestore.Timestamp.fromMillis(endOfDayUtc);

            const appointmentsQuery = db.collection('appointments')
                .where('doctorId', '==', resolvedDoctorId)
                .where('appointmentDate', '>=', startOfDay)
                .where('appointmentDate', '<=', endOfDay);
            const appointmentsSnap = await transaction.get(appointmentsQuery);

            for (const apptDoc of appointmentsSnap.docs) {
                const appt = apptDoc.data();
                if (ACTIVE_APPOINTMENT_STATUSES.includes(appt.status) && apptDoc.id !== ref.id) {
                    if (doesAppointmentOverlapSlot(appt, trustedSlot, doctorData, resolvedDate)) {
                        throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
                    }
                }
            }

            doctorUserId = doctorData.userId as string | undefined;
            resolvedDoctorName = typeof doctorData.name === 'string' && doctorData.name.trim()
                ? doctorData.name.trim()
                : resolvedDoctorName;
            resolvedDepartment = typeof doctorData.department === 'string' && doctorData.department.trim()
                ? doctorData.department.trim()
                : resolvedDepartment;
        } else if (resolvedType !== 'emergency') {
            throw new functions.https.HttpsError('invalid-argument', 'doctorId is required for non-emergency appointments.');
        }

        // --- WRITES (All reads precede writes) ---
        if (coordinationRef && resolvedDoctorId) {
            transaction.set(coordinationRef, {
                doctorId: resolvedDoctorId,
                dateKey: appointmentDateKey(resolvedDate),
                updatedAt: now,
            }, { merge: true });
        }

        if (canonicalSlotRef && resolvedDoctorId) {
            transaction.set(canonicalSlotRef, {
                appointmentId: ref.id,
                doctorId: resolvedDoctorId,
                appointmentDateKey: appointmentDateKey(resolvedDate),
                timeSlot: finalCanonicalSlot,
                startTime: trustedSlotStart,
                status: 'pending',
                updatedAt: now,
            });
        }

        transaction.set(ref, {
            id: ref.id,
            bookingReference,
            patientId: callerUid,
            patientName: callerData.fullName || '',
            patientEmail: callerData.email || '',
            doctorId: resolvedDoctorId || '',
            doctorName: resolvedDoctorName,
            department: resolvedDepartment,
            appointmentDate: admin.firestore.Timestamp.fromDate(resolvedDate),
            timeSlot: finalCanonicalSlot,
            type: resolvedType,
            status: 'pending',
            notes: resolvedNotes,
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

        if (chatRef && remainingOffers !== null) {
            const chatMessages = ((chatDoc?.messages as any[]) || []);
            const updatedMessages = chatMessages.map((msg: any) => {
                if (Array.isArray(msg.offerIds)) {
                    return {
                        ...msg,
                        offerIds: msg.offerIds.filter((id: string) => id !== offerId),
                    };
                }
                return msg;
            });
            transaction.update(chatRef, {
                offers: remainingOffers,
                messages: updatedMessages,
                revision: (chatDoc?.revision || 1) + 1,
                updatedAt: now,
            });
        }

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

        let resolvedNewSlot = timeSlot;

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

            const doctorRef = db.collection('doctors').doc(doctorId);
            const doctorDoc = await transaction.get(doctorRef);
            const doctorData = doctorDoc.data();
            if (!doctorDoc.exists || doctorData?.isActive !== true || doctorData?.isAvailable !== true) {
                throw new functions.https.HttpsError('failed-precondition', 'Doctor is unavailable.');
            }

            const doctorDeptKey = doctorData.department as string;
            const deptQuery = db.collection('departments').where('key', '==', doctorDeptKey).where('isActive', '==', true).limit(1);
            const deptSnap = await transaction.get(deptQuery);
            if (deptSnap.empty) {
                throw new functions.https.HttpsError('failed-precondition', 'Doctor department is inactive.');
            }

            const trustedSlot = resolveTrustedSlotFromSchedule(doctorData, parsedDate, timeSlot);
            resolvedNewSlot = trustedSlot.canonicalSlot;

            const coordinationRef = appointmentDayCoordinationRef(doctorId, parsedDate, db);
            await transaction.get(coordinationRef);

            const currentDate = firestoreDateToDate(currentAppointment.appointmentDate);
            let currentSlotRef: FirebaseFirestore.DocumentReference | null = null;
            let currentLegacySlotRef: FirebaseFirestore.DocumentReference | null = null;
            let currentSlotSnap: FirebaseFirestore.DocumentSnapshot | null = null;
            let currentLegacySnap: FirebaseFirestore.DocumentSnapshot | null = null;

            if (currentDate && currentAppointment.timeSlot) {
                currentSlotRef = canonicalAppointmentSlotLockRef(doctorId, currentDate, currentAppointment.timeSlot, db);
                currentLegacySlotRef = legacyAppointmentSlotLockRef(doctorId, currentDate, currentAppointment.timeSlot, db);
                [currentSlotSnap, currentLegacySnap] = await Promise.all([
                    transaction.get(currentSlotRef),
                    transaction.get(currentLegacySlotRef),
                ]);
            }

            const newSlotRef = canonicalAppointmentSlotLockRef(doctorId, parsedDate, resolvedNewSlot, db);
            const newLegacySlotRef = legacyAppointmentSlotLockRef(doctorId, parsedDate, resolvedNewSlot, db);
            const [newSlotSnap, newLegacySnap] = await Promise.all([
                transaction.get(newSlotRef),
                transaction.get(newLegacySlotRef),
            ]);

            for (const s of [newSlotSnap, newLegacySnap]) {
                if (s.exists && s.data()?.appointmentId !== appointmentId && ACTIVE_APPOINTMENT_STATUSES.includes(s.data()?.status || 'pending')) {
                    throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
                }
            }

            const dateKey = appointmentDateKey(parsedDate);
            const [year, month, day] = dateKey.split('-').map(Number);
            const startOfDayUtc = Date.UTC(year, month - 1, day, -3, 0, 0, 0);
            const endOfDayUtc = Date.UTC(year, month - 1, day, 20, 59, 59, 999);
            const startOfDay = admin.firestore.Timestamp.fromMillis(startOfDayUtc);
            const endOfDay = admin.firestore.Timestamp.fromMillis(endOfDayUtc);

            const appointmentsQuery = db.collection('appointments')
                .where('doctorId', '==', doctorId)
                .where('appointmentDate', '>=', startOfDay)
                .where('appointmentDate', '<=', endOfDay);
            const appointmentsSnap = await transaction.get(appointmentsQuery);

            for (const apptDoc of appointmentsSnap.docs) {
                const appt = apptDoc.data();
                if (ACTIVE_APPOINTMENT_STATUSES.includes(appt.status) && apptDoc.id !== appointmentId) {
                    if (doesAppointmentOverlapSlot(appt, trustedSlot, doctorData, parsedDate)) {
                        throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
                    }
                }
            }

            // --- WRITES (All reads precede writes) ---
            transaction.set(coordinationRef, {
                doctorId,
                dateKey,
                updatedAt: admin.firestore.Timestamp.now(),
            }, { merge: true });

            if (currentSlotRef && currentSlotSnap?.exists && currentSlotSnap.data()?.appointmentId === appointmentId) {
                if (currentSlotRef.path !== newSlotRef.path) {
                    transaction.delete(currentSlotRef);
                }
            }
            if (currentLegacySlotRef && currentLegacySnap?.exists && currentLegacySnap.data()?.appointmentId === appointmentId) {
                if (currentLegacySlotRef.path !== newSlotRef.path) {
                    transaction.delete(currentLegacySlotRef);
                }
            }

            transaction.set(newSlotRef, {
                appointmentId,
                doctorId,
                appointmentDateKey: dateKey,
                timeSlot: resolvedNewSlot,
                startTime: trustedSlot.startTime,
                status: currentAppointment.status,
                updatedAt: admin.firestore.Timestamp.now(),
            });

            transaction.update(ref, {
                appointmentDate: admin.firestore.Timestamp.fromDate(parsedDate),
                timeSlot: resolvedNewSlot,
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

export interface GetDoctorDayAvailabilityData {
    doctorId?: string;
    date?: string;
    appointmentDate?: string;
}

export interface AvailableSlotInfo {
    timeSlot: string;
    startTime: string;
    endTime: string;
    isAvailable: boolean;
}

export interface GetDoctorDayAvailabilityResult {
    success: true;
    doctorId: string;
    appointmentDate: string;
    doctorName: string;
    department: string;
    slots: AvailableSlotInfo[];
}

export const getDoctorDayAvailability = functions.https.onCall(
    async (
        request: functions.https.CallableRequest<GetDoctorDayAvailabilityData>
    ): Promise<GetDoctorDayAvailabilityResult> => {
        const callerUid = requireAuth(request);
        await getCallerUserDoc(callerUid);
        const data = request.data || {};
        const doctorId = typeof data.doctorId === 'string' ? data.doctorId.trim() : '';
        const dateStr = typeof data.date === 'string' && data.date.trim()
            ? data.date.trim()
            : (typeof data.appointmentDate === 'string' && data.appointmentDate.trim()
                ? data.appointmentDate.trim()
                : '');

        if (!doctorId || !dateStr) {
            throw new functions.https.HttpsError('invalid-argument', 'doctorId and date (YYYY-MM-DD) are required.');
        }

        const now = new Date();
        const parsedDate = parseAppointmentDate(dateStr);
        const dateKey = appointmentDateKey(parsedDate);

        const doctorDoc = await db.collection('doctors').doc(doctorId).get();
        if (!doctorDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        }
        const doctorData = doctorDoc.data()!;
        if (doctorData.isActive !== true || doctorData.isAvailable !== true) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor is currently unavailable.');
        }

        const deptKey = doctorData.department as string | undefined;
        if (!deptKey) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor has no assigned department.');
        }
        const deptQuery = db.collection('departments').where('key', '==', deptKey).where('isActive', '==', true).limit(1);
        const deptSnap = await deptQuery.get();
        if (deptSnap.empty) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor\'s department is not active.');
        }

        const daySlots = getDoctorDaySchedule(doctorData, dateKey);
        const doctorName = typeof doctorData.name === 'string' && doctorData.name.trim() ? doctorData.name.trim() : 'Doctor';

        if (daySlots.length === 0) {
            return {
                success: true,
                doctorId,
                appointmentDate: dateKey,
                doctorName,
                department: deptKey,
                slots: [],
            };
        }

        const [year, month, day] = dateKey.split('-').map(Number);
        const startOfDayUtc = Date.UTC(year, month - 1, day, -3, 0, 0, 0);
        const endOfDayUtc = Date.UTC(year, month - 1, day, 20, 59, 59, 999);
        const startOfDay = admin.firestore.Timestamp.fromMillis(startOfDayUtc);
        const endOfDay = admin.firestore.Timestamp.fromMillis(endOfDayUtc);

        const [apptsSnap, locksSnap] = await Promise.all([
            db.collection('appointments')
                .where('doctorId', '==', doctorId)
                .where('appointmentDate', '>=', startOfDay)
                .where('appointmentDate', '<=', endOfDay)
                .get(),
            db.collection('appointment_slot_locks')
                .where('doctorId', '==', doctorId)
                .where('appointmentDateKey', '==', dateKey)
                .get(),
        ]);

        const activeAppointments = apptsSnap.docs
            .map((d) => d.data())
            .filter((a) => ACTIVE_APPOINTMENT_STATUSES.includes(a.status));

        const activeLocks = locksSnap.docs
            .map((d) => d.data())
            .filter((l) => ACTIVE_APPOINTMENT_STATUSES.includes(l.status || 'pending'));

        const slots: AvailableSlotInfo[] = daySlots.map((slot) => {
            if (!slot.startTime || slot.isAvailable === false) {
                return {
                    timeSlot: slot.startTime,
                    startTime: slot.startTime,
                    endTime: slot.endTime || '',
                    isAvailable: false,
                };
            }

            const slotRange = slot.endTime ? `${slot.startTime} - ${slot.endTime}` : slot.startTime;

            const exactUtc = appointmentExactUtcTime(dateKey, slot.startTime);
            if (exactUtc.getTime() <= now.getTime()) {
                return {
                    timeSlot: slotRange,
                    startTime: slot.startTime,
                    endTime: slot.endTime || '',
                    isAvailable: false,
                };
            }

            const isLocked = activeLocks.some((l) => {
                const lockStart = canonicalSlotStartTime(l.startTime || l.timeSlot || '');
                return lockStart === slot.startTime || l.timeSlot === slotRange;
            });
            if (isLocked) {
                return {
                    timeSlot: slotRange,
                    startTime: slot.startTime,
                    endTime: slot.endTime || '',
                    isAvailable: false,
                };
            }

            const hasConflict = activeAppointments.some((appt) => {
                return doesAppointmentOverlapSlot(appt, { startTime: slot.startTime, endTime: slot.endTime }, doctorData, dateKey);
            });
            if (hasConflict) {
                return {
                    timeSlot: slotRange,
                    startTime: slot.startTime,
                    endTime: slot.endTime || '',
                    isAvailable: false,
                };
            }

            return {
                timeSlot: slotRange,
                startTime: slot.startTime,
                endTime: slot.endTime || '',
                isAvailable: true,
            };
        });

        return {
            success: true,
            doctorId,
            appointmentDate: dateKey,
            doctorName,
            department: deptKey,
            slots,
        };
    }
);

