const { test } = require('node:test');
const assert = require('node:assert/strict');
process.env.GCLOUD_PROJECT = 'demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const { db, auth } = require('../lib/firebase');
const { getAppointmentAnalytics } = require('../lib/analytics');

test('analytics-only admins receive aggregate counts without clinical records', async t => {
    t.mock.method(auth, 'getUser', async () => ({ providerData: [{ providerId: 'google.com' }] }));
    const query = {
        where() { return this; }, orderBy() { return this; }, select() { return this; }, limit() { return this; },
        get: async () => ({ size: 1, docs: [{ data: () => ({ status: 'completed', department: 'General',
            patientEmail: 'private@example.test', medicalNotes: 'Private synthetic notes',
            appointmentDate: { toDate: () => new Date('2026-10-29T09:00:00Z') } }) }] }),
    };
    t.mock.method(db, 'collection', name => name === 'users' ? {
        doc: () => ({ get: async () => ({ exists: true, data: () => ({ role: 'admin', isActive: true,
            adminPermissions: { 'analytics.view': true } }) }) }),
    } : query);
    const summary = await getAppointmentAnalytics.run({ auth: { uid: 'analytics' }, data: { period: 'week' } });
    assert.deepEqual(summary.statuses, { completed: 1 });
    assert.deepEqual(summary.departments, { General: 1 });
    assert.equal(summary.total, 1);
    assert.equal(JSON.stringify(summary).includes('Private'), false);
    assert.equal(JSON.stringify(summary).includes('example.test'), false);
    await assert.rejects(getAppointmentAnalytics.run({ auth: { uid: 'analytics' }, data: { period: 'all' } }),
        error => error.code === 'invalid-argument');
});

test('patients cannot request administrative analytics', async t => {
    t.mock.method(auth, 'getUser', async () => ({ providerData: [{ providerId: 'google.com' }] }));
    t.mock.method(db, 'collection', () => ({ doc: () => ({ get: async () => ({ exists: true,
        data: () => ({ role: 'student', isActive: true }) }) }) }));
    await assert.rejects(getAppointmentAnalytics.run({ auth: { uid: 'patient' }, data: { period: 'week' } }),
        error => error.code === 'permission-denied');
});
