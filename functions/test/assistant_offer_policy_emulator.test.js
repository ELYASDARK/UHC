const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID, createHash} = require('node:crypto');

process.env.GCLOUD_PROJECT = 'demo-uhc-test';
process.env.GOOGLE_CLOUD_PROJECT = 'demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.AI_OFFLINE_SYNTHETIC_TESTING = 'true';
const {db, auth, admin} = require('../lib/firebase');
const {createAppointment, createAppointmentCore} = require('../lib/appointments');
const {confirmAssistantAppointment} = require('../lib/assistant');

const baseline = process.env.QA_EXPECT_OFFER_BYPASS === 'true';
const suffix = randomUUID();
let sequence = 0;
const routes = {
    general: (uid, offerId) => createAppointment.run({auth: {uid}, data: {patientId: uid, offerId, confirmed: true}}),
    assistant: (uid, offerId) => confirmAssistantAppointment.run({auth: {uid}, data: {offerId, confirmed: true}}),
};

async function fixture(role = 'admin', {active = true, linked = true} = {}) {
    const uid = `qa-policy-${suffix}-${sequence++}`;
    const email = `${uid}@example.test`;
    await auth.importUsers([{uid, email, providerData: linked ? [{providerId: 'google.com', uid, email}] : []}]);
    await db.doc(`users/${uid}`).set({role, isActive: active, fullName: 'Synthetic Policy User', email});
    const doctorId = `${uid}-doctor`, department = `${uid}-department`;
    const date = new Date(Date.now() + 3 * 86400000).toISOString().slice(0, 10);
    await db.doc(`departments/${department}`).set({key: department, name: 'Synthetic Policy Department', isActive: true});
    await db.doc(`doctors/${doctorId}`).set({name: 'Synthetic Policy Doctor', department, isActive: true, isAvailable: true,
        weeklySchedule: Object.fromEntries(['monday','tuesday','wednesday','thursday','friday','saturday','sunday']
            .map(day => [day, [{startTime: '13:00', endTime: '13:30', isAvailable: true}]]))});
    const offerId = `${uid}-offer`;
    await db.doc(`assistant_chats/${uid}`).set({revision: 1, messages: [{sender: 'assistant', text: 'Synthetic offer', offerIds: [offerId]}],
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 600000),
        offers: [{offerId, doctorId, doctorName: 'Synthetic Policy Doctor', department, appointmentDate: date,
            timeSlot: '13:00 - 13:30', expiresAt: new Date(Date.now() + 600000).toISOString(), isAvailable: true}]});
    return {uid, offerId, doctorId, department, date};
}

// Compare persisted values in memory. Never print receipts, QR payloads or tokens.
async function digest() {
    const names = ['appointments','appointment_slot_locks','appointment_day_coordination',
        'doctor_patient_access','assistant_chats','appointment_idempotency'];
    const values = [];
    for (const name of names) {
        const snapshot = await db.collection(name).get();
        values.push([name, snapshot.docs.map(doc => [doc.id, doc.data()])]);
    }
    const access = await db.collectionGroup('patients').get();
    values.push(['accessPatients', access.docs.map(doc => [doc.ref.path, doc.data()])]);
    return createHash('sha256').update(JSON.stringify(values)).digest('hex');
}

async function denied(operation, code = 'permission-denied') {
    const before = await digest();
    let error;
    try { await operation(); } catch (caught) { error = caught; }
    assert.equal(error?.code, code, 'Expected authorization rejection; response details suppressed');
    assert.equal(await digest(), before, 'Denial changed booking state');
}

test('assistant offer policy on real demo Auth/Firestore, including general callable and receipt replay', {timeout: 240000}, async t => {
    t.mock.method(console, 'log', () => {});
    t.after(async () => {
        for (const name of ['doctors', 'departments']) {
            const snapshot = await db.collection(name).get();
            const batch = db.batch();
            for (const doc of snapshot.docs) {
                if (doc.id.startsWith(`qa-policy-${suffix}-`)) batch.update(doc.ref, {isActive: false});
            }
            await batch.commit();
        }
        await admin.app().delete();
    });
    if (baseline) {
        const fresh = await fixture();
        await db.doc(`users/${fresh.uid}`).update({role: 'superAdmin'});
        await denied(() => routes.assistant(fresh.uid, fresh.offerId));
        const result = await routes.general(fresh.uid, fresh.offerId);
        assert.equal(result.success, true);
        const replay = await routes.general(fresh.uid, fresh.offerId);
        assert.equal(replay.isExisting, true);
        process.stdout.write('BEFORE FIX: promoted super-admin consumed own saved offer and replayed its receipt through general callable; dedicated assistant route denied. Real demo Auth/Firestore.\n');
        return;
    }
    for (const [name, route] of Object.entries(routes)) {
        for (const role of ['student', 'staff', 'admin']) {
            await t.test(`${name}: ${role} confirms own offer and retries`, async () => {
                const f = await fixture(role);
                const result = await route(f.uid, f.offerId);
                assert.equal(result.success, true);
                assert.equal((await db.doc(`appointments/${result.appointmentId}`).get()).get('patientId'), f.uid);
                const before = await digest();
                const retry = await route(f.uid, f.offerId);
                assert.equal(retry.appointmentId === result.appointmentId, true);
                assert.equal(await digest(), before);
                await db.doc(`users/${f.uid}`).update({role: 'superAdmin'});
                for (const replayRoute of Object.values(routes)) await denied(() => replayRoute(f.uid, f.offerId));
            });
        }
        for (const role of ['superAdmin', 'doctor']) await t.test(`${name}: ${role} saved offer denied without mutation`, async () => {
            const f = await fixture(role);
            await denied(() => route(f.uid, f.offerId));
        });
        await t.test(`${name}: promotion before consumption, inactive, unlinked and foreign offers denied`, async () => {
            const promoted = await fixture();
            await db.doc(`users/${promoted.uid}`).update({role: 'superAdmin'});
            await denied(() => route(promoted.uid, promoted.offerId));
            const inactive = await fixture('admin', {active: false});
            await denied(() => route(inactive.uid, inactive.offerId));
            const unlinked = await fixture('admin', {linked: false});
            await denied(() => route(unlinked.uid, unlinked.offerId), 'failed-precondition');
            const owner = await fixture(), other = await fixture();
            await denied(() => route(other.uid, owner.offerId), 'not-found');
            const expired = await fixture();
            const chat = await db.doc(`assistant_chats/${expired.uid}`).get();
            await chat.ref.update({offers: chat.get('offers').map(offer => ({...offer, expiresAt: new Date(0).toISOString()}))});
            await denied(() => route(expired.uid, expired.offerId), 'failed-precondition');
        });
    }
    for (const role of ['student', 'staff', 'admin', 'superAdmin', 'doctor']) await t.test(`direct booking retains existing ${role} permission`, async () => {
        const f = await fixture(role);
        const result = await createAppointment.run({auth: {uid: f.uid}, data: {patientId: f.uid, doctorId: f.doctorId,
            department: f.department, appointmentDate: f.date, timeSlot: '13:00 - 13:30', idempotencyKey: 'synthetic-direct'}});
        assert.equal(result.success, true);
    });
    await t.test('consumed receipt is denied after deactivation or Google unlinking, including core callers', async () => {
        const f = await fixture();
        const stale = (await db.doc(`users/${f.uid}`).get()).data();
        await routes.general(f.uid, f.offerId);
        await db.doc(`users/${f.uid}`).update({isActive: false});
        for (const route of Object.values(routes)) await denied(() => route(f.uid, f.offerId));
        await db.doc(`users/${f.uid}`).update({isActive: true});
        await auth.updateUser(f.uid, {providersToUnlink: ['google.com']});
        for (const route of Object.values(routes)) await denied(() => route(f.uid, f.offerId), 'failed-precondition');
        await denied(() => createAppointmentCore(f.uid, stale,
            {patientId: f.uid, offerId: f.offerId, confirmed: true}), 'failed-precondition');
    });
    await t.test('promotion after outer caller read but before transaction check denies stale core data', async () => {
        const f = await fixture();
        const stale = (await db.doc(`users/${f.uid}`).get()).data();
        const original = db.runTransaction.bind(db);
        const hook = t.mock.method(db, 'runTransaction', async callback => {
            await db.doc(`users/${f.uid}`).update({role: 'superAdmin'});
            return original(callback);
        });
        try { await denied(() => createAppointmentCore(f.uid, stale, {patientId: f.uid, offerId: f.offerId, confirmed: true})); }
        finally { hook.mock.restore(); }
    });
    await t.test('confirmation holding profile read lock serializes before concurrent promotion', async () => {
        const f = await fixture();
        const original = db.runTransaction.bind(db);
        let promotion;
        const hook = t.mock.method(db, 'runTransaction', callback => original(async transaction => {
            const get = transaction.get.bind(transaction);
            transaction.get = async reference => {
                const snapshot = await get(reference);
                if (reference.path === `users/${f.uid}` && !promotion) {
                    promotion = db.doc(`users/${f.uid}`).update({role: 'superAdmin'});
                    await new Promise(resolve => setTimeout(resolve, 150));
                }
                return snapshot;
            };
            return callback(transaction);
        }));
        try {
            const result = await routes.general(f.uid, f.offerId);
            assert.equal(result.success, true);
            assert.ok(promotion, 'Policy must read profile inside transaction');
            await promotion;
        } finally { hook.mock.restore(); }
        for (const route of Object.values(routes)) await denied(() => route(f.uid, f.offerId));
    });
});
