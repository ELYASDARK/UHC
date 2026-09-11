import { AssistantReplyLanguage } from './types';

export function normalizeLocale(locale?: string): AssistantReplyLanguage {
    if (!locale || typeof locale !== 'string') return 'en';
    const clean = locale.trim().toLowerCase();
    if (clean === 'ar' || clean.startsWith('ar-')) return 'ar';
    if (clean === 'ku' || clean === 'ckb' || clean.startsWith('ku-') || clean.startsWith('ckb-')) return 'ckb';
    return 'en';
}

export type LocalizedMessageKey =
    | 'ready'
    | 'missing_date'
    | 'past_date'
    | 'invalid_date'
    | 'date_too_far'
    | 'unknown_department'
    | 'unknown_doctor'
    | 'doctor_department_mismatch'
    | 'doctor_not_found'
    | 'ambiguous_doctor'
    | 'no_doctors_in_department'
    | 'no_slots_found'
    | 'clarify_general'
    | 'out_of_scope_medical'
    | 'out_of_scope_emergency'
    | 'out_of_scope_prescription'
    | 'out_of_scope_general'
    | 'daily_limit'
    | 'throttled_user'
    | 'throttled_project'
    | 'disabled'
    | 'unavailable'
    | 'cancelled';

const MESSAGES: Record<LocalizedMessageKey, Record<AssistantReplyLanguage, string>> = {
    ready: {
        en: 'Here are available appointment slots matching your request. Please select a slot to confirm your booking. Note: Slots are not reserved until confirmed.',
        ar: 'إليك المواعيد المتاحة التي تطابق طلبك. يرجى اختيار موعد لتأكيد حجزك. ملاحظة: المواعيد غير محجوزة حتى يتم التأكيد.',
        ckb: 'ئەمەش کاتە بەردەستەکانن کە لەگەڵ داواکارییەکەتدا دەگونجێن. تکایە کاتێک هەڵبژێرە بۆ پشتڕاستکردنەوەی نۆرەکەت. تێبینی: کاتەکان پارێزراو نین تا پشتڕاست دەکرێنەوە.',
    },
    missing_date: {
        en: 'Please specify the date you would like to schedule your appointment for (e.g. tomorrow or YYYY-MM-DD).',
        ar: 'يرجى تحديد التاريخ الذي ترغب في حجز موعدك فيه (مثلاً غداً أو بصيغة YYYY-MM-DD).',
        ckb: 'تکایە ئەو بەروارە دیاری بکە کە دەتەوێت نۆرەکەت تێدا بێت (بۆ نموونە سبەی یان YYYY-MM-DD).',
    },
    past_date: {
        en: 'The requested date is in the past. Please select a future date.',
        ar: 'التاريخ المطلوب قد مضى. يرجى اختيار تاريخ قادم.',
        ckb: 'ئەو بەروارەی داوات کردووە بەسەرچووە. تکایە بەروارێکی داهاتوو هەڵبژێرە.',
    },
    invalid_date: {
        en: 'The requested date is invalid. Please provide a valid date in YYYY-MM-DD format.',
        ar: 'التاريخ المطلوب غير صالح. يرجى تقديم تاريخ صالح بصيغة YYYY-MM-DD.',
        ckb: 'بەرواری داواکراو نادروستە. تکایە بەروارێکی دروست بە شێوازی YYYY-MM-DD بنووسە.',
    },
    date_too_far: {
        en: 'Appointments can only be booked up to 30 days in advance.',
        ar: 'يمكن حجز المواعيد مسبقاً حتى 30 يوماً فقط.',
        ckb: 'نۆرەکان تەنها تاوەکو ٣٠ ڕۆژ پێشوەختە دەتوانرێت دابنرێن.',
    },
    unknown_department: {
        en: 'The specified department was not found. Please choose an active clinic department.',
        ar: 'القسم المحدد غير موجود. يرجى اختيار قسم نشط في العيادة.',
        ckb: 'بەشی دیاریکراو نەدۆزرایەوە. تکایە بەشێکی چالاکی کلینیک هەڵبژێرە.',
    },
    unknown_doctor: {
        en: 'The requested doctor is not currently available or active. Please select another doctor.',
        ar: 'الطبيب المطلوب غير متاح أو غير نشط حالياً. يرجى اختيار طبيب آخر.',
        ckb: 'پزیشکی داواکراو لە ئێستادا بەردەست نییە. تکایە پزیشکێکی تر هەڵبژێرە.',
    },
    doctor_department_mismatch: {
        en: 'The selected doctor does not belong to the requested department. Please check your selection.',
        ar: 'الطبيب المختار لا ينتمي إلى القسم المطلوب. يرجى التحقق من اختيارك.',
        ckb: 'پزیشکی هەڵبژێردراو لە بەشی داواکراودا نییە. تکایە دڵنیابەرەوە لە هەڵبژاردنەکەت.',
    },
    doctor_not_found: {
        en: 'Could not find a doctor matching that name. Please check the spelling or specify a department.',
        ar: 'لم نتمكن من العثور على طبيب بهذا الاسم. يرجى التحقق من الاسم أو تحديد القسم.',
        ckb: 'هیچ پزیشکێک بەو ناوە نەدۆزرایەوە. تکایە دڵنیابەرەوە لە ناوەکە یاخود بەشەکە دیاری بکە.',
    },
    ambiguous_doctor: {
        en: 'Multiple doctors match that name. Please specify the doctor’s full name or department.',
        ar: 'يوجد أكثر من طبيب بهذا الاسم. يرجى تحديد الاسم الكامل للطبيب أو القسم.',
        ckb: 'چەندین پزیشک بەو ناوە هەن. تکایە ناوی تەواوی پزیشک یان بەشەکەی دیاری بکە.',
    },
    no_doctors_in_department: {
        en: 'There are currently no active doctors available in this department.',
        ar: 'لا يوجد أطباء متاحون حالياً في هذا القسم.',
        ckb: 'لە ئێستادا هیچ پزیشکێکی بەردەست لەم بەشەدا نییە.',
    },
    no_slots_found: {
        en: 'No available appointment slots found matching those exact preferences. Please try a different date or time.',
        ar: 'لم يتم العثور على مواعيد متاحة تطابق هذه التفضيلات. يرجى تجربة تاريخ أو وقت آخر.',
        ckb: 'هیچ کاتێکی بەردەست بۆ ئەو داواکارییە نەدۆزرایەوە. تکایە بەروار یان کاتێکی تر تاقی بکەرەوە.',
    },
    clarify_general: {
        en: 'Could you please specify which doctor, department, or date you would like to book for?',
        ar: 'هل يمكنك تحديد الطبيب أو القسم أو التاريخ الذي ترغب في الحجز له؟',
        ckb: 'دەتوانیت دیاری بکەیت کە دەتەوێت بۆ چ پزیشکێک، بەشێک، یان بەروارێک نۆرە بگریت؟',
    },
    out_of_scope_medical: {
        en: 'I cannot provide medical advice, diagnosis, or treatment recommendations. For health concerns or emergencies, please consult a healthcare professional or visit emergency services immediately.',
        ar: 'لا يمكنني تقديم المشورة الطبية أو التشخيص أو التوصيات العلاجية. للحالات الصحية أو الطوارئ، يرجى استشارة أخصائي رعاية صحية أو التوجه فوراً للطوارئ.',
        ckb: 'من ناتوانم ڕاوێژی پزیشکی، دەستنیشانکردنی نەخۆشی یان چارەسەر پێشکەش بکەم. بۆ کێشەی تەندروستی یان باری لەناکاو، تکایە ڕاوێژ لەگەڵ پزیشک بکە یان سەردانی فریاکەوتن بکە.',
    },
    out_of_scope_emergency: {
        en: 'If you are experiencing a medical emergency, please call university emergency services or go to the nearest emergency room immediately.',
        ar: 'إذا كنت تعاني من حالة طوارئ طبية، يرجى الاتصال بخدمات الطوارئ الجامعية أو التوجه إلى أقرب قسم طوارئ فوراً.',
        ckb: 'ئەگەر لە باری لەناکاوی پزیشکیدایت، تکایە دەستبەجێ پەیوەندی بە فریاکەوتنەوە بکە یان سەردانی نزیکترین بەشی فریاکەوتن بکە.',
    },
    out_of_scope_prescription: {
        en: 'I cannot prescribe medication or advise on prescriptions. Please schedule an appointment with a clinic doctor for medication inquiries.',
        ar: 'لا يمكنني وصف الأدوية أو تقديم المشورة بشأن الوصفات الطبية. يرجى حجز موعد مع طبيب في العيادة.',
        ckb: 'من ناتوانم دەرمان بنووسم یان ڕاوێژ لەسەر دەرمان بدەم. تکایە نۆرەیەک لای پزیشک بگرە بۆ پرسیارەکانی دەرمان.',
    },
    out_of_scope_general: {
        en: 'I can only assist with scheduling clinic appointments. Please let me know which doctor or department you would like to book with.',
        ar: 'يمكنني فقط المساعدة في حجز مواعيد العيادة. يرجى إخباري بالطبيب أو القسم الذي ترغب في الحجز معه.',
        ckb: 'من تەنها دەتوانم هاوکاریت بکەم لە نۆرەگرتنی کلینیکدا. تکایە پێم بڵێ دەتەوێت لەگەڵ چ پزیشکێک یان بەشێک نۆرە بگریت.',
    },
    daily_limit: {
        en: 'The assistant has reached today’s daily limit. Standard booking remains available in the app.',
        ar: 'وصل المساعد إلى الحد اليومي الأقصى. الحجز الاعتيادي لا يزال متاحاً في التطبيق.',
        ckb: 'یاریدەدەر گەیشتووەتە سنووری ڕۆژانەی ئەمڕۆ. نۆرەگرتنی ئاسایی لە ئەپەکەدا هێشتا بەردەستە.',
    },
    throttled_user: {
        en: 'You have sent several messages quickly. Please wait a moment before sending another message.',
        ar: 'لقد أرسلت عدة رسائل بسرعة. يرجى الانتظار لحظة قبل إرسال رسالة أخرى.',
        ckb: 'چەندین نامەت بە خێرایی ناردووە. تکایە کەمێک بوەستە پێش ناردنی نامەیەکی تر.',
    },
    throttled_project: {
        en: 'The assistant is currently experiencing high demand. Please try again in a few moments.',
        ar: 'يشهد المساعد حالياً ضغطاً كبيراً. يرجى المحاولة مرة أخرى بعد لحظات.',
        ckb: 'یاریدەدەر لە ئێستادا لەژێر فشارێکی زۆردایە. تکایە دوای کەمێکی تر تاقی بکەرەوە.',
    },
    disabled: {
        en: 'The AI appointment assistant is currently disabled by administrator policy.',
        ar: 'المساعد الذكي للمواعيد معطل حالياً وفقاً لسياسة الإدارة.',
        ckb: 'یاریدەدەری زیرەکی نۆرەگرتن لە ئێستادا بە بڕیاری بەڕێوەبەرایەتی ناچالاک کراوە.',
    },
    unavailable: {
        en: 'The assistant service is temporarily unavailable. Standard booking remains available.',
        ar: 'خدمة المساعد غير متاحة مؤقتاً. الحجز الاعتيادي لا يزال متاحاً.',
        ckb: 'خزمەتگوزاری یاریدەدەر لە ئێستادا بەردەست نییە. نۆرەگرتنی ئاسایی بەردەستە.',
    },
    cancelled: {
        en: 'The conversation was reset or updated concurrently. Please send your message again.',
        ar: 'تمت إعادة ضبط المحادثة أو تحديثها بشكل متزامن. يرجى إرسال رسالتك مرة أخرى.',
        ckb: 'گفتوگۆکە لە هەمان کاتدا نوێکرایەوە یان ڕێکخرایەوە. تکایە نامەکەت دووبارە بنێرەوە.',
    },
};

export function getLocalizedMessage(key: LocalizedMessageKey, lang: AssistantReplyLanguage): string {
    const table = MESSAGES[key] || MESSAGES.clarify_general;
    return table[lang] || table.en;
}
