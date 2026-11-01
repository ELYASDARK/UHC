// Local operator tool. Dry-run by default. Deletes expired accounting/job metadata only.
// Never deletes Storage objects or changes upload balances, guards, retention, TTL or IAM.
'use strict';
const admin = require('firebase-admin');
const {createHash} = require('node:crypto');
const fs = require('node:fs');
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const projectId = option('--project', 'demo-uhc-test');
const mode = option('--mode', 'preflight');
const apply = args.includes('--apply');
const limit = Number(option('--limit', '100'));
if (!Number.isInteger(limit) || limit < 1 || limit > 500) throw Error('Limit must be 1..500.');
const loopback = value => /^(127\.0\.0\.1|localhost):[1-9][0-9]{0,4}$/.test(value || '') && Number(value.split(':')[1]) <= 65535;
if (projectId === 'demo-uhc-test') {
    if (!loopback(process.env.FIRESTORE_EMULATOR_HOST)) throw Error('Explicit loopback demo Firestore required.');
} else {
    if (!args.includes('--live-read') || apply || Object.keys(process.env).some(key => key.endsWith('_EMULATOR_HOST') && process.env[key])) {
        throw Error('Live access is read-only, explicit, and cannot mix emulator configuration.');
    }
}
const app = admin.initializeApp({projectId, storageBucket: `${projectId}.appspot.com`});
const db = app.firestore();

async function housekeeping() {
    const now = admin.firestore.Timestamp.now();
    const result = {};
    for (const collection of ['medical_upload_transfer_admissions', 'appointment_analytics_jobs', 'appointment_analytics_admissions']) {
        const page = await db.collection(collection).where('expiresAt', '<=', now).orderBy('expiresAt').limit(limit).get();
        let deleted = 0, skipped = 0;
        for (const snapshot of page.docs) {
            if (!apply) continue;
            const removed = await db.runTransaction(async tx => {
                const current = await tx.get(snapshot.ref);
                const value = current.data();
                if (!value?.expiresAt || value.expiresAt.toMillis() > now.toMillis() ||
                    value.leaseUntil?.toMillis() > now.toMillis() ||
                    !current.updateTime.isEqual(snapshot.updateTime)) return false;
                tx.delete(snapshot.ref);
                return true;
            });
            if (removed) deleted++; else skipped++;
        }
        result[collection] = {eligible: page.size, deleted, skipped, batchFull: page.size === limit};
    }
    return result;
}

async function migrateBudgets() {
    if (apply && !args.includes('--old-writers-drained')) throw Error('An operator must verify old-writer drain before applying.');
    let query = db.collection('medical_upload_budgets').orderBy(admin.firestore.FieldPath.documentId()).limit(limit);
    const afterId = option('--after-id', null);
    if (afterId) query = query.startAfter(afterId);
    const page = await query.get();
    let eligible = 0, created = 0, existing = 0;
    const hour = Math.floor(Date.now() / 3600000);
    for (const snapshot of page.docs) {
        if (snapshot.id !== 'project' && !/^user_[a-f0-9]{64}$/.test(snapshot.id)) continue;
        eligible++;
        const target = db.collection('medical_upload_budgets').doc(`v2_${snapshot.id}`);
        const converted = await db.runTransaction(async tx => {
            const [legacy, current] = await tx.getAll(snapshot.ref, target);
            if (current.exists) return false;
            const value = legacy.data();
            if (!value) return false;
            const debtHour = value.hour ?? hour;
            const bytes = value.bytes ?? 0;
            const attempts = value.attempts ?? 0;
            if (![debtHour, bytes, attempts].every(Number.isSafeInteger) || bytes < 0 || attempts < 0) {
                throw Error('Legacy accounting needs operator reconciliation. No debt was reset.');
            }
            const buckets = debtHour >= hour - 24 ? [{hour: debtHour, bytes}] : [];
            if (apply) tx.create(target, {version: 2, hour: debtHour, attempts, buckets,
                bytes: buckets.reduce((total, bucket) => total + bucket.bytes, 0)});
            return true;
        });
        if (converted) created++; else existing++;
    }
    return {scanned: page.size, eligible, [apply ? 'created' : 'wouldCreate']: created, existing,
        nextAfterId: page.size === limit ? page.docs[page.size - 1].id : null,
        oldWriterDrainProvenByTool: false};
}

async function inventory() {
    if (!loopback(process.env.FIREBASE_STORAGE_EMULATOR_HOST) && projectId === 'demo-uhc-test') throw Error('Loopback Storage emulator required.');
    const bucket = app.storage().bucket();
    const prefix = option('--prefix', 'medical_documents/');
    if (!['medical_documents/', 'medical_document_replacement_files/'].includes(prefix)) throw Error('Unsupported inventory prefix.');
    const marker = createHash('sha256').update(`${projectId}:${bucket.name}:${prefix}`).digest('hex');
    const statePath = option('--state-file', null);
    const prior = statePath && fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : null;
    if (prior && prior.marker !== marker) throw Error('Inventory checkpoint belongs to another bucket or prefix.');
    if (prior?.complete && !args.includes('--restart')) return {...prior, note: 'Completed inventory. Use --restart for a fresh scan.'};
    const job = args.includes('--restart') || !prior ? {marker, startedAt: Date.now(), objects: 0, bytes: 0, pages: 0} : prior;
    const [files, next] = await bucket.getFiles({prefix, maxResults: limit, autoPaginate: false, pageToken: job.pageToken || undefined});
    for (const file of files) {
        const size = Number(file.metadata.size);
        if (!Number.isSafeInteger(size) || size < 0) throw Error('Invalid Storage size metadata. No inventory progress saved.');
        job.objects++; job.bytes += size;
    }
    job.pages++; job.pageToken = next?.pageToken || null; job.complete = !job.pageToken; job.updatedAt = Date.now();
    // Local checkpoint only. Never writes the inventory into the clinic database.
    if (statePath) fs.writeFileSync(statePath, JSON.stringify(job, null, 2));
    const warningBytes = Number(option('--warn-bytes', '0'));
    if (!Number.isSafeInteger(warningBytes) || warningBytes < 0) throw Error('Invalid monitoring threshold.');
    return {...job, pageToken: job.pageToken ? '[server cursor retained locally]' : null,
        advisory: warningBytes > 0 && job.bytes >= warningBytes ? 'Capacity warning threshold reached' : 'No configured threshold exceeded',
        consistency: 'Metadata inventory is not an atomic snapshot. Concurrent changes require a new complete scan. Transfer allowance is independent.'};
}

async function main() {
    let result;
    if (mode === 'housekeeping') result = await housekeeping();
    else if (mode === 'migrate-budgets') result = await migrateBudgets();
    else if (mode === 'inventory') result = await inventory();
    else if (mode === 'preflight') {
        const [projectBudget, oldBudget, jobs] = await Promise.all([
            db.doc('medical_upload_budgets/v2_project').get(), db.doc('medical_upload_budgets/project').get(),
            db.collection('appointment_analytics_jobs').limit(limit).get(),
        ]);
        result = {newBudgetPresent: projectBudget.exists, legacyBudgetPresent: oldBudget.exists,
            sampledJobs: jobs.size, samplingBound: limit, oldWriterDrainProven: false,
            instructions: 'Read-only probe cannot prove old writers stopped. Verify serving revisions/traffic and wait for in-flight writers before migration.'};
    } else throw Error('Unknown mode.');
    console.log(JSON.stringify({project: projectId, mode, apply, result}, null, 2));
}
main().finally(() => app.delete()).catch(error => {
    console.error(`Capacity tool failed: ${error.code || error.name}. No secret or record content logged.`); process.exitCode = 1;
});
