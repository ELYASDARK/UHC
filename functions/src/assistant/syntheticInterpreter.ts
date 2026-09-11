import { CallGeminiParams } from './geminiClient';
import { StructuredIntent } from './types';

/**
 * Deterministic offline scheduling interpreter for local test execution.
 * Parses scheduling requests into strict StructuredIntent filters without
 * making any external network or AI calls.
 *
 * Visibly documented as OFFLINE TESTING; does not represent or market real Gemini quality.
 */
export class SyntheticSchedulingInterpreter {
    async interpretSchedulingRequest(params: CallGeminiParams): Promise<StructuredIntent> {
        const text = params.userMessage.trim();
        const lower = text.toLowerCase();
        const fallbackLocale = params.clientLocale || 'en';

        // 1. Language detection
        let replyLanguage: 'en' | 'ar' | 'ckb' = fallbackLocale;
        if (/[\u0600-\u06FF\u0750-\u077F]/.test(text)) {
            // Kurdish-specific Sorani characters: ێ, ۆ, ڕ, ڵ, ژ, ڤ, پ, چ, گ
            if (/[ێۆڕڵژڤپچگ]/.test(text)) {
                replyLanguage = 'ckb';
            } else if (fallbackLocale === 'ckb') {
                replyLanguage = 'ckb';
            } else {
                replyLanguage = 'ar';
            }
        }

        // 2. Safety / Out of Scope checks
        // Explicitly rejects medical advice, symptom diagnosis, prescriptions, and emergencies
        const emergencyKeywords = [
            'emergency', 'ambulance', '911', '122', 'heart attack', 'bleeding heavily',
            'طوارئ', 'اسعاف', 'إسعاف', 'فریاکەوتن'
        ];
        const prescriptionKeywords = [
            'prescribe', 'prescription', 'medication', 'medicine', 'pills',
            'دواء', 'علاج', 'وصفة طبية', 'دەرمان'
        ];
        const medicalAdviceKeywords = [
            'medical advice', 'diagnose', 'diagnosis', 'symptoms', 'what should i take',
            'cure', 'fever cure', 'headache cure', 'chest pain',
            'تشخيص', 'أعراض', 'اعراض', 'ألم في الصدر', 'الم صدري', 'وجع رأس',
            'دەستنیشانکردن', 'نیشانەکان', 'ئازاری سنگ'
        ];

        for (const kw of emergencyKeywords) {
            if (lower.includes(kw)) {
                return {
                    intent: 'out_of_scope',
                    outOfScopeReason: 'emergency',
                    replyLanguage,
                };
            }
        }

        for (const kw of prescriptionKeywords) {
            if (lower.includes(kw)) {
                return {
                    intent: 'out_of_scope',
                    outOfScopeReason: 'prescription',
                    replyLanguage,
                };
            }
        }

        for (const kw of medicalAdviceKeywords) {
            if (lower.includes(kw)) {
                return {
                    intent: 'out_of_scope',
                    outOfScopeReason: 'medical_advice',
                    replyLanguage,
                };
            }
        }

        // 3. Department matching from catalog
        let matchedDepartmentKey: string | null = null;
        for (const dept of params.departments) {
            const keyLower = dept.key.toLowerCase();
            const nameLower = dept.name.toLowerCase();
            if (lower.includes(keyLower) || lower.includes(nameLower)) {
                matchedDepartmentKey = dept.key;
                break;
            }
        }

        // Common synonyms / translations for known departments if not matched by exact name
        if (!matchedDepartmentKey) {
            const departmentSynonyms: Record<string, string[]> = {
                dentistry: ['dental', 'dentist', 'tooth', 'teeth', 'smile', 'أسنان', 'اسنان', 'ددان'],
                cardiology: ['cardio', 'heart', 'cardiac', 'قلب', 'دڵ'],
                pediatrics: ['pediatric', 'child', 'children', 'infant', 'أطفال', 'اطفال', 'منداڵ'],
                orthopedics: ['orthopedic', 'bone', 'bones', 'joint', 'joints', 'عظام', 'ئێسک'],
                generalMedicine: ['general medicine', 'general', 'family medicine', 'internal medicine', 'طب عام', 'طبيب عام', 'پزیشکی گشتی'],
            };

            for (const [deptKey, synonyms] of Object.entries(departmentSynonyms)) {
                const catalogMatch = params.departments.find(
                    (d) => d.key.toLowerCase() === deptKey.toLowerCase()
                );
                if (catalogMatch) {
                    if (synonyms.some((syn) => lower.includes(syn))) {
                        matchedDepartmentKey = catalogMatch.key;
                        break;
                    }
                }
            }
        }

        // 4. Doctor matching from catalog
        let matchedDoctorId: string | null = null;
        let matchedDoctorName: string | null = null;
        for (const doc of params.doctors) {
            if (lower.includes(doc.doctorId.toLowerCase())) {
                matchedDoctorId = doc.doctorId;
                matchedDoctorName = doc.name;
                if (!matchedDepartmentKey && doc.department) {
                    matchedDepartmentKey = doc.department;
                }
                break;
            }

            const docNameLower = doc.name.toLowerCase();
            if (lower.includes(docNameLower)) {
                matchedDoctorId = doc.doctorId;
                matchedDoctorName = doc.name;
                if (!matchedDepartmentKey && doc.department) {
                    matchedDepartmentKey = doc.department;
                }
                break;
            }

            // Match significant name parts (excluding "Dr.", "Doctor")
            const nameParts = docNameLower
                .replace(/^(dr\.?|doctor)\s+/i, '')
                .split(/\s+/)
                .filter((p) => p.length >= 3);
            for (const part of nameParts) {
                if (lower.includes(part)) {
                    matchedDoctorId = doc.doctorId;
                    matchedDoctorName = doc.name;
                    if (!matchedDepartmentKey && doc.department) {
                        matchedDepartmentKey = doc.department;
                    }
                    break;
                }
            }
            if (matchedDoctorId) break;
        }

        // 5. Date matching
        let preferredDate: string | null = null;
        const isoDateMatch = text.match(/\b(\d{4}-\d{2}-\d{2})\b/);
        if (isoDateMatch) {
            preferredDate = isoDateMatch[1];
        } else if (lower.includes('today') || lower.includes('اليوم') || lower.includes('ئەمڕۆ')) {
            preferredDate = params.baghdadDateString;
        } else if (lower.includes('tomorrow') || lower.includes('غدا') || lower.includes('سبەی')) {
            const today = new Date(`${params.baghdadDateString}T12:00:00Z`);
            today.setUTCDate(today.getUTCDate() + 1);
            preferredDate = today.toISOString().slice(0, 10);
        } else {
            // Check for weekday names
            const weekdayNames: Record<string, number> = {
                monday: 1, mon: 1, 'الاثنين': 1, 'دووشەممە': 1,
                tuesday: 2, tue: 2, 'الثلاثاء': 2, 'سێشەممە': 2,
                wednesday: 3, wed: 3, 'الاربعاء': 3, 'الأربعاء': 3, 'چوارشەممە': 3,
                thursday: 4, thu: 4, 'الخميس': 4, 'پێنجشەممە': 4,
                friday: 5, fri: 5, 'الجمعة': 5, 'هەینی': 5,
                saturday: 6, sat: 6, 'السبت': 6, 'شەممە': 6,
                sunday: 0, sun: 0, 'الاحد': 0, 'الأحد': 0, 'یەکشەممە': 0,
            };

            for (const [name, targetDay] of Object.entries(weekdayNames)) {
                if (lower.includes(name.toLowerCase())) {
                    const today = new Date(`${params.baghdadDateString}T12:00:00Z`);
                    for (let i = 1; i <= 7; i++) {
                        const candidate = new Date(today);
                        candidate.setUTCDate(today.getUTCDate() + i);
                        if (candidate.getUTCDay() === targetDay) {
                            preferredDate = candidate.toISOString().slice(0, 10);
                            break;
                        }
                    }
                    if (preferredDate) break;
                }
            }
        }

        // 6. Time slot & time filter
        let preferredTimeSlot: string | null = null;
        let timeFilter: 'morning' | 'afternoon' | 'evening' | 'any' | null = null;

        const timeMatch = text.match(/\b(\d{1,2}:\d{2})\b/);
        if (timeMatch) {
            const rawTime = timeMatch[1];
            preferredTimeSlot = rawTime.length === 4 ? `0${rawTime}` : rawTime;
        }

        if (lower.includes('morning') || lower.includes('صباحا') || lower.includes('بەیانی')) {
            timeFilter = 'morning';
        } else if (
            lower.includes('afternoon') ||
            lower.includes('مساء') ||
            lower.includes('عصرا') ||
            lower.includes('پاشنیوەڕۆ')
        ) {
            timeFilter = 'afternoon';
        } else if (lower.includes('evening') || lower.includes('ليلا') || lower.includes('شەو')) {
            timeFilter = 'evening';
        }

        // 7. Intent resolution
        if (!matchedDepartmentKey && !matchedDoctorId && !matchedDoctorName) {
            return {
                intent: 'clarify',
                clarificationReason: 'general',
                replyLanguage,
            };
        }

        return {
            intent: 'book_appointment',
            departmentKey: matchedDepartmentKey,
            doctorId: matchedDoctorId,
            doctorName: matchedDoctorName,
            preferredDate,
            preferredTimeSlot,
            timeFilter,
            replyLanguage,
        };
    }
}
