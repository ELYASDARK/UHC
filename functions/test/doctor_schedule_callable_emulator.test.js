const assert = require('node:assert/strict');
const { test } = require('node:test');
const admin = require('firebase-admin');

// This test calls the real local callable runtime, where namespace binding differs
// from importing the handler in a unit test. Never allow live Firebase access.
if (process.env.GCLOUD_PROJECT !== 'demo-uhc-test' ||
    process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080' ||
    process.env.FIREBASE_AUTH_EMULATOR_HOST !== '127.0.0.1:9099') {
    throw new Error('Requires the isolated demo-uhc-test Auth/Firestore/Functions emulators');
}
const app = admin.initializeApp({ projectId: 'demo-uhc-test' }, 'schedule-contract');
const db = app.firestore();
const auth = app.auth();
const prefix = `qa-schedule-contract-${Date.now()}`;

async function tokenFor(uid, role) {
    const email = `${uid}@demo.uhc.edu`;
    const imported = await auth.importUsers([{ uid, email, emailVerified: true,
        providerData: [{ providerId: 'google.com', uid: `synthetic-${uid}`, email }] }]);
    assert.equal(imported.failureCount, 0);
    await auth.updateUser(uid, { password: 'TestPassword123!' });
    await db.doc(`users/${uid}`).set({ role, isActive: true, adminPermissions: { 'doctors.manage': role === 'admin' } });
    const response = await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-emulator-api-key-demo-only', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: `${uid}@demo.uhc.edu`, password: 'TestPassword123!', returnSecureToken: true }),
    });
    const body = await response.json();
    assert.ok(body.idToken, 'Local Auth must return an ID token');
    return body.idToken;
}

test('real schedule callable persists only schedule/timestamp and rejects unauthorized writes', async () => {
    const doctorId = `${prefix}-doctor`;
    const adminId = `${prefix}-admin`;
    const studentId = `${prefix}-student`;
    const restrictedAdminId = `${prefix}-restricted-admin`;
    const doctor = db.doc(`doctors/${doctorId}`);
    try {
        const original = { name: 'Synthetic Schedule Contract', department: 'generalMedicine', email: 'synthetic@demo.uhc.edu', weeklySchedule: {} };
        await doctor.set(original);
        const adminToken = await tokenFor(adminId, 'admin');
        const studentToken = await tokenFor(studentId, 'student');
        const restrictedAdminToken = await tokenFor(restrictedAdminId, 'admin');
        await db.doc(`users/${restrictedAdminId}`).update({ adminPermissions: { 'doctors.manage': false } });
        const schedule = { monday: [{ startTime: '09:00', endTime: '09:30', isAvailable: false }] };
        const call = (token, weeklySchedule) => fetch('http://127.0.0.1:5001/demo-uhc-test/us-central1/updateDoctorSchedule', {
            method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
            body: JSON.stringify({ data: { doctorId, weeklySchedule } }),
        });
        const response = await call(adminToken, schedule);
        const result = await response.json();
        assert.equal(response.status, 200, JSON.stringify(result));
        assert.equal(result.result.success, true);
        const saved = (await doctor.get()).data();
        assert.deepEqual(saved.weeklySchedule, schedule);
        assert.ok(saved.updatedAt.toMillis() > 0);
        const { updatedAt, weeklySchedule, ...profile } = saved;
        const { weeklySchedule: ignored, ...originalProfile } = original;
        assert.deepEqual(profile, originalProfile);
        const denied = await call(studentToken, {});
        assert.equal(denied.status, 403);
        assert.equal((await denied.json()).error.status, 'PERMISSION_DENIED');
        assert.deepEqual((await doctor.get()).data(), saved);
        const restricted = await call(restrictedAdminToken, {});
        assert.equal(restricted.status, 403);
        assert.equal((await restricted.json()).error.status, 'PERMISSION_DENIED');
        assert.deepEqual((await doctor.get()).data(), saved);
    } finally {
        await Promise.all([doctor.delete(), ...[adminId, studentId, restrictedAdminId].map(async uid => {
            await db.doc(`users/${uid}`).delete();
            await auth.deleteUser(uid).catch(error => { if (error.code !== 'auth/user-not-found') throw error; });
        })]);
        await app.delete();
    }
});
