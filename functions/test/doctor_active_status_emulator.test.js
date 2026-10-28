const assert = require('node:assert/strict');
const { before, after, test } = require('node:test');
const admin = require('firebase-admin');

if (process.env.GCLOUD_PROJECT !== 'demo-uhc-test' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') {
    throw new Error('Requires isolated demo-uhc-test Auth, Firestore and Functions emulators');
}
const app = admin.initializeApp({ projectId: 'demo-uhc-test' }, 'doctor-status-regression');
const db = app.firestore(), auth = app.auth();
const prefix = `qa-doctor-status-${Date.now()}`;
const accounts = {}, records = new Set();
const userId = role => `${prefix}-${role}`;
const doctorRef = db.doc(`doctors/${prefix}-doctor`);
const userRef = db.doc(`users/${userId('doctor')}`);
const password = 'SyntheticTest123!';

async function signIn(uid) {
    const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-demo-key', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: `${uid}@demo.uhc.edu`, password, returnSecureToken: true }),
    });
    const credentials = await response.json();
    assert.equal(response.status, 200, JSON.stringify(credentials));
    return credentials.idToken;
}
async function callStatus(token, doctorId, isActive) {
    const response = await fetch('http://127.0.0.1:5001/demo-uhc-test/us-central1/setDoctorActiveStatus', {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ data: { doctorId, isActive } }),
    });
    return { status: response.status, body: await response.json() };
}
async function ownLoginProfile() {
    const token = await signIn(userId('doctor'));
    const response = await fetch(`http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents/users/${userId('doctor')}`, {
        headers: { Authorization: `Bearer ${token}` },
    });
    assert.equal(response.status, 200);
    return (await response.json()).fields;
}
async function seed(ref, fields) { records.add(ref.path); await ref.set(fields); }

before(async () => {
    for (const [name, role, canManage] of [['admin', 'admin', true], ['restricted', 'admin', false], ['patient', 'student', false], ['doctor', 'doctor', false]]) {
        const uid = userId(name), email = `${uid}@demo.uhc.edu`;
        const imported = await auth.importUsers([{ uid, email, emailVerified: true,
            providerData: [{ providerId: 'google.com', uid: `synthetic-${uid}`, email }] }]);
        assert.equal(imported.failureCount, 0);
        await auth.updateUser(uid, { password });
        await seed(db.doc(`users/${uid}`), { role, isActive: true, fullName: 'Synthetic status regression', adminPermissions: { 'doctors.manage': canManage } });
        accounts[name] = await signIn(uid);
    }
    await seed(doctorRef, { userId: userId('doctor'), name: 'Synthetic doctor', isActive: true, weeklySchedule: { monday: [] }, isAvailable: true });
});

// Production report, 27 October 2026: reactivation changed the directory badge
// but left the login profile inactive. Exercise the real callable and fresh login.
test('deactivate then reactivate restores the fresh doctor login profile and clears old tokens', async () => {
    await seed(db.doc(`user_tokens/${userId('doctor')}/tokens/synthetic-device`), { token: 'synthetic-only' });
    const originalDoctor = (await doctorRef.get()).data();
    const originalUser = (await userRef.get()).data();
    for (const isActive of [false, true]) {
        const response = await callStatus(accounts.admin, doctorRef.id, isActive);
        assert.equal(response.status, 200, JSON.stringify(response.body));
        assert.equal(response.body.result.success, true);
        assert.equal((await doctorRef.get()).data().isActive, isActive);
        assert.equal((await userRef.get()).data().isActive, isActive, 'Doctor badge and login account must agree');
        assert.equal((await ownLoginProfile()).isActive.booleanValue, isActive, 'Fresh login must observe the restored account state');
    }
    assert.equal((await db.collection(`user_tokens/${userId('doctor')}/tokens`).get()).size, 0);
    for (const [ref, original] of [[doctorRef, originalDoctor], [userRef, originalUser]]) {
        const { isActive, updatedAt, ...unchanged } = (await ref.get()).data();
        const { isActive: ignored, ...expected } = original;
        assert.deepEqual(unchanged, expected);
        assert.ok(updatedAt.toMillis() > 0);
    }
    // Repair an account already left inconsistent by the previous implementation.
    await userRef.update({ isActive: false });
    assert.equal((await callStatus(accounts.admin, doctorRef.id, true)).status, 200);
    assert.equal((await ownLoginProfile()).isActive.booleanValue, true);
});

test('unauthorized callers cannot change either doctor or account status', async () => {
    const beforeDoctor = (await doctorRef.get()).data(), beforeUser = (await userRef.get()).data();
    for (const [token, expected] of [[null, 401], [accounts.patient, 403], [accounts.restricted, 403]]) {
        assert.equal((await callStatus(token, doctorRef.id, false)).status, expected);
        assert.deepEqual((await doctorRef.get()).data(), beforeDoctor);
        assert.deepEqual((await userRef.get()).data(), beforeUser);
    }
});

test('broken or non-doctor account links fail without partially changing the doctor badge', async () => {
    for (const [name, link] of [['missing-link', {}], ['missing-user', { userId: `${prefix}-absent` }], ['wrong-role', { userId: userId('patient') }]]) {
        const ref = db.doc(`doctors/${prefix}-${name}`);
        await seed(ref, { ...link, name: 'Synthetic invalid link', isActive: false });
        const beforeDoctor = (await ref.get()).data();
        const response = await callStatus(accounts.admin, ref.id, true);
        assert.equal(response.body.error?.status, 'FAILED_PRECONDITION', JSON.stringify(response));
        assert.deepEqual((await ref.get()).data(), beforeDoctor);
    }
    assert.equal((await db.doc(`users/${userId('patient')}`).get()).data().isActive, true);
});

after(async () => {
    for (const record of records) await db.doc(record).delete();
    for (const name of Object.keys(accounts)) await auth.deleteUser(userId(name));
    await app.delete();
});
