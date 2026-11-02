import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { db } from './firebase';
import { getCallerUserDoc, requireAuth } from './shared/auth';
import { appointmentAnalyticsPage } from './shared/analyticsPages';

export const getAppointmentAnalytics = onCall({ region: 'us-central1', maxInstances: 10 }, async request => {
    const uid = requireAuth(request);
    const caller = (await getCallerUserDoc(uid)).data()!;
    if (caller.role !== 'superAdmin' && (caller.role !== 'admin' ||
        !['analytics.view', 'appointments.view', 'reports.view'].some(key => caller.adminPermissions?.[key] === true))) {
        throw new HttpsError('permission-denied', 'Analytics access is unavailable.');
    }
    const period = request.data?.period;
    if (request.data?.protocol === 2 && period !== 'dashboard') return appointmentAnalyticsPage(uid, request.data);
    const appointments = db.collection('appointments');
    if (period === 'dashboard') {
        const now = new Date();
        const day = new Date(now.toLocaleString('en-US', { timeZone: 'Asia/Baghdad' }));
        const start = Date.UTC(day.getFullYear(), day.getMonth(), day.getDate()) - 3 * 3600000;
        const counts = await Promise.all([
            appointments.count().get(), appointments.where('status', '==', 'pending').count().get(),
            appointments.where('appointmentDate', '>=', Timestamp.fromMillis(start))
                .where('appointmentDate', '<', Timestamp.fromMillis(start + 86400000)).count().get(),
            appointments.where('status', '==', 'completed').count().get(),
        ]);
        return { total: counts[0].data().count, pending: counts[1].data().count,
            today: counts[2].data().count, completed: counts[3].data().count };
    }
    if (!['week', 'month', 'year'].includes(period)) throw new HttpsError('invalid-argument', 'Invalid period.');
    const start = new Date();
    if (period === 'week') start.setDate(start.getDate() - 7);
    else if (period === 'month') start.setMonth(start.getMonth() - 1);
    else start.setFullYear(start.getFullYear() - 1);
    const end = Timestamp.now();
    // One lookahead record distinguishes exactly 5,000 from incomplete data.
    // Aggregate-only response: never return clinical rows or client cursors.
    const limit = 5000;
    const page = await appointments.where('createdAt', '>=', Timestamp.fromDate(start))
        .where('createdAt', '<=', end).orderBy('createdAt', 'desc')
        .select('status', 'department', 'appointmentDate').limit(limit + 1).get();
    const included = page.docs.slice(0, limit);
    const statuses = new Map<string, number>();
    const departments = new Map<string, number>();
    const days = new Map<string, number>();
    const count = (map: Map<string, number>, key: string) => map.set(key, (map.get(key) || 0) + 1);
    const dayFormatter = new Intl.DateTimeFormat('en-US', { month: '2-digit', day: '2-digit', timeZone: 'Asia/Baghdad' });
    for (const appointment of included) {
        const fields = appointment.data();
        count(statuses, String(fields.status || 'pending'));
        count(departments, String(fields.department || 'Unknown'));
        const date = fields.appointmentDate?.toDate?.();
        if (date) count(days, dayFormatter.format(date));
    }
    return { total: included.length, statuses: Object.fromEntries(statuses), departments: Object.fromEntries(departments),
        days: Object.fromEntries(days), truncated: page.size > limit, limit, period,
        selection: 'latest-created', asOf: end.toDate().toISOString() };
});
