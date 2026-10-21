import * as functions from 'firebase-functions';
import {
    ACTIVE_APPOINTMENT_STATUSES,
    appointmentDateKey,
    appointmentDayCoordinationRef,
    canonicalAppointmentSlotLockRef,
    doesAppointmentOverlapSlot,
    firestoreDateToDate,
    legacyAppointmentSlotLockRef,
    resolveTrustedSlotFromSchedule,
    TrustedSlotRange,
} from '../shared/appointmentHelpers';
import { doctorDayAppointmentsQuery } from './doctorDayAvailability';

export interface DoctorSlotReservation {
    doctorId: string;
    doctorName: string;
    doctorUserId?: string;
    department: string;
    dateKey: string;
    slot: TrustedSlotRange;
    coordinationRef: FirebaseFirestore.DocumentReference;
    slotRef: FirebaseFirestore.DocumentReference;
    previousLocks: FirebaseFirestore.DocumentSnapshot[];
}

export async function readDoctorSlotReservation(
    transaction: FirebaseFirestore.Transaction,
    request: {
        firestore: FirebaseFirestore.Firestore;
        doctorId: string;
        appointmentId: string;
        appointmentDate: Date;
        timeSlot: string;
        fallbackDoctorName: string;
        previousAppointment?: FirebaseFirestore.DocumentData;
    }
): Promise<DoctorSlotReservation> {
    const { firestore, doctorId, appointmentId, appointmentDate, timeSlot } = request;
    const doctorDoc = await transaction.get(firestore.collection('doctors').doc(doctorId));
    const doctor = doctorDoc.data();
    if (!doctorDoc.exists || doctor?.isActive !== true || doctor?.isAvailable !== true) {
        throw new functions.https.HttpsError('failed-precondition', 'Selected doctor is unavailable.');
    }
    const department = doctor.department as string | undefined;
    if (!department) throw new functions.https.HttpsError('failed-precondition', 'Doctor has no assigned department.');
    const departmentDocs = await transaction.get(firestore.collection('departments')
        .where('key', '==', department).where('isActive', '==', true).limit(1));
    if (departmentDocs.empty) {
        throw new functions.https.HttpsError('failed-precondition', 'Selected doctor department is inactive.');
    }

    const slot = resolveTrustedSlotFromSchedule(doctor, appointmentDate, timeSlot);
    const dateKey = appointmentDateKey(appointmentDate);
    const coordinationRef = appointmentDayCoordinationRef(doctorId, appointmentDate, firestore);
    // Different starts can overlap; every booking on this doctor/day contends on the same record.
    await transaction.get(coordinationRef);
    const slotRef = canonicalAppointmentSlotLockRef(doctorId, appointmentDate, slot.canonicalSlot, firestore);
    const legacyRef = legacyAppointmentSlotLockRef(doctorId, appointmentDate, slot.canonicalSlot, firestore);
    const locks = await transaction.getAll(slotRef, legacyRef);
    if (locks.some((lock) => lock.exists && lock.data()?.appointmentId !== appointmentId &&
        ACTIVE_APPOINTMENT_STATUSES.includes(lock.data()?.status || 'pending'))) {
        throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
    }
    const appointments = await transaction.get(doctorDayAppointmentsQuery(firestore, doctorId, dateKey));
    if (appointments.docs.some((doc) => doc.id !== appointmentId &&
        ACTIVE_APPOINTMENT_STATUSES.includes(doc.data().status) &&
        doesAppointmentOverlapSlot(doc.data(), slot, doctor, appointmentDate))) {
        throw new functions.https.HttpsError('already-exists', 'This time slot is no longer available.');
    }

    const previousLocks: FirebaseFirestore.DocumentSnapshot[] = [];
    const previousDate = firestoreDateToDate(request.previousAppointment?.appointmentDate);
    if (previousDate && request.previousAppointment?.timeSlot) {
        previousLocks.push(...await transaction.getAll(
            canonicalAppointmentSlotLockRef(doctorId, previousDate, request.previousAppointment.timeSlot, firestore),
            legacyAppointmentSlotLockRef(doctorId, previousDate, request.previousAppointment.timeSlot, firestore),
        ));
    }
    return {
        doctorId,
        doctorName: typeof doctor.name === 'string' && doctor.name.trim() ? doctor.name.trim() : request.fallbackDoctorName,
        doctorUserId: doctor.userId as string | undefined,
        department: department.trim() || department,
        dateKey,
        slot,
        coordinationRef,
        slotRef,
        previousLocks,
    };
}

export function writeDoctorSlotReservation(
    transaction: FirebaseFirestore.Transaction,
    reservation: DoctorSlotReservation,
    appointment: { appointmentId: string; status: string; now: FirebaseFirestore.Timestamp }
): void {
    for (const previousLock of reservation.previousLocks) {
        if (previousLock.exists && previousLock.data()?.appointmentId === appointment.appointmentId &&
            previousLock.ref.path !== reservation.slotRef.path) {
            transaction.delete(previousLock.ref);
        }
    }
    transaction.set(reservation.coordinationRef, {
        doctorId: reservation.doctorId,
        dateKey: reservation.dateKey,
        updatedAt: appointment.now,
    }, { merge: true });
    transaction.set(reservation.slotRef, {
        appointmentId: appointment.appointmentId,
        doctorId: reservation.doctorId,
        appointmentDateKey: reservation.dateKey,
        timeSlot: reservation.slot.canonicalSlot,
        startTime: reservation.slot.startTime,
        status: appointment.status,
        updatedAt: appointment.now,
    });
}
