import * as functions from 'firebase-functions';

import { admin, db } from '../firebase';

export const APPOINTMENT_STATUSES = ['pending', 'confirmed', 'completed', 'cancelled', 'noShow'];
export const APPOINTMENT_TYPES = ['regularCheckup', 'followUp', 'consultation', 'emergency'];
export const ACTIVE_APPOINTMENT_STATUSES = ['pending', 'confirmed'];
const DOCTOR_AVAILABILITY_TIME_ZONE = 'Asia/Baghdad';

export function appointmentDateKey(appointmentDate: Date): string {
    return new Intl.DateTimeFormat('en-CA', {
        timeZone: DOCTOR_AVAILABILITY_TIME_ZONE,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    }).format(appointmentDate);
}

export function isValidTimeFormat(timeStr: string): boolean {
    return /^([01]\d|2[0-3]):[0-5]\d$/.test(timeStr.trim());
}

export function normalizeTimeComponent(timeStr: string): string {
    const trimmed = timeStr.trim();
    const match = trimmed.match(/^(\d{1,2}):(\d{2})$/);
    if (!match) return trimmed;
    const hour = Number.parseInt(match[1], 10);
    const minute = Number.parseInt(match[2], 10);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return trimmed;
    return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

export function canonicalSlotStartTime(timeSlot: string): string {
    const rawStart = timeSlot.split('-')[0].trim();
    return normalizeTimeComponent(rawStart);
}

export function timeToMinutes(timeStr: string): number {
    const [h, m] = timeStr.split(':').map(Number);
    return (h || 0) * 60 + (m || 0);
}

export function parseExplicitSlotRange(timeSlot: string): { startTime: string; endTime: string } | null {
    const trimmed = timeSlot.trim();
    if (trimmed.includes('-')) {
        const parts = trimmed.split('-').map((p) => p.trim());
        if (parts.length !== 2) return null;
        const start = normalizeTimeComponent(parts[0]);
        const end = normalizeTimeComponent(parts[1]);
        if (!isValidTimeFormat(start) || !isValidTimeFormat(end)) return null;
        if (timeToMinutes(start) >= timeToMinutes(end)) return null;
        return { startTime: start, endTime: end };
    }
    return null;
}

export function parseSlotTimeRange(timeSlot: string): { startTime: string; endTime: string } | null {
    return parseExplicitSlotRange(timeSlot);
}

export function doSlotsOverlap(slotA: string, slotB: string): boolean {
    const rangeA = parseExplicitSlotRange(slotA);
    const rangeB = parseExplicitSlotRange(slotB);
    if (rangeA && rangeB) {
        const startA = timeToMinutes(rangeA.startTime);
        const endA = timeToMinutes(rangeA.endTime);
        const startB = timeToMinutes(rangeB.startTime);
        const endB = timeToMinutes(rangeB.endTime);
        return Math.max(startA, startB) < Math.min(endA, endB);
    }
    const startA = canonicalSlotStartTime(slotA);
    const startB = canonicalSlotStartTime(slotB);
    if (startA === startB) return true;
    if (rangeA) {
        const minStartA = timeToMinutes(rangeA.startTime);
        const minEndA = timeToMinutes(rangeA.endTime);
        const minB = timeToMinutes(startB);
        if (minB >= minStartA && minB < minEndA) return true;
    }
    if (rangeB) {
        const minStartB = timeToMinutes(rangeB.startTime);
        const minEndB = timeToMinutes(rangeB.endTime);
        const minA = timeToMinutes(startA);
        if (minA >= minStartB && minA < minEndB) return true;
    }
    return false;
}

export function slotLockComponent(value: string): string {
    return encodeURIComponent(value.trim());
}

export function appointmentDayCoordinationRef(
    doctorId: string,
    appointmentDate: Date,
    firestore: FirebaseFirestore.Firestore = db
): FirebaseFirestore.DocumentReference {
    const dateKey = appointmentDateKey(appointmentDate);
    return firestore.collection('appointment_day_coordination').doc(
        `${slotLockComponent(doctorId)}_${dateKey}`
    );
}

export function canonicalAppointmentSlotLockRef(
    doctorId: string,
    appointmentDate: Date,
    timeSlot: string,
    firestore: FirebaseFirestore.Firestore = db
): FirebaseFirestore.DocumentReference {
    const dateKey = appointmentDateKey(appointmentDate);
    const startTime = canonicalSlotStartTime(timeSlot);
    return firestore.collection('appointment_slot_locks').doc(
        `${slotLockComponent(doctorId)}_${dateKey}_${slotLockComponent(startTime)}`
    );
}

export function legacyAppointmentSlotLockRef(
    doctorId: string,
    appointmentDate: Date,
    timeSlot: string,
    firestore: FirebaseFirestore.Firestore = db
): FirebaseFirestore.DocumentReference {
    const dateKey = appointmentDateKey(appointmentDate);
    return firestore.collection('appointment_slot_locks').doc(
        `${slotLockComponent(doctorId)}_${dateKey}_${slotLockComponent(timeSlot)}`
    );
}

export function appointmentSlotLockRef(
    doctorId: string,
    appointmentDate: Date,
    timeSlot: string,
    firestore: FirebaseFirestore.Firestore = db
): FirebaseFirestore.DocumentReference {
    return canonicalAppointmentSlotLockRef(doctorId, appointmentDate, timeSlot, firestore);
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
        firestore?: FirebaseFirestore.Firestore;
    }
): Promise<FirebaseFirestore.DocumentReference> {
    const firestore = params.firestore || db;
    const canonicalRef = canonicalAppointmentSlotLockRef(params.doctorId, params.appointmentDate, params.timeSlot, firestore);
    const legacyRef = legacyAppointmentSlotLockRef(params.doctorId, params.appointmentDate, params.timeSlot, firestore);

    const [canonicalSnap, legacySnap] = await Promise.all([
        transaction.get(canonicalRef),
        transaction.get(legacyRef),
    ]);

    for (const snap of [canonicalSnap, legacySnap]) {
        if (snap.exists) {
            const data = snap.data();
            const lockedAppointmentId = data?.appointmentId as string | undefined;
            const lockedStatus = data?.status as string | undefined;
            if (
                lockedAppointmentId !== params.excludeAppointmentId &&
                ACTIVE_APPOINTMENT_STATUSES.includes(lockedStatus || 'pending')
            ) {
                throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
            }
        }
    }

    transaction.set(canonicalRef, {
        appointmentId: params.appointmentId,
        doctorId: params.doctorId,
        appointmentDateKey: appointmentDateKey(params.appointmentDate),
        timeSlot: params.timeSlot,
        startTime: canonicalSlotStartTime(params.timeSlot),
        status: params.status,
        updatedAt: admin.firestore.Timestamp.now(),
    });

    return canonicalRef;
}

export async function releaseAppointmentSlot(
    transaction: FirebaseFirestore.Transaction,
    appointmentId: string,
    appointmentData: FirebaseFirestore.DocumentData,
    firestore: FirebaseFirestore.Firestore = db
): Promise<void> {
    const appointmentDate = firestoreDateToDate(appointmentData.appointmentDate);
    if (!appointmentData.doctorId || !appointmentDate || !appointmentData.timeSlot) return;

    const canonicalRef = canonicalAppointmentSlotLockRef(
        appointmentData.doctorId,
        appointmentDate,
        appointmentData.timeSlot,
        firestore
    );
    const legacyRef = legacyAppointmentSlotLockRef(
        appointmentData.doctorId,
        appointmentDate,
        appointmentData.timeSlot,
        firestore
    );

    const [canonicalSnap, legacySnap] = await Promise.all([
        transaction.get(canonicalRef),
        transaction.get(legacyRef),
    ]);

    if (canonicalSnap.exists && canonicalSnap.data()?.appointmentId === appointmentId) {
        transaction.delete(canonicalRef);
    }
    if (legacySnap.exists && legacySnap.data()?.appointmentId === appointmentId) {
        transaction.delete(legacyRef);
    }
}

export function parseAppointmentDate(value: string): Date {
    const parsed = new Date(value);
    if (!value || Number.isNaN(parsed.getTime())) {
        throw new functions.https.HttpsError('invalid-argument', 'appointmentDate must be a valid ISO date string.');
    }
    return parsed;
}

export function isValidCalendarDate(dateStr: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return false;
    const [y, m, d] = dateStr.split('-').map(Number);
    const dt = new Date(Date.UTC(y, m - 1, d));
    return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

export function getBaghdadDateString(now = new Date()): string {
    return new Intl.DateTimeFormat('en-CA', {
        timeZone: DOCTOR_AVAILABILITY_TIME_ZONE,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    }).format(now);
}

export function appointmentExactTime(date: Date, timeSlot: string): Date {
    const dateKey = appointmentDateKey(date);
    return appointmentExactUtcTime(dateKey, timeSlot);
}

export function appointmentExactUtcTime(dateString: string, timeSlot: string): Date {
    const startTime = canonicalSlotStartTime(timeSlot);
    const [hourRaw, minuteRaw] = startTime.split(':');
    const hour = Number.parseInt(hourRaw || '0', 10);
    const minute = Number.parseInt(minuteRaw || '0', 10);

    const [year, month, day] = dateString.split('-').map(Number);
    // Baghdad is UTC+3. Exactly subtract 3 hours to get UTC instant.
    const utcMillis = Date.UTC(year, month - 1, day, hour - 3, minute, 0, 0);
    return new Date(utcMillis);
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

export const WEEKDAY_NAMES = [
    'sunday',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
] as const;
export type WeekdayName = typeof WEEKDAY_NAMES[number];

export function getWeekdayFromCalendarDate(dateStr: string): WeekdayName {
    const [y, m, d] = dateStr.split('-').map(Number);
    const utcDate = new Date(Date.UTC(y, m - 1, d));
    return WEEKDAY_NAMES[utcDate.getUTCDay()];
}

export function baghdadWeekdayName(date: Date): WeekdayName {
    const parts = availabilityDateParts(date);
    const utcDate = new Date(Date.UTC(parts.year, parts.month - 1, parts.day));
    return WEEKDAY_NAMES[utcDate.getUTCDay()];
}

export interface DoctorScheduleSlot {
    startTime: string;
    endTime?: string;
    isAvailable?: boolean;
}

export function getDoctorDaySchedule(
    doctorData: FirebaseFirestore.DocumentData,
    appointmentDate: Date | string
): DoctorScheduleSlot[] {
    const weeklySchedule = doctorData.weeklySchedule as Record<string, unknown> | undefined;
    if (!weeklySchedule || typeof weeklySchedule !== 'object') {
        return [];
    }
    const day = typeof appointmentDate === 'string'
        ? getWeekdayFromCalendarDate(appointmentDate)
        : baghdadWeekdayName(appointmentDate);
    const slots = weeklySchedule[day];
    if (!Array.isArray(slots)) {
        return [];
    }
    return slots.map((s: unknown) => {
        if (!s || typeof s !== 'object') return { startTime: '', isAvailable: false };
        const record = s as Record<string, unknown>;
        return {
            startTime: typeof record.startTime === 'string' ? canonicalSlotStartTime(record.startTime) : '',
            endTime: typeof record.endTime === 'string' ? normalizeTimeComponent(record.endTime) : '',
            isAvailable: record.isAvailable !== false,
        };
    });
}

export function matchesTimeSlot(slot: DoctorScheduleSlot, requestedTimeSlot: string): boolean {
    const normalizedReq = requestedTimeSlot.trim();
    const startOnly = canonicalSlotStartTime(normalizedReq);
    if (slot.startTime === normalizedReq || slot.startTime === startOnly) {
        return true;
    }
    if (slot.endTime) {
        const fullRange = `${slot.startTime} - ${slot.endTime}`;
        if (fullRange === normalizedReq) {
            return true;
        }
    }
    return false;
}

export function validateDoctorSlotAvailability(
    doctorData: FirebaseFirestore.DocumentData,
    appointmentDate: Date | string,
    timeSlot: string
): boolean {
    const daySlots = getDoctorDaySchedule(doctorData, appointmentDate);
    const matchingSlot = daySlots.find((s) => matchesTimeSlot(s, timeSlot));
    return !!matchingSlot && matchingSlot.isAvailable !== false;
}

export interface TrustedSlotRange {
    startTime: string;
    endTime: string;
    canonicalSlot: string;
}

/**
 * Resolves trusted schedule duration for a requested slot against doctor's actual weeklySchedule.
 * Rejects forged range ends if schedule defines endTime and caller passes a different endTime.
 */
export function resolveTrustedSlotFromSchedule(
    doctorData: FirebaseFirestore.DocumentData,
    appointmentDate: Date | string,
    requestedSlot: string
): TrustedSlotRange {
    const daySlots = getDoctorDaySchedule(doctorData, appointmentDate);
    const normalizedReq = requestedSlot.trim();
    const reqStart = canonicalSlotStartTime(normalizedReq);
    const explicitRange = parseExplicitSlotRange(normalizedReq);

    const matchingScheduleSlot = daySlots.find((s) => {
        if (!s.startTime || s.isAvailable === false) return false;
        if (s.startTime === reqStart) return true;
        return matchesTimeSlot(s, normalizedReq);
    });

    if (!matchingScheduleSlot || matchingScheduleSlot.isAvailable === false) {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'Selected time slot is not part of doctor\'s active schedule.'
        );
    }

    const schedStart = matchingScheduleSlot.startTime;
    const schedEnd = matchingScheduleSlot.endTime;

    if (explicitRange) {
        if (explicitRange.startTime !== schedStart) {
            throw new functions.https.HttpsError('failed-precondition', 'Slot start time does not match doctor schedule.');
        }
        if (schedEnd && explicitRange.endTime !== schedEnd) {
            throw new functions.https.HttpsError('invalid-argument', 'Invalid slot duration: end time does not match doctor schedule.');
        }
    }

    const resolvedEnd = schedEnd || (explicitRange ? explicitRange.endTime : '');
    const canonicalSlot = resolvedEnd ? `${schedStart} - ${resolvedEnd}` : schedStart;

    return {
        startTime: schedStart,
        endTime: resolvedEnd,
        canonicalSlot,
    };
}

/**
 * Resolves the effective time range for an existing stored appointment.
 * If stored appointment has an explicit range (e.g. "09:00 - 10:00"), uses it.
 * If start-only (legacy appointment stored with "09:00"), conservatively resolves duration
 * using doctor's actual schedule for that day.
 * Never silently assumes 30 minutes.
 */
export function resolveExistingAppointmentRange(
    appt: FirebaseFirestore.DocumentData,
    doctorData?: FirebaseFirestore.DocumentData,
    appointmentDate?: Date | string
): { startTime: string; endTime?: string } {
    const rawSlot = typeof appt.timeSlot === 'string' ? appt.timeSlot.trim() : '';
    const explicit = parseExplicitSlotRange(rawSlot);
    if (explicit) {
        return explicit;
    }
    const start = canonicalSlotStartTime(rawSlot);
    if (doctorData && appointmentDate) {
        const daySlots = getDoctorDaySchedule(doctorData, appointmentDate);
        const match = daySlots.find((s) => s.startTime === start);
        if (match && match.endTime) {
            return { startTime: start, endTime: match.endTime };
        }
    }
    return { startTime: start };
}

/**
 * Checks if an existing appointment overlaps with a proposed slot range.
 * Conservatively handles legacy start-only entries using actual doctor schedule.
 */
export function doesAppointmentOverlapSlot(
    existingAppt: FirebaseFirestore.DocumentData,
    proposedSlotRange: string | { startTime: string; endTime?: string },
    doctorData?: FirebaseFirestore.DocumentData,
    appointmentDate?: Date | string
): boolean {
    const rawProp = typeof proposedSlotRange === 'string'
        ? (parseExplicitSlotRange(proposedSlotRange) || { startTime: canonicalSlotStartTime(proposedSlotRange) })
        : { ...proposedSlotRange };
    const propRange: { startTime: string; endTime?: string } = { ...rawProp };
    if (!propRange.endTime && doctorData && appointmentDate) {
        const daySlots = getDoctorDaySchedule(doctorData, appointmentDate);
        const match = daySlots.find((s) => s.startTime === propRange.startTime);
        if (match && match.endTime) {
            propRange.endTime = match.endTime;
        }
    }
    const existingRange = resolveExistingAppointmentRange(existingAppt, doctorData, appointmentDate);
    const propStartMin = timeToMinutes(propRange.startTime);
    const propEndMin = propRange.endTime ? timeToMinutes(propRange.endTime) : propStartMin;
    const existStartMin = timeToMinutes(existingRange.startTime);

    if (existingRange.endTime) {
        const existEndMin = timeToMinutes(existingRange.endTime);
        if (propRange.endTime) {
            return Math.max(propStartMin, existStartMin) < Math.min(propEndMin, existEndMin);
        }
        return propStartMin >= existStartMin && propStartMin < existEndMin;
    }

    if (existStartMin === propStartMin) return true;

    if (propRange.endTime && existStartMin > propStartMin && existStartMin < propEndMin) {
        return true;
    }

    return false;
}

