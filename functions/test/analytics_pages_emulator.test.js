const {test} = require('node:test');
const assert = require('node:assert/strict');
process.env.GCLOUD_PROJECT='demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8080';
const {db,admin}=require('../lib/firebase');
const {appointmentAnalyticsPage}=require('../lib/shared/analyticsPages');
test('large aggregate pages are complete, replay-safe, owned, cancellable and snapshot-consistent', {timeout:180000}, async t => {
    t.after(() => admin.app().delete());
    const now=admin.firestore.Timestamp.now();
    for(let i=0;i<50001;i+=400) {
        const batch=db.batch();
        for(let j=i;j<Math.min(i+400,50001);j++) batch.set(db.doc(`appointments/qa-pages-${String(j).padStart(5,'0')}`),
            {createdAt:now,appointmentDate:now,status:'completed',department:'Synthetic Pages'});
        await batch.commit();
    }
    const input={protocol:2,period:'week',requestId:require('node:crypto').randomUUID(),action:'start',version:0};
    let page=await appointmentAnalyticsPage('qa-pages-owner',input);
    const baseline=page.total;
    assert.equal(page.complete,false); assert.equal(page.version,1);
    assert.deepEqual(await appointmentAnalyticsPage('qa-pages-owner',input),page);
    await db.doc('appointments/qa-pages-00000').delete();
    await db.doc('appointments/qa-pages-00001').update({status:'cancelled'});
    let calls=1;
    while(!page.complete) {
        page=await appointmentAnalyticsPage('qa-pages-owner',{...input,action:'next',version:page.version});
        calls++;
    }
    assert.equal(page.departments['Synthetic Pages'],50001);
    assert.equal(page.statuses.cancelled||0,0);
    assert.ok(page.total>=50001); assert.ok(calls>=26); assert.equal(baseline,2000);
    assert.equal(JSON.stringify(page).includes('patientId'),false);
    const other=await appointmentAnalyticsPage('qa-pages-other',{...input,action:'start'});
    assert.equal(other.version,1);
    const cancelled=await appointmentAnalyticsPage('qa-pages-other',{...input,action:'cancel',version:1});
    assert.equal(cancelled.cancelled,true);
    await assert.rejects(appointmentAnalyticsPage('qa-pages-other',{...input,action:'next',version:1}),{code:'cancelled'});
    console.log(JSON.stringify({pages:calls,total:page.total,complete:page.complete,asOf:page.asOf}));
});
