import * as admin from 'firebase-admin';

admin.initializeApp();

export { admin };
export const db = admin.firestore();
// Surface ABORTED reads to the transaction runner instead of replaying a closed ID.
db.settings({ gaxServerStreamingRetries: true });
export const auth = admin.auth();
export const messaging = admin.messaging();
