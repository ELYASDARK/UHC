import { randomUUID } from 'crypto';
import { FieldValue } from 'firebase-admin/firestore';
import * as functions from 'firebase-functions';
import { db } from '../firebase';

const lockedMessage = 'Account management is locked for an account change. Contact a Super Admin for reconciliation before retrying.';
const lockedDetails = { reason: 'account-mutation-locked' };

export function requireIdleAccount(profile: FirebaseFirestore.DocumentData): void {
    if (profile.accountMutationId) {
        throw new functions.https.HttpsError('aborted',
            lockedMessage, lockedDetails);
    }
}

// Auth and Firestore cannot commit together. Role changes honor this durable
// guard; it deliberately never expires while an Auth request may still finish.
export async function withAccountMutation<T>(options: {
    userId?: string;
    doctorId?: string;
    roles: string[];
    mutate: (uid: string, profile: FirebaseFirestore.DocumentData) => Promise<T>;
}): Promise<T> {
    const mutationId = randomUUID();
    const account = await db.runTransaction(async tx => {
        const doctor = options.doctorId
            ? await tx.get(db.collection('doctors').doc(options.doctorId)) : null;
        const uid = doctor ? doctor.data()?.userId : options.userId;
        if (typeof uid !== 'string' || !uid || uid.includes('/') || uid.startsWith('sample_')) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor has no valid linked account.');
        }
        const ref = db.collection('users').doc(uid);
        const snapshot = await tx.get(ref);
        const profile = snapshot.data();
        if (!profile || !options.roles.includes(profile.role)) {
            throw new functions.https.HttpsError('failed-precondition', 'Linked account role is invalid.');
        }
        requireIdleAccount(profile);
        tx.update(ref, { accountMutationId: mutationId });
        return { uid, ref, profile };
    });
    let release = false;
    try {
        const result = await options.mutate(account.uid, account.profile);
        release = true;
        return result;
    } catch (error) {
        // An ambiguous Auth/Firestore failure may leave an Auth write in flight.
        // Preserve the guard for operator reconciliation instead of permitting
        // promotion while that write could still complete.
        release = (error instanceof functions.https.HttpsError &&
            ['invalid-argument', 'unauthenticated', 'permission-denied', 'not-found', 'failed-precondition', 'already-exists'].includes(error.code)) ||
            ['auth/invalid-email', 'auth/email-already-exists', 'auth/invalid-password', 'auth/user-not-found']
                .includes((error as { code?: string }).code || '');
        // Classification above uses the original failure. Only then return a
        // stable recovery reason; clients must not show arbitrary server prose.
        if (!release) throw new functions.https.HttpsError('internal', lockedMessage, lockedDetails);
        throw error;
    } finally {
        if (release) await db.runTransaction(async tx => {
            const snapshot = await tx.get(account.ref);
            if (snapshot.data()?.accountMutationId === mutationId) {
                tx.update(account.ref, { accountMutationId: FieldValue.delete() });
            }
        });
    }
}
