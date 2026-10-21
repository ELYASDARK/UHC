import { randomUUID } from 'crypto';
import { loadDoctorDayAvailability } from '../appointments/doctorDayAvailability';
import {
    getBaghdadDateString,
    getDoctorDaySchedule,
    isValidCalendarDate,
    matchesTimeSlot,
} from '../shared/appointmentHelpers';
import { ASSISTANT_CONFIG } from './config';
import { getLocalizedMessage, LocalizedMessageKey } from './localization';
import {
    AssistantOffer,
    AssistantMessageStatus,
    StructuredIntent,
} from './types';

export interface ScheduleMatchResult {
    status: AssistantMessageStatus;
    reasonCode: string;
    message: string;
    offers: AssistantOffer[];
}

export interface DoctorCandidate {
    id: string;
    data: FirebaseFirestore.DocumentData;
}

export interface DepartmentCandidate {
    key: string;
    name: string;
}

interface ResolvedCandidates {
    candidates: DoctorCandidate[];
    clarificationReason?: LocalizedMessageKey;
}

export function resolveDoctorCandidates(
    intent: StructuredIntent,
    departments: DepartmentCandidate[],
    doctors: DoctorCandidate[]
): ResolvedCandidates {
    const activeDeptKeys = new Set(departments.map((d) => d.key));
    const activeDoctors = doctors.filter((d) => d.data.isActive === true && d.data.isAvailable === true && activeDeptKeys.has(d.data.department));

    if (intent.departmentKey && !activeDeptKeys.has(intent.departmentKey)) {
        return { candidates: [], clarificationReason: 'unknown_department' };
    }

    if (intent.doctorId) {
        const doc = activeDoctors.find((d) => d.id === intent.doctorId);
        if (!doc) {
            return { candidates: [], clarificationReason: 'unknown_doctor' };
        }
        if (intent.departmentKey && doc.data.department !== intent.departmentKey) {
            return { candidates: [], clarificationReason: 'doctor_department_mismatch' };
        }
        if (!activeDeptKeys.has(doc.data.department)) {
            return { candidates: [], clarificationReason: 'unknown_department' };
        }
        return { candidates: [doc] };
    }

    if (intent.doctorName) {
        const queryName = intent.doctorName.trim().toLowerCase();
        let matched = activeDoctors.filter((d) =>
            typeof d.data.name === 'string' && d.data.name.toLowerCase().includes(queryName)
        );

        if (intent.departmentKey) {
            matched = matched.filter((d) => d.data.department === intent.departmentKey);
        }

        if (matched.length === 0) {
            return { candidates: [], clarificationReason: 'doctor_not_found' };
        }
        if (matched.length > 1) {
            return { candidates: [], clarificationReason: 'ambiguous_doctor' };
        }
        return { candidates: matched };
    }

    if (intent.departmentKey) {
        const deptDocs = activeDoctors.filter((d) => d.data.department === intent.departmentKey);
        if (deptDocs.length === 0) {
            return { candidates: [], clarificationReason: 'no_doctors_in_department' };
        }
        return { candidates: deptDocs };
    }

    return { candidates: [], clarificationReason: 'clarify_general' };
}

export function validateRequestedDate(
    dateStr: string | null | undefined,
    now: Date
): { valid: boolean; reason?: LocalizedMessageKey } {
    if (!dateStr) {
        return { valid: false, reason: 'missing_date' };
    }
    if (!isValidCalendarDate(dateStr)) {
        return { valid: false, reason: 'invalid_date' };
    }
    const todayBaghdad = getBaghdadDateString(now);
    if (dateStr < todayBaghdad) {
        return { valid: false, reason: 'past_date' };
    }

    const [y, m, d] = dateStr.split('-').map(Number);
    const [ty, tm, td] = todayBaghdad.split('-').map(Number);
    const diffMs = Date.UTC(y, m - 1, d) - Date.UTC(ty, tm - 1, td);
    const diffDays = Math.round(diffMs / (24 * 60 * 60 * 1000));

    if (diffDays > ASSISTANT_CONFIG.MAX_FUTURE_DAYS) {
        return { valid: false, reason: 'date_too_far' };
    }

    return { valid: true };
}

function matchesTimeFilter(slotStartTime: string, timeFilter?: string | null): boolean {
    if (!timeFilter || timeFilter === 'any') return true;
    const norm = slotStartTime.trim();
    if (timeFilter === 'morning') return norm < '12:00';
    if (timeFilter === 'afternoon') return norm >= '12:00' && norm < '17:00';
    if (timeFilter === 'evening') return norm >= '17:00';
    return true;
}

export async function matchScheduleAndGenerateOffers(
    db: FirebaseFirestore.Firestore,
    intent: StructuredIntent,
    departments: DepartmentCandidate[],
    doctors: DoctorCandidate[],
    now = new Date()
): Promise<ScheduleMatchResult> {
    const lang = intent.replyLanguage || 'en';

    if (intent.intent === 'out_of_scope') {
        const reasonKey = intent.outOfScopeReason === 'emergency'
            ? 'out_of_scope_emergency'
            : intent.outOfScopeReason === 'prescription'
                ? 'out_of_scope_prescription'
                : 'out_of_scope_medical';
        return {
            status: 'out_of_scope',
            reasonCode: reasonKey,
            message: getLocalizedMessage(reasonKey, lang),
            offers: [],
        };
    }

    if (intent.intent === 'clarify') {
        const reasonKey = intent.clarificationReason === 'missing_date'
            ? 'missing_date'
            : intent.clarificationReason === 'ambiguous_doctor'
                ? 'ambiguous_doctor'
                : intent.clarificationReason === 'unknown_department'
                    ? 'unknown_department'
                    : intent.clarificationReason === 'unknown_doctor'
                        ? 'unknown_doctor'
                        : intent.clarificationReason === 'no_slots'
                            ? 'no_slots_found'
                            : 'clarify_general';
        return {
            status: 'clarify',
            reasonCode: reasonKey,
            message: getLocalizedMessage(reasonKey, lang),
            offers: [],
        };
    }

    const { candidates, clarificationReason } = resolveDoctorCandidates(intent, departments, doctors);
    if (clarificationReason || candidates.length === 0) {
        const key = clarificationReason || 'clarify_general';
        return {
            status: 'clarify',
            reasonCode: key,
            message: getLocalizedMessage(key, lang),
            offers: [],
        };
    }

    const dateValidation = validateRequestedDate(intent.preferredDate, now);
    if (!dateValidation.valid) {
        const key = dateValidation.reason || 'missing_date';
        return {
            status: 'clarify',
            reasonCode: key,
            message: getLocalizedMessage(key, lang),
            offers: [],
        };
    }

    const targetDate = intent.preferredDate!;

    const deptMap = new Map<string, string>();
    for (const d of departments) {
        deptMap.set(d.key, d.name);
    }

    const offers: AssistantOffer[] = [];
    const expiresAt = new Date(now.getTime() + ASSISTANT_CONFIG.OFFER_EXPIRATION_MINUTES * 60000).toISOString();

    const eligibleDoctors = candidates
        .map((doctor) => ({ doctor, daySlots: getDoctorDaySchedule(doctor.data, targetDate) }))
        .filter((entry) => entry.daySlots.length > 0);

    const BATCH_SIZE = 5;
    for (let i = 0; i < eligibleDoctors.length; i += BATCH_SIZE) {
        if (offers.length >= ASSISTANT_CONFIG.MAX_ACTIVE_OFFERS) break;

        const batch = eligibleDoctors.slice(i, i + BATCH_SIZE);
        const batchResults = await Promise.all(
            batch.map(async ({ doctor }) => {
                const availability = await loadDoctorDayAvailability(db, {
                    doctorId: doctor.id, doctor: doctor.data, dateKey: targetDate, now,
                });
                return { doctor, availability };
            })
        );

        for (const { doctor, availability } of batchResults) {
            if (offers.length >= ASSISTANT_CONFIG.MAX_ACTIVE_OFFERS) break;

            for (const slot of availability) {
                if (offers.length >= ASSISTANT_CONFIG.MAX_ACTIVE_OFFERS) break;
                if (slot.isAvailable === false || !slot.startTime) continue;

                if (!matchesTimeFilter(slot.startTime, intent.timeFilter)) {
                    continue;
                }

                if (intent.preferredTimeSlot && !matchesTimeSlot(slot, intent.preferredTimeSlot)) {
                    continue;
                }

                offers.push({
                    offerId: randomUUID(),
                    doctorId: doctor.id,
                    doctorName: typeof doctor.data.name === 'string' && doctor.data.name.trim()
                        ? doctor.data.name.trim()
                        : 'Doctor',
                    department: doctor.data.department || 'generalMedicine',
                    departmentName: deptMap.get(doctor.data.department) || doctor.data.department,
                    appointmentDate: targetDate,
                    timeSlot: slot.timeSlot,
                    expiresAt,
                    isAvailable: true,
                });
            }
        }
    }

    if (offers.length === 0) {
        return {
            status: 'clarify',
            reasonCode: 'no_slots_found',
            message: getLocalizedMessage('no_slots_found', lang),
            offers: [],
        };
    }

    return {
        status: 'ready',
        reasonCode: 'offers_available',
        message: getLocalizedMessage('ready', lang),
        offers,
    };
}
