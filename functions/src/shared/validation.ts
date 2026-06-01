import * as functions from 'firebase-functions';

export function requireTargetUserId(value: unknown, label: string): string {
    if (typeof value !== 'string') {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `${label} must be a string.`
        );
    }
    const trimmed = value.trim();
    if (trimmed.length < 1 || trimmed.length > 128 || trimmed.includes('/')) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            `${label} is invalid.`
        );
    }
    return trimmed;
}
