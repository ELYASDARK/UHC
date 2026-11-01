const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
assert.equal(process.env.GCLOUD_PROJECT, 'demo-uhc-test');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');
const { db, admin } = require('../lib/firebase');
const { reserveMedicalUpload } = require('../lib/shared/medicalUploadBudget');

test('concurrent retries reserve bytes once in real Firestore', async () => {
    const uid = `synthetic-budget-${randomUUID()}`;
    const hash = value => createHash('sha256').update(value).digest('hex');
    const personal = db.doc(`medical_upload_budgets/v2_user_${hash(uid)}`);
    const admission = db.doc(`medical_upload_transfer_admissions/${hash(JSON.stringify([uid, 'same']))}`);
    try {
        await Promise.all([reserveMedicalUpload(uid, 'same', 5), reserveMedicalUpload(uid, 'same', 5), reserveMedicalUpload(uid, 'different', 7)]);
        const usage = (await personal.get()).data();
        assert.equal(usage.bytes, 12);
        assert.equal(usage.attempts, 3);
    } finally {
        await personal.delete();
        await admission.delete();
        await db.doc(`medical_upload_transfer_admissions/${hash(JSON.stringify([uid, 'different']))}`).delete();
        await db.terminate();
        await admin.app().delete();
    }
});
