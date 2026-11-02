const { test } = require('node:test');
// Review evidence only. Runs current TypeScript source in memory and mocks the
// Firebase SDK boundaries. No production requests and no compiled output files.
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');

process.env.GCLOUD_PROJECT = 'demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';


const { db, auth } = require(path.join(root, 'functions/lib/firebase.js'));
const rows = new Map();
function ref(documentPath) {
    return {
        path: documentPath,
        id: documentPath.split('/').pop(),
        collection: name => collection(`${documentPath}/${name}`),
        get: async () => snapshot(ref(documentPath)),
    };
}
function snapshot(reference) {
    const data = rows.get(reference.path);
    return { ref: reference, id: reference.id, exists: !!data, data: () => data };
}
function collection(collectionPath) {
    return {
        doc: id => ref(`${collectionPath}/${id}`),
        where: (key, operator, value) => {
            assert.equal(operator, '==');
            return { path: collectionPath, key, value };
        },
    };
}
db.collection = collection;
auth.getUser = async uid => ({ uid, providerData: [{ providerId: 'google.com' }] });
db.runTransaction = async callback => callback({
    get: async reference => reference.key ? {
        docs: [...rows].filter(([documentPath, data]) =>
            documentPath.split('/').length === 2 &&
            documentPath.startsWith(`${reference.path}/`) &&
            data[reference.key] === reference.value,
        ).map(([documentPath]) => snapshot(ref(documentPath))),
    } : snapshot(reference),
    getAll: async (...references) => references.map(snapshot),
    set: (reference, data) => rows.set(reference.path, data),
    update: (reference, data) => rows.set(reference.path, { ...rows.get(reference.path), ...data }),
    delete: reference => rows.delete(reference.path),
});

// The callable, ownership check, patient-access maintenance and slot helpers are real.
const { cancelAppointment } = require(path.join(root, 'functions/lib/appointments.js'));
test('patients cannot cancel terminal visits or bypass notice window', async () => {
    for (const status of ['completed', 'noShow', 'cancelled', 'pending']) {
        rows.clear();
        rows.set('users/patient', {
            role: 'student', isActive: true, fullName: 'Synthetic Patient',
            googleEmail: 'synthetic@example.test',
        });
        rows.set('doctors/doctor', { userId: 'doctor-auth', isActive: true });
        rows.set('appointments/visit', {
            patientId: 'patient', doctorId: 'doctor', doctorName: 'Synthetic Doctor',
            status, appointmentDate: { toDate: () => new Date(Date.now() - 86400000) },
            timeSlot: '09:00 - 09:30',
        });
        await assert.rejects(cancelAppointment.run({
            auth: { uid: 'patient' }, data: { appointmentId: 'visit', statusUpdatedBy: 'forged' },
        }), error => error.code === 'failed-precondition');
        assert.equal(rows.get('appointments/visit').status, status);
    }
});
