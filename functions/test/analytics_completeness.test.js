const {test} = require('node:test');
const assert = require('node:assert/strict');
process.env.GCLOUD_PROJECT = 'demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
const {db,auth} = require('../lib/firebase');
const {getAppointmentAnalytics} = require('../lib/analytics');
test('bounded analytics distinguishes exact cap and partial results for each period without returning rows', async t => {
    let records = 0, cap, direction, selected;
    const filters=[];
    const query={where(...args){filters.push(args);return this},orderBy(_,dir){direction=dir;return this},
        select(...fields){selected=fields;return this},limit(n){cap=n;return this},
        get:async()=>({size:Math.min(records,cap),docs:Array.from({length:Math.min(records,cap)},()=>({data:()=>({
            status:'completed',department:'Synthetic',appointmentDate:{toDate:()=>new Date()},medicalNotes:'private-marker',patientId:'private-id'
        })}))})};
    t.mock.method(auth,'getUser',async()=>({providerData:[{providerId:'google.com'}]}));
    t.mock.method(db,'collection',name=>name==='users'?{doc:()=>({get:async()=>({exists:true,data:()=>({role:'admin',isActive:true,adminPermissions:{'analytics.view':true}})})})}:query);
    for(const period of ['week','month','year']) for(const n of [0,4999,5000,5001,12000]) {
        records=n;filters.length=0;
        const result=await getAppointmentAnalytics.run({auth:{uid:'synthetic-analytics'},data:{period}});
        assert.equal(result.total,Math.min(n,5000));
        assert.equal(result.truncated,n>5000);
        assert.equal(result.statuses.completed||0,Math.min(n,5000));
        assert.equal(result.period,period);
        assert.equal(result.selection,'latest-created');
        assert.equal(cap,5001); assert.equal(direction,'desc');
        assert.deepEqual(selected,['status','department','appointmentDate']);
        assert.equal(filters.length,2);assert.equal(filters[1][1],'<=');
        assert.equal(JSON.stringify(result).includes('private-'),false);
    }
});
