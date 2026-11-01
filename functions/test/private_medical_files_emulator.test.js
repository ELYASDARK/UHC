const assert = require('node:assert/strict');
const { before, after, test } = require('node:test');
const { randomUUID, randomBytes } = require('node:crypto');
const express = require('express');
if (process.env.GCLOUD_PROJECT !== 'demo-uhc-test' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099' ||
    process.env.FIREBASE_STORAGE_EMULATOR_HOST !== '127.0.0.1:9199') throw Error('Isolated demo emulators required.');
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-uhc-test', storageBucket: 'demo-uhc-test.appspot.com' });
process.env.FUNCTIONS_EMULATOR = 'true';
const { admin, db } = require('../lib/firebase');
const handlers = require('../lib/medicalFiles');
const replacement = require('../lib/documentReplacement');
const accounts = [], records = [], paths = [], grants = [];
let server, base;
before(async () => {
    const app = express();
    app.get('/read', handlers.readMedicalDocument);
    server = await new Promise(resolve => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
    base = `http://127.0.0.1:${server.address().port}/read`;
});
after(async () => {
    await new Promise(resolve => server.close(resolve));
    for (const uid of accounts) {
        const ops = await db.collection('medical_document_replacements').where('actor', '==', uid).get();
        for (const op of ops.docs) {
            await admin.storage().bucket().file(`medical_document_replacement_files/${op.data().docId}/${op.id}`).delete({ ignoreNotFound: true });
            await op.ref.delete();
        }
        await db.doc(`users/${uid}`).delete();
        await admin.auth().deleteUser(uid);
    }
    for (const path of paths) await admin.storage().bucket().file(path).delete({ ignoreNotFound: true });
    for (const id of records) await db.doc(`medical_documents/${id}`).delete();
    for (const grant of grants) await grant.delete();
    for (const app of [...admin.apps]) await app.delete();
});
async function account(role = 'student', permissions = {}) {
    const uid = `qa-private-${randomUUID()}`, email = `${uid}@demo.uhc.edu`;
    accounts.push(uid);
    assert.equal((await admin.auth().importUsers([{ uid, email, providerData: [{ providerId: 'google.com', uid, email }] }])).failureCount, 0);
    const password = randomBytes(24).toString('hex');
    await admin.auth().updateUser(uid, { password });
    await db.doc(`users/${uid}`).set({ role, isActive: true, googleEmail: email, adminPermissions: permissions });
    const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-demo-only', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
    const { idToken } = await response.json(); assert.ok(idToken);
    return { uid, token: idToken };
}
const invoke = (handler, actor, data) => handler.run({ auth: { uid: actor.uid }, data });
async function create(actor, { patientId = actor.uid, bytes = Buffer.from('synthetic medical bytes'), fileName = 'synthetic.pdf', documentId = randomUUID() } = {}) {
    records.push(documentId);
    const input = { action: 'create', documentId, patientId, fileName, metadata: { name: 'Synthetic document', notes: '', type: 'other' }, bytes: bytes.toString('base64') };
    await invoke(handlers.uploadMedicalDocument, actor, input);
    return { id: documentId, bytes, input, ref: db.doc(`medical_documents/${documentId}`) };
}
const read = (actor, id) => fetch(`${base}?documentId=${id}`, { headers: actor ? { Authorization: `Bearer ${actor.token}` } : {} });
async function grant(doctor, patient) {
    const ref = db.doc(`doctor_patient_access/${doctor.uid}/patients/${patient.uid}`);
    grants.push(ref); await ref.set({ schemaVersion: 2, activeAppointmentCount: 1 }); return ref;
}
test('server upload/read preserves bytes and retries, denies anonymous and other patients', async () => {
    const patient = await account(), other = await account();
    const doc = await create(patient);
    const response = await read(patient, doc.id);
    assert.equal(response.status, 200);
    assert.match(response.headers.get('cache-control'), /no-store/);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), doc.bytes);
    assert.equal((await read(null, doc.id)).status, 401);
    assert.equal((await read(other, doc.id)).status, 403);
    await invoke(handlers.uploadMedicalDocument, patient, doc.input);
    await assert.rejects(invoke(handlers.uploadMedicalDocument, patient, { ...doc.input, bytes: Buffer.from('different').toString('base64') }), e => e.code === 'already-exists');
    const saved = (await doc.ref.get()).data();
    assert.match(saved.url, /readMedicalDocument\?documentId=/);
    assert.equal(saved.url.includes('token='), false);
    const [metadata] = await admin.storage().bucket().file(saved.storagePath).getMetadata();
    assert.equal(metadata.metadata?.firebaseStorageDownloadTokens, undefined);
    for (const suffix of ['', '?alt=media']) {
        const denied = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(saved.storagePath)}${suffix}`, { headers: { Authorization: `Bearer ${patient.token}` } });
        assert.equal(denied.status, 403, 'Direct reads must not mint public tokens');
    }
});
test('doctor grant, active account and admin byte permissions are checked on each opening', async () => {
    const patient = await account(), doctor = await account('doctor');
    const doc = await create(patient); const access = await grant(doctor, patient);
    assert.equal((await read(doctor, doc.id)).status, 200);
    await access.update({ activeAppointmentCount: 0 });
    assert.equal((await read(doctor, doc.id)).status, 403);
    await access.set({ activeAppointmentCount: 1 });
    assert.equal((await read(doctor, doc.id)).status, 403, 'Unversioned grants fail closed');
    const analytics = await account('admin', { 'analytics.view': true });
    const reports = await account('admin', { 'reports.view': true });
    assert.equal((await read(analytics, doc.id)).status, 403);
    assert.equal((await read(reports, doc.id)).status, 200);
    await db.doc(`users/${patient.uid}`).update({ isActive: false });
    assert.equal((await read(patient, doc.id)).status, 403);
});
test('doctor upload requires a current grant and only the author may replace/delete', async () => {
    const patient = await account(), doctor = await account('doctor');
    await assert.rejects(create(doctor, { patientId: patient.uid }), e => e.code === 'permission-denied');
    const access = await grant(doctor, patient);
    const doc = await create(doctor, { patientId: patient.uid });
    await assert.rejects(invoke(handlers.deleteMedicalDocument, patient, { documentId: doc.id }), e => e.code === 'permission-denied');
    await access.delete();
    await assert.rejects(invoke(handlers.deleteMedicalDocument, doctor, { documentId: doc.id }), e => e.code === 'permission-denied');
    await access.set({ schemaVersion: 2, activeAppointmentCount: 1 });
    await invoke(handlers.deleteMedicalDocument, doctor, { documentId: doc.id });
    assert.equal((await read(patient, doc.id)).status, 404);
});
test('authoritative path validation rejects cross-patient and cross-document redirects', async () => {
    const patient = await account(), other = await account();
    const doc = await create(patient), victim = await create(other);
    await doc.ref.update({ storagePath: (await victim.ref.get()).data().storagePath });
    assert.equal((await read(patient, doc.id)).status, 400);
    await doc.ref.update({ storagePath: `medical_documents/${other.uid}/self/victim.pdf` });
    assert.equal((await read(patient, doc.id)).status, 400);
});
test('legacy and orphaned files cannot be read or overwritten through client Storage', async () => {
    const patient = await account();
    for (const path of [`medical_documents/${patient.uid}/legacy.pdf`, `medical_documents/${patient.uid}/self/orphan.pdf`]) {
        paths.push(path); await admin.storage().bucket().file(path).save(Buffer.from('private synthetic legacy'));
        const url = `http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(path)}`;
        for (const method of ['GET', 'DELETE']) assert.equal((await fetch(url, { method, headers: { Authorization: `Bearer ${patient.token}` } })).status, 403);
    }
});
test('all supported types and files above the streaming limit retain exact bytes', async () => {
    const patient = await account();
    for (const ext of ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx']) {
        const bytes = Buffer.alloc(ext === 'pdf' ? 11 * 1024 * 1024 : 1024, 79);
        const doc = await create(patient, { bytes, fileName: `synthetic.${ext}` });
        const response = await read(patient, doc.id); assert.equal(response.status, 200);
        assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
    }
    await assert.rejects(create(patient, { fileName: 'synthetic.html' }), e => e.code === 'invalid-argument');
    await assert.rejects(create(patient, { bytes: Buffer.alloc(0) }), e => e.code === 'invalid-argument');
    await assert.rejects(create(patient, { bytes: Buffer.alloc(20 * 1024 * 1024) }), e => e.code === 'invalid-argument');
});
test('replacement uses server staging, rejects a second body, and removes access to superseded bytes', async () => {
    const patient = await account(), doc = await create(patient);
    const oldPath = (await doc.ref.get()).data().storagePath;
    const op = await invoke(replacement.replaceMedicalDocument, patient, { action: 'begin', docId: doc.id, expectedStoragePath: oldPath,
        fileName: 'replacement.png', metadata: { name: 'Replacement', notes: '', type: 'imaging' } });
    const bytes = Buffer.from('replacement synthetic image');
    const input = { action: 'stageReplacement', operationId: op.operationId, bytes: bytes.toString('base64') };
    await invoke(handlers.uploadMedicalDocument, patient, input);
    await invoke(handlers.uploadMedicalDocument, patient, input);
    await assert.rejects(invoke(handlers.uploadMedicalDocument, patient, { ...input, bytes: Buffer.from('other').toString('base64') }), e => e.code === 'already-exists');
    await invoke(replacement.replaceMedicalDocument, patient, { action: 'finish', operationId: op.operationId });
    const response = await read(patient, doc.id); assert.equal(response.status, 200);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
    assert.equal((await admin.storage().bucket().file(oldPath).exists())[0], false);
});

test('HTTP upload accepts a large authenticated file and denies forged record creation', async () => {
    const patient = await account(), documentId = randomUUID(); records.push(documentId);
    const bytes = Buffer.alloc(11 * 1024 * 1024, 84);
    const response = await fetch('http://127.0.0.1:5001/demo-uhc-test/us-central1/uploadMedicalDocument', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${patient.token}` },
        body: JSON.stringify({ data: { action: 'create', documentId, patientId: patient.uid, fileName: 'synthetic.pdf',
            metadata: { name: 'Synthetic large HTTP file', notes: '', type: 'other' }, bytes: bytes.toString('base64') } }),
        signal: AbortSignal.timeout(120000),
    });
    assert.equal(response.status, 200, await response.text());
    const readback = await read(patient, documentId); assert.equal(readback.status, 200);
    assert.deepEqual(Buffer.from(await readback.arrayBuffer()), bytes);
    const forged = await fetch(`http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents/medical_documents?documentId=${randomUUID()}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${patient.token}` },
        body: JSON.stringify({ fields: { userId: { stringValue: patient.uid }, storagePath: { stringValue: 'medical_documents/other/self/private.pdf' } } }),
    });
    assert.equal(forged.status, 403);
});
