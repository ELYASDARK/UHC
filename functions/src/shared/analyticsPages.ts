import { createHash, randomUUID } from 'crypto';
import { FieldPath, Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { db } from '../firebase';

const pageSize = 2000;
const lifetimeMs = 15 * 60 * 1000;
const dayFormatter = new Intl.DateTimeFormat('en-CA', {
    year: 'numeric', month: '2-digit', day: '2-digit', timeZone: 'Asia/Baghdad',
});
type Counts = Record<string, number>;
type Aggregate = { total: number; statuses: Counts; departments: Counts; days: Counts };

export function addAnalyticsRows(aggregate: Aggregate, rows: FirebaseFirestore.QueryDocumentSnapshot[]): void {
    const increment = (counts: Counts, key: string) => {
        if (key.length > 256 || (!Object.prototype.hasOwnProperty.call(counts, key) && Object.keys(counts).length >= 512)) {
            throw new HttpsError('resource-exhausted', 'Analytics categories exceed the supported limit.');
        }
        Object.defineProperty(counts, key, { value: (Object.prototype.hasOwnProperty.call(counts, key) ? counts[key] : 0) + 1,
            writable: true, enumerable: true, configurable: true });
    };
    for (const row of rows) {
        const fields = row.data();
        increment(aggregate.statuses, String(fields.status || 'pending'));
        increment(aggregate.departments, String(fields.department || 'Unknown'));
        const date = fields.appointmentDate?.toDate?.();
        if (date) increment(aggregate.days, dayFormatter.format(date));
        aggregate.total++;
    }
}

/** Server-owned cursor and aggregate. Every page reads the same database snapshot. */
export async function appointmentAnalyticsPage(uid: string, data: Record<string, unknown>) {
    const action = data.action ?? 'start';
    const period = data.period;
    if (typeof period !== 'string' || !['week', 'month', 'year'].includes(period) ||
        typeof action !== 'string' || !['start', 'next', 'cancel'].includes(action)) {
        throw new HttpsError('invalid-argument', 'Invalid analytics request.');
    }
    const requestId = data.requestId;
    if (typeof requestId !== 'string' || !/^[a-zA-Z0-9-]{8,80}$/.test(requestId)) {
        throw new HttpsError('invalid-argument', 'Invalid analytics request identifier.');
    }
    const jobId = createHash('sha256').update(`${uid}:${requestId}`).digest('hex');
    const ref = db.collection('appointment_analytics_jobs').doc(jobId);
    const lease = randomUUID();
    const now = Timestamp.now();
    const result = await db.runTransaction(async tx => {
        const snapshot = await tx.get(ref);
        let job = snapshot.data();
        if (!job) {
            if (action !== 'start') throw new HttpsError('not-found', 'Analytics request expired. Refresh to start again.');
            // Bound parallel jobs and admission per caller without a collection scan.
            const admission = db.collection('appointment_analytics_admissions').doc(createHash('sha256').update(uid).digest('hex'));
            const previous = (await tx.get(admission)).data();
            if (previous?.lastStartedAt?.toMillis() > now.toMillis() - 2000) {
                throw new HttpsError('resource-exhausted', 'Please wait before refreshing analytics.');
            }
            if (previous?.activeJob) {
                const previousRef = db.collection('appointment_analytics_jobs').doc(previous.activeJob);
                const previousJob = (await tx.get(previousRef)).data();
                if (previousJob && !previousJob.complete) {
                    tx.update(previousRef, { cancelled: true, lease: null, leaseUntil: now });
                }
            }
            const start = snapshot.readTime.toDate();
            if (period === 'week') start.setUTCDate(start.getUTCDate() - 7);
            else if (period === 'month') start.setUTCMonth(start.getUTCMonth() - 1);
            else start.setUTCFullYear(start.getUTCFullYear() - 1);
            job = { owner: uid, period, readTime: snapshot.readTime, start: Timestamp.fromDate(start),
                end: snapshot.readTime, expiresAt: Timestamp.fromMillis(now.toMillis() + lifetimeMs), version: 0,
                complete: false, cancelled: false, total: 0, statuses: {}, departments: {}, days: {}, pageSize };
            tx.set(admission, { lastStartedAt: now, expiresAt: job.expiresAt, activeJob: jobId });
        }
        if (job.owner !== uid || job.period !== period) throw new HttpsError('permission-denied', 'Analytics request does not belong to this account.');
        if (job.expiresAt.toMillis() <= now.toMillis()) throw new HttpsError('deadline-exceeded', 'Analytics request expired. Refresh to start again.');
        if (action === 'cancel') {
            job.cancelled = true;
            tx.set(ref, { ...job, cancelled: true, lease: null, leaseUntil: now });
            return { job, cancelled: true };
        }
        if (job.cancelled) throw new HttpsError('cancelled', 'Analytics request was cancelled.');
        // Replay a completed page when an RPC response was lost. Never add it twice.
        const version = data.version ?? 0;
        if (typeof version !== 'number' || !Number.isInteger(version) || version < 0 || version > job.version) throw new HttpsError('invalid-argument', 'Invalid analytics page version.');
        if (job.complete || version < job.version) return { job, replay: true };
        if (job.leaseUntil?.toMillis() > now.toMillis()) throw new HttpsError('aborted', 'Analytics page is already running. Retry the same page.');
        if (job.version >= Math.ceil(250000 / (job.pageSize ?? 1000))) throw new HttpsError('resource-exhausted', 'Analytics exceeds 250,000 appointments. Choose a shorter period.');
        tx.set(ref, { ...job, lease, leaseUntil: Timestamp.fromMillis(now.toMillis() + 60000) });
        return { job };
    });
    const response = (job: FirebaseFirestore.DocumentData) => ({
        protocol: 2, period, total: job.total, statuses: job.statuses, departments: job.departments,
        days: job.days, complete: job.complete, cancelled: job.cancelled, version: job.version,
        truncated: !job.complete, pageSize: job.pageSize ?? 1000, asOf: job.readTime.toDate().toISOString(),
    });
    if (result.replay || result.cancelled) return response(result.job);
    const job = result.job;
    const size = job.pageSize ?? 1000;
    try {
        let query = db.collection('appointments').where('createdAt', '>=', job.start).where('createdAt', '<=', job.end)
            .orderBy('createdAt', 'desc').orderBy(FieldPath.documentId(), 'desc');
        if (job.cursor) query = query.startAfter(job.cursor.createdAt, job.cursor.id);
        const page = await db.runTransaction(tx => tx.get(query.select('status', 'department', 'appointmentDate', 'createdAt')
            .limit(size + 1)), { readOnly: true, readTime: job.readTime });
        const rows = page.docs.slice(0, size);
        addAnalyticsRows(job as Aggregate, rows);
        const last = rows[rows.length - 1];
        const next = { ...job, version: job.version + 1, complete: page.size <= size,
            cursor: last ? { createdAt: last.get('createdAt'), id: last.id } : job.cursor ?? null,
            lease: null, leaseUntil: Timestamp.now() };
        await db.runTransaction(async tx => {
            const current = (await tx.get(ref)).data();
            if (current?.cancelled || current?.lease !== lease || current?.version !== job.version) {
                throw new HttpsError('aborted', 'Analytics page changed. Retry or refresh.');
            }
            tx.set(ref, next);
        });
        return response(next);
    } catch (error) {
        await db.runTransaction(async tx => {
            const current = (await tx.get(ref)).data();
            if (current?.lease === lease) tx.update(ref, { lease: null, leaseUntil: Timestamp.now() });
        }).catch(() => undefined);
        throw error;
    }
}
