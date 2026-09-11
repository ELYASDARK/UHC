import { AssistantConfig } from './types';

export const ASSISTANT_CONFIG: AssistantConfig = {
    MODEL_NAME: 'gemini-3.5-flash-lite',
    MAX_MESSAGE_LENGTH: 500,
    MAX_CHAT_MESSAGES: 20,
    MAX_ACTIVE_OFFERS: 6,
    OFFER_EXPIRATION_MINUTES: 10,
    CHAT_RETENTION_DAYS: 7,
    MAX_FUTURE_DAYS: 30,
    DEFAULT_RPD_CAP: 500,
    DEFAULT_RPM_CAP: 15,
    USER_RPM_CAP: 10,
    PACIFIC_TIME_ZONE: 'America/Los_Angeles',
    CLINIC_TIME_ZONE: 'Asia/Baghdad',
    DAILY_EXHAUSTION_MESSAGE: 'The assistant has reached today’s limit.',
    API_ENDPOINT_BASE: 'https://generativelanguage.googleapis.com/v1beta/models',
    REQUEST_TIMEOUT_MS: 28000,
};

export const REQUIRED_DEMO_PROJECT_ID = 'demo-uhc-test';

export interface SyntheticGateCheckResult {
    allowed: boolean;
    rejectedReason?: string;
}

export interface ParsedHostPort {
    host: string;
    port: number;
}

/**
 * Strictly parses and validates a host:port string against permitted loopback addresses.
 * Rejects loose prefixes, non-numeric or out-of-range ports, and remote addresses.
 */
export function parseLoopbackHostAndPort(hostString?: string): ParsedHostPort | null {
    if (!hostString || typeof hostString !== 'string') return null;
    const trimmed = hostString.trim();

    // Check for bracketed IPv6: e.g. [::1]:8080
    const ipv6BracketMatch = trimmed.match(/^\[([a-fA-F0-9:]+)\]:(\d+)$/);
    if (ipv6BracketMatch) {
        const host = ipv6BracketMatch[1].toLowerCase();
        const port = parseInt(ipv6BracketMatch[2], 10);
        if (host === '::1' && port > 0 && port <= 65535) {
            return { host, port };
        }
        return null;
    }

    // Check standard host:port: e.g. localhost:8080, 127.0.0.1:8080, or ::1:8080
    const hostPortMatch = trimmed.match(/^([a-zA-Z0-9.-]+|::1):(\d+)$/);
    if (hostPortMatch) {
        const host = hostPortMatch[1].toLowerCase();
        const port = parseInt(hostPortMatch[2], 10);
        if ((host === 'localhost' || host === '127.0.0.1' || host === '::1') && port > 0 && port <= 65535) {
            return { host, port };
        }
        return null;
    }

    return null;
}

/**
 * Returns true if the host string is a strictly validated loopback address with valid port.
 */
export function isLoopbackHost(hostString?: string): boolean {
    return parseLoopbackHostAndPort(hostString) !== null;
}

/**
 * Validates that all environment and admin project identifiers strictly agree on demo-uhc-test.
 * Rejects inconsistent, empty, or live production project identifiers (such as uhca-20800).
 */
export function validateDemoProjectConsistency(adminProjectId?: string): { valid: boolean; rejectedReason?: string } {
    const gcloud = process.env.GCLOUD_PROJECT?.trim();
    const googleCloud = process.env.GOOGLE_CLOUD_PROJECT?.trim();

    let firebaseConfigProject: string | undefined;
    if (process.env.FIREBASE_CONFIG) {
        try {
            const parsed = JSON.parse(process.env.FIREBASE_CONFIG);
            if (parsed && typeof parsed.projectId === 'string') {
                firebaseConfigProject = parsed.projectId.trim();
            }
        } catch {
            return { valid: false, rejectedReason: 'malformed_firebase_config' };
        }
    }

    // Every present project identifier MUST strictly match REQUIRED_DEMO_PROJECT_ID
    if (gcloud && gcloud !== REQUIRED_DEMO_PROJECT_ID) {
        return { valid: false, rejectedReason: `gcloud_project_mismatch:${gcloud}` };
    }
    if (googleCloud && googleCloud !== REQUIRED_DEMO_PROJECT_ID) {
        return { valid: false, rejectedReason: `google_cloud_project_mismatch:${googleCloud}` };
    }
    if (firebaseConfigProject && firebaseConfigProject !== REQUIRED_DEMO_PROJECT_ID) {
        return { valid: false, rejectedReason: `firebase_config_project_mismatch:${firebaseConfigProject}` };
    }
    if (adminProjectId && adminProjectId !== REQUIRED_DEMO_PROJECT_ID) {
        return { valid: false, rejectedReason: `admin_project_mismatch:${adminProjectId}` };
    }

    // At least one project identifier MUST be explicitly set to REQUIRED_DEMO_PROJECT_ID
    const effectiveProject = gcloud || googleCloud || firebaseConfigProject || adminProjectId;
    if (!effectiveProject || effectiveProject !== REQUIRED_DEMO_PROJECT_ID) {
        return { valid: false, rejectedReason: 'demo_project_required' };
    }

    return { valid: true };
}

export function getProjectId(): string {
    if (process.env.GCLOUD_PROJECT) {
        return process.env.GCLOUD_PROJECT.trim();
    }
    if (process.env.FIREBASE_CONFIG) {
        try {
            const parsed = JSON.parse(process.env.FIREBASE_CONFIG);
            if (parsed && typeof parsed.projectId === 'string') {
                return parsed.projectId.trim();
            }
        } catch {
            // Ignore parse error
        }
    }
    return '';
}

/**
 * Validates strict preconditions for local offline synthetic testing.
 * MUST satisfy all 5 criteria:
 * 1. Explicit local opt-in via AI_OFFLINE_SYNTHETIC_TESTING='true'
 * 2. Running inside Functions emulator (FUNCTIONS_EMULATOR='true')
 * 3. Connected to strictly parsed loopback Firestore emulator (FIRESTORE_EMULATOR_HOST)
 * 4. Connected to strictly parsed loopback Auth emulator (FIREBASE_AUTH_EMULATOR_HOST)
 * 5. All project environment identifiers strictly match 'demo-uhc-test'
 *
 * Any mismatch or live configuration is rejected (fail-closed) to prevent
 * synthetic mode from ever becoming a production bypass.
 */
export function checkSyntheticTestingConditions(adminProjectId?: string): SyntheticGateCheckResult {
    const isExplicitOptIn = process.env.AI_OFFLINE_SYNTHETIC_TESTING === 'true';
    if (!isExplicitOptIn) {
        return { allowed: false, rejectedReason: 'opt_in_missing' };
    }

    const isFunctionsEmulator = process.env.FUNCTIONS_EMULATOR === 'true';
    if (!isFunctionsEmulator) {
        return { allowed: false, rejectedReason: 'functions_emulator_required' };
    }

    const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
    if (!firestoreHost || !isLoopbackHost(firestoreHost)) {
        return { allowed: false, rejectedReason: 'loopback_firestore_emulator_required' };
    }

    const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
    if (!authHost || !isLoopbackHost(authHost)) {
        return { allowed: false, rejectedReason: 'loopback_auth_emulator_required' };
    }

    const projectCheck = validateDemoProjectConsistency(adminProjectId);
    if (!projectCheck.valid) {
        return { allowed: false, rejectedReason: projectCheck.rejectedReason };
    }

    return { allowed: true };
}

export interface TransmissionGateStatus {
    enabled: boolean;
    isSynthetic?: boolean;
    reasonCode?: 'assistant_disabled' | 'assistant_unconfigured' | 'synthetic_mismatch_rejected';
    message?: string;
    apiKey?: string;
}

/**
 * Evaluates the strict server transmission release gate.
 * External transmission to AI is DISABLED BY DEFAULT until
 * both operational enablement and privacy/terms clearance are explicitly set.
 *
 * When AI_OFFLINE_SYNTHETIC_TESTING is explicitly enabled, runs in synthetic
 * mode ONLY if all emulator, loopback host, and demo project checks pass.
 * Mismatched or live configurations fail closed.
 */
export function evaluateTransmissionGate(adminProjectId?: string): TransmissionGateStatus {
    // 1. Check if offline synthetic testing is requested
    const isSyntheticOptIn = process.env.AI_OFFLINE_SYNTHETIC_TESTING === 'true';
    if (isSyntheticOptIn) {
        const syntheticCheck = checkSyntheticTestingConditions(adminProjectId);
        if (syntheticCheck.allowed) {
            return {
                enabled: true,
                isSynthetic: true,
                message: 'Offline synthetic interpretation active for local emulator testing.',
            };
        }

        // Mismatched or live configuration: fail closed immediately.
        // Never fall through to the live Gemini path!
        return {
            enabled: false,
            isSynthetic: false,
            reasonCode: 'synthetic_mismatch_rejected',
            message: `Offline synthetic testing rejected: ${syntheticCheck.rejectedReason}. Must run with loopback emulators on project '${REQUIRED_DEMO_PROJECT_ID}'.`,
        };
    }

    // 2. Production transmission gate (DISABLED BY DEFAULT)
    const isOperationallyEnabled = process.env.AI_ASSISTANT_ENABLED === 'true';
    const isPrivacyGateAccepted = process.env.AI_PRIVACY_RELEASE_GATE_ACCEPTED === 'true';
    const apiKey = (process.env.GEMINI_API_KEY || '').trim();

    if (!isOperationallyEnabled || !isPrivacyGateAccepted) {
        return {
            enabled: false,
            isSynthetic: false,
            reasonCode: 'assistant_disabled',
            message: 'The AI appointment assistant is currently disabled by administrator policy.',
        };
    }

    if (!apiKey) {
        return {
            enabled: false,
            isSynthetic: false,
            reasonCode: 'assistant_unconfigured',
            message: 'The AI appointment assistant is enabled but the API key is not configured.',
        };
    }

    return {
        enabled: true,
        isSynthetic: false,
        apiKey,
    };
}
