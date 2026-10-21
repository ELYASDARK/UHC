import { Timestamp } from 'firebase-admin/firestore';
import { createHash, randomUUID } from 'crypto';
import * as functions from 'firebase-functions';
import { appointmentExactUtcTime, matchesTimeSlot } from '../shared/appointmentHelpers';
import { AvailableSlotInfo, loadDoctorDayAvailability } from '../appointments/doctorDayAvailability';
import { ASSISTANT_CONFIG } from './config';
import { DepartmentCandidate, DoctorCandidate, matchScheduleAndGenerateOffers } from './scheduleMatcher';
import {
    AssistantChatDocument,
    AssistantChatMessage,
    AssistantOffer,
    AssistantReplyLanguage,
    SearchPreferences,
    SendAssistantMessageResult,
} from './types';

export function pruneExpiredMessages(
    messages: AssistantChatMessage[],
    now = new Date()
): AssistantChatMessage[] {
    const cutoffMs = now.getTime() - ASSISTANT_CONFIG.CHAT_RETENTION_DAYS * 24 * 60 * 60 * 1000;
    return messages.filter((m) => {
        const msgTime = new Date(m.createdAt).getTime();
        return !Number.isNaN(msgTime) && msgTime >= cutoffMs;
    });
}

export function createInitialChatDoc(patientId: string, now = new Date()): AssistantChatDocument {
    const timestampNow = Timestamp.fromDate(now);
    const expiresAt = Timestamp.fromDate(
        new Date(now.getTime() + ASSISTANT_CONFIG.CHAT_RETENTION_DAYS * 24 * 60 * 60 * 1000)
    );

    return {
        patientId,
        generationId: randomUUID(),
        revision: 1,
        inFlightTurnId: null,
        lastClientRequestId: null,
        lastClientRequestHash: null,
        lastResult: null,
        messages: [],
        offers: [],
        searchPreferences: null,
        resetAt: null,
        createdAt: timestampNow,
        updatedAt: timestampNow,
        expiresAt,
    };
}

export interface ReserveTurnParams {
    patientId: string;
    clientRequestId?: string;
    userMessage: string;
    now?: Date;
}

export interface ReserveTurnResult {
    deduplicated: boolean;
    lastResult?: SendAssistantMessageResult;
    generationId: string;
    reservedRevision: number;
    turnId: string;
    history: AssistantChatMessage[];
    searchPreferences?: SearchPreferences | null;
}

/**
 * Reserves a conversational turn before network dispatch.
 * Performs clientRequestId deduplication bound to user message hash,
 * enforces a bounded in-flight lease (90s), 7-day retention pruning,
 * generation check, and resets lastResult on new reservation.
 */
export async function reserveAssistantTurn(
    db: FirebaseFirestore.Firestore,
    params: ReserveTurnParams
): Promise<ReserveTurnResult> {
    if (params.clientRequestId && (typeof params.clientRequestId !== 'string' || params.clientRequestId.length > 128)) {
        throw new Error('clientRequestId must not exceed 128 characters.');
    }

    const now = params.now || new Date();
    const chatRef = db.collection('assistant_chats').doc(params.patientId);
    const messageHash = createHash('sha256').update(params.userMessage).digest('hex');

    return db.runTransaction(async (transaction) => {
        const snap = await transaction.get(chatRef);
        let doc: AssistantChatDocument;

        if (!snap.exists) {
            doc = createInitialChatDoc(params.patientId, now);
        } else {
            doc = snap.data() as AssistantChatDocument;
        }

        const expiresAtMs = doc.expiresAt?.toMillis ? doc.expiresAt.toMillis() : 0;
        if (expiresAtMs > 0 && expiresAtMs <= now.getTime()) {
            // Retention period expired: clean reset with new generation
            doc = {
                ...createInitialChatDoc(params.patientId, now),
                revision: (doc.revision || 1) + 1,
            };
        }

        // Deduplication check bound to clientRequestId AND user message content hash
        if (
            params.clientRequestId &&
            doc.lastClientRequestId === params.clientRequestId &&
            doc.lastResult
        ) {
            if (!doc.lastClientRequestHash || doc.lastClientRequestHash === messageHash) {
                return {
                    deduplicated: true,
                    lastResult: doc.lastResult,
                    generationId: doc.generationId,
                    reservedRevision: doc.revision,
                    turnId: doc.inFlightTurnId || '',
                    history: doc.messages || [],
                    searchPreferences: doc.searchPreferences,
                };
            }
        }

        // Enforce bounded in-flight turn lease (90 seconds)
        const inFlightAgeMs = doc.updatedAt?.toMillis ? (now.getTime() - doc.updatedAt.toMillis()) : 0;
        if (doc.inFlightTurnId && inFlightAgeMs >= 0 && inFlightAgeMs < 90000) {
            if (params.clientRequestId && doc.lastClientRequestId === params.clientRequestId) {
                throw new functions.https.HttpsError('already-exists', 'An assistant turn is already in progress for this request.');
            }
            throw new functions.https.HttpsError('failed-precondition', 'An assistant turn is already in progress. Please wait.');
        }

        const prunedMessages = pruneExpiredMessages(doc.messages || [], now);
        const turnId = randomUUID();
        const reservedRevision = (doc.revision || 1) + 1;

        const userMsg: AssistantChatMessage = {
            id: `usr_${Date.now()}`,
            sender: 'patient',
            text: params.userMessage,
            status: 'ready',
            createdAt: now.toISOString(),
        };

        const updatedMessages = [...prunedMessages, userMsg].slice(-ASSISTANT_CONFIG.MAX_CHAT_MESSAGES);
        const timestampNow = Timestamp.fromDate(now);

        const updatedDoc: AssistantChatDocument = {
            ...doc,
            revision: reservedRevision,
            inFlightTurnId: turnId,
            lastClientRequestId: params.clientRequestId || null,
            lastClientRequestHash: messageHash,
            lastResult: null, // Reset previous completed result on new reservation
            expiresAt: Timestamp.fromMillis(
                now.getTime() + ASSISTANT_CONFIG.CHAT_RETENTION_DAYS * 86400000
            ),
            messages: updatedMessages,
            updatedAt: timestampNow,
        };

        transaction.set(chatRef, updatedDoc);

        return {
            deduplicated: false,
            generationId: doc.generationId,
            reservedRevision,
            turnId,
            history: updatedMessages,
            searchPreferences: doc.searchPreferences,
        };
    });
}

export interface CommitTurnParams {
    patientId: string;
    generationId: string;
    reservedRevision: number;
    turnId: string;
    assistantMessage: string;
    status: AssistantChatMessage['status'];
    reasonCode?: string | null;
    replyLanguage: AssistantReplyLanguage;
    offers: AssistantOffer[];
    searchPreferences?: SearchPreferences | null;
    resetAt?: string | null;
    now?: Date;
}

export interface CommitTurnResult {
    committed: boolean;
    result?: SendAssistantMessageResult;
}

/**
 * Commits the assistant's turn transactionally.
 * Validates that generationId, revision, and turnId still match.
 * If chat was cleared concurrently, safely aborts without committing.
 */
export async function commitAssistantTurn(
    db: FirebaseFirestore.Firestore,
    params: CommitTurnParams
): Promise<CommitTurnResult> {
    const now = params.now || new Date();
    const chatRef = db.collection('assistant_chats').doc(params.patientId);

    return db.runTransaction(async (transaction) => {
        const snap = await transaction.get(chatRef);
        if (!snap.exists) {
            return { committed: false };
        }

        const currentDoc = snap.data() as AssistantChatDocument;
        if (
            currentDoc.generationId !== params.generationId ||
            currentDoc.inFlightTurnId !== params.turnId ||
            currentDoc.revision !== params.reservedRevision
        ) {
            // Chat was cleared or superseded concurrently
            return { committed: false };
        }

        const newRevision = currentDoc.revision + 1;
        const nowIso = now.toISOString();

        const assistantMsg: AssistantChatMessage = {
            id: `asst_${Date.now()}`,
            sender: 'assistant',
            text: params.assistantMessage,
            status: params.status,
            reasonCode: params.reasonCode || null,
            offerIds: params.offers.map((o) => o.offerId),
            createdAt: nowIso,
        };

        const isAccepted = params.status === 'ready' || params.status === 'clarify' || params.status === 'out_of_scope';
        const baseMessages = isAccepted
            ? (currentDoc.messages || [])
            : (currentDoc.messages || []).slice(0, -1);

        const updatedMessages = params.assistantMessage
            ? [...baseMessages, assistantMsg].slice(-ASSISTANT_CONFIG.MAX_CHAT_MESSAGES)
            : baseMessages.slice(-ASSISTANT_CONFIG.MAX_CHAT_MESSAGES);

        const updatedOffers = (params.offers || []).slice(0, ASSISTANT_CONFIG.MAX_ACTIVE_OFFERS);

        const finalResult: SendAssistantMessageResult = {
            success: true,
            status: params.status,
            reasonCode: params.reasonCode || null,
            message: params.assistantMessage,
            replyLanguage: params.replyLanguage,
            offers: updatedOffers,
            resetAt: params.resetAt || null,
            revision: newRevision,
        };

        const timestampNow = Timestamp.fromDate(now);

        const updatedDoc: AssistantChatDocument = {
            ...currentDoc,
            revision: newRevision,
            inFlightTurnId: null,
            messages: updatedMessages,
            offers: updatedOffers,
            searchPreferences: params.searchPreferences !== undefined ? params.searchPreferences : currentDoc.searchPreferences,
            lastResult: finalResult,
            expiresAt: Timestamp.fromMillis(
                now.getTime() + ASSISTANT_CONFIG.CHAT_RETENTION_DAYS * 86400000
            ),
            resetAt: params.resetAt || null,
            updatedAt: timestampNow,
        };

        transaction.set(chatRef, updatedDoc);

        return {
            committed: true,
            result: finalResult,
        };
    });
}

/**
 * Releases an in-flight turn lease if it has not been superseded or committed.
 * Clears inFlightTurnId so subsequent user requests are not blocked for 90 seconds
 * when an unhandled error or network failure occurs during processing.
 */
export async function releaseAssistantTurn(
    db: FirebaseFirestore.Firestore,
    patientId: string,
    turnId: string
): Promise<void> {
    const chatRef = db.collection('assistant_chats').doc(patientId);

    await db.runTransaction(async (transaction) => {
        const snap = await transaction.get(chatRef);
        if (!snap.exists) {
            return;
        }

        const currentDoc = snap.data() as AssistantChatDocument;
        if (currentDoc.inFlightTurnId === turnId) {
            transaction.update(chatRef, {
                inFlightTurnId: null,
                updatedAt: Timestamp.now(),
            });
        }
    });
}

/**
 * Clears the patient's chat history and active offers immediately.
 * Increments revision and generates a new generationId to safely
 * invalidate any in-flight completion.
 */
export async function clearPatientChat(
    db: FirebaseFirestore.Firestore,
    patientId: string,
    now = new Date()
): Promise<{ revision: number }> {
    const chatRef = db.collection('assistant_chats').doc(patientId);

    return db.runTransaction(async (transaction) => {
        const snap = await transaction.get(chatRef);
        const currentRevision = snap.exists ? (snap.data()?.revision || 0) : 0;
        const nextRevision = currentRevision + 1;

        const timestampNow = Timestamp.fromDate(now);
        const expiresAt = Timestamp.fromDate(
            new Date(now.getTime() + ASSISTANT_CONFIG.CHAT_RETENTION_DAYS * 24 * 60 * 60 * 1000)
        );

        const clearedDoc: AssistantChatDocument = {
            patientId,
            generationId: randomUUID(),
            revision: nextRevision,
            inFlightTurnId: null,
            lastClientRequestId: null,
            lastResult: null,
            messages: [],
            offers: [],
            searchPreferences: null,
            resetAt: null,
            createdAt: snap.exists ? snap.data()?.createdAt : timestampNow,
            updatedAt: timestampNow,
            expiresAt,
        };

        transaction.set(chatRef, clearedDoc);
        return { revision: nextRevision };
    });
}

/**
 * Loads the patient's chat document with 7-day retention filtering.
 */
export async function getPatientChatDoc(
    db: FirebaseFirestore.Firestore,
    patientId: string,
    now = new Date()
): Promise<{ doc: AssistantChatDocument; exists: boolean }> {
    const ref = db.collection('assistant_chats').doc(patientId);
    const snap = await ref.get();

    if (!snap.exists) {
        return {
            doc: createInitialChatDoc(patientId, now),
            exists: false,
        };
    }

    const data = snap.data() as AssistantChatDocument;
    const expiresAtMs = data.expiresAt?.toMillis ? data.expiresAt.toMillis() : 0;

    if (expiresAtMs > 0 && expiresAtMs <= now.getTime()) {
        return {
            doc: {
                ...createInitialChatDoc(patientId, now),
                revision: (data.revision || 1) + 1,
            },
            exists: false,
        };
    }

    // Prune messages older than 7 days
    const prunedMessages = pruneExpiredMessages(data.messages || [], now);
    return {
        doc: {
            ...data,
            messages: prunedMessages,
        },
        exists: true,
    };
}

/**
 * Refreshes availability of existing offers and, if expired, resumes prior
 * preferences without calling Gemini.
 */
export async function refreshPatientChatHistory(
    db: FirebaseFirestore.Firestore,
    patientId: string,
    departments: DepartmentCandidate[],
    doctors: DoctorCandidate[],
    now = new Date()
): Promise<AssistantChatDocument> {
    const { doc: chatDoc, exists } = await getPatientChatDoc(db, patientId, now);
    if (!exists) {
        return chatDoc;
    }

    const activeDeptKeys = new Set(departments.map((d) => d.key));

    const existingOffers = chatDoc.offers || [];
    const availabilityByDay = new Map<string, Promise<AvailableSlotInfo[]>>();
    const refreshedOffers = await Promise.all(existingOffers.map(async (offer) => {
        const expiresAt = Date.parse(offer.expiresAt);
        if (!Number.isFinite(expiresAt) || expiresAt <= now.getTime() ||
            appointmentExactUtcTime(offer.appointmentDate, offer.timeSlot).getTime() <= now.getTime()) {
            return { ...offer, isAvailable: false };
        }
        try {
            const dayKey = `${offer.doctorId}:${offer.appointmentDate}`;
            let availability = availabilityByDay.get(dayKey);
            if (!availability) {
                availability = loadOfferDayAvailability(db, offer, activeDeptKeys, now);
                availabilityByDay.set(dayKey, availability);
            }
            const slots = await availability;
            return { ...offer, isAvailable: slots.some((slot) => slot.isAvailable && matchesTimeSlot(slot, offer.timeSlot)) };
        } catch {
            // Existing offers fail closed if their current availability cannot be read.
            return { ...offer, isAvailable: false };
        }
    }));

    // If all existing offers are expired and preferences exist, revalidate fresh offers
    const allExpired = refreshedOffers.every((o) => !o.isAvailable);
    // An unfinished turn owns this revision until it commits or is superseded.
    // Refresh can report availability, but must not replace its reserved history.
    if (!chatDoc.inFlightTurnId && allExpired && existingOffers.length > 0 &&
        (!chatDoc.lastResult || chatDoc.lastResult.status === 'ready') && chatDoc.searchPreferences) {
        const pref = chatDoc.searchPreferences;
        const freshMatch = await matchScheduleAndGenerateOffers(
            db,
            {
                intent: 'book_appointment',
                departmentKey: pref.departmentKey,
                doctorId: pref.doctorId,
                doctorName: pref.doctorName,
                preferredDate: pref.preferredDate,
                preferredTimeSlot: pref.preferredTimeSlot,
                timeFilter: pref.timeFilter,
                replyLanguage: 'en',
            },
            departments,
            doctors,
            now
        );

        if (freshMatch.offers.length > 0) {
            const chatRef = db.collection('assistant_chats').doc(patientId);
            const refreshedChat = await db.runTransaction(async (tx): Promise<AssistantChatDocument | null> => {
                const curSnap = await tx.get(chatRef);
                if (!curSnap.exists) return null;
                const current = curSnap.data() as AssistantChatDocument;
                if (current.generationId !== chatDoc.generationId || current.revision !== chatDoc.revision ||
                    current.inFlightTurnId) return null;
                const freshOfferIds = freshMatch.offers.map((offer) => offer.offerId);
                const messages = [...(current.messages || [])];
                const lastIndex = messages.length - 1;
                if (lastIndex >= 0 && messages[lastIndex].sender === 'assistant') {
                    messages[lastIndex] = { ...messages[lastIndex], offerIds: freshOfferIds };
                }
                const refreshedDoc: AssistantChatDocument = {
                    ...current,
                    offers: freshMatch.offers,
                    messages,
                    revision: (current.revision || 1) + 1,
                    updatedAt: Timestamp.fromDate(now),
                };
                tx.update(chatRef, {
                    offers: refreshedDoc.offers,
                    messages: refreshedDoc.messages,
                    revision: refreshedDoc.revision,
                    updatedAt: refreshedDoc.updatedAt,
                });
                return refreshedDoc;
            });
            // A retry returns only its own snapshot; abandoned attempts cannot resurrect cleared offers.
            return refreshedChat || (await getPatientChatDoc(db, patientId, now)).doc;
        }
    }

    return { ...chatDoc, offers: refreshedOffers };
}

async function loadOfferDayAvailability(
    firestore: FirebaseFirestore.Firestore,
    offer: AssistantOffer,
    activeDepartments: Set<string>,
    now: Date
): Promise<AvailableSlotInfo[]> {
    const doctorDoc = await firestore.collection('doctors').doc(offer.doctorId).get();
    const doctor = doctorDoc.data();
    if (!doctorDoc.exists || doctor?.isActive !== true || doctor?.isAvailable !== true ||
        !activeDepartments.has(doctor.department || offer.department)) return [];
    return loadDoctorDayAvailability(firestore, { doctorId: offer.doctorId, doctor, dateKey: offer.appointmentDate, now });
}
