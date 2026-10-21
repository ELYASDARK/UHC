import { Timestamp } from 'firebase-admin/firestore';
import * as functions from 'firebase-functions';
import { db } from '../firebase';
import { getCallerUserDoc, requireAuth } from '../shared/auth';
import {
    ACTIVE_APPOINTMENT_STATUSES,
    appointmentDateKey,
    appointmentExactUtcTime,
    canonicalAppointmentSlotLockRef,
    canonicalSlotStartTime,
    doesAppointmentOverlapSlot,
    getDoctorDaySchedule,
    legacyAppointmentSlotLockRef,
    parseAppointmentDate,
} from '../shared/appointmentHelpers';

export interface AvailableSlotInfo {
    timeSlot: string;
    startTime: string;
    endTime: string;
    isAvailable: boolean;
}

export function doctorDayAppointmentsQuery(
    firestore: FirebaseFirestore.Firestore,
    doctorId: string,
    dateKey: string
): FirebaseFirestore.Query {
    const [year, month, day] = dateKey.split('-').map(Number);
    return firestore.collection('appointments')
        .where('doctorId', '==', doctorId)
        .where('appointmentDate', '>=', Timestamp.fromMillis(Date.UTC(year, month - 1, day, -3)))
        .where('appointmentDate', '<=', Timestamp.fromMillis(Date.UTC(year, month - 1, day, 20, 59, 59, 999)));
}

export async function loadDoctorDayAvailability(
    firestore: FirebaseFirestore.Firestore,
    request: {
        doctorId: string;
        doctor: FirebaseFirestore.DocumentData;
        dateKey: string;
        now: Date;
    }
): Promise<AvailableSlotInfo[]> {
    const { doctorId, doctor, dateKey, now } = request;
    const appointmentDate = parseAppointmentDate(dateKey);
    const daySlots = getDoctorDaySchedule(doctor, dateKey).map((schedule) => {
        const timeSlot = schedule.isAvailable === false || !schedule.startTime
            ? schedule.startTime
            : `${schedule.startTime}${schedule.endTime ? ` - ${schedule.endTime}` : ''}`;
        return {
            schedule,
            timeSlot,
            lockRefs: schedule.isAvailable === false || !schedule.startTime ? [] : [
                canonicalAppointmentSlotLockRef(doctorId, appointmentDate, timeSlot, firestore),
                legacyAppointmentSlotLockRef(doctorId, appointmentDate, timeSlot, firestore),
            ],
        };
    });
    if (daySlots.length === 0) return [];

    const [appointments, locks] = await Promise.all([
        doctorDayAppointmentsQuery(firestore, doctorId, dateKey).get(),
        readDoctorDayLocks(firestore, doctorId, dateKey, daySlots.flatMap((slot) => slot.lockRefs)),
    ]);
    const activeAppointments = appointments.docs.map((doc) => doc.data())
        .filter((appointment) => ACTIVE_APPOINTMENT_STATUSES.includes(appointment.status));
    const activeLocks = locks.filter((lock) => ACTIVE_APPOINTMENT_STATUSES.includes(lock.data()?.status || 'pending'));
    const activeLockPaths = new Set(activeLocks.map((lock) => lock.ref.path));

    return daySlots.map(({ schedule: slot, timeSlot, lockRefs }) => {
        const isLocked = lockRefs.some((ref) => activeLockPaths.has(ref.path)) || activeLocks.some((lock) => {
            const fields = lock.data()!;
            return canonicalSlotStartTime(fields.startTime || fields.timeSlot || '') === slot.startTime ||
                fields.timeSlot === timeSlot;
        });
        const hasConflict = activeAppointments.some((appointment) =>
            doesAppointmentOverlapSlot(appointment, slot, doctor, dateKey));
        return {
            timeSlot,
            startTime: slot.startTime,
            endTime: slot.endTime || '',
            isAvailable: !!slot.startTime && slot.isAvailable !== false &&
                appointmentExactUtcTime(dateKey, slot.startTime).getTime() > now.getTime() &&
                !isLocked && !hasConflict,
        };
    });
}

async function readDoctorDayLocks(
    firestore: FirebaseFirestore.Firestore,
    doctorId: string,
    dateKey: string,
    expectedRefs: FirebaseFirestore.DocumentReference[]
): Promise<FirebaseFirestore.DocumentSnapshot[]> {
    const indexed = await firestore.collection('appointment_slot_locks')
        .where('doctorId', '==', doctorId).where('appointmentDateKey', '==', dateKey).get();
    const indexedPaths = new Set(indexed.docs.map((lock) => lock.ref.path));
    const missingRefs = [...new Map(expectedRefs.map((ref) => [ref.path, ref])).values()]
        .filter((ref) => !indexedPaths.has(ref.path));
    // Older locks remain authoritative by document ID even without query metadata.
    const direct = missingRefs.length > 0 ? await firestore.getAll(...missingRefs) : [];
    return [...indexed.docs, ...direct.filter((lock) => lock.exists)];
}

export interface GetDoctorDayAvailabilityData {
    doctorId?: string;
    date?: string;
    appointmentDate?: string;
}

export interface GetDoctorDayAvailabilityResult {
    success: true;
    doctorId: string;
    appointmentDate: string;
    doctorName: string;
    department: string;
    slots: AvailableSlotInfo[];
}

export const getDoctorDayAvailability = functions.https.onCall(
    async (request: functions.https.CallableRequest<GetDoctorDayAvailabilityData>): Promise<GetDoctorDayAvailabilityResult> => {
        const callerUid = requireAuth(request);
        await getCallerUserDoc(callerUid);
        const requestData = request.data || {};
        const doctorId = typeof requestData.doctorId === 'string' ? requestData.doctorId.trim() : '';
        const dateString = typeof requestData.date === 'string' && requestData.date.trim()
            ? requestData.date.trim()
            : (typeof requestData.appointmentDate === 'string' ? requestData.appointmentDate.trim() : '');
        if (!doctorId || !dateString) {
            throw new functions.https.HttpsError('invalid-argument', 'doctorId and date (YYYY-MM-DD) are required.');
        }

        const now = new Date();
        const dateKey = appointmentDateKey(parseAppointmentDate(dateString));
        const doctorDoc = await db.collection('doctors').doc(doctorId).get();
        if (!doctorDoc.exists) throw new functions.https.HttpsError('not-found', 'Doctor not found.');
        const doctor = doctorDoc.data()!;
        if (doctor.isActive !== true || doctor.isAvailable !== true) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor is currently unavailable.');
        }
        const department = doctor.department as string | undefined;
        if (!department) throw new functions.https.HttpsError('failed-precondition', 'Doctor has no assigned department.');
        const departmentDocs = await db.collection('departments').where('key', '==', department)
            .where('isActive', '==', true).limit(1).get();
        if (departmentDocs.empty) {
            throw new functions.https.HttpsError('failed-precondition', 'Doctor\'s department is not active.');
        }
        return {
            success: true,
            doctorId,
            appointmentDate: dateKey,
            doctorName: typeof doctor.name === 'string' && doctor.name.trim() ? doctor.name.trim() : 'Doctor',
            department,
            slots: await loadDoctorDayAvailability(db, { doctorId, doctor, dateKey, now }),
        };
    }
);
