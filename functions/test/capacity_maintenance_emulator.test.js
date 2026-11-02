const {test} = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const {randomUUID,createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
process.env.GCLOUD_PROJECT='demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8080';
process.env.FIREBASE_STORAGE_EMULATOR_HOST='127.0.0.1:9199';
const admin = require('firebase-admin');
const app=admin.initializeApp({projectId:'demo-uhc-test',storageBucket:'demo-uhc-test.appspot.com'});
const db=app.firestore();
const run=(...args)=>JSON.parse(execFileSync(process.execPath,[path.resolve(__dirname,'../scripts/maintain_capacity.js'),
    '--project','demo-uhc-test',...args],{env:process.env,encoding:'utf8',timeout:30000}));
test('bounded maintenance preserves active jobs and debt, and inventories retained bytes without deleting files', {timeout:120000},async t=>{
    const id=randomUUID(),hour=Math.floor(Date.now()/3600000),now=Date.now();
    const expired=db.doc(`medical_upload_transfer_admissions/qa-${id}`);
    const active=db.doc(`appointment_analytics_jobs/qa-active-${id}`);
    const hash=createHash('sha256').update(id).digest('hex');
    const legacy=db.doc(`medical_upload_budgets/user_${hash}`),v2=db.doc(`medical_upload_budgets/v2_user_${hash}`);
    const files=Array.from({length:7},(_,i)=>app.storage().bucket().file(`medical_documents/qa-capacity-${id}/sample-${i}`));
    t.after(async()=>{
        await Promise.all([expired.delete(),active.delete(),legacy.delete(),v2.delete(),...files.map(file=>file.delete({ignoreNotFound:true}))]);
        await app.delete();
    });
    await expired.set({hour:hour-50,bytes:10,expiresAt:admin.firestore.Timestamp.fromMillis(now-60000)});
    await active.set({expiresAt:admin.firestore.Timestamp.fromMillis(now-60000),leaseUntil:admin.firestore.Timestamp.fromMillis(now+60000)});
    const dry=run('--mode','housekeeping','--limit','500');
    assert.ok(dry.result.medical_upload_transfer_admissions.eligible>=1);
    assert.equal((await expired.get()).exists,true);
    const applied=run('--mode','housekeeping','--limit','500','--apply');
    assert.equal((await expired.get()).exists,false);assert.equal((await active.get()).exists,true);
    assert.ok(applied.result.appointment_analytics_jobs.skipped>=1);
    await legacy.set({hour,bytes:999,attempts:7});
    run('--mode','migrate-budgets','--limit','500');assert.equal((await v2.get()).exists,false);
    run('--mode','migrate-budgets','--limit','500','--apply','--old-writers-drained');
    assert.equal((await v2.get()).get('bytes'),999);assert.equal((await v2.get()).get('buckets')[0].hour,hour);
    await legacy.update({bytes:777});
    run('--mode','migrate-budgets','--limit','500','--apply','--old-writers-drained');
    assert.equal((await v2.get()).get('bytes'),999);
    await Promise.all(files.map(file=>file.save(Buffer.alloc(10),{resumable:false,metadata:{contentType:'application/octet-stream'}})));
    const checkpoint=path.resolve(__dirname,`../../build/qa/2026-10-30-assistant-management-followup/capacity-inventory-${id}.json`);
    let inventory;
    for(let page=0;page<10;page++){
        inventory=run('--mode','inventory','--limit','3','--state-file',checkpoint);
        if(inventory.result.complete)break;
    }
    assert.equal(inventory.result.complete,true);assert.ok(inventory.result.objects>=7);assert.ok(inventory.result.bytes>=70);
    for(const file of files)assert.equal((await file.exists())[0],true);
    assert.equal(fs.readFileSync(checkpoint,'utf8').includes('sample-'),false);
    console.log(JSON.stringify({expiredReceiptRemoved:true,activeLeasePreserved:true,migrationDebtPreserved:true,
        inventoryObjects:inventory.result.objects,inventoryBytes:inventory.result.bytes,inventoryComplete:inventory.result.complete}));
});
