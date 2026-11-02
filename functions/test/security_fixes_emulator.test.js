const assert = require('node:assert/strict');
const { before, after, test } = require('node:test');
const { randomUUID } = require('node:crypto');
if (process.env.GCLOUD_PROJECT !== 'demo-uhc-test' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099' ||
    process.env.FIREBASE_STORAGE_EMULATOR_HOST !== '127.0.0.1:9199') {
    throw Error('Requires isolated demo-uhc-test Auth/Firestore/Storage emulators.');
}
process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-uhc-test', storageBucket: 'demo-uhc-test.appspot.com' });
const { db, auth, admin } = require('../lib/firebase');
const doctors = require('../lib/doctors');
const { completeInitialPasswordChange } = require('../lib/users');
const { changeAdminRole, assignSuperAdminSlot, rotateSuperAdminSlot } = require('../lib/admin');
const appointments = require('../lib/appointments');
const { withAccountMutation } = require('../lib/shared/accountMutation');
const prefix = `security-${Date.now()}`;
const password = randomUUID();
const records = new Set(), accounts = [], files = new Set();
let manager, owner, patient, doctorA, doctorB;
async function seed(path, fields) { records.add(path); await db.doc(path).set(fields); return db.doc(path); }
async function account(name, role) {
    const uid = `${prefix}-${name}`, email = `${uid}@demo.uhc.edu`;
    const imported = await auth.importUsers([{ uid, email, providerData: [{ providerId: 'google.com', uid, email }] }]);
    assert.equal(imported.failureCount, 0);
    await auth.updateUser(uid, { password });
    accounts.push(uid);
    await seed(`users/${uid}`, { role, isActive: true, fullName: 'Synthetic account', googleEmail: email,
        adminPermissions: { 'doctors.manage': true, 'appointments.manage': true } });
    return { uid, email, token: await signIn(email, password) };
}
async function signIn(email, secret) {
    const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-only', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password: secret, returnSecureToken: true }), signal: AbortSignal.timeout(15000),
    });
    assert.equal(response.status, 200, 'Synthetic sign-in must succeed');
    return (await response.json()).idToken;
}
async function run(handler, actor, data) {
    const token = await auth.verifyIdToken(actor.token);
    return handler.run({ auth: { uid: actor.uid, token }, data,
        rawRequest: { headers: { authorization: `Bearer ${actor.token}` } } });
}
async function grant(doctor, count = 1) {
    return seed(`doctor_patient_access/${doctor.uid}/patients/${patient.uid}`, {
        schemaVersion: 2, activeAppointmentCount: count, doctorUserId: doctor.uid, patientId: patient.uid,
    });
}
async function storage(actor, path, method = 'GET', metadata = {}) {
    const headers = { Authorization: `Bearer ${actor.token}` };
    let url = `http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o/${encodeURIComponent(path)}?alt=media`;
    let body;
    if (method === 'POST') {
        const boundary = 'synthetic_security_boundary';
        url = `http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o?name=${encodeURIComponent(path)}`;
        headers['Content-Type'] = `multipart/related; boundary=${boundary}`;
        headers['X-Goog-Upload-Protocol'] = 'multipart';
        body = `--${boundary}\r\nContent-Type: application/json\r\n\r\n${JSON.stringify({ name: path, contentType: 'image/png', metadata })}\r\n--${boundary}\r\nContent-Type: image/png\r\n\r\nsynthetic bytes\r\n--${boundary}--\r\n`;
        files.add(path);
    }
    return fetch(url, { method, headers, body, signal: AbortSignal.timeout(15000) });
}
async function patchDoctor(actor, id, fields) {
    const masks = Object.keys(fields).map(key => `updateMask.fieldPaths=${key}`).join('&');
    return fetch(`http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents/doctors/${id}?${masks}`, {
        method: 'PATCH', headers: { Authorization: `Bearer ${actor.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields }), signal: AbortSignal.timeout(15000),
    });
}
before(async () => {
    manager = await account('manager', 'admin'); owner = await account('owner', 'superAdmin');
    patient = await account('patient', 'student'); doctorA = await account('doctor-a', 'doctor'); doctorB = await account('doctor-b', 'doctor');
    await seed(`doctors/${doctorA.uid}`, { userId: doctorA.uid, name: 'Synthetic doctor A', specialization: 'General',
        experienceYears: 0, qualifications: [], isActive: true, isAvailable: true, department: 'security-general',
        weeklySchedule: { monday: [{ startTime: '09:00' }, { startTime: '10:00', endTime: '10:30' }] } });
    await seed(`doctors/${doctorB.uid}`, { userId: doctorB.uid, name: 'Synthetic doctor B', isActive: true });
    await seed(`departments/${prefix}`, { key: 'security-general', isActive: true });
});
after(async () => {
    for (const file of files) await admin.storage().bucket().file(file).delete({ ignoreNotFound: true });
    for (const path of records) await db.doc(path).delete();
    for (const uid of accounts) await auth.deleteUser(uid).catch(error => { if (error.code !== 'auth/user-not-found') throw error; });
    await admin.app().delete();
});

test('all doctor Auth operations reject promoted accounts without changing Auth or directory state', async () => {
    for (const role of ['admin', 'superAdmin']) {
        await db.doc(`users/${doctorB.uid}`).update({ role });
        const original = (await db.doc(`doctors/${doctorB.uid}`).get()).data();
        for (const [handler, parameters] of [[doctors.resetDoctorPassword, { newPassword: randomUUID() }],
            [doctors.updateDoctorEmail, { newEmail: 'changed@demo.uhc.edu' }], [doctors.deleteDoctorAccount, {}]]) {
            await assert.rejects(run(handler, manager, { doctorId: doctorB.uid, ...parameters }), error => error.code === 'failed-precondition');
            assert.deepEqual((await db.doc(`doctors/${doctorB.uid}`).get()).data(), original);
            assert.equal((await auth.getUser(doctorB.uid)).email, doctorB.email);
            assert.equal((await db.doc(`users/${doctorB.uid}`).get()).data().role, role);
        }
    }
    await db.doc(`users/${doctorB.uid}`).update({ role: 'doctor' });
    const replacementEmail = `${prefix}-changed@demo.uhc.edu`;
    assert.equal((await run(doctors.updateDoctorEmail, manager, { doctorId: doctorB.uid, newEmail: replacementEmail })).success, true);
    assert.equal((await auth.getUser(doctorB.uid)).email, replacementEmail);
    await run(doctors.updateDoctorEmail, manager, { doctorId: doctorB.uid, newEmail: doctorB.email });
    const removable = await account('removable', 'doctor');
    await seed(`doctors/${removable.uid}`, { userId: removable.uid });
    assert.equal((await run(doctors.deleteDoctorAccount, manager, { doctorId: removable.uid })).success, true);
    assert.equal((await db.doc(`users/${removable.uid}`).get()).exists, false);
    assert.equal((await db.doc(`doctors/${removable.uid}`).get()).exists, false);
    await assert.rejects(auth.getUser(removable.uid), error => error.code === 'auth/user-not-found');
    const sampleId = `${prefix}-sample`;
    await seed(`doctors/${sampleId}`, { userId: 'sample_synthetic' });
    assert.equal((await run(doctors.deleteDoctorAccount, manager, { doctorId: sampleId })).success, true);
});

test('account mutation serializes role promotion and password completion; normal onboarding remains available', async () => {
    let release, entered;
    const blocked = new Promise(resolve => { entered = resolve; });
    const hold = new Promise(resolve => { release = resolve; });
    const inFlight = withAccountMutation({ doctorId: doctorA.uid, roles: ['doctor'], mutate: async () => { entered(); await hold; } });
    await blocked;
    try {
        await db.doc(`users/${owner.uid}`).update({ superAdminType: 'primary' });
        for (const [handler, parameters] of [[changeAdminRole, { targetUid: doctorA.uid, newRole: 'admin' }],
            [assignSuperAdminSlot, { targetUid: doctorA.uid, slotType: 'backup' }],
            [rotateSuperAdminSlot, { replacementUid: doctorA.uid, slotType: 'primary' }]]) {
            await assert.rejects(run(handler, owner, parameters), error => error.code === 'aborted');
        }
        await assert.rejects(run(completeInitialPasswordChange, doctorA, { newPassword: randomUUID() }), error => error.code === 'aborted');
    } finally { release(); await inFlight; }
    const newPassword = randomUUID();
    await run(doctors.resetDoctorPassword, manager, { doctorId: doctorA.uid, newPassword });
    const cutoff = (await db.doc(`users/${doctorA.uid}`).get()).data().passwordResetAfter;
    // Exercise our freshness predicate directly even when the emulator verifier
    // rejects a revoked token before the handler can run.
    await assert.rejects(completeInitialPasswordChange.run({ auth: { uid: doctorA.uid, token: { auth_time: cutoff, iat: cutoff + 100 } },
        rawRequest: { headers: { authorization: `Bearer ${doctorA.token}` } }, data: { newPassword: randomUUID() } }), error => error.code === 'unauthenticated');
    await new Promise(resolve => setTimeout(resolve, Math.max(1, (cutoff + 1) * 1000 - Date.now() + 50)));
    doctorA.token = await signIn(doctorA.email, newPassword);
    const finalPassword = randomUUID();
    assert.equal((await run(completeInitialPasswordChange, doctorA, { newPassword: finalPassword })).success, true);
    doctorA.token = await signIn(doctorA.email, finalPassword);
    const onboarding = await account('onboarding', 'student');
    await db.doc(`users/${onboarding.uid}`).update({ requiresInitialPasswordChange: true, googleEmail: null });
    await auth.updateUser(onboarding.uid, { providersToUnlink: ['google.com'] });
    assert.equal((await run(completeInitialPasswordChange, onboarding, { newPassword: password })).success, true);
});

test('profile rules reject schedule/schema poisoning while preserving ordinary profile editing', async () => {
    for (const fields of [{ weeklySchedule: { integerValue: '0' } }, { name: { arrayValue: { values: [] } } },
        { userId: { stringValue: doctorB.uid } }, { isAvailable: { booleanValue: false } },
        { pendingAvailabilityRequestId: { stringValue: 'forged' } }]) {
        assert.equal((await patchDoctor(doctorA, doctorA.uid, fields)).status, 403);
    }
    assert.equal((await patchDoctor(doctorA, doctorA.uid, { name: { stringValue: 'Synthetic renamed doctor' } })).status, 200);
    for (const weeklySchedule of [{ monday: 0 }, { monday: [null] }]) {
        await assert.rejects(run(doctors.updateDoctorSchedule, manager, { doctorId: doctorA.uid, weeklySchedule }), error => error.code === 'invalid-argument');
    }
    const weeklySchedule = { monday: [{ startTime: '09:00' }, { startTime: '10:00', endTime: '10:30' }] };
    assert.equal((await run(doctors.updateDoctorSchedule, manager, { doctorId: doctorA.uid, weeklySchedule })).success, true);
});

test('medical blobs reject direct client reads, uploads and deletes for every formerly allowed actor', async () => {
    await grant(doctorA); await grant(doctorB);
    const path = `medical_documents/${patient.uid}/${prefix}/owned.png`;
    files.add(path); await admin.storage().bucket().file(path).save(Buffer.from('synthetic legacy'));
    for (const actor of [doctorA, doctorB, patient]) {
        assert.equal((await storage(actor, path, 'POST', { uhcAuthor: actor.uid })).status, 403);
        assert.equal((await storage(actor, path)).status, 403);
        assert.equal((await storage(actor, path, 'DELETE')).status, 403);
    }
    assert.equal((await admin.storage().bucket().file(path).download())[0].toString(), 'synthetic legacy');
});

test('final encounter closures revoke all access consumers, preserve other encounters, and serialize new bookings', async () => {
    const accessPath = `doctor_patient_access/${doctorA.uid}/patients/${patient.uid}`;
    records.add(accessPath);
    const medical = await seed(`medical_documents/${prefix}`, { userId: patient.uid, addedBy: doctorA.uid, addedByRole: 'doctor',
        storagePath: `medical_documents/${patient.uid}/${prefix}/lifecycle.png`, name: 'Synthetic file', notes: '', type: 'other', url: 'https://example.invalid/file' });
    files.add((await medical.get()).data().storagePath);
    await admin.storage().bucket().file((await medical.get()).data().storagePath).save(Buffer.from('synthetic document'));
    const readDocument = () => fetch(`http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents/${medical.path}`, { headers: { Authorization: `Bearer ${doctorA.token}` } });
    const readAccessCount = async () => (await db.doc(accessPath).get()).data().activeAppointmentCount;
    const makeAppointment = async (id, status = 'pending') => seed(`appointments/${prefix}-${id}`, {
        patientId: patient.uid, doctorId: doctorA.uid, doctorName: 'Synthetic doctor', status,
        appointmentDate: admin.firestore.Timestamp.fromDate(new Date('2030-11-04T00:00:00Z')), timeSlot: '09:00', type: 'consultation',
    });
    const a = await makeAppointment('a', 'confirmed'), b = await makeAppointment('b');
    await run(appointments.updateAppointmentStatus, doctorA, { appointmentId: a.id, status: 'completed' });
    assert.equal(await readAccessCount(), 1); assert.equal((await readDocument()).status, 200);
    await run(appointments.cancelAppointment, patient, { appointmentId: b.id });
    assert.equal(await readAccessCount(), 0); assert.equal((await readDocument()).status, 403);
    assert.equal((await storage(doctorA, (await medical.get()).data().storagePath)).status, 403);
    const { replaceMedicalDocument } = require('../lib/documentReplacement');
    await assert.rejects(run(replaceMedicalDocument, doctorA, { action: 'begin', docId: medical.id,
        expectedStoragePath: (await medical.get()).data().storagePath, metadata: { name: 'Synthetic', type: 'other', notes: '' }, fileName: 'new.png' }), error => error.code === 'permission-denied');
    // Real Firestore transactions and shared grant contention cover closures on
    // different appointment documents; mock transactions cannot prove this.
    const c = await makeAppointment('c'), d = await makeAppointment('d');
    await Promise.all([c, d].map(ref => run(appointments.cancelAppointment, patient, { appointmentId: ref.id })));
    assert.equal(await readAccessCount(), 0);
    const e = await makeAppointment('e');
    const booking = { patientId: patient.uid, doctorId: doctorA.uid, department: 'security-general', appointmentDate: '2030-11-04', timeSlot: '10:00', type: 'consultation' };
    const [, created] = await Promise.all([
        run(appointments.cancelAppointment, patient, { appointmentId: e.id }),
        appointments.createAppointmentCore(patient.uid, { fullName: 'Synthetic patient', email: patient.email }, booking),
    ]);
    records.add(`appointments/${created.appointmentId}`);
    assert.equal(await readAccessCount(), 1); assert.equal((await readDocument()).status, 200);
    await run(appointments.deleteAppointment, manager, { appointmentId: created.appointmentId });
    assert.equal(await readAccessCount(), 0);
    const noShow = await makeAppointment('no-show');
    const duplicate = await seed(`doctors/${prefix}-duplicate`, { userId: doctorA.uid, isActive: true });
    const secondMapping = await makeAppointment('second-mapping');
    await secondMapping.update({ doctorId: duplicate.id });
    await run(appointments.updateAppointmentStatus, doctorA, { appointmentId: noShow.id, status: 'noShow' });
    assert.equal(await readAccessCount(), 1, 'Another directory record linked to the same account preserves access');
    await run(appointments.cancelAppointment, patient, { appointmentId: secondMapping.id });
    assert.equal(await readAccessCount(), 0);
    const unavailable = await makeAppointment('unavailable');
    const { setDoctorAvailabilityByAdmin } = require('../lib/doctorAvailability');
    await run(setDoctorAvailabilityByAdmin, manager, { doctorId: doctorA.uid, isAvailable: false });
    assert.equal((await unavailable.get()).data().status, 'cancelled');
    assert.equal(await readAccessCount(), 0);
    await db.doc(accessPath).set({ granted: true });
    assert.equal((await readDocument()).status, 403, 'Unreconciled historical grant must fail closed');
});
