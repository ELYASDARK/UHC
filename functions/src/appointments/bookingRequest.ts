import { createHash } from 'crypto';
import * as functions from 'firebase-functions';
import { AssistantChatDocument, AssistantOffer } from '../assistant/types';
import { APPOINTMENT_TYPES, appointmentExactTime, appointmentExactUtcTime, parseAppointmentDate } from '../shared/appointmentHelpers';

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

interface BookingReceiptKey {
    idempotencyDocId?: string;
    payloadHash: string;
    notes: string | null;
}

export type PreparedBookingRequest = BookingReceiptKey & (
    { kind: 'assistant'; offerId: string } |
    { kind: 'direct'; doctorId?: string; department: string; appointmentDate: string; timeSlot: string; type: string }
);

export interface AssistantOfferConsumption {
    ref: FirebaseFirestore.DocumentReference;
    chat: AssistantChatDocument;
    remainingOffers: AssistantOffer[];
    offerId: string;
}

export interface ResolvedBookingRequest {
    doctorId?: string;
    doctorName: string;
    department: string;
    appointmentDate: Date;
    timeSlot: string;
    type: string;
    notes: string | null;
    offerConsumption?: AssistantOfferConsumption;
}

export function prepareBookingRequest(callerUid: string, request: CreateAppointmentData): PreparedBookingRequest {
    if (request.patientId !== callerUid) {
        throw new functions.https.HttpsError('permission-denied', 'You can only create appointments for yourself.');
    }
    if (typeof request.offerId === 'string' && request.offerId.trim()) {
        const offerId = request.offerId.trim();
        if (request.confirmed !== true) {
            throw new functions.https.HttpsError('invalid-argument', 'confirmed must be explicitly true.');
        }
        if (offerId.length > 128) {
            throw new functions.https.HttpsError('invalid-argument', 'offerId must be a non-empty string up to 128 characters.');
        }
        if (request.notes !== undefined && request.notes !== null &&
            (typeof request.notes !== 'string' || request.notes.length > 1000)) {
            throw new functions.https.HttpsError('invalid-argument', 'notes must be 1000 characters or fewer.');
        }
        const payloadHash = createHash('sha256').update(`${callerUid}:${offerId}`).digest('hex');
        return { kind: 'assistant', offerId, payloadHash, idempotencyDocId: `asst_confirm_${payloadHash}`,
            notes: typeof request.notes === 'string' ? request.notes.trim() : null };
    }
    return prepareDirectBooking(callerUid, request);
}

function prepareDirectBooking(callerUid: string, request: CreateAppointmentData): PreparedBookingRequest {
    if (!request.department || !request.appointmentDate || !request.timeSlot) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required appointment fields.');
    }
    if (typeof request.department !== 'string' || !request.department.trim() || request.department.trim().length > 128) {
        throw new functions.https.HttpsError('invalid-argument', 'department must be 1 to 128 characters.');
    }
    if (typeof request.appointmentDate !== 'string' || !/^\d{4}-\d{2}-\d{2}/.test(request.appointmentDate.trim()) || request.appointmentDate.trim().length > 32) {
        throw new functions.https.HttpsError('invalid-argument', 'appointmentDate must be a valid date string.');
    }
    if (typeof request.timeSlot !== 'string' || !request.timeSlot.trim() || request.timeSlot.trim().length > 64) {
        throw new functions.https.HttpsError('invalid-argument', 'timeSlot must be 1 to 64 characters.');
    }
    const type = request.type || 'regularCheckup';
    if (!APPOINTMENT_TYPES.includes(type)) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid appointment type.');
    }
    const doctorId = type === 'emergency' && request.doctorId === '' ? undefined : request.doctorId;
    if (doctorId !== undefined && doctorId !== null &&
        (typeof doctorId !== 'string' || !doctorId.trim() || doctorId.trim().length > 128)) {
        throw new functions.https.HttpsError('invalid-argument', 'doctorId must be a string up to 128 characters.');
    }
    if (request.bookingReference !== undefined && request.bookingReference !== null &&
        (typeof request.bookingReference !== 'string' || request.bookingReference.trim().length > 64)) {
        throw new functions.https.HttpsError('invalid-argument', 'bookingReference must be 64 characters or fewer.');
    }
    if (typeof request.notes === 'string' && request.notes.length > 1000) {
        throw new functions.https.HttpsError('invalid-argument', 'notes must be 1000 characters or fewer.');
    }
    if (typeof request.idempotencyKey === 'string' && request.idempotencyKey.trim().length > 128) {
        throw new functions.https.HttpsError('invalid-argument', 'idempotencyKey must be 128 characters or fewer.');
    }
    const key = typeof request.idempotencyKey === 'string' && request.idempotencyKey.trim()
        ? request.idempotencyKey.trim()
        : (typeof request.bookingReference === 'string' && request.bookingReference.trim()
            ? `bref_${request.bookingReference.trim().toUpperCase()}` : undefined);
    return {
        kind: 'direct', doctorId, department: request.department,
        appointmentDate: request.appointmentDate, timeSlot: request.timeSlot, type,
        notes: typeof request.notes === 'string' ? request.notes.trim() : null,
        idempotencyDocId: key ? `${callerUid}_${encodeURIComponent(key)}` : undefined,
        payloadHash: createHash('sha256')
            .update(`${callerUid}:${request.doctorId || ''}:${request.department}:${request.appointmentDate}:${request.timeSlot}:${type}:${request.notes || ''}`)
            .digest('hex'),
    };
}

export async function resolveBookingRequest(
    transaction: FirebaseFirestore.Transaction,
    firestore: FirebaseFirestore.Firestore,
    request: { booking: PreparedBookingRequest; patientId: string; now: Date }
): Promise<ResolvedBookingRequest> {
    const { booking, patientId, now } = request;
    if (booking.kind === 'assistant') {
        return resolveAssistantOffer(transaction, firestore, { booking, patientId, now });
    }
    const isEmergency = booking.type === 'emergency';
    const appointmentDate = isEmergency ? now : parseAppointmentDate(booking.appointmentDate);
    if (!isEmergency && appointmentExactTime(appointmentDate, booking.timeSlot).getTime() <= now.getTime()) {
        throw new functions.https.HttpsError('failed-precondition', 'Appointment time must be in the future.');
    }
    return {
        doctorId: booking.doctorId,
        doctorName: 'Any Available',
        department: booking.department,
        appointmentDate,
        timeSlot: isEmergency ? '00:00 - Emergency' : booking.timeSlot,
        type: booking.type,
        notes: booking.notes,
    };
}

async function resolveAssistantOffer(
    transaction: FirebaseFirestore.Transaction,
    firestore: FirebaseFirestore.Firestore,
    request: { booking: PreparedBookingRequest & { kind: 'assistant' }; patientId: string; now: Date }
): Promise<ResolvedBookingRequest> {
    const { booking, patientId, now } = request;
    const ref = firestore.collection('assistant_chats').doc(patientId);
    const chatSnap = await transaction.get(ref);
    const chat = chatSnap.data() as AssistantChatDocument | undefined;
    if (!chat) throw new functions.https.HttpsError('not-found', 'Appointment offer not found or has been cleared.');
    const chatExpiresAt = chat.expiresAt?.toMillis ? chat.expiresAt.toMillis() : 0;
    if (chatExpiresAt > 0 && chatExpiresAt <= now.getTime()) {
        throw new functions.https.HttpsError('failed-precondition', 'Chat session has expired. Please request a new appointment.');
    }
    const offers = chat.offers || [];
    const offer = offers.find((candidate) => candidate.offerId === booking.offerId);
    if (!offer) throw new functions.https.HttpsError('not-found', 'Appointment offer not found or has been cleared.');
    if (offer.isAvailable === false) {
        throw new functions.https.HttpsError('failed-precondition', 'This appointment offer is no longer available.');
    }
    const expiresAt = Date.parse(offer.expiresAt);
    if (Number.isNaN(expiresAt) || expiresAt <= now.getTime()) {
        throw new functions.https.HttpsError('failed-precondition', 'This appointment offer has expired. Please request a new appointment.');
    }
    if (appointmentExactUtcTime(offer.appointmentDate, offer.timeSlot).getTime() <= now.getTime()) {
        throw new functions.https.HttpsError('failed-precondition', 'This appointment slot is in the past.');
    }
    return {
        doctorId: offer.doctorId, doctorName: offer.doctorName || 'Doctor', department: offer.department,
        appointmentDate: parseAppointmentDate(offer.appointmentDate), timeSlot: offer.timeSlot,
        type: 'regularCheckup', notes: booking.notes,
        offerConsumption: { ref, chat, offerId: booking.offerId, remainingOffers: offers.filter((candidate) => candidate.offerId !== booking.offerId) },
    };
}

export function consumeAssistantOffer(
    transaction: FirebaseFirestore.Transaction,
    consumption: AssistantOfferConsumption,
    now: FirebaseFirestore.Timestamp
): void {
    transaction.update(consumption.ref, {
        offers: consumption.remainingOffers,
        messages: (consumption.chat.messages || []).map((message) => Array.isArray(message.offerIds)
            ? { ...message, offerIds: message.offerIds.filter((offerId) => offerId !== consumption.offerId) }
            : message),
        revision: (consumption.chat.revision || 1) + 1,
        updatedAt: now,
    });
}
