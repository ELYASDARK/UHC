import * as functions from 'firebase-functions';
import { PATIENT_ROLES } from '../shared/auth';

// Assistant sessions and offer confirmation are always owned by this caller.
// This does not broaden the shared patient-only clinical or administration gates.
export function requireAssistantUser(caller: FirebaseFirestore.DocumentSnapshot): void {
    const profile = caller.data();
    if (!profile || profile.isActive !== true ||
        ![...PATIENT_ROLES, 'admin'].includes(profile.role)) {
        throw new functions.https.HttpsError('permission-denied', 'This account cannot use the scheduling assistant.');
    }
}
