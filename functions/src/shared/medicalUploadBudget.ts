import { createHash } from 'crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { db } from '../firebase';

const hourMs = 3600000;
const personalLimit = 1024 ** 3;
const projectLimit = 100 * 1024 ** 3;
type Bucket = { hour: number; bytes: number };

// Distinct admitted bytes, not retained storage. Keep the current hour and the
// previous 24 hours, so every charge lasts at least 24 hours. Failed, cancelled
// and deleted uploads remain charged; uncertain remote writes are never refunded.
export async function reserveMedicalUpload(uid: string, identity: string, bytes: number): Promise<void> {
    if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes >= 20 * 1024 * 1024) {
        throw new HttpsError('invalid-argument', 'Invalid medical upload size.');
    }
    const hash = (value: string) => createHash('sha256').update(value).digest('hex');
    const key = hash(JSON.stringify([uid, identity]));
    const admission = db.doc(`medical_upload_transfer_admissions/${key}`);
    const user = db.doc(`medical_upload_budgets/v2_user_${hash(uid)}`);
    const project = db.doc('medical_upload_budgets/v2_project');
    const hour = Math.floor(Date.now() / hourMs);
    await db.runTransaction(async tx => {
        const [prior, personal, global] = await tx.getAll(admission, user, project);
        // Carry legacy debt once, conservatively, rather than resetting an
        // exhausted allowance on rollout. It ages out without manual refunds.
        const legacyRefs = [];
        if (!personal.exists) legacyRefs.push(db.doc(`medical_upload_budgets/user_${hash(uid)}`));
        if (!global.exists) legacyRefs.push(db.doc('medical_upload_budgets/project'));
        const legacy = legacyRefs.length ? await tx.getAll(...legacyRefs) : [];
        let legacyIndex = 0;
        const personalUsage = personal.data() || legacy[legacyIndex++]?.data() || {};
        const projectUsage = global.data() || legacy[legacyIndex]?.data() || {};
        const buckets = (usage: FirebaseFirestore.DocumentData): Bucket[] => {
            const values: Bucket[] = usage.version === 2 ? usage.buckets :
                [{ hour: usage.hour ?? hour, bytes: usage.bytes || 0 }];
            if (!Array.isArray(values) || values.some(b => !Number.isSafeInteger(b.hour) ||
                !Number.isSafeInteger(b.bytes) || b.bytes < 0)) {
                throw new HttpsError('failed-precondition', 'Upload accounting requires operator reconciliation.');
            }
            return values.filter(b => b.hour >= hour - 24);
        };
        const personalBuckets = buckets(personalUsage);
        const projectBuckets = buckets(projectUsage);
        const attempts = personalUsage.hour === hour ? personalUsage.attempts || 0 : 0;
        const projectAttempts = projectUsage.hour === hour ? projectUsage.attempts || 0 : 0;
        const previous = prior.data();
        if (previous && previous.bytes !== bytes) throw new HttpsError('invalid-argument', 'Upload identity size changed.');
        const charge = previous && previous.hour >= hour - 24 ? 0 : bytes;
        const total = (values: Bucket[]) => values.reduce((sum, b) => sum + b.bytes, 0);
        if (attempts >= 60 || projectAttempts >= 1000 ||
            total(personalBuckets) + charge > personalLimit || total(projectBuckets) + charge > projectLimit) {
            throw new HttpsError('resource-exhausted',
                'Medical upload transfer allowance reached. Capacity recovers as requests and transfers age out within 25 hours.');
        }
        const update = (ref: FirebaseFirestore.DocumentReference, values: Bucket[], count: number) => {
            const current = values.find(b => b.hour === hour);
            if (current) current.bytes += charge;
            else values.push({ hour, bytes: charge });
            tx.set(ref, { version: 2, hour, attempts: count + 1, buckets: values, bytes: total(values) });
        };
        update(user, personalBuckets, attempts);
        update(project, projectBuckets, projectAttempts);
        // Optional TTL is housekeeping only. Early removal only recharges bytes.
        // Zero-byte begin requests need no deduplication record.
        if (bytes > 0 && charge > 0) tx.set(admission, {
            bytes, hour, expiresAt: Timestamp.fromMillis((hour + 49) * hourMs),
        });
    });
}
