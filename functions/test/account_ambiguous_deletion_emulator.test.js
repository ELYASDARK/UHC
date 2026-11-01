const {test,after}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
assert.equal(process.env.GCLOUD_PROJECT,'demo-uhc-test');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
const {db,auth,admin}=require('../lib/firebase');
const {deleteUserAccount}=require('../lib/users');
const {deleteAdminAccount,assignSuperAdminSlot}=require('../lib/admin');
const accounts=[];
async function account(role,extra={}){
 const uid=`qa-account-${randomUUID()}`,email=`${uid}@example.test`;accounts.push(uid);
 await auth.importUsers([{uid,email,providerData:[{providerId:'google.com',uid,email}]}]);
 await db.doc(`users/${uid}`).set({role,isActive:true,fullName:'Synthetic QA Account',...extra});
 return uid;
}
after(async()=>{for(const uid of accounts){await db.doc(`users/${uid}`).delete();await auth.deleteUser(uid).catch(e=>{if(e.code!=='auth/user-not-found')throw e});}await admin.app().delete();});
test('real Firestore guard prevents promotion through late Auth completion for student and admin deletion',async t=>{
 const owner=await account('superAdmin',{superAdminType:'primary'});
 const manager=await account('admin',{adminPermissions:{'users.manageNonAdmin':true}});
 const originalDelete=auth.deleteUser.bind(auth);
 for(const role of ['student','admin']){
  const uid=await account(role);let lateDelete;
  const mock=t.mock.method(auth,'deleteUser',async target=>{
   if(target!==uid)return originalDelete(target);
   lateDelete=()=>originalDelete(uid);
   throw Object.assign(new Error('Synthetic ambiguous response'),{code:'auth/internal-error'});
  });
  const handler=role==='admin'?deleteAdminAccount:deleteUserAccount;
  const caller=role==='admin'?owner:manager;
  const log=console.error;console.error=()=>{};
  try{await assert.rejects(handler.run({auth:{uid:caller},data:{targetUid:uid}}),e=>e.code==='internal'&&e.details?.reason==='account-mutation-locked');}finally{console.error=log;}
  const ref=db.doc(`users/${uid}`),guard=(await ref.get()).data().accountMutationId;
  assert.equal(typeof guard,'string');
  await assert.rejects(assignSuperAdminSlot.run({auth:{uid:owner},data:{targetUid:uid,slotType:'backup'}}),{code:'aborted'});
  await lateDelete();
  await assert.rejects(auth.getUser(uid),{code:'auth/user-not-found'});
  const profile=(await ref.get()).data();assert.equal(profile.role,role);assert.equal(profile.accountMutationId,guard);
  mock.mock.restore();
  // Controlled reconciliation after late deletion has acknowledged completion.
  await db.runTransaction(async tx=>{const current=await tx.get(ref);assert.equal(current.data().accountMutationId,guard);tx.delete(ref);});
  await assert.rejects(assignSuperAdminSlot.run({auth:{uid:owner},data:{targetUid:uid,slotType:'backup'}}),{code:'not-found'});
 }
});
