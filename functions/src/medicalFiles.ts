import { createHash, randomUUID } from 'crypto';
import { reserveMedicalUpload } from './shared/medicalUploadBudget';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { admin, auth, db } from './firebase';
import { getCallerUserDoc, requireAuth } from './shared/auth';
import { authenticatedMedicalUrl, authorizeMedicalCreate, authorizeMedicalMutation,
    authorizeMedicalRead, medicalDocumentPath, medicalId } from './shared/medicalDocumentAccess';
import { cancelMedicalUpload, validateMedicalMetadata } from './documentReplacement';

const maxBytes = 20 * 1024 * 1024;
const operations = db.collection('medical_document_replacements');
const documents = db.collection('medical_documents');
const options = { region: 'us-central1', memory: '512MiB' as const, concurrency: 1, maxInstances: 10, timeoutSeconds: 120 };
const fileTypes: Record<string, string> = { pdf: 'application/pdf', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png',
    doc: 'application/msword', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' };

function uploadBytes(encoded: unknown): Buffer {
    if (typeof encoded !== 'string' || !encoded || encoded.length > Math.ceil(maxBytes / 3) * 4 ||
        !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) throw new HttpsError('invalid-argument', 'Invalid document bytes.');
    const bytes = Buffer.from(encoded, 'base64');
    if (!bytes.length || bytes.length >= maxBytes || bytes.toString('base64') !== encoded) {
        throw new HttpsError('invalid-argument', 'Document must be between 1 byte and 20 MB.');
    }
    return bytes;
}

function fileType(fileName: unknown): { name: string; contentType: string } {
    if (typeof fileName !== 'string' || !fileName || fileName.length > 255 || /[\/\\\x00-\x1f]/.test(fileName)) {
        throw new HttpsError('invalid-argument', 'Invalid file name.');
    }
    const contentType = fileTypes[fileName.split('.').pop()!.toLowerCase()];
    if (!contentType) throw new HttpsError('invalid-argument', 'Unsupported document type.');
    return { name: fileName, contentType };
}

async function savePrivateFile(path: string, bytes: Buffer, contentType: string, owner: { actor: string; patientId: string }) {
    const file = admin.storage().bucket().file(path);
    await file.save(bytes, { resumable: false, contentType, preconditionOpts: { ifGenerationMatch: 0 }, metadata: {
        cacheControl: 'private, no-store, max-age=0', metadata: {
            uhcReplacementUser: owner.patientId, uhcReplacementAuthor: owner.actor, uhcReplacementCommitted: 'true',
        },
    } });
}

async function stageReplacement(uid: string, input: Record<string, unknown>, bytes: Buffer): Promise<void> {
    const operationId = medicalId(input.operationId);
    const ref = operations.doc(operationId);
    const stagedHash = createHash('sha256').update(bytes).digest('hex');
    const operation = await db.runTransaction(async tx => {
        const op = await tx.get(ref);
        if (!op.exists || op.data()!.actor !== uid || op.data()!.status !== 'uploading' || op.data()!.expiresAt.toMillis() <= Date.now()) {
            throw new HttpsError('failed-precondition', 'Upload is unavailable.');
        }
        await authorizeMedicalMutation(tx, uid, await tx.get(documents.doc(medicalId(op.data()!.docId))));
        if (op.data()!.stagedHash && op.data()!.stagedHash !== stagedHash) {
            throw new HttpsError('already-exists', 'Upload already contains different bytes.');
        }
        tx.update(ref, { stagedHash });
        return op.data()!;
    });
    const path = `medical_document_replacement_files/${medicalId(operation.docId)}/${operationId}`;
    const { contentType } = fileType(operation.fileName);
    try {
        await savePrivateFile(path, bytes, contentType, { actor: uid, patientId: operation.userId });
    } catch (error) {
        // Retry may follow an acknowledged immutable upload with a lost response.
        if ((error as { code?: number }).code !== 412) throw error;
        const [existing] = await admin.storage().bucket().file(path).download();
        if (!existing.equals(bytes)) throw new HttpsError('already-exists', 'Upload already contains different bytes.');
    }
    const fresh = await ref.get();
    if (fresh.data()?.status === 'aborted') {
        await cancelMedicalUpload(uid, operationId);
        throw new HttpsError('aborted', 'Upload was cancelled.');
    }
}

async function createDocument(uid: string, input: Record<string, unknown>, bytes: Buffer) {
    const documentId = medicalId(input.documentId);
    const patientId = medicalId(input.patientId);
    const changes = validateMedicalMetadata(input.metadata);
    const file = fileType(input.fileName);
    const appointmentId = input.appointmentId == null ? null : medicalId(input.appointmentId);
    const hash = createHash('sha256').update(JSON.stringify([patientId, changes, file.name, appointmentId])).update(bytes).digest('hex');
    const documentRef = documents.doc(documentId);
    const profile = await db.runTransaction(async tx => {
        const current = await tx.get(documentRef);
        const actor = await authorizeMedicalCreate(tx, uid, patientId);
        if (current.exists && (current.data()!.addedBy !== uid || current.data()!.initialUploadHash !== hash)) {
            throw new HttpsError('already-exists', 'Document identifier is already in use.');
        }
        return { actor, existing: current.exists };
    });
    if (profile.existing) return { documentId, committed: true };
    const operationRef = operations.doc(randomUUID());
    const path = `medical_document_replacement_files/${documentId}/${operationRef.id}`;
    const now = Timestamp.now();
    await operationRef.create({ actor: uid, userId: patientId, docId: documentId, status: 'uploading',
        expiresAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000), maintenanceVersion: 2,
        nextMaintenanceAt: Timestamp.fromMillis(Date.now() + 2 * 60 * 60 * 1000), oldStoragePath: null });
    try {
        await savePrivateFile(path, bytes, file.contentType, { actor: uid, patientId });
        const created = await db.runTransaction(async tx => {
            const current = await tx.get(documentRef);
            await authorizeMedicalCreate(tx, uid, patientId);
            if (current.exists) {
                if (current.data()!.addedBy !== uid || current.data()!.initialUploadHash !== hash) {
                    throw new HttpsError('already-exists', 'Document identifier is already in use.');
                }
                return false;
            }
            tx.create(documentRef, { id: documentId, userId: patientId, ...changes, fileName: file.name,
                storagePath: path, url: authenticatedMedicalUrl(documentId), addedBy: uid,
                addedByRole: patientId === uid ? 'patient' : 'doctor', addedByName: profile.actor.fullName || '',
                appointmentId, initialUploadHash: hash, uploadedAt: now, updatedAt: now });
            tx.update(operationRef, { status: 'committed', nextMaintenanceAt: FieldValue.delete() });
            return true;
        });
        if (!created) await cancelMedicalUpload(uid, operationRef.id);
    } catch (error) {
        if (!await cancelMedicalUpload(uid, operationRef.id)) throw error;
    }
    return { documentId, committed: true };
}

// Server uploads never use Firebase's client upload endpoint, which mints public
// download tokens. The existing finish/cancel protocol still owns replacement.
export const uploadMedicalDocument = onCall(options, async request => {
    const uid = requireAuth(request);
    await getCallerUserDoc(uid);
    const input = request.data as Record<string, unknown>;
    const bytes = uploadBytes(input?.bytes);
    if (!['create', 'stageReplacement'].includes(String(input.action))) throw new HttpsError('invalid-argument', 'Invalid upload action.');
    const uploadId = medicalId(input.action === 'create' ? input.documentId : input.operationId);
    await reserveMedicalUpload(uid, `${input.action}:${uploadId}:${createHash('sha256').update(bytes).digest('hex')}`, bytes.length);
    if (input.action === 'create') return createDocument(uid, input, bytes);
    if (input.action === 'stageReplacement') {
        await stageReplacement(uid, input, bytes);
        return { uploaded: true };
    }
    throw new HttpsError('invalid-argument', 'Invalid upload action.');
});

export const deleteMedicalDocument = onCall({ region: 'us-central1' }, async request => {
    const uid = requireAuth(request);
    await getCallerUserDoc(uid);
    const ref = documents.doc(medicalId(request.data?.documentId));
    await db.runTransaction(async tx => {
        const snapshot = await tx.get(ref);
        await authorizeMedicalMutation(tx, uid, snapshot);
        tx.delete(ref);
    });
    // The existing idempotent cleanup trigger handles proven managed objects.
    // Legacy shared bytes remain private instead of risking another record.
    return { deleted: true };
});

export const readMedicalDocument = onRequest({ ...options, cors: true }, async (request, response) => {
    response.set({ 'Cache-Control': 'private, no-store, max-age=0', Pragma: 'no-cache', Vary: 'Authorization', 'X-Content-Type-Options': 'nosniff' });
    if (request.method !== 'GET') { response.status(405).send('Method not allowed.'); return; }
    try {
        const bearer = request.headers.authorization;
        if (!bearer?.startsWith('Bearer ')) throw new HttpsError('unauthenticated', 'Sign in required.');
        let uid: string;
        try { uid = (await auth.verifyIdToken(bearer.slice(7), true)).uid; }
        catch { throw new HttpsError('unauthenticated', 'Sign in required.'); }
        await getCallerUserDoc(uid);
        const documentId = medicalId(request.query.documentId);
        const result = await db.runTransaction(async tx => {
            const snapshot = await tx.get(documents.doc(documentId));
            const path = await authorizeMedicalRead(tx, uid, snapshot);
            medicalDocumentPath(documentId, snapshot.data()!);
            return { path, fileName: String(snapshot.data()!.fileName || 'document') };
        });
        const file = admin.storage().bucket().file(result.path);
        const [info] = await file.getMetadata();
        if (Number(info.size) <= 0 || Number(info.size) >= maxBytes) throw new HttpsError('failed-precondition', 'Invalid document size.');
        const [bytes] = await file.download();
        if (!bytes.length || bytes.length >= maxBytes) throw new HttpsError('failed-precondition', 'Invalid document size.');
        // Recheck after the fetch as access or the current file may change in flight.
        await db.runTransaction(async tx => {
            const current = await tx.get(documents.doc(documentId));
            if (await authorizeMedicalRead(tx, uid, current) !== result.path) {
                throw new HttpsError('aborted', 'Document changed. Open it again.');
            }
        });
        response.type(info.contentType || 'application/octet-stream');
        response.set('Content-Disposition', `inline; filename*=UTF-8''${encodeURIComponent(result.fileName)}`);
        response.status(200).send(bytes);
    } catch (error) {
        const status = error instanceof HttpsError ? error.httpErrorCode.status : (error as { code?: number }).code === 404 ? 404 : 500;
        response.status(status).send('Document is unavailable.');
    }
});
