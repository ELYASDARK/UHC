const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID,createHash}=require('node:crypto');
process.env.GCLOUD_PROJECT='demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099';
const {db,auth,admin}=require('../lib/firebase');
const {getAppointmentAnalytics}=require('../lib/analytics');
test('new analytics jobs supersede unfinished work, expire, reauthorize every page and remain private to server code', {timeout:60000},async t=>{
    const uid='qa-analytics-auth-'+randomUUID(),email=uid+'@example.test';
    const own=db.doc('appointments/qa-own-'+randomUUID()),other=db.doc('appointments/qa-other-'+randomUUID());
    const admission=db.doc('appointment_analytics_admissions/'+createHash('sha256').update(uid).digest('hex'));
    const input={protocol:2,period:'week',requestId:randomUUID(),action:'start',version:0};
    const jobRef=requestId=>db.doc('appointment_analytics_jobs/'+createHash('sha256').update(uid+':'+requestId).digest('hex'));
    const next={...input,requestId:randomUUID()};
    const rows=Array.from({length:2001},(_,i)=>db.doc('appointments/'+uid+'-'+i));
    t.after(async()=>{
        for(let i=0;i<rows.length;i+=400){const batch=db.batch();for(const ref of rows.slice(i,i+400))batch.delete(ref);await batch.commit();}
        await Promise.all([own.delete(),other.delete(),db.doc('users/'+uid).delete(),
        admission.delete(),jobRef(input.requestId).delete(),jobRef(next.requestId).delete(),auth.deleteUser(uid)]);await admin.app().delete();});
    await auth.importUsers([{uid,email,providerData:[{providerId:'google.com',uid,email}]}]);
    await db.doc('users/'+uid).set({role:'admin',isActive:true,googleEmail:email,adminPermissions:{'analytics.view':true}});
    // This test needs a next page independently of fixtures from other files.
    const now=admin.firestore.Timestamp.now();
    for(let i=0;i<rows.length;i+=400){const batch=db.batch();for(const ref of rows.slice(i,i+400))batch.set(ref,{createdAt:now,appointmentDate:now,status:'completed',department:'Synthetic authorization'});await batch.commit();}
    for (const invalid of [{period:['week']},{action:['start']}]) {
        await assert.rejects(getAppointmentAnalytics.run({auth:{uid},data:{...input,...invalid}}),{code:'invalid-argument'});
    }
    const first=await getAppointmentAnalytics.run({auth:{uid},data:input});
    assert.equal(first.complete,false);assert.equal(first.total,2000);
    await assert.rejects(getAppointmentAnalytics.run({auth:{uid},data:{...input,action:'next',version:'1'}}),{code:'invalid-argument'});
    // Emulator-only unsigned identity is constructed in memory and never logged or saved.
    const header=Buffer.from(JSON.stringify({alg:'none',typ:'JWT'})).toString('base64url');
    const payload=Buffer.from(JSON.stringify({sub:uid,user_id:uid,aud:'demo-uhc-test',iss:'https://securetoken.google.com/demo-uhc-test'})).toString('base64url');
    const headers={Authorization:'Bearer '+header+'.'+payload+'.'};
    const base='http://127.0.0.1:8080/v1/projects/demo-uhc-test/databases/(default)/documents/';
    await own.set({patientId:uid,doctorId:'synthetic-doctor',status:'pending'});
    await other.set({patientId:'another-synthetic-patient',doctorId:'synthetic-doctor',status:'pending'});
    assert.equal((await fetch(base+jobRef(input.requestId).path,{headers})).status,403);
    assert.equal((await fetch(base+own.path,{headers})).status,200);
    assert.equal((await fetch(base+other.path,{headers})).status,403);
    // Keep the admission window deterministic even when emulator I/O exceeds two seconds.
    await admission.update({lastStartedAt:admin.firestore.Timestamp.fromMillis(Date.now()+30000)});
    await assert.rejects(getAppointmentAnalytics.run({auth:{uid},data:next}),{code:'resource-exhausted'});
    await admission.update({lastStartedAt:admin.firestore.Timestamp.fromMillis(Date.now()-3000)});
    const replacement=await getAppointmentAnalytics.run({auth:{uid},data:next});assert.equal(replacement.total,2000);
    await assert.rejects(getAppointmentAnalytics.run({auth:{uid},data:{...input,action:'next',version:first.version}}),{code:'cancelled'});
    await db.doc('users/'+uid).update({adminPermissions:{}});
    await assert.rejects(getAppointmentAnalytics.run({auth:{uid},data:{...next,action:'next',version:replacement.version}}),{code:'permission-denied'});
    await db.doc('users/'+uid).update({adminPermissions:{'analytics.view':true}});
    await jobRef(next.requestId).update({expiresAt:admin.firestore.Timestamp.fromMillis(Date.now()-1)});
    await assert.rejects(getAppointmentAnalytics.run({auth:{uid},data:{...next,action:'next',version:replacement.version}}),{code:'deadline-exceeded'});
    console.log(JSON.stringify({supersededJobStopped:true,reauthorized:true,expiredJobStopped:true,
        serverJobClientReadDenied:true,ownBookingReadAllowed:true,otherPatientReadDenied:true}));
});
