export type AssistantMessageStatus =
    | 'ready'
    | 'clarify'
    | 'out_of_scope'
    | 'daily_limit'
    | 'throttled'
    | 'unavailable'
    | 'disabled'
    | 'cancelled';

export type AssistantReplyLanguage = 'en' | 'ar' | 'ckb';

export interface AssistantOffer {
    offerId: string;
    doctorId: string;
    doctorName: string;
    department: string;
    departmentName?: string;
    appointmentDate: string; // Canonical YYYY-MM-DD
    timeSlot: string; // 'HH:MM - HH:MM' or 'HH:MM'
    expiresAt: string; // ISO 8601 UTC string (10 minutes from creation)
    isAvailable: boolean;
}

export interface AssistantChatMessage {
    id: string;
    sender: 'patient' | 'assistant';
    text: string;
    status: AssistantMessageStatus;
    reasonCode?: string | null;
    offerIds?: string[];
    createdAt: string; // ISO 8601 UTC string
}

export interface SearchPreferences {
    departmentKey?: string | null;
    doctorId?: string | null;
    doctorName?: string | null;
    preferredDate?: string | null;
    preferredTimeSlot?: string | null;
    timeFilter?: string | null;
}

export interface AssistantChatDocument {
    patientId: string;
    generationId: string;
    revision: number;
    inFlightTurnId?: string | null;
    lastClientRequestId?: string | null;
    lastClientRequestHash?: string | null;
    lastResult?: SendAssistantMessageResult | null;
    messages: AssistantChatMessage[];
    offers: AssistantOffer[];
    searchPreferences?: SearchPreferences | null;
    resetAt?: string | null;
    createdAt: FirebaseFirestore.Timestamp;
    updatedAt: FirebaseFirestore.Timestamp;
    expiresAt: FirebaseFirestore.Timestamp;
}

export interface SendAssistantMessageData {
    message: string;
    locale?: string;
    clientRequestId?: string;
}

export interface SendAssistantMessageResult {
    success: boolean;
    status: AssistantMessageStatus;
    reasonCode?: string | null;
    message: string;
    replyLanguage: AssistantReplyLanguage;
    offers: AssistantOffer[];
    resetAt?: string | null;
    revision: number;
}

export interface GetAssistantHistoryResult {
    success: boolean;
    messages: AssistantChatMessage[];
    offers: AssistantOffer[];
    revision: number;
    resetAt?: string | null;
    status?: AssistantMessageStatus | null;
    reasonCode?: string | null;
}

export interface ClearAssistantHistoryResult {
    success: boolean;
    message: string;
}

export interface ConfirmAssistantAppointmentData {
    offerId: string;
    confirmed: boolean;
    notes?: string | null;
    idempotencyKey?: string;
}

export interface ConfirmAssistantAppointmentResult {
    success: boolean;
    appointmentId: string;
    bookingReference: string;
    qrCode?: string;
    isExisting?: boolean;
}

export interface StructuredIntent {
    intent: 'book_appointment' | 'inquire_schedule' | 'clarify' | 'out_of_scope';
    clarificationReason?: 'missing_date' | 'ambiguous_doctor' | 'unknown_department' | 'unknown_doctor' | 'no_slots' | 'general' | null;
    outOfScopeReason?: 'medical_advice' | 'emergency' | 'prescription' | 'general' | null;
    departmentKey?: string | null;
    doctorId?: string | null;
    doctorName?: string | null;
    preferredDate?: string | null;
    preferredTimeSlot?: string | null;
    timeFilter?: 'morning' | 'afternoon' | 'evening' | string | null;
    replyLanguage: AssistantReplyLanguage;
}

export interface DoctorCatalogEntry {
    doctorId: string;
    name: string;
    specialization: string;
    department: string;
    availableDays: string[];
}

export interface DepartmentCatalogEntry {
    key: string;
    name: string;
}

export interface AssistantConfig {
    MODEL_NAME: string;
    MAX_MESSAGE_LENGTH: number;
    MAX_CHAT_MESSAGES: number;
    MAX_ACTIVE_OFFERS: number;
    OFFER_EXPIRATION_MINUTES: number;
    CHAT_RETENTION_DAYS: number;
    MAX_FUTURE_DAYS: number;
    DEFAULT_RPD_CAP: number;
    DEFAULT_RPM_CAP: number;
    USER_RPM_CAP: number;
    PACIFIC_TIME_ZONE: string;
    CLINIC_TIME_ZONE: string;
    DAILY_EXHAUSTION_MESSAGE: string;
    API_ENDPOINT_BASE: string;
    REQUEST_TIMEOUT_MS: number;
}
