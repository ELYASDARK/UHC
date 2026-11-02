const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
process.env.GCLOUD_PROJECT='demo-uhc-test';
process.env.GOOGLE_CLOUD_PROJECT='demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099';
process.env.FUNCTIONS_EMULATOR='true';
process.env.AI_OFFLINE_SYNTHETIC_TESTING='true';
const {db,auth,admin}=require('../lib/firebase');
const {sendAssistantMessage,getAssistantHistory,clearAssistantHistory,confirmAssistantAppointment}=require('../lib/assistant');
test('active Google-linked patients and regular admins own assistant bookings while super-admins and doctors are denied', {timeout:120000},async t=>{
    // Receipt payloads must never be printed by this test, including downstream diagnostics.
    t.mock.method(console,'log',()=>{});
    t.after(()=>admin.app().delete());
    const suffix=randomUUID(),doctorId=`qa-self-doctor-${suffix}`,department=`qa-own-${suffix}`;
    const now=admin.firestore.Timestamp.now();
    await db.doc(`departments/${department}`).set({key:department,name:'Synthetic Self Booking',isActive:true});
    await db.doc(`doctors/${doctorId}`).set({name:`Synthetic Clinician ${suffix}`,department,isActive:true,isAvailable:true,
        weeklySchedule:Object.fromEntries(['monday','tuesday','wednesday','thursday','friday','saturday','sunday'].map(day=>[day,[
            {startTime:'13:00',endTime:'13:30',isAvailable:true},{startTime:'14:00',endTime:'14:30',isAvailable:true},
            {startTime:'15:00',endTime:'15:30',isAvailable:true}]])),createdAt:now});
    let firstOffer;
    for(const role of ['student','staff','admin']){
        const uid=`qa-self-${role}-${suffix}`,email=`${role}-${suffix}@example.test`;
        await auth.importUsers([{uid,email,providerData:[{providerId:'google.com',uid,email}]}]);
        await db.doc(`users/${uid}`).set({role,isActive:true,googleEmail:email,fullName:'Synthetic Self User'});
        const request={auth:{uid},data:{message:'Book Synthetic Self Booking tomorrow.',locale:'en',clientRequestId:randomUUID()}};
        const turn=await sendAssistantMessage.run(request);
        assert.equal(turn.success,true);assert.ok(turn.offers.length>0,JSON.stringify({role,status:turn.status,reason:turn.reasonCode}));
        assert.equal(turn.replyLanguage,'en');
        const history=await getAssistantHistory.run({auth:{uid},data:{}});
        assert.equal(history.messages.length,2);
        const offer=turn.offers[0];
        if(firstOffer) await assert.rejects(confirmAssistantAppointment.run({auth:{uid},data:{offerId:firstOffer,confirmed:true}}));
        else firstOffer=offer.offerId;
        await assert.rejects(confirmAssistantAppointment.run({auth:{uid},data:{offerId:offer.offerId,confirmed:false}}),{code:'invalid-argument'});
        const result=await confirmAssistantAppointment.run({auth:{uid},data:{offerId:offer.offerId,confirmed:true,patientId:'another-patient'}});
        assert.equal(result.success,true);
        const appointment=await db.doc(`appointments/${result.appointmentId}`).get();
        assert.equal(appointment.get('patientId'),uid);assert.equal(appointment.get('doctorId'),doctorId);
        const retry=await confirmAssistantAppointment.run({auth:{uid},data:{offerId:offer.offerId,confirmed:true}});
        assert.equal(retry.appointmentId,result.appointmentId);
        await clearAssistantHistory.run({auth:{uid},data:{patientId:'another-patient'}});
        assert.equal((await getAssistantHistory.run({auth:{uid},data:{}})).messages.length,0);
        await db.doc(`users/${uid}`).update({isActive:false});
        await assert.rejects(getAssistantHistory.run({auth:{uid},data:{}}),{code:'permission-denied'});
        await assert.rejects(clearAssistantHistory.run({auth:{uid},data:{}}),{code:'permission-denied'});
        if(role==='admin'){
            await db.doc(`users/${uid}`).update({role:'superAdmin',isActive:true});
            for(const [endpoint,data] of [[sendAssistantMessage,{message:'Book tomorrow.',locale:'en'}],
                [getAssistantHistory,{}],[clearAssistantHistory,{}],
                [confirmAssistantAppointment,{offerId:offer.offerId,confirmed:true}]]){
                await assert.rejects(endpoint.run({auth:{uid},data}),{code:'permission-denied'});
            }
        }
    }
    for(const role of ['superAdmin','doctor']){
        const uid=`qa-denied-${role}-${suffix}`,email=`denied-${role}-${suffix}@example.test`;
        await auth.importUsers([{uid,email,providerData:[{providerId:'google.com',uid,email}]}]);
        await db.doc(`users/${uid}`).set({role,isActive:true,googleEmail:email});
        // Keep existing history intact on denial, including a promoted account.
        const historyRef=db.doc(`assistant_chats/${uid}`);
        await historyRef.set({messages:[{sender:'patient',text:'Synthetic preserved history'}],revision:7});
        const before=(await historyRef.get()).data();
        for(const [endpoint,data] of [[sendAssistantMessage,{message:'Book tomorrow.',locale:'en'}],
            [getAssistantHistory,{}],[clearAssistantHistory,{}],
            [confirmAssistantAppointment,{offerId:firstOffer,confirmed:true}]]){
            await assert.rejects(endpoint.run({auth:{uid},data}),{code:'permission-denied'});
        }
        assert.deepEqual((await historyRef.get()).data(),before);
    }
    const unlinkedUid=`qa-unlinked-${suffix}`;
    await auth.createUser({uid:unlinkedUid,email:`unlinked-${suffix}@example.test`});
    await db.doc(`users/${unlinkedUid}`).set({role:'admin',isActive:true});
    for(const [endpoint,data] of [[sendAssistantMessage,{message:'Book tomorrow.',locale:'en'}],
        [getAssistantHistory,{}],[clearAssistantHistory,{}],
        [confirmAssistantAppointment,{offerId:firstOffer,confirmed:true}]]){
        await assert.rejects(endpoint.run({auth:{uid:unlinkedUid},data}),{code:'failed-precondition'});
    }
});
