const assert = require('node:assert/strict');
const { test } = require('node:test');
const { admin, auth, db } = require('../lib/firebase');
const { deleteAdminAccount } = require('../lib/admin');

function deletionFixture(t, authErrorCode) {
    const profiles = new Map([
        ['owner', { role: 'superAdmin', isActive: true, fullName: 'Owner' }],
        ['target', { role: 'admin', isActive: true, fullName: 'Target' }],
    ]);
    const authUsers = new Set(authErrorCode === 'auth/user-not-found'
        ? ['owner'] : ['owner', 'target']);
    const deletedPhotos = [];
    const auditEntries = [];

    // Firebase SDK boundaries are isolated; the callable and its helpers are real.
    t.mock.method(auth, 'getUser', async (uid) => {
        assert.ok(authUsers.has(uid));
        return { uid, providerData: [{ providerId: 'google.com' }] };
    });
    t.mock.method(auth, 'deleteUser', async (uid) => {
        if (authErrorCode) {
            throw Object.assign(new Error('Auth deletion failed'), { code: authErrorCode });
        }
        authUsers.delete(uid);
    });
    t.mock.method(db, 'collection', (name) => {
        if (name === 'admin_audit_logs') {
            return { add: async (entry) => auditEntries.push(entry) };
        }
        assert.equal(name, 'users');
        return {
            doc: (uid) => ({
                get: async () => ({ exists: profiles.has(uid), data: () => profiles.get(uid) }),
                delete: async () => profiles.delete(uid),
            }),
        };
    });
    t.mock.method(admin.storage(), 'bucket', () => ({
        file: (path) => ({ delete: async () => deletedPhotos.push(path) }),
    }));

    return { profiles, authUsers, deletedPhotos, auditEntries };
}

for (const code of ['auth/internal-error', 'auth/insufficient-permission']) {
    test(`Auth deletion failure (${code}) preserves the profile and reports failure`, async (t) => {
        const state = deletionFixture(t, code);

        await assert.rejects(
            deleteAdminAccount.run({ auth: { uid: 'owner' }, data: { targetUid: 'target' } }),
            (error) => error.code === 'internal',
        );

        assert.ok(state.authUsers.has('target'));
        assert.ok(state.profiles.has('target'));
        assert.deepEqual(state.deletedPhotos, []);
        assert.deepEqual(state.auditEntries, []);
    });
}

for (const code of [null, 'auth/user-not-found']) {
    test(`admin cleanup succeeds when Auth is ${code ? 'already absent' : 'deleted'}`, async (t) => {
        const state = deletionFixture(t, code);

        const result = await deleteAdminAccount.run({
            auth: { uid: 'owner' }, data: { targetUid: 'target' },
        });

        assert.equal(result.success, true);
        assert.equal(state.authUsers.has('target'), false);
        assert.equal(state.profiles.has('target'), false);
        assert.equal(state.deletedPhotos.length, 4);
        assert.equal(state.auditEntries.length, 1);
        assert.equal(state.auditEntries[0].action, 'admin.delete');
        assert.equal(state.auditEntries[0].targetUid, 'target');
    });
}
