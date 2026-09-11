import { createHash } from 'crypto';
import * as functions from 'firebase-functions';
import { admin, db } from '../firebase';
import {
    appointmentDateKey,
} from '../shared/appointmentHelpers';
import { getCallerUserDoc, requireAuth, requirePatientRole } from '../shared/auth';
import { createAppointmentCore } from '../appointments';
import { ASSISTANT_CONFIG, evaluateTransmissionGate, checkSyntheticTestingConditions } from './config';
import { getLocalizedMessage, normalizeLocale } from './localization';
import {
    classifyGeminiError,
    checkAssistantAdmission,
    markDailyQuotaExhausted,
    getNextPacificMidnightUtc,
    getPacificDateKey,
} from './quota';
import { GeminiAssistantClient } from './geminiClient';
import { SyntheticSchedulingInterpreter } from './syntheticInterpreter';
export { seedSyntheticEmulatorData, SeedEmulatorDataResult } from './seedEmulatorData';
import {
    clearPatientChat,
    commitAssistantTurn,
    getPatientChatDoc,
    refreshPatientChatHistory,
    releaseAssistantTurn,
    reserveAssistantTurn,
} from './chatService';
import {
    DepartmentCandidate,
    DoctorCandidate,
    matchScheduleAndGenerateOffers,
    ScheduleMatchResult,
} from './scheduleMatcher';
import {
    AssistantChatDocument,
    ClearAssistantHistoryResult,
    ConfirmAssistantAppointmentData,
    ConfirmAssistantAppointmentResult,
    DepartmentCatalogEntry,
    DoctorCatalogEntry,
    GetAssistantHistoryResult,
    SendAssistantMessageData,
    SendAssistantMessageResult,
    StructuredIntent,
} from './types';

/**
 * Sends a message to the AI Appointment Assistant.
 * Validates patient authorization, applies rate limits, checks server transmission gate,
 * interprets intent with Gemini, matches against real doctor schedules, and saves bounded history.
 */
export const sendAssistantMessage = functions.https.onCall(
    { secrets: ['GEMINI_API_KEY'], timeoutSeconds: 60 },
    async (
        request: functions.https.CallableRequest<SendAssistantMessageData>
    ): Promise<SendAssistantMessageResult> => {
        const adminProjectId = admin.app().options.projectId;
        const isSyntheticOptIn = process.env.AI_OFFLINE_SYNTHETIC_TESTING === 'true';

        // When offline synthetic testing is opted in, evaluate the gate and isolation
        // BEFORE getCallerUserDoc or any Auth/Firestore network access.
        // If mismatched or disallowed, fail closed immediately without touching Auth/db.
        if (isSyntheticOptIn) {
            const preGate = evaluateTransmissionGate(adminProjectId);
            if (!preGate.enabled) {
                const clientLocale = normalizeLocale(request.data?.locale);
                return {
                    success: true,
                    status: 'disabled',
                    reasonCode: preGate.reasonCode || 'synthetic_mismatch_rejected',
                    message: preGate.message || getLocalizedMessage('disabled', clientLocale),
                    replyLanguage: clientLocale,
                    offers: [],
                    revision: 0,
                };
            }
        }

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePatientRole(callerDoc);

        const data = request.data || ({} as SendAssistantMessageData);
        const rawMessage = typeof data.message === 'string' ? data.message.trim() : '';

        if (!rawMessage) {
            throw new functions.https.HttpsError('invalid-argument', 'Message cannot be empty.');
        }

        if (data.clientRequestId !== undefined && data.clientRequestId !== null) {
            if (typeof data.clientRequestId !== 'string' || data.clientRequestId.length > 128) {
                throw new functions.https.HttpsError('invalid-argument', 'clientRequestId must be a string up to 128 characters.');
            }
        }

        if (rawMessage.length > ASSISTANT_CONFIG.MAX_MESSAGE_LENGTH) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                `Message cannot exceed ${ASSISTANT_CONFIG.MAX_MESSAGE_LENGTH} characters.`
            );
        }

        const sanitizedMessage = rawMessage;
        const clientLocale = normalizeLocale(data.locale);
        const now = new Date();

        // 1. Check transmission gate (DISABLED BY DEFAULT). Do not perform database writes when disabled.
        const gate = evaluateTransmissionGate(adminProjectId);
        if (!gate.enabled) {
            const message = getLocalizedMessage('disabled', clientLocale);
            return {
                success: true,
                status: 'disabled',
                reasonCode: gate.reasonCode,
                message,
                replyLanguage: clientLocale,
                offers: [],
                revision: 0,
            };
        }

        // 2. Fast check: return already-completed turn if clientRequestId matches without consuming quota
        if (data.clientRequestId) {
            const chatSnap = await db.collection('assistant_chats').doc(callerUid).get();
            if (chatSnap.exists) {
                const chatDoc = chatSnap.data() as AssistantChatDocument;
                const expiresAtMs = chatDoc.expiresAt?.toMillis ? chatDoc.expiresAt.toMillis() : 0;
                const isExpired = expiresAtMs > 0 && expiresAtMs <= now.getTime();
                if (!isExpired) {
                    const messageHash = createHash('sha256').update(sanitizedMessage).digest('hex');
                    if (
                        chatDoc.lastClientRequestId === data.clientRequestId &&
                        chatDoc.lastResult &&
                        (!chatDoc.lastClientRequestHash || chatDoc.lastClientRequestHash === messageHash)
                    ) {
                        return chatDoc.lastResult;
                    }
                }
            }
        }

        // 3. Admission check (project RPM, user RPM, project RPD) BEFORE reserving turn
        const quotaCheck = await checkAssistantAdmission(db, callerUid, now, clientLocale);
        if (!quotaCheck.allowed) {
            const status = quotaCheck.status || 'throttled';
            const msg = quotaCheck.message || getLocalizedMessage('throttled_project', clientLocale);

            return {
                success: true,
                status,
                reasonCode: quotaCheck.reasonCode || null,
                message: msg,
                replyLanguage: clientLocale,
                offers: [],
                resetAt: quotaCheck.resetAt,
                revision: 0,
            };
        }

        // 4. Reserve user turn transactionally before network dispatch
        const reservation = await reserveAssistantTurn(db, {
            patientId: callerUid,
            clientRequestId: data.clientRequestId,
            userMessage: sanitizedMessage,
            now,
        });

        if (reservation.deduplicated && reservation.lastResult) {
            return reservation.lastResult;
        }

        let committed = false;
        try {
            // 5. Load active catalog with bounds (honest overflow response instead of silent truncation)
            const [deptsSnap, doctorsSnap] = await Promise.all([
                db.collection('departments').where('isActive', '==', true).limit(51).get(),
                db.collection('doctors').where('isActive', '==', true).where('isAvailable', '==', true).limit(101).get(),
            ]);

            if (deptsSnap.docs.length > 50 || doctorsSnap.docs.length > 100) {
                const unavailMsg = getLocalizedMessage('unavailable', clientLocale);
                const commitResult = await commitAssistantTurn(db, {
                    patientId: callerUid,
                    generationId: reservation.generationId,
                    reservedRevision: reservation.reservedRevision,
                    turnId: reservation.turnId,
                    assistantMessage: unavailMsg,
                    status: 'unavailable',
                    reasonCode: 'catalog_overflow',
                    replyLanguage: clientLocale,
                    offers: [],
                    now,
                });
                if (!commitResult.committed) {
                    return {
                        success: false,
                        status: 'cancelled',
                        reasonCode: 'session_reset_concurrently',
                        message: getLocalizedMessage('cancelled', clientLocale),
                        replyLanguage: clientLocale,
                        offers: [],
                        revision: 0,
                    };
                }
                committed = true;
                return commitResult.result!;
            }

            const departmentsCatalog: DepartmentCatalogEntry[] = deptsSnap.docs.map((d) => ({
                key: d.data().key as string,
                name: (d.data().name as string) || (d.data().key as string),
            }));

            const doctorsCatalog: DoctorCatalogEntry[] = doctorsSnap.docs.map((d) => {
                const docData = d.data();
                const weeklySchedule = docData.weeklySchedule as Record<string, unknown[]> | undefined;
                const availableDays: string[] = [];
                if (weeklySchedule && typeof weeklySchedule === 'object') {
                    for (const [day, slots] of Object.entries(weeklySchedule)) {
                        if (Array.isArray(slots) && slots.length > 0) {
                            availableDays.push(day);
                        }
                    }
                }
                return {
                    doctorId: d.id,
                    name: (docData.name as string)?.substring(0, 50) || 'Doctor',
                    specialization: (docData.specialization as string)?.substring(0, 50) || '',
                    department: (docData.department as string)?.substring(0, 50) || '',
                    availableDays,
                };
            });

            // 6. Interpret request: Offline Synthetic Interpreter (if in synthetic test mode) or Gemini Client
            let callResult: {
                parsedIntent?: StructuredIntent;
                httpStatus?: number;
                errorBody?: unknown;
                networkError?: Error;
            };

            if (gate.isSynthetic) {
                const syntheticInterpreter = new SyntheticSchedulingInterpreter();
                const parsedIntent = await syntheticInterpreter.interpretSchedulingRequest({
                    userMessage: sanitizedMessage,
                    chatHistory: reservation.history.map((m) => ({ sender: m.sender, text: m.text })),
                    baghdadDateString: appointmentDateKey(now),
                    departments: departmentsCatalog,
                    doctors: doctorsCatalog,
                    clientLocale,
                });
                callResult = { parsedIntent };
            } else {
                const geminiClient = new GeminiAssistantClient({
                    apiKey: gate.apiKey || '',
                });

                callResult = await geminiClient.interpretSchedulingRequest({
                    userMessage: sanitizedMessage,
                    chatHistory: reservation.history.map((m) => ({ sender: m.sender, text: m.text })),
                    baghdadDateString: appointmentDateKey(now),
                    departments: departmentsCatalog,
                    doctors: doctorsCatalog,
                    clientLocale,
                });
            }

            if (callResult.networkError || (callResult.httpStatus && callResult.httpStatus !== 200)) {
                const classification = classifyGeminiError(
                    callResult.httpStatus || 500,
                    callResult.errorBody,
                    now,
                    clientLocale
                );

                if (classification.status === 'daily_limit') {
                    await markDailyQuotaExhausted(db, now);
                }

                const commitResult = await commitAssistantTurn(db, {
                    patientId: callerUid,
                    generationId: reservation.generationId,
                    reservedRevision: reservation.reservedRevision,
                    turnId: reservation.turnId,
                    assistantMessage: classification.message,
                    status: classification.status,
                    reasonCode: classification.reasonCode,
                    replyLanguage: clientLocale,
                    offers: [],
                    resetAt: classification.resetAt || null,
                    now,
                });

                if (!commitResult.committed) {
                    return {
                        success: false,
                        status: 'cancelled',
                        reasonCode: 'session_reset_concurrently',
                        message: getLocalizedMessage('cancelled', clientLocale),
                        replyLanguage: clientLocale,
                        offers: [],
                        revision: 0,
                    };
                }

                committed = true;
                return commitResult.result!;
            }

            const structuredIntent: StructuredIntent = callResult.parsedIntent || {
                intent: 'clarify',
                clarificationReason: 'general',
                replyLanguage: clientLocale,
            };

            const targetLang = structuredIntent.replyLanguage || clientLocale;

            // 7. Match schedules & generate real expiring offers
            const doctorCandidates: DoctorCandidate[] = doctorsSnap.docs.map((d) => ({
                id: d.id,
                data: d.data(),
            }));
            const departmentCandidates: DepartmentCandidate[] = departmentsCatalog;

            let matchResult: ScheduleMatchResult;
            try {
                matchResult = await matchScheduleAndGenerateOffers(
                    db,
                    structuredIntent,
                    departmentCandidates,
                    doctorCandidates,
                    now
                );
            } catch (scheduleErr) {
                console.error('[sendAssistantMessage] Schedule match error:', scheduleErr);
                matchResult = {
                    status: 'unavailable',
                    reasonCode: 'schedule_match_error',
                    message: getLocalizedMessage('unavailable', targetLang),
                    offers: [],
                };
            }

            // 8. Commit chat turn transactionally
            const commitResult = await commitAssistantTurn(db, {
                patientId: callerUid,
                generationId: reservation.generationId,
                reservedRevision: reservation.reservedRevision,
                turnId: reservation.turnId,
                assistantMessage: matchResult.message,
                status: matchResult.status,
                reasonCode: matchResult.reasonCode,
                replyLanguage: targetLang,
                offers: matchResult.offers,
                searchPreferences: {
                    departmentKey: structuredIntent.departmentKey || null,
                    doctorId: structuredIntent.doctorId || null,
                    doctorName: structuredIntent.doctorName || null,
                    preferredDate: structuredIntent.preferredDate || null,
                    preferredTimeSlot: structuredIntent.preferredTimeSlot || null,
                    timeFilter: structuredIntent.timeFilter || null,
                },
                now,
            });

            if (!commitResult.committed) {
                // Lost ownership or cleared during network processing
                return {
                    success: false,
                    status: 'cancelled',
                    reasonCode: 'session_reset_concurrently',
                    message: getLocalizedMessage('cancelled', targetLang),
                    replyLanguage: targetLang,
                    offers: [],
                    revision: 0,
                };
            }

            committed = true;
            return commitResult.result!;
        } finally {
            if (!committed) {
                try {
                    await releaseAssistantTurn(db, callerUid, reservation.turnId);
                } catch (releaseErr) {
                    console.error('[sendAssistantMessage] Failed to release turn reservation:', releaseErr);
                }
            }
        }
        }
    );

/**
 * Fetches the saved chat history and refreshes availability of existing offers
 * WITHOUT invoking Gemini. Resumes prior preferences if offers have expired.
 */
export const getAssistantHistory = functions.https.onCall(
    async (
        request: functions.https.CallableRequest<unknown>
    ): Promise<GetAssistantHistoryResult> => {
        const adminProjectId = admin.app().options.projectId;
        if (process.env.AI_OFFLINE_SYNTHETIC_TESTING === 'true') {
            const syntheticCheck = checkSyntheticTestingConditions(adminProjectId);
            if (!syntheticCheck.allowed) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    `Synthetic testing rejected: ${syntheticCheck.rejectedReason}`
                );
            }
        }

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePatientRole(callerDoc);

        const now = new Date();
        const gate = evaluateTransmissionGate(adminProjectId);
        if (!gate.enabled) {
            const { doc: chatDoc } = await getPatientChatDoc(db, callerUid, now);
            return {
                success: true,
                messages: chatDoc.messages,
                offers: [],
                revision: chatDoc.revision,
                resetAt: null,
                status: 'disabled',
                reasonCode: gate.reasonCode,
            };
        }

        const [deptsSnap, doctorsSnap] = await Promise.all([
            db.collection('departments').where('isActive', '==', true).limit(51).get(),
            db.collection('doctors').where('isActive', '==', true).where('isAvailable', '==', true).limit(101).get(),
        ]);

        if (deptsSnap.docs.length > 50 || doctorsSnap.docs.length > 100) {
            const { doc: chatDoc } = await getPatientChatDoc(db, callerUid, now);
            return {
                success: true,
                messages: chatDoc.messages,
                offers: [],
                revision: chatDoc.revision,
                resetAt: chatDoc.resetAt || null,
                status: 'unavailable',
                reasonCode: 'catalog_overflow',
            };
        }

        const departments: DepartmentCandidate[] = deptsSnap.docs.map((d) => ({
            key: d.data().key as string,
            name: (d.data().name as string) || (d.data().key as string),
        }));

        const doctors: DoctorCandidate[] = doctorsSnap.docs.map((d) => ({
            id: d.id,
            data: d.data(),
        }));

        const pacificDateKey = getPacificDateKey(now);
        const [projectQuotaSnap, refreshed, chatDocResult] = await Promise.all([
            db.collection('assistant_project_quota').doc(pacificDateKey).get(),
            refreshPatientChatHistory(db, callerUid, departments, doctors, now),
            getPatientChatDoc(db, callerUid, now),
        ]);
        const chatDoc = chatDocResult.doc;
        const projectQuotaData = projectQuotaSnap.data();
        const isProjectDailyExhausted =
            projectQuotaData?.isDailyExhausted === true ||
            (projectQuotaData?.requestCount || 0) >= ASSISTANT_CONFIG.DEFAULT_RPD_CAP;

        let status = chatDoc.lastResult?.status || null;
        let reasonCode = chatDoc.lastResult?.reasonCode || null;
        let resetAt = chatDoc.resetAt || chatDoc.lastResult?.resetAt || null;

        if (!isProjectDailyExhausted && status === 'daily_limit' &&
            resetAt && Date.parse(resetAt) <= now.getTime()) {
            status = 'ready';
            reasonCode = null;
            resetAt = null;
        }

        if (isProjectDailyExhausted) {
            status = 'daily_limit';
            reasonCode = projectQuotaData?.isDailyExhausted === true
                ? 'upstream_daily_limit_reached'
                : 'local_daily_cap_reached';
            resetAt = getNextPacificMidnightUtc(now);
        }

        return {
            success: true,
            messages: refreshed.messages,
            offers: refreshed.offers,
            revision: refreshed.revision,
            resetAt,
            status: status || 'ready',
            reasonCode,
        };
    }
);

/**
 * Clears the caller's saved chat history and active offers.
 * Increments revision and resets generation to prevent late completions from resurrecting deleted history.
 */
export const clearAssistantHistory = functions.https.onCall(
    async (
        request: functions.https.CallableRequest<unknown>
    ): Promise<ClearAssistantHistoryResult> => {
        const adminProjectId = admin.app().options.projectId;
        if (process.env.AI_OFFLINE_SYNTHETIC_TESTING === 'true') {
            const syntheticCheck = checkSyntheticTestingConditions(adminProjectId);
            if (!syntheticCheck.allowed) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    `Synthetic testing rejected: ${syntheticCheck.rejectedReason}`
                );
            }
        }

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePatientRole(callerDoc);

        await clearPatientChat(db, callerUid, new Date());

        return {
            success: true,
            message: 'Chat history cleared successfully.',
        };
    }
);

/**
 * Explicitly confirms and books an assistant appointment offer.
 * Delegates to the unified createAppointmentCore transaction which enforces ownership,
 * offer expiry, doctor schedule duration, day coordination, canonical slot locking,
 * duration-aware active appointment overlap, idempotency, and offer consumption.
 */
export const confirmAssistantAppointment = functions.https.onCall(
    async (
        request: functions.https.CallableRequest<ConfirmAssistantAppointmentData>
    ): Promise<ConfirmAssistantAppointmentResult> => {
        const adminProjectId = admin.app().options.projectId;
        if (process.env.AI_OFFLINE_SYNTHETIC_TESTING === 'true') {
            const syntheticCheck = checkSyntheticTestingConditions(adminProjectId);
            if (!syntheticCheck.allowed) {
                throw new functions.https.HttpsError(
                    'failed-precondition',
                    `Synthetic testing rejected: ${syntheticCheck.rejectedReason}`
                );
            }
        }

        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePatientRole(callerDoc);

        const data = request.data;
        if (!data || typeof data.offerId !== 'string' || !data.offerId.trim()) {
            throw new functions.https.HttpsError('invalid-argument', 'offerId is required.');
        }

        if (data.confirmed !== true) {
            throw new functions.https.HttpsError('invalid-argument', 'confirmed must be explicitly true.');
        }

        const res = await createAppointmentCore(callerUid, callerDoc.data() || {}, {
            patientId: callerUid,
            offerId: data.offerId.trim(),
            confirmed: true,
            notes: typeof data.notes === 'string' ? data.notes : undefined,
        });

        return {
            success: res.success,
            appointmentId: res.appointmentId,
            bookingReference: res.bookingReference,
            qrCode: res.qrCode,
            isExisting: res.isExisting,
        };
    }
);


