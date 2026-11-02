// Explicit deployment migration. Prints counts only; never copies patient data.
const path = require('node:path');
const admin = require('firebase-admin');
const cliArgs = process.argv.slice(2);
const option = name => cliArgs[cliArgs.indexOf(name) + 1];
const projectId = option('--project');
if (!['demo-uhc-test', 'uhca-20800'].includes(projectId)) throw Error('Supply the explicit UHC project.');
process.env.GCLOUD_PROJECT = projectId;
if (projectId === 'demo-uhc-test') {
    if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8080') throw Error('Local demo emulator required.');
} else if (Object.keys(process.env).some(key => key.endsWith('_EMULATOR_HOST') && process.env[key])) {
    throw Error('Do not mix live migration with emulator configuration.');
}
const apply = cliArgs.includes('--apply');
async function main() {
    const options = { projectId };
    if (cliArgs.includes('--firebase-tools-root')) {
        const cliAuth = require(path.join(option('--firebase-tools-root'), 'lib/auth.js'));
        const account = cliAuth.getProjectDefaultAccount(path.resolve(__dirname, '../..'));
        if (!account) throw Error('Firebase CLI login required.');
        const { OAuth2Client } = require('google-auth-library');
        const authClient = new OAuth2Client();
        authClient.refreshHandler = async () => {
            const tokens = await cliAuth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
            return { access_token: tokens.access_token, expiry_date: tokens.expires_at };
        };
        await authClient.getAccessToken();
        options.authClient = authClient;
    }
    const { Firestore } = require('@google-cloud/firestore');
    const db = new Firestore(options);
    const { readPatientAccessForUid, writePatientAccessChange } = require('../lib/shared/patientAccess');
    const [grants, doctors, appointments] = await Promise.all([
        db.collectionGroup('patients').get(), db.collection('doctors').get(),
        db.collection('appointments').where('status', 'in', ['pending', 'confirmed']).get(),
    ]);
    const pairs = new Map();
    const add = (doctorUserId, patientId) => {
        if (typeof doctorUserId === 'string' && doctorUserId && !doctorUserId.includes('/') &&
            typeof patientId === 'string' && patientId && !patientId.includes('/')) {
            pairs.set(JSON.stringify([doctorUserId, patientId]), { doctorUserId, patientId });
        }
    };
    for (const snapshot of grants.docs) {
        if (snapshot.ref.parent.parent?.parent.id === 'doctor_patient_access') add(snapshot.ref.parent.parent.id, snapshot.id);
    }
    const linked = new Map(doctors.docs.map(snapshot => [snapshot.id, snapshot.data().userId]));
    for (const snapshot of appointments.docs) add(linked.get(snapshot.data().doctorId), snapshot.data().patientId);
    const summary = { projectId, apply, pairs: pairs.size, changed: 0, active: 0, inactive: 0 };
    for (const pair of pairs.values()) {
        const result = await db.runTransaction(async tx => {
            const change = await readPatientAccessForUid(tx, pair, db);
            const saved = await tx.get(change.ref);
            const changed = saved.data()?.schemaVersion !== 2 || saved.data()?.activeAppointmentCount !== change.activeAppointmentCount;
            if (apply && changed) writePatientAccessChange(tx, change);
            return { changed, active: change.activeAppointmentCount > 0 };
        });
        summary.changed += Number(result.changed);
        summary[result.active ? 'active' : 'inactive']++;
    }
    console.log(JSON.stringify(summary));
    await db.terminate();
    await admin.app().delete();
}
main().catch(error => {
    console.error(JSON.stringify({ error: 'Patient-access reconciliation failed', code: error.code || error.name }));
    process.exitCode = 1;
});
