const { test } = require('node:test');
// Review evidence only. Real current-source callables and helpers, SDK methods
// isolated in memory. Promotion uses the supported Super Admin slot callable.
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
process.env.GCLOUD_PROJECT = 'demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

const { db, auth, admin } = require(path.join(root, 'functions/lib/firebase.js'));
const profiles = new Map([
    ['owner', { role: 'superAdmin', superAdminType: 'primary', isActive: true, fullName: 'Synthetic Owner' }],
    ['manager', { role: 'admin', isActive: true, fullName: 'Synthetic Manager', adminPermissions: { 'users.manageNonAdmin': true } }],
    ['target', { role: 'student', isActive: true, fullName: 'Synthetic Target' }],
]);
const authUsers = new Set(profiles.keys());
const auditEntries = [];
const deletedPhotos = [];
const snapshot = uid => ({
    id: uid, exists: profiles.has(uid), data: () => profiles.get(uid),
    ref: reference('users', uid),
});
function reference(collection, uid) {
    return {
        id: uid,
        get: async () => snapshot(uid),
        delete: async () => collection === 'users' && profiles.delete(uid),
        update: async changes => profiles.set(uid, { ...profiles.get(uid), ...changes }),
        collection: name => {
            assert.equal(collection, 'user_tokens');
            assert.equal(name, 'tokens');
            return { get: async () => ({ docs: [] }) };
        },
    };
}
db.collection = name => {
    if (name === 'admin_audit_logs') return { add: async entry => auditEntries.push(entry) };
    assert.ok(['users', 'user_tokens'].includes(name));
    return {
        doc: uid => reference(name, uid),
        where: (key, operator, value) => {
            assert.equal(name, 'users');
            assert.equal(operator, '==');
            return { key, value };
        },
    };
};
db.runTransaction = async callback => callback({
    get: async target => target.key ? {
        docs: [...profiles].filter(([, data]) => data[target.key] === target.value)
            .map(([uid]) => snapshot(uid)),
    } : target.get(),
    update: (target, changes) => profiles.set(target.id, { ...profiles.get(target.id), ...changes }),
});
auth.getUser = async uid => {
    assert.ok(authUsers.has(uid));
    return { uid, providerData: [{ providerId: 'google.com' }] };
};
let pauseDeletion, continueDeletion;
const deletionPaused = new Promise(resolve => { pauseDeletion = resolve; });
const resumeDeletion = new Promise(resolve => { continueDeletion = resolve; });
auth.revokeRefreshTokens = async uid => {
    assert.equal(uid, 'target');
    pauseDeletion();
    await resumeDeletion;
};
let targetRoleWhenAuthDeleted;
auth.deleteUser = async uid => {
    targetRoleWhenAuthDeleted = profiles.get(uid)?.role;
    authUsers.delete(uid);
};
admin.storage().bucket = () => ({ file: name => ({ delete: async () => deletedPhotos.push(name) }) });
const { deleteUserAccount } = require(path.join(root, 'functions/lib/users.js'));
const { assignSuperAdminSlot } = require(path.join(root, 'functions/lib/admin.js'));
test('non-admin deletion excludes concurrent super-admin promotion', async () => {
    // The manager may delete students but cannot delete an existing Super Admin.
    const pendingDeletion = deleteUserAccount.run({
        auth: { uid: 'manager' }, data: { targetUid: 'target' },
    });
    await deletionPaused;
    await assert.rejects(assignSuperAdminSlot.run({
        auth: { uid: 'owner' }, data: { targetUid: 'target', slotType: 'backup' },
    }), error => error.code === 'aborted');
    assert.equal(profiles.get('target').role, 'student');
    continueDeletion();
    const deletion = await pendingDeletion;
    assert.equal(deletion.success, true);
    assert.equal(targetRoleWhenAuthDeleted, 'student');
    assert.equal(authUsers.has('target'), false);
    assert.equal(profiles.has('target'), false);
    assert.equal(auditEntries.length, 0);
});
