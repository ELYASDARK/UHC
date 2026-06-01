import * as functions from 'firebase-functions';

export const MIN_PASSWORD_LENGTH = 8;
export const MIN_PASSWORD_ERROR = `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
export const MIN_PASSWORD_ERROR_LONG = `Password must be at least ${MIN_PASSWORD_LENGTH} characters long.`;

export function toHttpsError(
    error: unknown,
    fallbackMessage: string
): functions.https.HttpsError {
    if (error instanceof functions.https.HttpsError) {
        return error;
    }

    const maybe = error as { code?: string; message?: string } | undefined;
    const code = maybe?.code;

    if (code === 'auth/user-not-found') {
        return new functions.https.HttpsError(
            'not-found',
            'Target auth user not found.'
        );
    }
    if (code === 'auth/invalid-password' || code === 'auth/weak-password') {
        return new functions.https.HttpsError(
            'invalid-argument',
            MIN_PASSWORD_ERROR
        );
    }

    const message = maybe?.message || fallbackMessage;
    return new functions.https.HttpsError('internal', message);
}

export function errorMessage(error: unknown): string {
    if (error instanceof Error) return error.message;
    if (error && typeof error === 'object' && 'message' in error) {
        const message = (error as { message?: unknown }).message;
        if (typeof message === 'string') return message;
    }
    return String(error);
}
