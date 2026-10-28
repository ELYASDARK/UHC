const assert = require('node:assert/strict');
const { test, after } = require('node:test');
const express = require('express');
const admin = require('firebase-admin');
if (process.env.GCLOUD_PROJECT !== 'demo-uhc-test' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099' ||
    process.env.FIREBASE_STORAGE_EMULATOR_HOST !== '127.0.0.1:9199') {
    throw Error('Requires isolated demo-uhc-test Auth/Firestore/Storage/Functions.');
}
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-uhc-test', storageBucket: 'demo-uhc-test.appspot.com' });
const app = admin.initializeApp({ projectId: 'demo-uhc-test', storageBucket: 'demo-uhc-test.appspot.com' }, 'replacement-tests');
const db = app.firestore();
const bucket = app.storage().bucket();
const prefix = `qa-replacement-${Date.now()}`;
const users = new Set();
const records = new Set();
const originalFiles = new Set();
const ops = new Set();
let nextAccount = 0;
let scheduleServer;
after(async () => {
    if (scheduleServer) await new Promise((resolve, reject) => scheduleServer.close(error => error ? reject(error) : resolve()));
    for (const operationId of ops) {
        const op = await db.doc(`medical_document_replacements/${operationId}`).get();
        if (op.exists) await bucket.file(`medical_document_replacement_files/${op.data().docId}/${operationId}`).delete({ ignoreNotFound: true });
        await op.ref.delete();
    }
    for (const docId of records) await db.doc(`medical_documents/${docId}`).delete();
    for (const file of originalFiles) await bucket.file(file).delete({ ignoreNotFound: true });
    for (const uid of users) {
        await db.doc(`users/${uid}`).delete();
        await app.auth().deleteUser(uid);
    }
    await app.delete();
    for (const instance of [...admin.apps]) await instance.delete();
});
async function runCleanup() {
    process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-uhc-test', storageBucket: 'demo-uhc-test.appspot.com' });
    await require('../lib/documentReplacement').cleanDocumentReplacements.run({ scheduleTime: new Date().toISOString() });
}

async function runScheduledHttp() {
    if (!scheduleServer) {
        const server = express();
        // Exercise the actual v2 HTTP wrapper and Cloud Scheduler headers.
        // Cloud Scheduler itself and invoker IAM are verified in the live stage.
        server.post('/cleanup', require('../lib/documentReplacement').cleanDocumentReplacements);
        scheduleServer = await new Promise(resolve => {
            const listener = server.listen(0, '127.0.0.1', () => resolve(listener));
        });
    }
    const response = await fetch(`http://127.0.0.1:${scheduleServer.address().port}/cleanup`, {
        method: 'POST', headers: { 'X-CloudScheduler-JobName': 'projects/demo-uhc-test/locations/us-central1/jobs/synthetic-cleanup',
            'X-CloudScheduler-ScheduleTime': new Date().toISOString() }, signal: AbortSignal.timeout(30000),
    });
    assert.equal(response.status, 200, await response.text());
}
async function account(role) {
    const uid = `${prefix}-${role}-${nextAccount++}`;
    const email = `${uid}@demo.uhc.edu`;
    assert.equal((await app.auth().importUsers([{ uid, email, providerData: [{ providerId: 'google.com', uid, email }] }])).failureCount, 0);
    await app.auth().updateUser(uid, { password: 'TestPassword123!' });
    await db.doc(`users/${uid}`).set({ role, googleEmail: email, isActive: true });
    users.add(uid);
    const res = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-emulator-api-key-demo-only', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: 'TestPassword123!', returnSecureToken: true }),
    });
    const token = (await res.json()).idToken;
    assert.ok(token);
    return { uid, token };
}
async function callRaw(actor, data) {
    const response = await fetch('http://127.0.0.1:5001/demo-uhc-test/us-central1/replaceMedicalDocument', {
        signal: AbortSignal.timeout(60000),
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${actor.token}` }, body: JSON.stringify({ data }),
    });
    const body = await response.json();
    return { status: response.status, body };
}
async function call(actor, data, status = 200) {
    const response = await callRaw(actor, data);
    const body = response.body;
    assert.equal(response.status, status, JSON.stringify(body));
    if (body.result?.operationId) ops.add(body.result.operationId);
    return body.result ?? body.error;
}
async function record(actor, patientId = actor.uid) {
    const ref = db.collection('medical_documents').doc();
    const storagePath = `medical_documents/${patientId}/self/${ref.id}.png`;
    await bucket.file(storagePath).save(Buffer.from('ORIGINAL synthetic document'));
    originalFiles.add(storagePath);
    const data = { userId: patientId, addedBy: actor.uid, addedByRole: patientId === actor.uid ? 'patient' : 'doctor', storagePath, url: 'https://example.invalid/original', fileName: 'original.png', name: 'Original', notes: '', type: 'other' };
    await ref.set(data);
    records.add(ref.id);
    return { ref, data };
}
async function begin(actor, document, fileName = 'new.png') {
    const current = (await document.ref.get()).data();
    return call(actor, { action: 'begin', docId: document.ref.id, expectedStoragePath: current.storagePath, fileName, metadata: { name: 'Replaced', notes: 'Synthetic', type: 'other' } });
}
async function upload(actor, op, contentType = 'image/png', status = 200, customMetadata = {}) {
    const boundary = 'qa_synthetic_boundary';
    const body = `--${boundary}\r\nContent-Type: application/json\r\n\r\n${JSON.stringify({ name: op.storagePath, contentType, metadata: customMetadata })}\r\n--${boundary}\r\nContent-Type: ${contentType}\r\n\r\nsynthetic bytes\r\n--${boundary}--\r\n`;
    const response = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o?name=${encodeURIComponent(op.storagePath)}`, {
        method: 'POST', headers: { Authorization: `Bearer ${actor.token}`, 'Content-Type': `multipart/related; boundary=${boundary}`, 'X-Goog-Upload-Protocol': 'multipart' }, body,
    });
    const result = await response.text();
    assert.equal(response.status, status, result);
}

test('patient replacement preserves identity, rejects direct rule bypass and cleans superseded managed bytes', async () => {
    const patient = await account('student');
    const document = await record(patient);
    const first = await begin(patient, document);
    await upload(patient, first, 'image/png', 403, { uhcReplacementCommitted: 'true', uhcReplacementUser: patient.uid });
    await upload(patient, first);
    const stagedDelete = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(first.storagePath)}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${patient.token}` },
    });
    assert.equal(stagedDelete.status, 403);
    const forgedUpdate = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(first.storagePath)}`, {
        method: 'PATCH', headers: { Authorization: `Bearer ${patient.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ metadata: { uhcReplacementCommitted: 'true', uhcReplacementAuthor: patient.uid } }),
    });
    assert.equal(forgedUpdate.status, 403);
    await upload(patient, first, 'image/png', 403); // immutable
    assert.equal((await call(patient, { action: 'finish', operationId: first.operationId })).committed, true);
    const replaced = (await document.ref.get()).data();
    assert.equal((await db.doc(`medical_document_replacements/${first.operationId}`).get()).data().metadata, undefined,
        'Settled operations must not retain a duplicate of document notes/name');
    const [sealed] = await bucket.file(first.storagePath).getMetadata();
    assert.equal(sealed.metadata.uhcReplacementUser, patient.uid);
    assert.equal(sealed.metadata.uhcReplacementAuthor, patient.uid);
    assert.equal(sealed.metadata.uhcReplacementCommitted, 'true');
    await bucket.file(first.storagePath).setMetadata({ metadata: { uhcReplacementCommitted: null, uhcReplacementAuthor: null, uhcReplacementUser: null } });
    await db.doc(`medical_document_replacements/${first.operationId}`).update({ expiresAt: admin.firestore.Timestamp.fromMillis(1), nextMaintenanceAt: admin.firestore.Timestamp.fromMillis(1) });
    await runCleanup();
    const [repaired] = await bucket.file(first.storagePath).getMetadata();
    assert.equal(repaired.metadata.uhcReplacementCommitted, 'true', 'Cleanup repairs a seal missing after committed replacement');
    assert.equal((await document.ref.get()).data().storagePath, first.storagePath);
    assert.equal(replaced.storagePath, first.storagePath);
    assert.equal(replaced.addedBy, document.data.addedBy);
    assert.equal(replaced.userId, document.data.userId);
    assert.equal(replaced.fileName, 'new.png');
    assert.ok(replaced.url.includes(encodeURIComponent(first.storagePath)));
    assert.equal((await call(patient, { action: 'cancel', operationId: first.operationId })).committed, true);
    assert.equal((await bucket.file(first.storagePath).exists())[0], true);
    const second = await begin(patient, document, 'new.pdf');
    await upload(patient, second, 'application/pdf');
    await call(patient, { action: 'finish', operationId: second.operationId });
    assert.equal((await document.ref.get()).data().storagePath, second.storagePath);
    assert.equal((await bucket.file(first.storagePath).exists())[0], false);
    assert.equal((await bucket.file(document.data.storagePath).download())[0].toString(), 'ORIGINAL synthetic document');
    const response = await fetch(`http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents/medical_documents/${document.ref.id}?updateMask.fieldPaths=storagePath`, {
        method: 'PATCH', headers: { Authorization: `Bearer ${patient.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: { storagePath: { stringValue: 'unrelated-file' } } }),
    });
    assert.equal(response.status, 403);
});

test('concurrent replacement has one winner, loser cleanup cannot delete winner or unrelated bytes', async () => {
    const patient = await account('student');
    const document = await record(patient);
    const [a, b] = await Promise.all([begin(patient, document), begin(patient, document)]);
    await Promise.all([upload(patient, a), upload(patient, b)]);
    const results = await Promise.all([a, b].map(op => callRaw(patient, { action: 'finish', operationId: op.operationId })));
    assert.deepEqual(results.map(result => result.status).sort(), [200, 409]);
    const winner = results[0].status === 200 ? a : b;
    const loser = winner === a ? b : a;
    assert.equal((await document.ref.get()).data().storagePath, winner.storagePath);
    assert.equal((await bucket.file(winner.storagePath).exists())[0], true);
    assert.equal((await bucket.file(loser.storagePath).exists())[0], false);
});

test('doctor author can replace, revoked access and cancelled/invalid uploads preserve original record', async () => {
    const doctor = await account('doctor');
    const patient = await account('student');
    const patientId = patient.uid;
    const access = db.doc(`doctor_patient_access/${doctor.uid}/patients/${patientId}`);
    await access.set({ granted: true });
    const document = await record(doctor, patientId);
    await call(patient, { action: 'begin', docId: document.ref.id,
        expectedStoragePath: document.data.storagePath, fileName: 'x.png',
        metadata: { name: 'Forbidden', type: 'other', notes: '' } }, 403);
    const success = await begin(doctor, document, 'doctor.pdf');
    await upload(doctor, success, 'application/pdf');
    await call(doctor, { action: 'finish', operationId: success.operationId });
    const saved = (await document.ref.get()).data();
    const revoked = await begin(doctor, document);
    await upload(doctor, revoked);
    await access.delete();
    const deniedDelete = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(success.storagePath)}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${doctor.token}` },
    });
    assert.equal(deniedDelete.status, 403);
    assert.equal((await bucket.file(success.storagePath).exists())[0], true);
    const deniedRead = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(success.storagePath)}`, {
        headers: { Authorization: `Bearer ${doctor.token}` },
    });
    assert.equal(deniedRead.status, 403);
    await call(doctor, { action: 'finish', operationId: revoked.operationId }, 403);
    assert.deepEqual((await document.ref.get()).data(), saved);
    assert.equal((await bucket.file(revoked.storagePath).exists())[0], false);
    await call(doctor, { action: 'begin', docId: document.ref.id, expectedStoragePath: saved.storagePath, fileName: 'x.png', metadata: { name: 'Bad', type: 'other', notes: '' } }, 403);
    await access.set({ granted: true });
    const cancelled = await begin(doctor, document);
    await upload(doctor, cancelled);
    assert.equal((await call(doctor, { action: 'cancel', operationId: cancelled.operationId })).committed, false);
    await call(doctor, { action: 'finish', operationId: cancelled.operationId }, 409);
    assert.deepEqual((await document.ref.get()).data(), saved);
    assert.equal((await bucket.file(cancelled.storagePath).exists())[0], false);
    assert.equal((await db.doc(`medical_document_replacements/${cancelled.operationId}`).get()).data().metadata, undefined);
    const invalid = await begin(doctor, document);
    await upload(doctor, invalid, 'text/plain', 403);
    await call(doctor, { action: 'cancel', operationId: invalid.operationId });
    const allowedRead = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(success.storagePath)}`, {
        headers: { Authorization: `Bearer ${doctor.token}` },
    });
    assert.equal(allowedRead.status, 200);
    const allowedDelete = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(success.storagePath)}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${doctor.token}` },
    });
    assert.equal(allowedDelete.status, 204);
    assert.equal((await bucket.file(success.storagePath).exists())[0], false);
    const missingRef = db.doc(`medical_document_replacements/${success.operationId}`);
    await missingRef.update({ nextMaintenanceAt: admin.firestore.Timestamp.fromMillis(1) });
    await runCleanup();
    assert.equal((await missingRef.get()).data().nextMaintenanceAt, undefined, 'Missing bytes cannot be repaired and should not retry forever');
    await access.delete();
});

test('finish/cancel arbitration preserves committed bytes and delayed sweep catches an in-flight cancelled upload', async () => {
    const patient = await account('student');
    const document = await record(patient);
    const op = await begin(patient, document);
    await upload(patient, op);
    // Exercise the real handlers and Firestore/Storage concurrently in this
    // process. This avoids a second CLI worker's cold-start timeout on the host;
    // the other groups establish the HTTP callable/authentication contract.
    const callable = require('../lib/documentReplacement').replaceMedicalDocument;
    const context = { auth: { uid: patient.uid } };
    const [finish, cancellation] = await Promise.allSettled([
        callable.run({ data: { action: 'finish', operationId: op.operationId }, ...context }),
        callable.run({ data: { action: 'cancel', operationId: op.operationId }, ...context }),
    ]);
    assert.equal(cancellation.status, 'fulfilled', cancellation.reason?.stack);
    const cancelled = cancellation.value;
    const current = (await document.ref.get()).data().storagePath;
    if (cancelled.committed) {
        assert.equal(finish.status, 'fulfilled');
        assert.equal(finish.value.committed, true);
        assert.equal(current, op.storagePath);
        assert.equal((await bucket.file(op.storagePath).exists())[0], true);
    } else {
        assert.equal(finish.status, 'rejected');
        assert.equal(finish.reason.code, 'aborted');
        assert.equal(current, document.data.storagePath);
        assert.equal((await bucket.file(op.storagePath).exists())[0], false);
    }
    const late = await begin(patient, document);
    await call(patient, { action: 'cancel', operationId: late.operationId });
    await bucket.file(late.storagePath).save(Buffer.from('Synthetic late upload completion'));
    await runCleanup();
    assert.equal((await bucket.file(late.storagePath).exists())[0], true, 'Grace sweep is delayed until upload expiry plus one hour');
    await db.doc(`medical_document_replacements/${late.operationId}`).update({ expiresAt: admin.firestore.Timestamp.fromMillis(1), nextMaintenanceAt: admin.firestore.Timestamp.fromMillis(1) });
    await runCleanup();
    assert.equal((await bucket.file(late.storagePath).exists())[0], false);
    assert.equal((await document.ref.get()).data().storagePath, current);
});

test('metadata edits and expired uploads keep the existing file and scheduled cleanup removes only abandoned candidates', async () => {
    const patient = await account('student');
    const document = await record(patient);
    const stale = await begin(patient, document);
    await upload(patient, stale);
    await document.ref.update({ notes: 'Newer metadata edit' });
    await call(patient, { action: 'finish', operationId: stale.operationId }, 409);
    assert.equal((await document.ref.get()).data().notes, 'Newer metadata edit');
    assert.equal((await document.ref.get()).data().storagePath, document.data.storagePath);
    assert.equal((await bucket.file(stale.storagePath).exists())[0], false);
    const expired = await begin(patient, document);
    await upload(patient, expired);
    await db.doc(`medical_document_replacements/${expired.operationId}`).update({ expiresAt: admin.firestore.Timestamp.fromMillis(1), nextMaintenanceAt: admin.firestore.Timestamp.fromMillis(1) });
    await runCleanup();
    assert.equal((await bucket.file(expired.storagePath).exists())[0], false);
    assert.equal((await bucket.file(document.data.storagePath).download())[0].toString(), 'ORIGINAL synthetic document');
    assert.equal((await document.ref.get()).data().storagePath, document.data.storagePath);
});

test('settled work leaves the due queue, failed deletion retries, and later deletion requeues safely', async () => {
    const patient = await account('student');
    const document = await record(patient);
    const replacement = await begin(patient, document);
    await upload(patient, replacement);
    await call(patient, { action: 'finish', operationId: replacement.operationId });
    const ref = db.doc(`medical_document_replacements/${replacement.operationId}`);
    assert.equal((await ref.get()).data().nextMaintenanceAt, undefined);
    await runCleanup();
    assert.equal((await ref.get()).data().nextMaintenanceAt, undefined);
    assert.equal((await bucket.file(replacement.storagePath).exists())[0], true);

    const before = await document.ref.get();
    await document.ref.delete();
    // Invoke the actual event handler deterministically; emulator delivery may
    // also duplicate it, as production Eventarc/Firestore can.
    const cleanup = require('../lib/documentReplacement');
    await cleanup.queueMedicalDocumentCleanup.run({
        id: `synthetic-${replacement.operationId}`, type: 'google.cloud.firestore.document.v1.written',
        time: new Date().toISOString(), params: { documentId: document.ref.id },
        data: { before, after: await document.ref.get() },
    });
    const { File } = require('@google-cloud/storage');
    const originalDelete = File.prototype.delete;
    let failed = 0;
    File.prototype.delete = function (...args) {
        if (this.name === replacement.storagePath) { failed++; return Promise.reject(new Error('Synthetic Storage outage')); }
        return originalDelete.apply(this, args);
    };
    try { await runCleanup(); } finally { File.prototype.delete = originalDelete; }
    assert.equal(failed, 1);
    assert.ok((await ref.get()).data().nextMaintenanceAt.toMillis() > Date.now());
    assert.equal((await bucket.file(replacement.storagePath).exists())[0], true);
    await ref.update({ nextMaintenanceAt: admin.firestore.Timestamp.fromMillis(1) });
    await Promise.all([runCleanup(), runCleanup()]);
    assert.equal((await bucket.file(replacement.storagePath).exists())[0], false);
    assert.equal((await ref.get()).data().nextMaintenanceAt, undefined);
    assert.equal((await bucket.file(document.data.storagePath).exists())[0], true, 'Legacy bytes are retained');
});

test('scheduler bounds its due batch and migration ends without rescanning settled history', async () => {
    const batch = db.batch();
    const refs = [];
    for (let i = 0; i < 57; i++) {
        const ref = db.doc(`medical_document_replacements/${prefix}-batch-${i}`);
        refs.push(ref); ops.add(ref.id);
        batch.set(ref, { docId: `${prefix}-absent`, actor: `${prefix}-absent`, userId: `${prefix}-absent`, status: 'aborted',
            expiresAt: admin.firestore.Timestamp.fromMillis(1), maintenanceVersion: 2,
            nextMaintenanceAt: admin.firestore.Timestamp.fromMillis(1) });
    }
    await batch.commit();
    await runCleanup();
    let due = (await db.getAll(...refs)).filter(doc => doc.data().nextMaintenanceAt);
    assert.equal(due.length, 7, 'Exactly 50 of 57 due records processed');
    await runCleanup();
    due = (await db.getAll(...refs)).filter(doc => doc.data().nextMaintenanceAt);
    assert.equal(due.length, 0);

    const state = db.doc('maintenance/documentReplacementV2');
    await state.delete(); // Local demo only; exercise the one-time legacy pass.
    for (const ref of refs) await ref.update({ maintenanceVersion: admin.firestore.FieldValue.delete() });
    await runCleanup();
    const first = (await state.get()).data();
    assert.equal(first.complete, false);
    assert.ok(first.cursor);
    for (let page = 0; page < 5 && !(await state.get()).data().complete; page++) await runCleanup();
    const completed = (await state.get()).data();
    assert.equal(completed.complete, true);
    await runCleanup();
    assert.deepEqual((await state.get()).data(), completed, 'Completed migration cursor does not restart');
});

test('v2 runtime contract delivers real Firestore events and HTTP scheduled cleanup without changing old paths', async () => {
    const functions = require('../lib/documentReplacement');
    for (const fn of Object.values(functions)) assert.equal(fn.__endpoint.platform, 'gcfv2');
    assert.equal(functions.queueMedicalDocumentCleanup.__endpoint.eventTrigger.eventType, 'google.cloud.firestore.document.v1.written');
    assert.equal(functions.queueMedicalDocumentCleanup.__endpoint.eventTrigger.retry, true);
    assert.equal(functions.cleanDocumentReplacements.__endpoint.scheduleTrigger.schedule, 'every 60 minutes');
    const patient = await account('student');
    const document = await record(patient);
    const replacement = await begin(patient, document);
    await upload(patient, replacement);
    await call(patient, { action: 'finish', operationId: replacement.operationId });
    const ref = db.doc(`medical_document_replacements/${replacement.operationId}`);
    assert.equal((await ref.get()).data().nextMaintenanceAt, undefined);
    await document.ref.delete();
    const deadline = Date.now() + 30000;
    while (!(await ref.get()).data().nextMaintenanceAt && Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 200));
    }
    assert.ok((await ref.get()).data().nextMaintenanceAt, 'Actual Functions emulator must deliver the v2 Firestore event');
    await runScheduledHttp();
    assert.equal((await bucket.file(replacement.storagePath).exists())[0], false);
    assert.equal((await ref.get()).data().nextMaintenanceAt, undefined);
    assert.equal((await bucket.file(document.data.storagePath).exists())[0], true, 'Original legacy file retained');
    const profile = `profile_images/${patient.uid}.png`;
    originalFiles.add(profile);
    await bucket.file(profile).save(Buffer.from('Synthetic original profile'), { contentType: 'image/png' });
    const oldImage = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(document.data.storagePath)}?alt=media`, {
        headers: { Authorization: `Bearer ${patient.token}` },
    });
    assert.equal(oldImage.status, 200);
    const photo = await fetch(`http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(profile)}?alt=media`, {
        headers: { Authorization: `Bearer ${patient.token}` },
    });
    assert.equal(photo.status, 200, 'Existing profile-photo policy retained');
    const legacy = await record(patient);
    const edited = await fetch(`http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents/medical_documents/${legacy.ref.id}?updateMask.fieldPaths=name&updateMask.fieldPaths=notes`, {
        method: 'PATCH', headers: { Authorization: `Bearer ${patient.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields: { name: { stringValue: 'Synthetic old-client metadata edit' }, notes: { stringValue: 'No reference change' } } }),
    });
    assert.equal(edited.status, 200, await edited.text());
    assert.equal((await legacy.ref.get()).data().storagePath, legacy.data.storagePath);
});

test('rollout pause blocks new begin calls while finish/cancel recovery remains available', async () => {
    const patient = await account('student');
    const document = await record(patient);
    const staged = await begin(patient, document);
    await upload(patient, staged);
    const callable = require('../lib/documentReplacement').replaceMedicalDocument;
    const previous = process.env.DOCUMENT_REPLACEMENT_PAUSED;
    process.env.DOCUMENT_REPLACEMENT_PAUSED = 'true';
    const request = data => ({ data, auth: { uid: patient.uid } });
    try {
        await assert.rejects(callable.run(request({ action: 'begin', docId: document.ref.id,
            expectedStoragePath: document.data.storagePath, fileName: 'paused.png',
            metadata: { name: 'Synthetic paused', type: 'other', notes: '' } })), error => error.code === 'unavailable');
        assert.equal((await callable.run(request({ action: 'finish', operationId: staged.operationId }))).committed, true);
        assert.equal((await callable.run(request({ action: 'cancel', operationId: staged.operationId }))).committed, true);
        assert.equal((await bucket.file(staged.storagePath).exists())[0], true);
    } finally {
        if (previous === undefined) delete process.env.DOCUMENT_REPLACEMENT_PAUSED;
        else process.env.DOCUMENT_REPLACEMENT_PAUSED = previous;
    }
});
