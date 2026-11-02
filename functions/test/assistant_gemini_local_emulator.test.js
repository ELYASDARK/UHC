const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
process.env.GCLOUD_PROJECT='demo-uhc-test';
process.env.GOOGLE_CLOUD_PROJECT='demo-uhc-test';
process.env.FIRESTORE_EMULATOR_HOST='127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099';
process.env.FUNCTIONS_EMULATOR='true';
const {db,auth,admin}=require('../lib/firebase');
const {sendAssistantMessage,getAssistantHistory}=require('../lib/assistant');

test('real send endpoint retains model language and releases failed turns with injected HTTP and real demo persistence', {timeout:90000},async t=>{
    const oldEnv={...process.env};
    t.after(async()=>{for(const key of Object.keys(process.env))if(!(key in oldEnv))delete process.env[key];Object.assign(process.env,oldEnv);await admin.app().delete();});
    let httpFixture;
    // Install the network boundary before using dummy process-local gate fixtures.
    // Nothing is deployed, real credentials are never read, and no fetch can escape.
    t.mock.method(globalThis,'fetch',async(...args)=>httpFixture(...args));
    t.mock.method(console,'log',()=>{});t.mock.method(console,'error',()=>{});
    delete process.env.AI_OFFLINE_SYNTHETIC_TESTING;
    process.env.AI_ASSISTANT_ENABLED='true';
    process.env.AI_PRIVACY_RELEASE_GATE_ACCEPTED='true';
    process.env.GEMINI_API_KEY='unused-local-http-fixture';
    const cases=[['سلام','en','ckb'],['موعد مع الدكتور ژوان','ku','ar'],['ژوان Please book tomorrow','ar','en']];
    for(const [message,locale,language] of cases){
        const uid='qa-http-'+randomUUID(),email=uid+'@example.test';
        await auth.importUsers([{uid,email,providerData:[{providerId:'google.com',uid,email}]}]);
        await db.doc('users/'+uid).set({role:'student',isActive:true,googleEmail:email});
        let duplicateCurrentTurns;
        httpFixture=(_,options)=>{
            const contents=JSON.parse(options.body).contents;
            duplicateCurrentTurns=contents.slice(0,-1).filter(turn=>turn.role==='user'&&turn.parts[0].text===message).length;
            return new Response(JSON.stringify({candidates:[{content:{parts:[{text:JSON.stringify({
            intent:'clarify',clarificationReason:'missing_date',replyLanguage:language})}]}}]}),{status:200});
        };
        const result=await sendAssistantMessage.run({auth:{uid},data:{message,locale,clientRequestId:randomUUID()}});
        assert.equal(duplicateCurrentTurns,0,'The current request must not be duplicated in prior history');
        assert.equal(result.status,'clarify');assert.equal(result.replyLanguage,language);
        const history=await getAssistantHistory.run({auth:{uid},data:{}});
        assert.equal(history.messages.at(-1).text,result.message);
        assert.equal((await db.doc('assistant_chats/'+uid).get()).get('lastResult.replyLanguage'),language);
    }
    const uid='qa-http-error-'+randomUUID(),email=uid+'@example.test';
    await auth.importUsers([{uid,email,providerData:[{providerId:'google.com',uid,email}]}]);
    await db.doc('users/'+uid).set({role:'student',isActive:true,googleEmail:email});
    httpFixture=()=>new Response('{"error":{"message":"synthetic upstream unavailable"}}',{status:503});
    const unavailable=await sendAssistantMessage.run({auth:{uid},data:{message:'کاتی ددان',locale:'en',clientRequestId:randomUUID()}});
    assert.equal(unavailable.status,'unavailable');assert.equal(unavailable.reasonCode,'upstream_unavailable');assert.equal(unavailable.replyLanguage,'ckb');
    const saved=await db.doc('assistant_chats/'+uid).get();
    assert.equal(saved.exists,true);assert.equal(saved.get('lastResult.status'),'unavailable');
    assert.equal(saved.get('inFlightTurnId')??null,null);
    const failures=[
        [()=>new Response('not-json'),'upstream_invalid_json'],
        [()=>new Response('{}'),'upstream_empty_response'],
        [()=>new Response(JSON.stringify({candidates:[{content:{parts:[{text:JSON.stringify({intent:'execute_booking',replyLanguage:'ckb'})}]}}]})),'upstream_invalid_intent'],
        [()=>{throw new TypeError('synthetic network failure');},'upstream_network'],
    ];
    for(const [fixture,reason] of failures){
        httpFixture=fixture;
        const result=await sendAssistantMessage.run({auth:{uid},data:{message:'کاتی ددان',locale:'en',clientRequestId:randomUUID()}});
        assert.equal(result.status,'unavailable');assert.equal(result.reasonCode,reason);assert.equal(result.offers.length,0);
        const after=await db.doc('assistant_chats/'+uid).get();
        assert.equal(after.get('inFlightTurnId')??null,null);assert.equal(after.get('lastResult.reasonCode'),reason);
    }
});
