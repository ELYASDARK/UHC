import { AssistantReplyLanguage } from './types';
import { normalizeLocale } from './localization';

// Scheduling vocabulary is only a local fallback when no model language exists.
// Names, script and individual characters cannot establish sentence language.
const schedulingWords: Record<AssistantReplyLanguage, ReadonlySet<string>> = {
    en: new Set('please book appointment appointments tomorrow schedule available want need with at dentist dentistry'.split(' ')),
    ar: new Set('ارید موعد احجز حجز غدا مع عند الدکتور اسنان صباح مساء متاح'.split(' ')),
    ckb: new Set('کاتی کاتم کاتێک ددان سبەی دەمەوێت پزیشک پزیشکی لای بگرم بەیانی ئەمڕۆ نۆرە'.split(' ')),
};

export function detectSchedulingLanguage(text: string): AssistantReplyLanguage | null {
    const withoutNames = text.replace(/"[^"\n]*"|'[^'\n]*'|“[^”\n]*”|‘[^’\n]*’|«[^»\n]*»/gu, ' ');
    const sentence = /\p{L}/u.test(withoutNames) ? withoutNames : text;
    const words = new Set(sentence.normalize('NFKC').toLowerCase()
        .replace(/[\u064b-\u065f\u0670]/gu, '')
        .replace(/[أإآ]/gu, 'ا').replace(/ك/gu, 'ک').replace(/[يى]/gu, 'ی')
        .match(/[\p{L}\p{M}]+/gu) || []);
    const scores = (Object.keys(schedulingWords) as AssistantReplyLanguage[])
        .map(language => ({ language, score: [...words].filter(word => schedulingWords[language].has(word)).length }))
        .sort((left, right) => right.score - left.score);
    return scores[0].score > scores[1].score ? scores[0].language : null;
}

// Unknown vocabulary, names-only input and tied mixed requests remain uncertain.
// UI locale resolves that uncertainty only; history never overrides a new turn.
export function messageLanguage(text: string, fallback?: string): AssistantReplyLanguage {
    return detectSchedulingLanguage(text) || normalizeLocale(fallback);
}
