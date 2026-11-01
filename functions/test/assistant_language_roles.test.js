const {test} = require('node:test');
const assert = require('node:assert/strict');
const {messageLanguage,detectSchedulingLanguage} = require('../lib/assistant/language');
const {SyntheticSchedulingInterpreter} = require('../lib/assistant/syntheticInterpreter');
const {requireAssistantUser} = require('../lib/assistant/auth');
const {requirePatientRole} = require('../lib/shared/auth');
test('each message language is independent of all three UI locales, including history and punctuation', async () => {
    const samples = [['Please book dentistry tomorrow.', 'en'], ['أريد موعد أسنان غدا.', 'ar'], ['دەمەوێت کاتێک لای پزیشکی ددان بگرم.', 'ckb']];
    for (const ui of ['en','ar','ku']) for (const [message, language] of samples) {
        assert.equal(messageLanguage(message,ui),language);
        const result = await new SyntheticSchedulingInterpreter().interpretSchedulingRequest({
            baghdadDateString:'2026-10-30',userMessage:message,clientLocale:ui==='ku'?'ckb':ui,chatHistory:[{sender:'patient',text:'Earlier English turn.'}],
            departments:[{key:'dentistry',name:'Dentistry'}],doctors:[],
        });
        assert.equal(result.replyLanguage,language);
        assert.equal(result.intent,'book_appointment');
        assert.equal(result.departmentKey,'dentistry');
    }
    assert.equal(messageLanguage('"09:00, ددان پزیشک"','en'),'ckb');
    assert.equal(messageLanguage('09:00','ku'),'ckb');
    assert.equal(messageLanguage('Please book ددان سبەی at 09:00.','ku'),'en');
});
test('2026-10-30 language regression: scheduling syntax beats names and script, uncertain input falls back explicitly', () => {
    const examples = [
        ['کاتی ددان','ckb'], ['ددان','ckb'], ['کاتم سبەی','ckb'],
        ['موعد مع الدكتور ژوان','ar'], ['موعد مع الدكتور چنار','ar'],
        ['John أريد موعد غدا','ar'], ['"Please Book" موعد مع الدكتور چنار','ar'],
        ["'Please book tomorrow' موعد مع الدكتور ژوان",'ar'],
        ['ژوان Please book dentistry tomorrow','en'],
        ['Please book ددان سبەی at 09:00','en'],
        ['دەمەوێت لای "John" کاتی ددان بگرم','ckb'],
        ['أريد موعد مع "Dr. ژوان" غدا','ar'],
    ];
    for(const [text,expected] of examples) for(const ui of ['en','ar','ku']) {
        assert.equal(detectSchedulingLanguage(text),expected,text);
        assert.equal(messageLanguage(text,ui),expected,text);
    }
    for(const text of ['ژوان','چنار','John','09:00 ١٢٣ ؟!','Book موعد','سلام']) {
        assert.equal(detectSchedulingLanguage(text),null,text);
        for(const [ui,expected] of [['en','en'],['ar','ar'],['ku','ckb']]) {
            assert.equal(messageLanguage(text,ui),expected,text);
        }
    }
});
test('assistant-only self-use allows active regular admins and denies super-admins without broadening shared patient policy', () => {
    for (const role of ['student','staff','admin']) {
        requireAssistantUser({data:()=>({role,isActive:true})});
        if (role==='admin') assert.throws(()=>requirePatientRole({data:()=>({role,isActive:true})}));
    }
    for (const profile of [{role:'superAdmin',isActive:true},{role:'doctor',isActive:true},{role:'admin',isActive:false},{}]) {
        assert.throws(()=>requireAssistantUser({data:()=>profile}),{code:'permission-denied'});
    }
});
