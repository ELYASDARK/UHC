import { randomUUID } from 'crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { FunctionsErrorCode, HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { admin, db } from './firebase';
import { getCallerUserDoc, requireAuth } from './shared/auth';

const operations = db.collection('medical_document_replacements');
const documents = db.collection('medical_documents');
const hour = 60 * 60 * 1000;
const cleanupBatchSize = 50;
const migrationState = db.doc('maintenance/documentReplacementV2');
const fail = (code: FunctionsErrorCode, message: string): never => {
    throw new HttpsError(code, message);
};
function id(value: unknown): string {
    if (typeof value !== 'string' || !/^[\w-]{1,128}$/.test(value)) return fail('invalid-argument', 'Invalid identifier.');
    return value;
}
function metadata(value: unknown): Record<string, string> {
    const data = value as Record<string, unknown> | null;
    if (!data || Object.keys(data).some(key => !['name', 'type', 'notes'].includes(key)) ||
        typeof data.name !== 'string' || !data.name.trim() || data.name.length > 200 ||
        typeof data.notes !== 'string' || data.notes.length > 10000 ||
        !['lab_results', 'prescription', 'medical_record', 'imaging', 'medicine', 'other'].includes(String(data.type))) {
        return fail('invalid-argument', 'Invalid document metadata.');
    }
    return { name: data.name.trim(), type: String(data.type), notes: data.notes };
}

// All permission-bearing Firestore reads are inside the committing transaction.
async function authorize(tx: FirebaseFirestore.Transaction, uid: string, document: FirebaseFirestore.DocumentSnapshot): Promise<void> {
    if (!document.exists) return fail('not-found', 'Document no longer exists.');
    const data = document.data()!;
    const user = (await tx.get(db.doc(`users/${uid}`))).data();
    if (!user || user.isActive !== true || typeof user.googleEmail !== 'string' || !user.googleEmail ||
        (data.addedBy ?? data.userId) !== uid) return fail('permission-denied', 'Document replacement is not permitted.');
    if (data.userId === uid) return;
    if (user.role !== 'doctor' || !(await tx.get(db.doc(`doctor_patient_access/${uid}/patients/${id(data.userId)}`))).exists) {
        return fail('permission-denied', 'Patient access is unavailable.');
    }
}

function candidatePath(docId: string, operationId: string): string {
    return `medical_document_replacement_files/${docId}/${operationId}`;
}

async function removeCandidate(op: FirebaseFirestore.DocumentSnapshot): Promise<void> {
    // Paths are derived from server-owned identifiers, never supplied by callers.
    await admin.storage().bucket().file(candidatePath(id(op.data()!.docId), op.id)).delete({ ignoreNotFound: true });
}

async function cancel(uid: string, operationId: string): Promise<boolean> {
    const ref = operations.doc(operationId);
    const committed = await db.runTransaction(async tx => {
        const op = await tx.get(ref);
        if (!op.exists || op.data()!.actor !== uid) return fail('permission-denied', 'Invalid replacement operation.');
        if (op.data()!.status === 'committed') return true;
        // Keep one delayed sweep for an upload already in flight at cancellation.
        tx.update(ref, { status: 'aborted', maintenanceVersion: 2,
            nextMaintenanceAt: Timestamp.fromMillis(Math.max(Date.now(), op.data()!.expiresAt.toMillis() + hour)),
            metadata: FieldValue.delete(), fileName: FieldValue.delete(), expectedUpdateTime: FieldValue.delete() });
        return false;
    });
    if (!committed) await removeCandidate(await ref.get());
    return committed;
}

export const replaceMedicalDocument = onCall({ region: 'us-central1', concurrency: 1, maxInstances: 10 }, async request => {
    const input = request.data;
    const uid = requireAuth(request);
    // Cancellation remains available after access revocation, but can only clean
    // the caller's uncommitted operation. It cannot remove a committed file.
    if (input?.action === 'cancel') return { committed: await cancel(uid, id(input.operationId)) };
    await getCallerUserDoc(uid);
    if (input?.action === 'begin') {
        // Rollback can stop new uploads while existing finish/cancel recovery
        // remains available and committed-file reads keep their current policy.
        if (process.env.DOCUMENT_REPLACEMENT_PAUSED === 'true') return fail('unavailable', 'Document replacement is temporarily paused.');
        const docId = id(input.docId);
        const changes = metadata(input.metadata);
        const fileName = input.fileName;
        if (typeof fileName !== 'string' || !fileName || fileName.length > 255 || /[\/\\\x00-\x1f]/.test(fileName) ||
            !/\.(pdf|jpe?g|png|docx?)$/i.test(fileName)) return fail('invalid-argument', 'Invalid file name.');
        const ref = operations.doc(randomUUID());
        await db.runTransaction(async tx => {
            const doc = await tx.get(documents.doc(docId));
            await authorize(tx, uid, doc);
            if (doc.data()!.storagePath !== input.expectedStoragePath) return fail('aborted', 'Document changed. Reopen it before replacing.');
            tx.create(ref, {
                actor: uid, docId, userId: doc.data()!.userId, status: 'uploading',
                expectedUpdateTime: doc.updateTime!, oldStoragePath: doc.data()!.storagePath,
                metadata: changes, fileName, expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
                maintenanceVersion: 2, nextMaintenanceAt: Timestamp.fromMillis(Date.now() + 2 * hour),
            });
        });
        return { operationId: ref.id, storagePath: candidatePath(docId, ref.id) };
    }
    if (input?.action !== 'finish') return fail('invalid-argument', 'Invalid replacement action.');
    const operationId = id(input.operationId);
    const ref = operations.doc(operationId);
    const op = await ref.get();
    if (!op.exists || op.data()!.actor !== uid) return fail('permission-denied', 'Invalid replacement operation.');
    if (op.data()!.status === 'committed') {
        await processMaintenance(op);
        return { committed: true };
    }
    if (op.data()!.status !== 'uploading') return fail('aborted', 'Replacement cancelled.');
    const path = candidatePath(id(op.data()!.docId), operationId);
    const file = admin.storage().bucket().file(path);
    try {
        const [fileMetadata] = await file.getMetadata();
        if (Number(fileMetadata.size) <= 0 || Number(fileMetadata.size) >= 20 * 1024 * 1024 ||
            !/^(application\/pdf|image\/(jpeg|png)|application\/msword|application\/vnd.openxmlformats-officedocument.wordprocessingml.document)$/.test(fileMetadata.contentType ?? '')) {
            return fail('invalid-argument', 'Invalid document file.');
        }
        const token = String(fileMetadata.metadata?.firebaseStorageDownloadTokens ?? '').split(',')[0];
        if (!token) return fail('failed-precondition', 'Uploaded document has no download token.');
        const host = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
        const origin = host && process.env.GCLOUD_PROJECT === 'demo-uhc-test'
            ? `http://${host}` : 'https://firebasestorage.googleapis.com';
        const url = `${origin}/v0/b/${encodeURIComponent(file.bucket.name)}/o/${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`;
        await db.runTransaction(async tx => {
            const fresh = await tx.get(ref);
            if (fresh.data()!.status === 'committed') return;
            if (fresh.data()!.status !== 'uploading' || fresh.data()!.expiresAt.toMillis() <= Date.now()) return fail('aborted', 'Replacement expired or cancelled.');
            const docRef = documents.doc(op.data()!.docId);
            const doc = await tx.get(docRef);
            await authorize(tx, uid, doc);
            if (!doc.updateTime!.isEqual(op.data()!.expectedUpdateTime)) return fail('aborted', 'Document changed. Reopen it before replacing.');
            tx.update(docRef, { ...op.data()!.metadata, fileName: op.data()!.fileName, storagePath: path, url, updatedAt: FieldValue.serverTimestamp() });
            tx.update(ref, { status: 'committed', maintenanceVersion: 2, nextMaintenanceAt: Timestamp.now(),
                metadata: FieldValue.delete(), fileName: FieldValue.delete(), expectedUpdateTime: FieldValue.delete() });
        });
    } catch (error) {
        // Also handles a lost transaction response: cancel serializes against
        // finish and reports success if the transaction actually committed.
        if (!(await cancel(uid, operationId))) throw error;
    }
    await processMaintenance(await ref.get());
    return { committed: true };
});

async function maintainCommittedFile(op: FirebaseFirestore.DocumentSnapshot): Promise<void> {
    const data = op.data()!;
    const path = candidatePath(id(data.docId), op.id);
    const current = await documents.doc(data.docId).get();
    if (current.data()?.storagePath === path) {
        const file = admin.storage().bucket().file(path);
        const info = await file.getMetadata().then(([value]) => value).catch((error: { code?: number }) => {
            // An authorized file deletion can precede document deletion. There
            // are no bytes to seal or recover; do not retry a permanent 404.
            if (error.code === 404) return null;
            throw error;
        });
        // Clients cannot create or update these reserved metadata fields. They
        // let Storage evaluate committed-file access within its two-doc limit.
        if (info) await file.setMetadata({ metadata: {
            ...info.metadata,
            uhcReplacementUser: data.userId,
            uhcReplacementAuthor: data.actor,
            uhcReplacementCommitted: 'true',
        } });
    } else {
        // No client can attach this server-owned path to another document.
        await removeCandidate(op);
    }
    await cleanPreviousFile(op);
}

async function cleanPreviousFile(op: FirebaseFirestore.DocumentSnapshot): Promise<void> {
    const data = op.data()!;
    const prefix = `medical_document_replacement_files/${id(data.docId)}/`;
    const old = data.oldStoragePath;
    // Legacy paths cannot be proven exclusive to this record. Keep those bytes
    // instead of risking deletion of another document's file.
    if (typeof old !== 'string' || !old.startsWith(prefix)) return;
    const priorId = old.slice(prefix.length);
    if (!/^[\w-]{1,128}$/.test(priorId)) return;
    const prior = await operations.doc(priorId).get();
    if (!prior.exists || prior.data()!.docId !== data.docId || prior.data()!.status !== 'committed') return;
    const current = await documents.doc(data.docId).get();
    if (current.data()?.storagePath === old) return;
    await admin.storage().bucket().file(old).delete({ ignoreNotFound: true });
}

// Claim with a lease so overlapping scheduler/callable invocations do not repeat
// settled work. A crash leaves a due lease; an error receives a delayed retry.
async function processMaintenance(snapshot: FirebaseFirestore.DocumentSnapshot): Promise<void> {
    const token = randomUUID();
    const op = await db.runTransaction(async tx => {
        const fresh = await tx.get(snapshot.ref);
        const data = fresh.data();
        if (!data?.nextMaintenanceAt || data.nextMaintenanceAt.toMillis() > Date.now()) return null;
        tx.update(fresh.ref, { maintenanceToken: token, nextMaintenanceAt: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000) });
        return fresh;
    });
    if (!op) return;
    let succeeded = false;
    try {
        if (op.data()!.status === 'committed') {
            await maintainCommittedFile(op);
        } else {
            // Serialize abort against finish before deleting any candidate.
            const committed = await db.runTransaction(async tx => {
                const fresh = await tx.get(op.ref);
                if (fresh.data()!.status === 'committed') return true;
                if (fresh.data()!.expiresAt.toMillis() + hour > Date.now()) throw new Error('Upload grace period is active.');
                tx.update(op.ref, { status: 'aborted', metadata: FieldValue.delete(), fileName: FieldValue.delete(), expectedUpdateTime: FieldValue.delete() });
                return false;
            });
            if (committed) await maintainCommittedFile(await op.ref.get());
            else await removeCandidate(op);
        }
        succeeded = true;
    } catch (_) {
        logger.warn('Document replacement cleanup will retry.');
    }
    await db.runTransaction(async tx => {
        const fresh = await tx.get(op.ref);
        // A document event may enqueue new work while this lease is running.
        if (fresh.data()?.maintenanceToken !== token) return;
        tx.update(op.ref, { maintenanceToken: FieldValue.delete(),
            nextMaintenanceAt: succeeded ? FieldValue.delete() : Timestamp.fromMillis(Date.now() + hour) });
    });
}

// Only an old managed reference needs maintenance on delete/replacement. This
// trigger is idempotent and paths still require a committed provenance record.
export const queueMedicalDocumentCleanup = onDocumentWritten({
    document: 'medical_documents/{documentId}', region: 'us-central1',
    concurrency: 1, maxInstances: 10, retry: true,
}, async event => {
    const change = event.data;
    if (!change) throw new Error('Document cleanup event is missing its change.');
    const docId = change.before.id;
    const old = change.before.data()?.storagePath;
    if (old === change.after.data()?.storagePath || typeof old !== 'string') return;
    const prefix = `medical_document_replacement_files/${docId}/`;
    if (!old.startsWith(prefix)) return;
    const operationId = old.slice(prefix.length);
    if (!/^[\w-]{1,128}$/.test(operationId)) return;
    await db.runTransaction(async tx => {
        const op = await tx.get(operations.doc(operationId));
        if (op.data()?.docId !== docId || op.data()?.status !== 'committed') return;
        tx.update(op.ref, { maintenanceVersion: 2, nextMaintenanceAt: Timestamp.now(), maintenanceToken: FieldValue.delete() });
    });
});

// One bounded, resumable pass upgrades pre-v2 records. The persisted cursor
// stops at completion; new operations are born with due-work fields above.
async function migrateCleanupBatch(): Promise<void> {
    await db.runTransaction(async tx => {
        const state = await tx.get(migrationState);
        if (state.data()?.complete) return;
        let query = operations.orderBy('__name__').limit(cleanupBatchSize);
        if (state.data()?.cursor) query = query.startAfter(state.data()!.cursor);
        const page = await tx.get(query);
        for (const op of page.docs) {
            if (op.data().maintenanceVersion === 2) continue;
            tx.update(op.ref, { maintenanceVersion: 2,
                nextMaintenanceAt: Timestamp.fromMillis(Math.max(Date.now(), op.data().expiresAt.toMillis() + hour)) });
        }
        tx.set(migrationState, { cursor: page.docs[page.size - 1]?.id ?? state.data()?.cursor ?? null, complete: page.size < cleanupBatchSize });
    });
}

// At most 50 migration records and 50 due operations per invocation. A single
// field index suffices; settled operations have no nextMaintenanceAt entry.
export const cleanDocumentReplacements = onSchedule({
    schedule: 'every 60 minutes', region: 'us-central1', timeoutSeconds: 300,
    concurrency: 1, maxInstances: 1,
}, async () => {
    await migrateCleanupBatch();
    const due = await operations.where('nextMaintenanceAt', '<=', Timestamp.now()).orderBy('nextMaintenanceAt').limit(cleanupBatchSize).get();
    for (const op of due.docs) await processMaintenance(op);
});
