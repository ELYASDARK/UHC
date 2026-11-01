import { HttpsError } from 'firebase-functions/v2/https';
import { db } from '../firebase';
import { hasCurrentPatientAccess } from './patientAccess';

export function medicalId(value: unknown): string {
    if (typeof value !== 'string' || !/^[\w-]{1,128}$/.test(value)) {
        throw new HttpsError('invalid-argument', 'Invalid document identifier.');
    }
    return value;
}

async function medicalUser(tx: FirebaseFirestore.Transaction, uid: string) {
    const profile = (await tx.get(db.collection('users').doc(uid))).data();
    if (!profile || profile.isActive !== true || typeof profile.googleEmail !== 'string' || !profile.googleEmail) {
        throw new HttpsError('permission-denied', 'Medical document access is unavailable.');
    }
    return profile;
}

async function doctorAccess(tx: FirebaseFirestore.Transaction, uid: string, patientId: string): Promise<boolean> {
    return hasCurrentPatientAccess((await tx.get(db.doc(`doctor_patient_access/${uid}/patients/${medicalId(patientId)}`))).data());
}

export async function authorizeMedicalCreate(tx: FirebaseFirestore.Transaction, uid: string, patientId: string) {
    const profile = await medicalUser(tx, uid);
    if (patientId !== uid && (profile.role !== 'doctor' || !await doctorAccess(tx, uid, patientId))) {
        throw new HttpsError('permission-denied', 'Patient access is unavailable.');
    }
    return profile;
}

export async function authorizeMedicalMutation(tx: FirebaseFirestore.Transaction, uid: string,
    document: FirebaseFirestore.DocumentSnapshot): Promise<void> {
    if (!document.exists) throw new HttpsError('not-found', 'Document no longer exists.');
    const fields = document.data()!;
    if ((fields.addedBy ?? fields.userId) !== uid) {
        throw new HttpsError('permission-denied', 'Only the document author can change this file.');
    }
    await authorizeMedicalCreate(tx, uid, medicalId(fields.userId));
}

export function medicalDocumentPath(documentId: string, fields: FirebaseFirestore.DocumentData): string {
    const patientId = medicalId(fields.userId);
    const path = fields.storagePath;
    if (typeof path !== 'string' || path.includes('..') || path.includes('\\')) {
        throw new HttpsError('failed-precondition', 'Invalid medical document reference.');
    }
    const parts = path.split('/');
    if (parts[0] === 'medical_documents' && parts[1] === patientId &&
        [3, 4].includes(parts.length) && parts.every(part => /^[\w.\-]+$/.test(part))) return path;
    if (parts[0] === 'medical_document_replacement_files' && parts.length === 3 &&
        parts[1] === documentId && /^[\w-]{1,128}$/.test(parts[2])) return path;
    throw new HttpsError('failed-precondition', 'Invalid medical document reference.');
}

export async function authorizeMedicalRead(tx: FirebaseFirestore.Transaction, uid: string,
    document: FirebaseFirestore.DocumentSnapshot): Promise<string> {
    if (!document.exists) throw new HttpsError('not-found', 'Document no longer exists.');
    const fields = document.data()!;
    const path = medicalDocumentPath(document.id, fields);
    const profile = await medicalUser(tx, uid);
    if (fields.userId === uid) return path;
    // The oldest two-segment file namespace was patient-only in Storage rules.
    if (path.startsWith('medical_documents/') && path.split('/').length === 3) {
        throw new HttpsError('permission-denied', 'Medical document access is unavailable.');
    }
    if (profile.role === 'superAdmin' || (profile.role === 'admin' &&
        (profile.adminPermissions?.['reports.view'] === true || profile.adminPermissions?.['appointments.view'] === true))) return path;
    if (profile.role === 'doctor' && await doctorAccess(tx, uid, fields.userId)) return path;
    throw new HttpsError('permission-denied', 'Medical document access is unavailable.');
}

export function authenticatedMedicalUrl(documentId: string): string {
    const project = process.env.GCLOUD_PROJECT;
    const host = process.env.FUNCTIONS_EMULATOR === 'true' && project === 'demo-uhc-test'
        ? `http://127.0.0.1:5001/${project}/us-central1` : `https://us-central1-${project}.cloudfunctions.net`;
    return `${host}/readMedicalDocument?documentId=${encodeURIComponent(documentId)}`;
}
