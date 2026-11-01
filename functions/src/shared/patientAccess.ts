import { Timestamp } from 'firebase-admin/firestore';
import { db } from '../firebase';
import { ACTIVE_APPOINTMENT_STATUSES } from './appointmentHelpers';

// Call before any transaction writes. The shared access read serializes booking
// against final closure, even when their appointment documents differ.
export async function readPatientAccessChange(tx: FirebaseFirestore.Transaction, options: {
    doctorId: string;
    patientId: string;
    appointmentId: string;
    nextStatus?: string;
}) {
    if (!options.doctorId || !options.patientId) return null;
    const doctor = await tx.get(db.collection('doctors').doc(options.doctorId));
    const uid = doctor.data()?.userId;
    if (typeof uid !== 'string' || !uid || uid.includes('/')) return null;
    return readPatientAccessForUid(tx, { ...options, doctorUserId: uid });
}

export async function readPatientAccessForUid(tx: FirebaseFirestore.Transaction, options: {
    doctorUserId: string;
    patientId: string;
    appointmentId?: string;
    nextStatus?: string;
}, firestore: FirebaseFirestore.Firestore = db) {
    const uid = options.doctorUserId;
    const ref = firestore.collection('doctor_patient_access').doc(uid).collection('patients').doc(options.patientId);
    await tx.get(ref);
    // Support legacy duplicate directory records linked to the same Auth UID.
    const doctors = await tx.get(firestore.collection('doctors').where('userId', '==', uid));
    const doctorIds = new Set(doctors.docs.map(snapshot => snapshot.id));
    const appointments = await tx.get(firestore.collection('appointments').where('patientId', '==', options.patientId));
    const remaining = appointments.docs.filter(snapshot => snapshot.id !== options.appointmentId &&
        doctorIds.has(snapshot.data().doctorId) && ACTIVE_APPOINTMENT_STATUSES.includes(snapshot.data().status));
    const activeAppointmentCount = remaining.length +
        (options.nextStatus && ACTIVE_APPOINTMENT_STATUSES.includes(options.nextStatus) ? 1 : 0);
    return { ref, doctorUserId: uid, patientId: options.patientId, activeAppointmentCount };
}

export function writePatientAccessChange(tx: FirebaseFirestore.Transaction,
    change: Awaited<ReturnType<typeof readPatientAccessChange>>): void {
    if (!change) return;
    const { ref, ...access } = change;
    // Keep a zero-count tombstone so concurrent transactions share a version.
    tx.set(ref, { ...access, schemaVersion: 2, updatedAt: Timestamp.now() });
}

export function hasCurrentPatientAccess(access: FirebaseFirestore.DocumentData | undefined): boolean {
    return access?.schemaVersion === 2 && Number.isInteger(access.activeAppointmentCount) && access.activeAppointmentCount > 0;
}
