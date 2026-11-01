const {test}=require('node:test');
const assert=require('node:assert/strict');
const {GeminiAssistantClient}=require('../lib/assistant/geminiClient');
const {matchScheduleAndGenerateOffers}=require('../lib/assistant/scheduleMatcher');
const {classifyGeminiError}=require('../lib/assistant/quota');
const {messageLanguage}=require('../lib/assistant/language');
const {ASSISTANT_CONFIG}=require('../lib/assistant/config');

const now=new Date('2026-10-30T09:00:00Z');
const request=(message,locale='en')=>({userMessage:message,clientLocale:messageLanguage(message,locale),
    chatHistory:[{sender:'patient',text:'Please book tomorrow.'},{sender:'assistant',text:'Earlier English response.'}],
    baghdadDateString:'2026-10-30',departments:[],doctors:[]});
const response=body=>new Response(JSON.stringify(body),{status:200});
const candidate=intent=>response({candidates:[{content:{parts:[{text:JSON.stringify(intent)}]}}]});

test('real Gemini HTTP parser preserves validated language, current turn and bounded history across switches',async t=>{
    const previous=process.env.AI_OFFLINE_SYNTHETIC_TESTING;
    delete process.env.AI_OFFLINE_SYNTHETIC_TESTING;
    t.after(()=>{if(previous===undefined)delete process.env.AI_OFFLINE_SYNTHETIC_TESTING;else process.env.AI_OFFLINE_SYNTHETIC_TESTING=previous;});
    const examples=[['کاتی ددان','ckb'],['ددان','ckb'],['موعد مع الدكتور ژوان','ar'],
        ['موعد مع الدكتور چنار','ar'],['John أريد موعد غدا','ar'],['ژوان Please book tomorrow','en'],
        ['"John" دەمەوێت کاتی ددان بگرم','ckb'],['سلام','ckb']];
    for(const ui of ['en','ar','ku']) for(const [text,language] of examples){
        let payload;
        // Only the outbound HTTP boundary is replaced; the real validator and matcher run.
        const client=new GeminiAssistantClient({apiKey:'unused-local-fixture',fetchImpl:async(_,options)=>{
            payload=JSON.parse(options.body);
            return candidate({intent:'clarify',clarificationReason:'missing_date',replyLanguage:language});
        }});
        const parsed=await client.interpretSchedulingRequest(request(text,ui));
        assert.equal(parsed.parsedIntent.replyLanguage,language);
        assert.ok(payload.contents.at(-1).parts[0].text.includes(text));
        const matched=await matchScheduleAndGenerateOffers({},parsed.parsedIntent,[],[],now);
        assert.equal(matched.status,'clarify');
        assert.ok(matched.message.length>0);
    }
});

test('malformed HTTP success responses remain failures; unknown catalog entries do not become bookings',async t=>{
    const previous=process.env.AI_OFFLINE_SYNTHETIC_TESTING;delete process.env.AI_OFFLINE_SYNTHETIC_TESTING;
    t.after(()=>{if(previous===undefined)delete process.env.AI_OFFLINE_SYNTHETIC_TESTING;else process.env.AI_OFFLINE_SYNTHETIC_TESTING=previous;});
    const malformed=[[()=>new Response('not json'),'upstream_invalid_json'],[()=>response({}),'upstream_empty_response'],
        [()=>response({candidates:[{content:{parts:[{text:'{bad'}]}}]}),'upstream_invalid_json'],
        [()=>candidate({intent:'execute_booking',replyLanguage:'ckb'}),'upstream_invalid_intent'],
        [()=>candidate({intent:'clarify',replyLanguage:'xx'}),'upstream_invalid_intent'],
        [()=>candidate({intent:'clarify',replyLanguage:'ar',unexpected:'field'}),'upstream_invalid_intent']];
    for(const [fixture,reason] of malformed){
        const parsed=await new GeminiAssistantClient({apiKey:'unused-local-fixture',fetchImpl:async()=>fixture()})
            .interpretSchedulingRequest(request('کاتی ددان','en'));
        assert.equal(parsed.parsedIntent,undefined);assert.equal(parsed.httpStatus,502);assert.equal(parsed.upstreamStatus,200);assert.equal(parsed.failureReason,reason);
    }
    const mismatch=await new GeminiAssistantClient({apiKey:'unused-local-fixture',fetchImpl:async()=>candidate({
        intent:'book_appointment',doctorId:'not-in-catalog',departmentKey:'unknown',preferredDate:'2026-10-31',replyLanguage:'ar'})})
        .interpretSchedulingRequest(request('موعد مع الدكتور ژوان'));
    const matched=await matchScheduleAndGenerateOffers({},mismatch.parsedIntent,[],[],now);
    assert.equal(matched.status,'clarify');assert.equal(matched.offers.length,0);
});

test('injected HTTP quota, network and timeout failures retain bounded errors instead of success',async t=>{
    const previous=process.env.AI_OFFLINE_SYNTHETIC_TESTING;delete process.env.AI_OFFLINE_SYNTHETIC_TESTING;
    t.after(()=>{if(previous===undefined)delete process.env.AI_OFFLINE_SYNTHETIC_TESTING;else process.env.AI_OFFLINE_SYNTHETIC_TESTING=previous;});
    t.mock.method(console,'error',()=>{});
    for(const [status,body,expected] of [
        [429,{error:{details:[{violations:[{quotaId:'GenerateRequestsPerDay'}]}]}},'daily_limit'],
        [429,{error:{message:'rate limited'}},'throttled'],[503,{error:{}},'unavailable'],[400,{error:{}},'unavailable'],
    ]){
        const parsed=await new GeminiAssistantClient({apiKey:'unused-local-fixture',fetchImpl:async()=>new Response(JSON.stringify(body),{status})})
            .interpretSchedulingRequest(request('کاتی ددان'));
        assert.equal(parsed.parsedIntent,undefined);assert.equal(classifyGeminiError(parsed.httpStatus,parsed.errorBody,now,'ckb').status,expected);
    }
    const network=await new GeminiAssistantClient({apiKey:'unused-local-fixture',fetchImpl:async()=>{throw new TypeError('synthetic offline failure');}})
        .interpretSchedulingRequest(request('موعد مع الدكتور چنار'));
    assert.ok(network.networkError);assert.equal(network.parsedIntent,undefined);assert.equal(network.failureReason,'upstream_network');
    t.mock.timers.enable({apis:['setTimeout']});
    const pending=new GeminiAssistantClient({apiKey:'unused-local-fixture',fetchImpl:async(_,options)=>new Promise((_,reject)=>{
        options.signal.addEventListener('abort',()=>reject(new DOMException('synthetic timeout','AbortError')),{once:true});
    })}).interpretSchedulingRequest(request('Please book tomorrow'));
    t.mock.timers.tick(ASSISTANT_CONFIG.REQUEST_TIMEOUT_MS);
    const timedOut=await pending;assert.equal(timedOut.networkError.name,'AbortError');assert.equal(timedOut.parsedIntent,undefined);assert.equal(timedOut.failureReason,'upstream_timeout');
});
