// Read-only security review probe. Creates and removes only unique synthetic records.
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const admin = require('firebase-admin');

assert.equal(process.env.GCLOUD_PROJECT, 'demo-uhc-test');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8080');

const app = admin.initializeApp({ projectId: 'demo-uhc-test' }, `metadata-probe-${randomUUID()}`);
const db = app.firestore();
const uid = `audit-analytics-${randomUUID()}`;
const email = `${uid}@demo.uhc.edu`;
const docId = `audit-medical-${randomUUID()}`;
const appointmentId = `audit-appointment-${randomUUID()}`;
const marker = 'SYNTHETIC medical note for permission boundary validation';

async function main() {
  try {
    await db.doc(`users/${uid}`).set({
      role: 'admin', isActive: true, googleEmail: email,
      adminPermissions: { 'analytics.view': true },
    });
    await db.doc(`medical_documents/${docId}`).set({
      userId: `synthetic-patient-${randomUUID()}`,
      addedBy: 'synthetic-patient', addedByRole: 'patient',
      name: 'Synthetic clinical record', type: 'medical_record', notes: marker,
      fileName: 'synthetic.pdf',
      storagePath: `medical_document_replacement_files/${docId}/${randomUUID()}`,
      url: 'https://example.invalid/private',
    });
    await db.doc(`appointments/${appointmentId}`).set({
      patientId: `synthetic-patient-${randomUUID()}`,
      patientName: 'Synthetic patient', patientEmail: 'synthetic-patient@demo.uhc.edu',
      doctorId: 'synthetic-doctor', status: 'completed',
      medicalNotes: marker, notes: 'Synthetic patient note',
    });
    // Unsigned token works only against the emulator. Keep it in memory.
    const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ sub: uid, user_id: uid, aud: 'demo-uhc-test',
      iss: 'https://securetoken.google.com/demo-uhc-test' })).toString('base64url');
    const idToken = `${header}.${payload}.`;
    const headers = { Authorization: `Bearer ${idToken}` };
    const base = 'http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents';
    const get = await fetch(`${base}/medical_documents/${docId}`, { headers });
    const body = await get.json();
    const query = await fetch(`${base}:runQuery`, {
      method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' },
      body: JSON.stringify({ structuredQuery: {
        from: [{ collectionId: 'medical_documents' }],
        where: { fieldFilter: { field: { fieldPath: '__name__' }, op: 'EQUAL', value: {
          referenceValue: `projects/demo-uhc-test/databases/(default)/documents/medical_documents/${docId}`,
        } } },
      } }),
    });
    const queryBody = await query.json();
    const appointmentGet = await fetch(`${base}/appointments/${appointmentId}`, { headers });
    const appointmentBody = await appointmentGet.json();
    await db.doc(`users/${uid}`).update({ adminPermissions: {} });
    const noPermissionGet = await fetch(`${base}/medical_documents/${docId}`, { headers });
    const noPermissionAppointmentGet = await fetch(`${base}/appointments/${appointmentId}`, { headers });
    const result = {
      actor: 'analytics-only admin',
      firestoreGetStatus: get.status,
      firestoreReturnsSyntheticMedicalNotes: body.fields?.notes?.stringValue === marker,
      firestoreQueryStatus: query.status,
      firestoreQueryReturnsSyntheticMedicalNotes: Array.isArray(queryBody) && queryBody.some(row => row.document?.fields?.notes?.stringValue === marker),
      appointmentGetStatus: appointmentGet.status,
      appointmentReturnsSyntheticMedicalNotes: appointmentBody.fields?.medicalNotes?.stringValue === marker,
      noPermissionMedicalDocumentStatus: noPermissionGet.status,
      noPermissionAppointmentStatus: noPermissionAppointmentGet.status,
    };
    console.log(JSON.stringify(result));
    assert.equal(get.status, 403);
    assert.equal(result.firestoreReturnsSyntheticMedicalNotes, false);
    assert.equal(query.status, 403);
    assert.equal(result.firestoreQueryReturnsSyntheticMedicalNotes, false);
    assert.equal(appointmentGet.status, 403);
    assert.equal(result.appointmentReturnsSyntheticMedicalNotes, false);
    await db.doc(`users/${uid}`).update({ adminPermissions: { 'reports.view': true } });
    assert.equal((await fetch(`${base}/medical_documents/${docId}`, { headers })).status, 200);
    assert.equal((await fetch(`${base}/appointments/${appointmentId}`, { headers })).status, 200);
    assert.equal(noPermissionGet.status, 403);
    assert.equal(noPermissionAppointmentGet.status, 403);
  } finally {
    await db.doc(`medical_documents/${docId}`).delete();
    await db.doc(`appointments/${appointmentId}`).delete();
    await db.doc(`users/${uid}`).delete();
    await app.delete();
  }
}
main().catch(error => {
  console.error(JSON.stringify({ probeFailed: true, code: error.code || error.name }));
  process.exitCode = 1;
});
