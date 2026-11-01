const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
process.env.GCLOUD_PROJECT = 'demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const { db } = require('../lib/firebase');
const { reserveMedicalUpload } = require('../lib/shared/medicalUploadBudget');
const MiB = 1024 ** 2, hour = 3600000;
const hash = value => createHash('sha256').update(value).digest('hex');
function fixture(t) {
    const documents = new Map();
    let now = 100 * hour;
    t.mock.method(Date, 'now', () => now);
    t.mock.method(db, 'doc', path => ({ path }));
    t.mock.method(db, 'runTransaction', async callback => callback({
        getAll: async (...refs) => refs.map(ref => ({ exists: documents.has(ref.path), data: () => structuredClone(documents.get(ref.path)) })),
        set: (ref, fields) => documents.set(ref.path, fields),
    }));
    return { documents, advance: hours => now += hours * hour,
        personal: uid => documents.get(`medical_upload_budgets/v2_user_${hash(uid)}`) };
}

test('retries deduplicate admitted bytes, remain request bounded, and zero-byte begin creates no receipt', async t => {
    const f = fixture(t);
    for (let i = 0; i < 60; i++) await reserveMedicalUpload('doctor', 'same', 19 * MiB);
    assert.equal(f.personal('doctor').bytes, 19 * MiB);
    await assert.rejects(reserveMedicalUpload('doctor', 'new', 1), { code: 'resource-exhausted' });
    f.advance(1);
    await reserveMedicalUpload('doctor', 'begin', 0);
    assert.equal([...f.documents.keys()].filter(k => k.startsWith('medical_upload_transfer_admissions/')).length, 1);
    await assert.rejects(reserveMedicalUpload('doctor', 'same', 1), { code: 'invalid-argument' });
});

test('failed, aborted, replaced and deleted uploads stay charged then clinic capacity recovers within 25 hours', async t => {
    const f = fixture(t);
    for (let i = 0; i < 53; i++) await reserveMedicalUpload('doctor', `patient-${i}`, 19 * MiB);
    f.advance(1);
    await assert.rejects(reserveMedicalUpload('doctor', 'failed-or-deleted-retry', 19 * MiB), { code: 'resource-exhausted' });
    // Other identities retain independent caller capacity.
    await reserveMedicalUpload('another-doctor', 'patient-1', 19 * MiB);
    f.advance(23);
    await assert.rejects(reserveMedicalUpload('doctor', 'still-protected', 19 * MiB), { code: 'resource-exhausted' });
    f.advance(1);
    await reserveMedicalUpload('doctor', 'patient-0', 19 * MiB);
    assert.equal(f.personal('doctor').bytes, 19 * MiB);
    for (let day = 0; day < 30; day++) {
        f.advance(25);
        for (let i = 0; i < 53; i++) await reserveMedicalUpload('doctor', `day-${day}-${i}`, 19 * MiB);
        assert.ok(f.personal('doctor').buckets.length <= 25);
    }
});

test('legacy exhausted budgets recover without resetting debt on each denied retry', async t => {
    const f = fixture(t);
    f.documents.set(`medical_upload_budgets/user_${hash('doctor')}`, { hour: 100, attempts: 10, bytes: 1024 ** 3 });
    f.documents.set('medical_upload_budgets/project', { hour: 100, attempts: 10, bytes: 100 * 1024 ** 3 });
    await assert.rejects(reserveMedicalUpload('doctor', 'new', 1), { code: 'resource-exhausted' });
    f.advance(24);
    await assert.rejects(reserveMedicalUpload('doctor', 'new', 1), { code: 'resource-exhausted' });
    f.advance(1);
    await reserveMedicalUpload('doctor', 'new', 1);
    assert.equal(f.personal('doctor').bytes, 1);
});

test('project quota blocks a fresh caller and recovers after the rolling window', async t => {
    const f = fixture(t);
    f.documents.set('medical_upload_budgets/v2_project', { version: 2, hour: 100, attempts: 0, buckets: [{ hour: 100, bytes: 100 * 1024 ** 3 }] });
    await assert.rejects(reserveMedicalUpload('fresh', 'new', 1), { code: 'resource-exhausted' });
    f.advance(25);
    await reserveMedicalUpload('fresh', 'new', 1);
    assert.equal(f.personal('fresh').bytes, 1);
});

test('invalid sizes never create accounting state', async t => {
    const f = fixture(t);
    for (const bytes of [-1, NaN, 1.5, 20 * MiB]) await assert.rejects(reserveMedicalUpload('doctor', 'invalid', bytes), { code: 'invalid-argument' });
    assert.equal(f.documents.size, 0);
});
