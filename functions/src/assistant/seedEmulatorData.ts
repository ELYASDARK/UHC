import { admin, db } from '../firebase';
import { checkSyntheticTestingConditions, REQUIRED_DEMO_PROJECT_ID } from './config';

export interface SeedEmulatorDataResult {
    success: boolean;
    seededDepartments: number;
    seededDoctors: number;
    seededPatients: number;
}

/**
 * Explicitly gated utility to seed synthetic demo data into local Firebase Emulators.
 * Strictly verifies all fail-closed emulator preconditions before writing any data.
 *
 * Seeds:
 * 1. Firebase Auth user 'synthetic-patient-1' with password 'TestPassword123!'
 *    and linked 'google.com' provider to pass getCallerUserDoc checks.
 * 2. Firestore patient document 'users/synthetic-patient-1' with role 'student'.
 * 3. Firestore departments and doctors with weekly schedules for deterministic synthetic booking.
 */
export async function seedSyntheticEmulatorData(): Promise<SeedEmulatorDataResult> {
    const adminProjectId = admin.app().options.projectId;
    const check = checkSyntheticTestingConditions(adminProjectId);
    if (!check.allowed) {
        throw new Error(
            `Refusing to seed: synthetic preconditions not met: ${check.rejectedReason}. ` +
            `Must run with loopback Auth and Firestore emulators on project '${REQUIRED_DEMO_PROJECT_ID}'.`
        );
    }

    // 1. Seed Auth user in Firebase Auth Emulator
    const patientUid = 'synthetic-patient-1';
    const patientEmail = 'synthetic.patient@demo.uhc.edu';
    const patientName = 'Synthetic Student';

    try {
        await admin.auth().deleteUser(patientUid);
    } catch {
        // Ignore if user does not exist yet
    }

    // Import user with Google provider metadata
    const importResults = await admin.auth().importUsers([
        {
            uid: patientUid,
            email: patientEmail,
            displayName: patientName,
            emailVerified: true,
            providerData: [
                {
                    uid: 'synthetic-google-uid-1',
                    email: patientEmail,
                    displayName: patientName,
                    providerId: 'google.com',
                },
            ],
        },
    ]);

    if (importResults.errors && importResults.errors.length > 0) {
        throw new Error(`Failed to import synthetic patient into Auth emulator: ${JSON.stringify(importResults.errors)}`);
    }

    // Set local password for direct email/password login against Auth emulator
    await admin.auth().updateUser(patientUid, {
        password: 'TestPassword123!',
    });

    // 2. Seed Firestore patient user document
    await db.collection('users').doc(patientUid).set({
        fullName: patientName,
        email: patientEmail,
        role: 'student',
        isActive: true,
        googleEmail: patientEmail,
        hasLinkedGoogle: true,
        createdAt: admin.firestore.Timestamp.now(),
    });

    // 3. Seed departments
    const departments = [
        { key: 'dermatology', name: 'Dermatology Clinic', isActive: true },
        { key: 'dentistry', name: 'Dental Care', isActive: true },
        { key: 'cardiology', name: 'Cardiology Care', isActive: true },
        { key: 'pediatrics', name: 'Pediatrics Clinic', isActive: true },
        { key: 'generalMedicine', name: 'General Medicine', isActive: true },
    ];

    for (const d of departments) {
        await db.collection('departments').doc(`dept_${d.key}`).set({
            ...d,
            createdAt: admin.firestore.Timestamp.now(),
        });
    }

    // 4. Seed doctors with deterministic weekly schedules
    const doctors = [
        {
            id: 'doc_derm_demo',
            name: 'Dr. Noor Dermatology',
            specialization: 'Dermatology',
            department: 'dermatology',
            isActive: true,
            isAvailable: true,
            weeklySchedule: {
                tuesday: [
                    { startTime: '10:00', endTime: '10:30', isAvailable: true },
                    { startTime: '10:30', endTime: '11:00', isAvailable: true },
                ],
                thursday: [
                    { startTime: '14:00', endTime: '14:30', isAvailable: true },
                ],
            },
        },
        {
            id: 'doc_dentist_demo',
            name: 'Dr. Smile Dentistry',
            specialization: 'Dentistry',
            department: 'dentistry',
            isActive: true,
            isAvailable: true,
            weeklySchedule: {
                monday: [
                    { startTime: '09:00', endTime: '09:30', isAvailable: true },
                    { startTime: '09:30', endTime: '10:00', isAvailable: true },
                    { startTime: '10:00', endTime: '10:30', isAvailable: true },
                ],
                wednesday: [
                    { startTime: '14:00', endTime: '14:30', isAvailable: true },
                ],
            },
        },
        {
            id: 'doc_general_demo',
            name: 'Dr. Sarah Al-Mansoor',
            specialization: 'Internal Medicine',
            department: 'generalMedicine',
            isActive: true,
            isAvailable: true,
            weeklySchedule: {
                monday: [
                    { startTime: '09:00', endTime: '09:30', isAvailable: true },
                    { startTime: '09:30', endTime: '10:00', isAvailable: true },
                ],
                wednesday: [
                    { startTime: '11:00', endTime: '11:30', isAvailable: true },
                ],
            },
        },
    ];

    for (const doc of doctors) {
        await db.collection('doctors').doc(doc.id).set({
            ...doc,
            createdAt: admin.firestore.Timestamp.now(),
        });
    }

    return {
        success: true,
        seededDepartments: departments.length,
        seededDoctors: doctors.length,
        seededPatients: 1,
    };
}
