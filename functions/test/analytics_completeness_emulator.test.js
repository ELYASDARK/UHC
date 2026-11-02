const {test,after} = require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
assert.equal(process.env.GCLOUD_PROJECT,'demo-uhc-test');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8080');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9099');
const {db,auth,admin}=require('../lib/firebase');
const {getAppointmentAnalytics}=require('../lib/analytics');
const uid=`qa-analytics-${randomUUID()}`, prefix=`qa-analytics-${randomUUID()}`;
const refs=[];
after(async()=>{
 for(let i=0;i<refs.length;i+=400){const b=db.batch();refs.slice(i,i+400).forEach(r=>b.delete(r));await b.commit();}
 await db.doc(`users/${uid}`).delete();await auth.deleteUser(uid).catch(()=>{});await admin.app().delete();
});
test('real emulator analytics handles 4,999, 5,000 and 5,001 records with bounded aggregate-only responses',async()=>{
 const email=`${uid}@example.test`;
 await auth.importUsers([{uid,email,providerData:[{providerId:'google.com',uid,email}]}]);
 await db.doc(`users/${uid}`).set({role:'admin',isActive:true,adminPermissions:{'analytics.view':true}});
 const createdAt=admin.firestore.Timestamp.now();
 for(let i=0;i<4999;i+=400){const b=db.batch();for(let j=i;j<Math.min(i+400,4999);j++){
  const r=db.doc(`appointments/${prefix}-${j}`);refs.push(r);
  b.set(r,{status:'completed',createdAt,appointmentDate:createdAt,department:'Synthetic',medicalNotes:'private-marker'});
 }await b.commit();}
 for(const n of [4999,5000,5001]){
  if(n>4999){const r=db.doc(`appointments/${prefix}-${n}`);refs.push(r);await r.set({status:'completed',createdAt,appointmentDate:createdAt,department:'Synthetic'});}
  const started=performance.now();
  const result=await getAppointmentAnalytics.run({auth:{uid},data:{period:'week'}});
  console.log(JSON.stringify({records:n,ms:Math.round(performance.now()-started),included:result.total,truncated:result.truncated}));
  assert.equal(result.total,Math.min(n,5000));assert.equal(result.truncated,n>5000);
  assert.equal(JSON.stringify(result).includes('private-marker'),false);
 }
});
