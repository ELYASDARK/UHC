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
            return { filters: [[key, value]], where(nextKey, nextOperator, nextValue) {
                assert.equal(nextOperator, '=='); this.filters.push([nextKey,nextValue]); return this;
            } };
        },
    };
};
db.runTransaction = async callback => callback({
    get: async target => target.filters ? {
        docs: [...profiles].filter(([, data]) => target.filters.every(([key,value]) => data[key] === value))
            .map(([uid]) => snapshot(uid)),
    } : target.get(),
    update: (target, changes) => { const next = {...profiles.get(target.id)}; for (const [k,v] of Object.entries(changes)) { if (v?.isEqual?.(admin.firestore.FieldValue.delete())) delete next[k]; else next[k]=v; } profiles.set(target.id,next); },
});
auth.getUser = async uid => {
    assert.ok(authUsers.has(uid));
    return { uid, providerData: [{ providerId: 'google.com' }] };
};

auth.revokeRefreshTokens = async () => {};
let lateDelete;
auth.deleteUser = async uid => {
    lateDelete = () => authUsers.delete(uid);
    throw Object.assign(new Error('Synthetic ambiguous transport failure'), {code:'auth/internal-error'});
};
const { deleteUserAccount } = require(path.join(root, 'functions/lib/users.js'));
const { assignSuperAdminSlot } = require(path.join(root, 'functions/lib/admin.js'));
const { withAccountMutation } = require('../lib/shared/accountMutation');
const { HttpsError } = require('firebase-functions/v2/https');
test('ambiguous deletion retains guard through delayed completion and requires explicit recovery', async () => {
    const original = console.error; console.error = () => {};
    try { await assert.rejects(deleteUserAccount.run({auth:{uid:'manager'},data:{targetUid:'target'}}), e => e.code === 'internal'); }
    finally { console.error=original; }
    const guard = profiles.get('target').accountMutationId;
    assert.equal(typeof guard, 'string');
    await assert.rejects(assignSuperAdminSlot.run({auth:{uid:'owner'},data:{targetUid:'target',slotType:'backup'}}), { code: 'aborted' });
    lateDelete();
    assert.equal(profiles.get('target').role, 'student');
    assert.equal(profiles.get('target').accountMutationId, guard);
    // Model trusted reconciliation AFTER remote completion has been established:
    // deleted Auth account requires completion of deletion, never promotion.
    profiles.delete('target');
    await assert.rejects(assignSuperAdminSlot.run({auth:{uid:'owner'},data:{targetUid:'target',slotType:'backup'}}));
});
test('definite validation failure releases, ambiguous callable/transport errors retain, success releases', async () => {
    for (const [error, retained] of [[new HttpsError('invalid-argument','Invalid'), false],
        [Object.assign(new Error('Invalid'), { code:'auth/invalid-email' }),false],
        [new HttpsError('internal','Unknown'), true], [new HttpsError('unavailable','Transport'), true],
        [Object.assign(new Error('Transport'), { code:'auth/internal-error' }),true]]) {
        profiles.set('target',{role:'student'});
        await assert.rejects(withAccountMutation({userId:'target',roles:['student'],mutate:async()=>{throw error}}));
        assert.equal(typeof profiles.get('target').accountMutationId === 'string',retained);
    }
    profiles.set('target',{role:'student'});
    assert.equal(await withAccountMutation({userId:'target',roles:['student'],mutate:async()=>42}),42);
    assert.equal(profiles.get('target').accountMutationId,undefined);
});
const { deleteAdminAccount, rotateSuperAdminSlot, changeAdminRole } = require('../lib/admin');
test('admin deletion also excludes promotion after ambiguous remote completion', async () => {
    profiles.set('target',{role:'admin',isActive:true});authUsers.add('target');
    await assert.rejects(deleteAdminAccount.run({auth:{uid:'owner'},data:{targetUid:'target'}}), {code:'internal'});
    const guard=profiles.get('target').accountMutationId;
    assert.equal(typeof guard,'string');
    for(const [callable,data] of [[assignSuperAdminSlot,{targetUid:'target',slotType:'backup'}],
        [rotateSuperAdminSlot,{replacementUid:'target',slotType:'primary'}],
        [changeAdminRole,{targetUid:'target',newRole:'student'}]]) {
        await assert.rejects(callable.run({auth:{uid:'owner'},data}),{code:'aborted'});
    }
    lateDelete();assert.equal(authUsers.has('target'),false);
    assert.equal(profiles.get('target').role,'admin');
    assert.equal(profiles.get('target').accountMutationId,guard);
});
