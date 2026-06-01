import * as functions from 'firebase-functions';

import { admin, db } from './firebase';
import { getCallerUserDoc, requireAuth, requirePermission } from './shared/auth';

interface CreateDepartmentData {
    key: string;
    name: string;
    description?: string;
    iconName?: string;
    colorHex?: string;
    workingHours: Record<string, unknown>;
}

/**
 * Cloud Function to create a department document.
 */
export const createDepartment = functions.https.onCall(
    async (request: functions.https.CallableRequest<CreateDepartmentData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.key || !data.name || !data.workingHours) {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'key, name, and workingHours are required.'
            );
        }

        const existing = await db.collection('departments')
            .where('key', '==', data.key)
            .limit(1)
            .get();
        if (!existing.empty) {
            throw new functions.https.HttpsError('already-exists', 'Department key already exists.');
        }

        const now = admin.firestore.Timestamp.now();
        const ref = await db.collection('departments').add({
            key: data.key,
            name: data.name,
            description: data.description ?? '',
            iconName: data.iconName ?? 'medical_services',
            colorHex: data.colorHex ?? '#2196F3',
            workingHours: data.workingHours,
            isActive: true,
            doctorCount: 0,
            createdAt: now,
            updatedAt: now,
        });

        return { success: true, departmentId: ref.id, message: 'Department created successfully' };
    }
);

interface UpdateDepartmentData {
    departmentId: string;
    key?: string;
    name?: string;
    description?: string;
    iconName?: string;
    colorHex?: string;
    workingHours?: Record<string, unknown>;
}

/**
 * Cloud Function to update department fields.
 */
export const updateDepartment = functions.https.onCall(
    async (request: functions.https.CallableRequest<UpdateDepartmentData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.departmentId) {
            throw new functions.https.HttpsError('invalid-argument', 'departmentId is required.');
        }

        const ref = db.collection('departments').doc(data.departmentId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new functions.https.HttpsError('not-found', 'Department not found.');
        }

        const updates: Record<string, unknown> = {
            updatedAt: admin.firestore.Timestamp.now(),
        };
        if (data.key !== undefined) updates.key = data.key;
        if (data.name !== undefined) updates.name = data.name;
        if (data.description !== undefined) updates.description = data.description;
        if (data.iconName !== undefined) updates.iconName = data.iconName;
        if (data.colorHex !== undefined) updates.colorHex = data.colorHex;
        if (data.workingHours !== undefined) updates.workingHours = data.workingHours;

        await ref.update(updates);
        return { success: true, message: 'Department updated successfully' };
    }
);

interface SetDepartmentActiveStatusData {
    departmentId: string;
    isActive: boolean;
}

/**
 * Cloud Function to activate/deactivate a department.
 */
export const setDepartmentActiveStatus = functions.https.onCall(
    async (request: functions.https.CallableRequest<SetDepartmentActiveStatusData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.departmentId || typeof data.isActive !== 'boolean') {
            throw new functions.https.HttpsError(
                'invalid-argument',
                'departmentId and isActive are required.'
            );
        }

        const ref = db.collection('departments').doc(data.departmentId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new functions.https.HttpsError('not-found', 'Department not found.');
        }

        await ref.update({
            isActive: data.isActive,
            updatedAt: admin.firestore.Timestamp.now(),
        });

        return {
            success: true,
            message: data.isActive
                ? 'Department activated successfully'
                : 'Department deactivated successfully',
        };
    }
);

interface DeleteDepartmentData {
    departmentId: string;
}

/**
 * Cloud Function to delete a department.
 */
export const deleteDepartment = functions.https.onCall(
    async (request: functions.https.CallableRequest<DeleteDepartmentData>) => {
        const data = request.data;
        const callerUid = requireAuth(request);
        const callerDoc = await getCallerUserDoc(callerUid);
        requirePermission(callerDoc, 'departments.manage');

        if (!data.departmentId) {
            throw new functions.https.HttpsError('invalid-argument', 'departmentId is required.');
        }

        const ref = db.collection('departments').doc(data.departmentId);
        const snap = await ref.get();
        if (!snap.exists) {
            throw new functions.https.HttpsError('not-found', 'Department not found.');
        }

        await ref.delete();
        return { success: true, message: 'Department deleted successfully' };
    }
);
