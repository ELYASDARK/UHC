import * as functions from 'firebase-functions';

import { admin, db } from '../firebase';

export const APPOINTMENT_STATUSES = ['pending', 'confirmed', 'completed', 'cancelled', 'noShow'];
export const APPOINTMENT_TYPES = ['regularCheckup', 'followUp', 'consultation', 'emergency'];
export const ACTIVE_APPOINTMENT_STATUSES = ['pending', 'confirmed'];
const DOCTOR_AVAILABILITY_TIME_ZONE = 'Asia/Baghdad';

export function appointmentDateKey(appointmentDate: Date): string {
    const year = appointmentDate.getFullYear();
    const month = String(appointmentDate.getMonth() + 1).padStart(2, '0');
    const day = String(appointmentDate.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

export function slotLockComponent(value: string): string {
    return encodeURIComponent(value.trim());
}

export function appointmentSlotLockRef(
    doctorId: string,
    appointmentDate: Date,
    timeSlot: string
): FirebaseFirestore.DocumentReference {
    return db.collection('appointment_slot_locks').doc(
        `${slotLockComponent(doctorId)}_${appointmentDateKey(appointmentDate)}_${slotLockComponent(timeSlot)}`
    );
}

export function firestoreDateToDate(value: unknown): Date | null {
    if (value instanceof Date) return value;
    if (value && typeof (value as { toDate?: unknown }).toDate === 'function') {
        return (value as { toDate: () => Date }).toDate();
    }
    return null;
}

export async function lockAppointmentSlot(
    transaction: FirebaseFirestore.Transaction,
    params: {
        doctorId: string;
        appointmentDate: Date;
        timeSlot: string;
        appointmentId: string;
        status: string;
        excludeAppointmentId?: string;
    }
): Promise<FirebaseFirestore.DocumentReference> {
    const slotRef = appointmentSlotLockRef(params.doctorId, params.appointmentDate, params.timeSlot);
    const slotLockSnap = await transaction.get(slotRef);
    const lockedAppointmentId = slotLockSnap.data()?.appointmentId as string | undefined;
    const lockedStatus = slotLockSnap.data()?.status as string | undefined;
    if (
        slotLockSnap.exists &&
        lockedAppointmentId !== params.excludeAppointmentId &&
        ACTIVE_APPOINTMENT_STATUSES.includes(lockedStatus || 'pending')
    ) {
        throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
    }

    transaction.set(slotRef, {
        appointmentId: params.appointmentId,
        doctorId: params.doctorId,
        appointmentDateKey: appointmentDateKey(params.appointmentDate),
        timeSlot: params.timeSlot,
        status: params.status,
        updatedAt: admin.firestore.Timestamp.now(),
    });
    return slotRef;
}

export function releaseAppointmentSlot(
    transaction: FirebaseFirestore.Transaction,
    appointmentId: string,
    appointmentData: FirebaseFirestore.DocumentData
): Promise<void> {
    const appointmentDate = firestoreDateToDate(appointmentData.appointmentDate);
    if (!appointmentData.doctorId || !appointmentDate || !appointmentData.timeSlot) return Promise.resolve();
    const slotRef = appointmentSlotLockRef(
        appointmentData.doctorId,
        appointmentDate,
        appointmentData.timeSlot
    );
    return transaction.get(slotRef).then((slotSnap) => {
        if (!slotSnap.exists || slotSnap.data()?.appointmentId !== appointmentId) return;
        transaction.delete(slotRef);
    });
}


export function parseAppointmentDate(value: string): Date {
    const parsed = new Date(value);
    if (!value || Number.isNaN(parsed.getTime())) {
        throw new functions.https.HttpsError('invalid-argument', 'appointmentDate must be a valid ISO date string.');
    }
    return parsed;
}

export function appointmentExactTime(date: Date, timeSlot: string): Date {
    const startTime = timeSlot.split(' - ')[0] || '00:00';
    const [hourRaw, minuteRaw] = startTime.split(':');
    const hour = Number.parseInt(hourRaw || '0', 10);
    const minute = Number.parseInt(minuteRaw || '0', 10);
    
    // Extracted components in UTC to be completely timezone-agnostic.
    const year = date.getUTCFullYear();
    const month = date.getUTCMonth();
    const day = date.getUTCDate();
    
    // Construct local Date inside a UTC representation.
    const utcDate = new Date(Date.UTC(
        year, 
        month, 
        day, 
        Number.isNaN(hour) ? 0 : hour, 
        Number.isNaN(minute) ? 0 : minute
    ));
    
    // Shift from Baghdad (UTC+3) to UTC time by subtracting 3 hours.
    return new Date(utcDate.getTime() - 3 * 60 * 60 * 1000);
}

export function formatDateForNotification(date: Date): string {
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

export function isAdminWithAppointmentAccess(data: FirebaseFirestore.DocumentData): boolean {
    if (data.role === 'superAdmin') return true;
    if (data.role !== 'admin') return false;
    const perms = data.adminPermissions as Record<string, boolean> | undefined;
    return !!(perms?.['appointments.view'] || perms?.['analytics.view'] || perms?.['reports.view']);
}

export function isAdminWithAppointmentMutationAccess(data: FirebaseFirestore.DocumentData): boolean {
    if (data.role === 'superAdmin') return true;
    if (data.role !== 'admin') return false;
    const perms = data.adminPermissions as Record<string, boolean> | undefined;
    return perms?.['appointments.manage'] === true;
}

export async function getDoctorForUser(uid: string): Promise<FirebaseFirestore.DocumentSnapshot | null> {
    const snap = await db.collection('doctors')
        .where('userId', '==', uid)
        .where('isActive', '==', true)
        .limit(1)
        .get();
    return snap.empty ? null : snap.docs[0];
}

export async function canMutateAppointment(
    callerUid: string,
    callerDoc: FirebaseFirestore.DocumentSnapshot,
    appointmentData: FirebaseFirestore.DocumentData,
    options: { allowPatient?: boolean; allowDoctor?: boolean; allowAdmin?: boolean }
): Promise<boolean> {
    const callerData = callerDoc.data()!;
    if (options.allowPatient && appointmentData.patientId === callerUid) return true;
    if (options.allowAdmin && isAdminWithAppointmentMutationAccess(callerData)) return true;
    if (options.allowDoctor && callerData.role === 'doctor') {
        const doctorDoc = await getDoctorForUser(callerUid);
        return doctorDoc?.id === appointmentData.doctorId;
    }
    return false;
}


export function availabilityDateParts(date: Date): { year: number; month: number; day: number } {
    const formatted = new Intl.DateTimeFormat('en-CA', {
        timeZone: DOCTOR_AVAILABILITY_TIME_ZONE,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    }).format(date);
    const match = formatted.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) {
        return {
            year: Number(match[1]),
            month: Number(match[2]),
            day: Number(match[3]),
        };
    }

    const fallback = new Date(date.getTime() + 3 * 60 * 60 * 1000);
    return {
        year: fallback.getUTCFullYear(),
        month: fallback.getUTCMonth() + 1,
        day: fallback.getUTCDate(),
    };
}

export function availabilityMonthKey(date = new Date()): string {
    const parts = availabilityDateParts(date);
    return `${parts.year}-${String(parts.month).padStart(2, '0')}`;
}

export function baghdadStartOfToday(date = new Date()): Date {
    const parts = availabilityDateParts(date);
    return new Date(Date.UTC(parts.year, parts.month - 1, parts.day, -3, 0, 0, 0));
}
