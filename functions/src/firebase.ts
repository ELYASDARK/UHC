import * as admin from 'firebase-admin';

admin.initializeApp();

export { admin };
export const db = admin.firestore();
export const auth = admin.auth();
export const messaging = admin.messaging();
