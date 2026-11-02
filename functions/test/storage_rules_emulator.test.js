const assert = require('node:assert/strict');
const { before, after, test } = require('node:test');
const { randomUUID, randomBytes } = require('node:crypto');
const admin = require('firebase-admin');

if (process.env.GCLOUD_PROJECT !== 'demo-uhc-test' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099' ||
    process.env.FIREBASE_STORAGE_EMULATOR_HOST !== '127.0.0.1:9199') {
    throw Error('Requires isolated demo Auth/Firestore/Storage emulators.');
}
const app = admin.initializeApp({ projectId: 'demo-uhc-test', storageBucket: 'demo-uhc-test.appspot.com' });
const db = app.firestore(), bucket = app.storage().bucket();
const suffix = randomUUID(), accounts = [], objects = new Set(), records = [];
const image = Buffer.from('synthetic image bytes');
let patient, doctor, manager, inactive, unlinked, superAdmin;

async function account(role, { active = true, linked = true, permissions = {} } = {}) {
    const uid = `synthetic-rules-${randomUUID()}`, email = `${uid}@example.test`;
    accounts.push(uid);
    assert.equal((await app.auth().importUsers([{ uid, email,
        providerData: linked ? [{ providerId: 'google.com', uid, email }] : [] }])).failureCount, 0);
    const password = randomBytes(24).toString('hex');
    await app.auth().updateUser(uid, { password });
    await db.doc(`users/${uid}`).set({ role, isActive: active,
        ...(linked ? { googleEmail: email } : {}), adminPermissions: permissions });
    const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-demo-only', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
    assert.equal(response.status, 200);
    const { idToken } = await response.json();
    assert.ok(idToken);
    return { uid, token: idToken };
}

async function request(actor, method, object, { body, type = 'image/png', media = false } = {}) {
    const base = 'http://127.0.0.1:9199/v0/b/demo-uhc-test.appspot.com/o';
    const url = method === 'POST'
        ? `${base}?uploadType=media&name=${encodeURIComponent(object)}`
        : `${base}/${encodeURIComponent(object)}${media ? '?alt=media' : ''}`;
    const response = await fetch(url, { method,
        headers: { ...(actor ? { Authorization: `Bearer ${actor.token}` } : {}),
            ...(body ? { 'Content-Type': type } : {}) }, body });
    const status = response.status;
    // Upload responses can include download tokens. Never log/save their bodies.
    await response.arrayBuffer();
    if (method === 'POST' && status === 200) objects.add(object);
    return status;
}

async function seedObject(name) {
    objects.add(name);
    await bucket.file(name).save(Buffer.from('synthetic private bytes'), { contentType: 'application/pdf' });
}

before(async () => {
    patient = await account('student');
    doctor = await account('doctor');
    manager = await account('admin', { permissions: { 'doctors.manage': true, 'users.manageNonAdmin': true,
        'reports.view': true, 'appointments.view': true } });
    inactive = await account('student', { active: false });
    unlinked = await account('student', { linked: false });
    superAdmin = await account('superAdmin');
});

after(async () => {
    for (const name of objects) await bucket.file(name).delete({ ignoreNotFound: true });
    for (const ref of records) await ref.delete();
    for (const uid of accounts) {
        await db.doc(`users/${uid}`).delete();
        await app.auth().deleteUser(uid);
    }
    await app.delete();
});

test('direct medical Storage remains denied even for owners, granted doctors and clinical administrators', async () => {
    const paths = [`medical_documents/${patient.uid}/self/${suffix}.pdf`,
        `medical_document_replacement_files/synthetic-${suffix}/operation`];
    const grant = db.doc(`doctor_patient_access/${doctor.uid}/patients/${patient.uid}`);
    records.push(grant);
    await grant.set({ schemaVersion: 2, activeAppointmentCount: 1 });
    const document = db.doc(`medical_documents/synthetic-${suffix}`);
    records.push(document);
    await document.set({ userId: patient.uid, addedBy: patient.uid, addedByRole: 'student', storagePath: paths[1] });
    for (const object of paths) {
        await seedObject(object);
        for (const [label, actor] of [['anonymous', null], ['owner', patient], ['granted doctor', doctor],
            ['clinical admin', manager], ['super-admin', superAdmin]]) {
            assert.equal(await request(actor, 'GET', object), 403, `${label} metadata denial`);
            assert.equal(await request(actor, 'GET', object, { media: true }), 403, `${label} media denial`);
            assert.equal(await request(actor, 'POST', object, { body: image }), 403, `${label} write denial`);
            assert.equal(await request(actor, 'DELETE', object), 403, `${label} delete denial`);
        }
    }
});

test('profile images retain active linked account, ownership, MIME and size checks', async () => {
    const own = `profile_images/${patient.uid}.png`;
    assert.equal(await request(patient, 'POST', own, { body: image }), 200);
    assert.equal(await request(doctor, 'GET', own, { media: true }), 200);
    for (const actor of [null, inactive, unlinked]) {
        assert.equal(await request(actor, 'GET', own), 403);
    }
    assert.equal(await request(doctor, 'POST', own, { body: image }), 403);
    assert.equal(await request(patient, 'POST', own, { body: image, type: 'application/pdf' }), 403);
    assert.equal(await request(patient, 'POST', own, { body: Buffer.alloc(5 * 1024 * 1024) }), 403);
    for (const actor of [inactive, unlinked]) {
        assert.equal(await request(actor, 'POST', `profile_images/${actor.uid}.png`, { body: image }), 403);
    }
    assert.equal(await request(patient, 'GET', `unmanaged/${suffix}.png`), 403);
});

test('managed photos retain separate permission checks and authorized deletion', async () => {
    const doctorsOnly = await account('admin', { permissions: { 'doctors.manage': true } });
    const usersOnly = await account('admin', { permissions: { 'users.manageNonAdmin': true } });
    for (const [prefix, allowed, wrong] of [['doctor_photos', doctorsOnly, usersOnly],
        ['user_photos', usersOnly, doctorsOnly]]) {
        const object = `${prefix}/synthetic-${suffix}.png`;
        assert.equal(await request(allowed, 'POST', object, { body: image }), 200);
        assert.equal(await request(patient, 'GET', object, { media: true }), 200);
        assert.equal(await request(wrong, 'POST', object, { body: image }), 403);
        assert.equal(await request(patient, 'DELETE', object), 403);
        assert.equal(await request(allowed, 'DELETE', object), 204);
        assert.equal(await request(superAdmin, 'POST', object, { body: image }), 200);
        assert.equal(await request(superAdmin, 'DELETE', object), 204);
    }
});
