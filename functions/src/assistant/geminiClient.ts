import { ASSISTANT_CONFIG } from './config';
import {
    DepartmentCatalogEntry,
    DoctorCatalogEntry,
    StructuredIntent,
} from './types';

export interface GeminiClientOptions {
    apiKey: string;
    fetchImpl?: typeof fetch;
}

export interface CallGeminiParams {
    userMessage: string;
    chatHistory: Array<{ sender: 'patient' | 'assistant'; text: string }>;
    baghdadDateString: string;
    departments: DepartmentCatalogEntry[];
    doctors: DoctorCatalogEntry[];
    clientLocale?: 'en' | 'ar' | 'ckb';
}

export interface GeminiCallResult {
    parsedIntent?: StructuredIntent;
    httpStatus?: number;
    errorBody?: unknown;
    networkError?: Error;
}

const SYSTEM_PROMPT = `You are the scheduling interpreter for the UHC (University Health Center) appointment assistant.
Your ONLY role is to parse scheduling requests into structured filter fields for real clinic database lookup.

SAFETY RULES:
1. You are NOT a medical doctor. You CANNOT give medical advice, triage, diagnose illnesses, or recommend medications.
2. If the user asks for medical advice, diagnose symptoms, or emergency help, set intent="out_of_scope" and outOfScopeReason appropriately.
3. You do NOT generate appointment confirmations or conversational prose. You only extract structured search filters.
4. Do NOT execute bookings. Only extract desired departmentKey, doctorId, doctorName, preferredDate (YYYY-MM-DD), preferredTimeSlot, timeFilter, and replyLanguage.`;

const RESPONSE_SCHEMA = {
    type: 'OBJECT',
    properties: {
        intent: {
            type: 'STRING',
            enum: ['book_appointment', 'inquire_schedule', 'clarify', 'out_of_scope'],
        },
        clarificationReason: {
            type: 'STRING',
            enum: [
                'missing_date',
                'ambiguous_doctor',
                'unknown_department',
                'unknown_doctor',
                'no_slots',
                'general',
            ],
        },
        outOfScopeReason: {
            type: 'STRING',
            enum: ['medical_advice', 'emergency', 'prescription', 'general'],
        },
        departmentKey: { type: 'STRING' },
        doctorId: { type: 'STRING' },
        doctorName: { type: 'STRING' },
        preferredDate: { type: 'STRING' },
        preferredTimeSlot: { type: 'STRING' },
        timeFilter: {
            type: 'STRING',
            enum: ['morning', 'afternoon', 'evening', 'any'],
        },
        replyLanguage: {
            type: 'STRING',
            enum: ['en', 'ar', 'ckb'],
        },
    },
    required: ['intent', 'replyLanguage'],
};

export function extractAndParseJson(text: string): unknown {
    const trimmed = text.trim();
    if (trimmed.startsWith('```')) {
        const lines = trimmed.split('\n');
        const contentLines = lines.slice(1, lines[lines.length - 1].trim().startsWith('```') ? -1 : undefined);
        return JSON.parse(contentLines.join('\n').trim());
    }
    return JSON.parse(trimmed);
}

export function validateStructuredIntent(
    obj: unknown,
    defaultLocale: 'en' | 'ar' | 'ckb' = 'en'
): StructuredIntent | null {
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) {
        return null;
    }
    const raw = obj as Record<string, unknown>;
    const allowedKeys = new Set([
        'intent',
        'clarificationReason',
        'outOfScopeReason',
        'departmentKey',
        'doctorId',
        'doctorName',
        'preferredDate',
        'preferredTimeSlot',
        'timeFilter',
        'replyLanguage',
    ]);
    for (const key of Object.keys(raw)) {
        if (!allowedKeys.has(key)) {
            return null;
        }
    }
    const allowedIntents = ['book_appointment', 'inquire_schedule', 'clarify', 'out_of_scope'] as const;
    const allowedClarifyReasons = [
        'missing_date',
        'ambiguous_doctor',
        'unknown_department',
        'unknown_doctor',
        'no_slots',
        'general',
    ] as const;
    const allowedOutOfScopeReasons = [
        'medical_advice',
        'emergency',
        'prescription',
        'general',
    ] as const;
    const allowedTimeFilters = ['morning', 'afternoon', 'evening', 'any'] as const;

    if (typeof raw.intent !== 'string' || !allowedIntents.includes(raw.intent as typeof allowedIntents[number])) {
        return null;
    }

    const intent = raw.intent as typeof allowedIntents[number];

    let replyLanguage: 'en' | 'ar' | 'ckb' = defaultLocale;
    if (raw.replyLanguage !== undefined && raw.replyLanguage !== null) {
        if (typeof raw.replyLanguage !== 'string') {
            return null;
        }
        const normLang = raw.replyLanguage.trim().toLowerCase();
        if (normLang === 'ku' || normLang === 'ckb') {
            replyLanguage = 'ckb';
        } else if (normLang === 'ar') {
            replyLanguage = 'ar';
        } else if (normLang === 'en') {
            replyLanguage = 'en';
        } else {
            return null;
        }
    }

    let clarificationReason: StructuredIntent['clarificationReason'] = null;
    if (raw.clarificationReason !== undefined && raw.clarificationReason !== null) {
        if (
            typeof raw.clarificationReason !== 'string' ||
            !allowedClarifyReasons.includes(raw.clarificationReason as typeof allowedClarifyReasons[number])
        ) {
            return null;
        }
        clarificationReason = raw.clarificationReason as typeof allowedClarifyReasons[number];
    }

    let outOfScopeReason: StructuredIntent['outOfScopeReason'] = null;
    if (raw.outOfScopeReason !== undefined && raw.outOfScopeReason !== null) {
        if (
            typeof raw.outOfScopeReason !== 'string' ||
            !allowedOutOfScopeReasons.includes(raw.outOfScopeReason as typeof allowedOutOfScopeReasons[number])
        ) {
            return null;
        }
        outOfScopeReason = raw.outOfScopeReason as typeof allowedOutOfScopeReasons[number];
    }

    let departmentKey: string | null = null;
    if (raw.departmentKey !== undefined && raw.departmentKey !== null) {
        if (typeof raw.departmentKey !== 'string' || raw.departmentKey.length > 128) {
            return null;
        }
        departmentKey = raw.departmentKey.trim() || null;
    }

    let doctorId: string | null = null;
    if (raw.doctorId !== undefined && raw.doctorId !== null) {
        if (typeof raw.doctorId !== 'string' || raw.doctorId.length > 128) {
            return null;
        }
        doctorId = raw.doctorId.trim() || null;
    }

    let doctorName: string | null = null;
    if (raw.doctorName !== undefined && raw.doctorName !== null) {
        if (typeof raw.doctorName !== 'string' || raw.doctorName.length > 128) {
            return null;
        }
        doctorName = raw.doctorName.trim() || null;
    }

    let preferredDate: string | null = null;
    if (raw.preferredDate !== undefined && raw.preferredDate !== null) {
        if (typeof raw.preferredDate !== 'string') {
            return null;
        }
        const trimmedDate = raw.preferredDate.trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmedDate)) {
            return null;
        }
        preferredDate = trimmedDate;
    }

    let preferredTimeSlot: string | null = null;
    if (raw.preferredTimeSlot !== undefined && raw.preferredTimeSlot !== null) {
        if (typeof raw.preferredTimeSlot !== 'string' || raw.preferredTimeSlot.length > 64) {
            return null;
        }
        preferredTimeSlot = raw.preferredTimeSlot.trim() || null;
    }

    let timeFilter: 'morning' | 'afternoon' | 'evening' | 'any' | null = null;
    if (raw.timeFilter !== undefined && raw.timeFilter !== null) {
        if (
            typeof raw.timeFilter !== 'string' ||
            !allowedTimeFilters.includes(raw.timeFilter as typeof allowedTimeFilters[number])
        ) {
            return null;
        }
        timeFilter = raw.timeFilter as typeof allowedTimeFilters[number];
    }

    return {
        intent,
        clarificationReason,
        outOfScopeReason,
        departmentKey,
        doctorId,
        doctorName,
        preferredDate,
        preferredTimeSlot,
        timeFilter,
        replyLanguage,
    };
}

export class GeminiAssistantClient {
    private readonly apiKey: string;
    private readonly fetchImpl: typeof fetch;

    constructor(options: GeminiClientOptions) {
        this.apiKey = options.apiKey;
        this.fetchImpl = options.fetchImpl || globalThis.fetch;
    }

    async interpretSchedulingRequest(params: CallGeminiParams): Promise<GeminiCallResult> {
        // Strict guard: GeminiAssistantClient must NEVER be invoked when synthetic testing is active
        if (process.env.AI_OFFLINE_SYNTHETIC_TESTING === 'true') {
            throw new Error(
                'Direct GeminiAssistantClient invocation rejected: AI_OFFLINE_SYNTHETIC_TESTING is active. ' +
                'External AI calls are strictly forbidden in offline synthetic mode. Use SyntheticSchedulingInterpreter.'
            );
        }

        const endpoint = `${ASSISTANT_CONFIG.API_ENDPOINT_BASE}/${ASSISTANT_CONFIG.MODEL_NAME}:generateContent`;

        const catalogContext = {
            todayInBaghdad: params.baghdadDateString,
            clinicTimeZone: ASSISTANT_CONFIG.CLINIC_TIME_ZONE,
            departments: params.departments.map((d) => ({ key: d.key, name: d.name })),
            doctors: params.doctors.map((doc) => ({
                id: doc.doctorId,
                name: doc.name,
                specialization: doc.specialization,
                department: doc.department,
                availableDays: doc.availableDays,
            })),
        };

        const boundedHistory = params.chatHistory.slice(-4).map((msg) => ({
            role: msg.sender === 'patient' ? 'user' : 'model',
            parts: [{ text: msg.text.substring(0, 200) }],
        }));

        const currentTurn = {
            role: 'user',
            parts: [{
                text: `Catalog Data:\n${JSON.stringify(catalogContext)}\n\nPatient message: "${params.userMessage.substring(0, ASSISTANT_CONFIG.MAX_MESSAGE_LENGTH)}"`,
            }],
        };

        const contents = [...boundedHistory, currentTurn];

        const requestPayload = {
            systemInstruction: {
                parts: [{ text: SYSTEM_PROMPT }],
            },
            contents,
            generationConfig: {
                responseMimeType: 'application/json',
                responseSchema: RESPONSE_SCHEMA,
                temperature: 0.0,
                maxOutputTokens: 400,
            },
        };

        const fallbackLocale = params.clientLocale || 'en';
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), ASSISTANT_CONFIG.REQUEST_TIMEOUT_MS);

        try {
            const response = await this.fetchImpl(endpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'x-goog-api-key': this.apiKey,
                },
                body: JSON.stringify(requestPayload),
                signal: controller.signal,
            });

            let rawText = '';
            const maxResponseBytes = 65536;
            if (response.body && typeof (response.body as { getReader?: unknown }).getReader === 'function') {
                const reader = (response.body as ReadableStream<Uint8Array>).getReader();
                const decoder = new TextDecoder();
                let totalBytes = 0;
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    if (value) {
                        totalBytes += value.byteLength;
                        if (totalBytes > maxResponseBytes) {
                            await reader.cancel();
                            return {
                                httpStatus: 500,
                                errorBody: { error: { message: 'Model response exceeded size limit' } },
                            };
                        }
                        rawText += decoder.decode(value, { stream: true });
                    }
                }
                rawText += decoder.decode();
            } else {
                rawText = await response.text();
                if (rawText.length > maxResponseBytes) {
                    return {
                        httpStatus: 500,
                        errorBody: { error: { message: 'Model response exceeded size limit' } },
                    };
                }
            }

            if (!response.ok) {
                let errorBody: unknown;
                try {
                    errorBody = JSON.parse(rawText);
                } catch {
                    errorBody = rawText;
                }
                console.error('[GeminiAssistantClient] HTTP Error status:', response.status);
                return {
                    httpStatus: response.status,
                    errorBody,
                };
            }

            let parsedBody: {
                candidates?: Array<{
                    content?: {
                        parts?: Array<{ text?: string }>;
                    };
                }>;
            };

            try {
                parsedBody = JSON.parse(rawText);
            } catch {
                return {
                    parsedIntent: {
                        intent: 'clarify',
                        clarificationReason: 'general',
                        replyLanguage: fallbackLocale,
                    },
                };
            }

            const candidateText = parsedBody?.candidates?.[0]?.content?.parts?.[0]?.text;
            if (!candidateText) {
                return {
                    parsedIntent: {
                        intent: 'clarify',
                        clarificationReason: 'general',
                        replyLanguage: fallbackLocale,
                    },
                };
            }

            try {
                const intentObj = extractAndParseJson(candidateText);
                const validated = validateStructuredIntent(intentObj, fallbackLocale);
                return {
                    parsedIntent: validated || {
                        intent: 'clarify',
                        clarificationReason: 'general',
                        replyLanguage: fallbackLocale,
                    },
                };
            } catch {
                return {
                    parsedIntent: {
                        intent: 'clarify',
                        clarificationReason: 'general',
                        replyLanguage: fallbackLocale,
                    },
                };
            }
        } catch (err: unknown) {
            console.error('[GeminiAssistantClient] Exception/Network Error:', err);
            return {
                networkError: err instanceof Error ? err : new Error(String(err)),
            };
        } finally {
            clearTimeout(timeoutId);
        }
    }
}
