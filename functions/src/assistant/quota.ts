import { admin } from '../firebase';
import { ASSISTANT_CONFIG } from './config';
import { getLocalizedMessage } from './localization';
import { AssistantMessageStatus, AssistantReplyLanguage } from './types';

export interface ClassifiedGeminiError {
    status: Extract<AssistantMessageStatus, 'daily_limit' | 'throttled' | 'unavailable'>;
    reasonCode: string;
    message: string;
    resetAt?: string;
}

export function getPacificDateParts(date = new Date()): {
    year: number;
    month: number;
    day: number;
    hour: number;
    minute: number;
} {
    const formatter = new Intl.DateTimeFormat('en-US', {
        timeZone: ASSISTANT_CONFIG.PACIFIC_TIME_ZONE,
        year: 'numeric',
        month: 'numeric',
        day: 'numeric',
        hour: 'numeric',
        minute: 'numeric',
        hourCycle: 'h23',
    });
    const parts = formatter.formatToParts(date);
    const map: Record<string, number> = {};
    for (const p of parts) {
        if (p.type !== 'literal') {
            map[p.type] = Number.parseInt(p.value, 10);
        }
    }
    return {
        year: map.year,
        month: map.month,
        day: map.day,
        hour: map.hour,
        minute: map.minute,
    };
}

export function getPacificDateKey(date = new Date()): string {
    const p = getPacificDateParts(date);
    const m = String(p.month).padStart(2, '0');
    const d = String(p.day).padStart(2, '0');
    return `${p.year}-${m}-${d}`;
}

export function getNextPacificMidnightUtc(now = new Date()): string {
    const p = getPacificDateParts(now);
    const anchorNoon = new Date(Date.UTC(p.year, p.month - 1, p.day, 20, 0, 0));
    const tomorrowNoon = new Date(anchorNoon.getTime() + 24 * 60 * 60 * 1000);
    const tomParts = getPacificDateParts(tomorrowNoon);

    for (let utcHour = 0; utcHour < 24; utcHour++) {
        const candidate = new Date(Date.UTC(tomParts.year, tomParts.month - 1, tomParts.day, utcHour, 0, 0, 0));
        const candParts = getPacificDateParts(candidate);
        if (
            candParts.year === tomParts.year &&
            candParts.month === tomParts.month &&
            candParts.day === tomParts.day &&
            candParts.hour === 0 &&
            candParts.minute === 0
        ) {
            return candidate.toISOString();
        }
    }

    return new Date(Date.UTC(tomParts.year, tomParts.month - 1, tomParts.day, 7, 0, 0, 0)).toISOString();
}

/**
 * Classifies HTTP errors and 429 status from Gemini API.
 * Distinguishes confirmed daily exhaustion (RPD) from rate-limiting/RPM/concurrency (throttled).
 * Inspects structured error details per Google RPC QuotaFailure / ErrorInfo strictly.
 * Never falls back to unstructured error message regexes for daily limit classification.
 */
export function classifyGeminiError(
    statusCode: number,
    responseBody: unknown,
    now = new Date(),
    lang: AssistantReplyLanguage = 'en'
): ClassifiedGeminiError {
    if (statusCode === 429) {
        let isDailyExhausted = false;

        if (responseBody && typeof responseBody === 'object') {
            const errObj = (responseBody as Record<string, unknown>).error as Record<string, unknown> | undefined;
            if (errObj && Array.isArray(errObj.details)) {
                for (const detail of errObj.details) {
                    if (detail && typeof detail === 'object') {
                        const d = detail as Record<string, unknown>;

                        // Check violations in QuotaFailure strictly
                        if (Array.isArray(d.violations)) {
                            for (const v of d.violations) {
                                const vObj = v as Record<string, unknown>;
                                const quotaId = String(vObj?.quotaId || '');
                                const quotaMetric = String(vObj?.quotaMetric || '');
                                const desc = String(vObj?.description || '');
                                const subject = String(vObj?.subject || '');
                                const quotaPattern = /(?:GenerateContentRequestsPerDay|GenerateRequestsPerDay|requests_per_day|Per[-_ ]?Day|RPD|daily)/i;
                                if (
                                    quotaPattern.test(quotaId) ||
                                    quotaPattern.test(quotaMetric) ||
                                    quotaPattern.test(desc) ||
                                    quotaPattern.test(subject)
                                ) {
                                    isDailyExhausted = true;
                                    break;
                                }
                            }
                        }

                        // Check metadata in ErrorInfo strictly
                        if (d.metadata && typeof d.metadata === 'object') {
                            const meta = d.metadata as Record<string, unknown>;
                            const metric = String(meta.quota_metric || meta.quota_id || '');
                            if (/(?:GenerateContentRequestsPerDay|GenerateRequestsPerDay|requests_per_day|Per[-_ ]?Day|RPD|daily)/i.test(metric)) {
                                isDailyExhausted = true;
                                break;
                            }
                        }
                    }
                    if (isDailyExhausted) break;
                }
            }
        }

        if (isDailyExhausted) {
            return {
                status: 'daily_limit',
                reasonCode: 'upstream_daily_limit_reached',
                message: getLocalizedMessage('daily_limit', lang),
                resetAt: getNextPacificMidnightUtc(now),
            };
        }

        // Ambiguous 429 or RPM / per-minute rate limiting -> throttled
        return {
            status: 'throttled',
            reasonCode: 'upstream_throttled',
            message: getLocalizedMessage('throttled_project', lang),
        };
    }

    if (statusCode >= 500) {
        return {
            status: 'unavailable',
            reasonCode: 'upstream_unavailable',
            message: getLocalizedMessage('unavailable', lang),
        };
    }

    return {
        status: 'unavailable',
        reasonCode: 'upstream_error',
        message: getLocalizedMessage('unavailable', lang),
    };
}

export interface AssistantUsageCheckResult {
    allowed: boolean;
    status?: Extract<AssistantMessageStatus, 'daily_limit' | 'throttled'>;
    reasonCode?: string;
    message?: string;
    resetAt?: string;
}

/**
 * Checks and records assistant usage transactionally for admission.
 * Enforces per-user RPM abuse limits even when daily limit is reached to prevent uncounted spam.
 * Enforces project-wide RPD caps and project RPM caps.
 * Includes TTL fields for automatic Firestore data cleanup.
 */
export async function checkAssistantAdmission(
    db: FirebaseFirestore.Firestore,
    patientId: string,
    now = new Date(),
    lang: AssistantReplyLanguage = 'en'
): Promise<AssistantUsageCheckResult> {
    const pacificDateKey = getPacificDateKey(now);
    const minuteKey = Math.floor(now.getTime() / 60000).toString();
    const projectQuotaRef = db.collection('assistant_project_quota').doc(pacificDateKey);
    const userLimitRef = db.collection('assistant_user_limits').doc(`${patientId}_${minuteKey}`);

    const result = await db.runTransaction(async (transaction) => {
        const [projectSnap, userSnap] = await Promise.all([
            transaction.get(projectQuotaRef),
            transaction.get(userLimitRef),
        ]);

        const userCount = userSnap.data()?.count || 0;
        const userTtl = admin.firestore.Timestamp.fromMillis(now.getTime() + 2 * 60 * 60 * 1000);
        const projectTtl = admin.firestore.Timestamp.fromMillis(now.getTime() + 7 * 24 * 60 * 60 * 1000);

        // 1. Enforce per-user RPM abuse limit first
        if (userCount >= ASSISTANT_CONFIG.USER_RPM_CAP) {
            return {
                allowed: false as const,
                status: 'throttled' as const,
                reasonCode: 'user_rate_limited',
                message: getLocalizedMessage('throttled_user', lang),
            };
        }

        const projectData = projectSnap.data();

        // 2. Enforce project daily limit, while still recording user's attempt to prevent unmetered spam
        if (
            projectData?.isDailyExhausted === true ||
            (projectData?.requestCount || 0) >= ASSISTANT_CONFIG.DEFAULT_RPD_CAP
        ) {
            transaction.set(
                userLimitRef,
                {
                    patientId,
                    minuteKey,
                    count: userCount + 1,
                    updatedAt: now,
                    expiresAt: userTtl,
                },
                { merge: true }
            );

            const reasonCode = projectData?.isDailyExhausted === true
                ? 'upstream_daily_limit_reached'
                : 'local_daily_cap_reached';
            return {
                allowed: false as const,
                status: 'daily_limit' as const,
                reasonCode,
                message: getLocalizedMessage('daily_limit', lang),
                resetAt: getNextPacificMidnightUtc(now),
            };
        }

        // 3. Enforce project minute cap, recording user's attempt
        const currentMinuteProjectCount = (projectData?.minuteCounts?.[minuteKey] as number) || 0;
        if (currentMinuteProjectCount >= ASSISTANT_CONFIG.DEFAULT_RPM_CAP) {
            transaction.set(
                userLimitRef,
                {
                    patientId,
                    minuteKey,
                    count: userCount + 1,
                    updatedAt: now,
                    expiresAt: userTtl,
                },
                { merge: true }
            );

            return {
                allowed: false as const,
                status: 'throttled' as const,
                reasonCode: 'project_rate_limited',
                message: getLocalizedMessage('throttled_project', lang),
            };
        }

        // 4. Usage admitted: record both user count and project quota
        transaction.set(
            userLimitRef,
            {
                patientId,
                minuteKey,
                count: userCount + 1,
                updatedAt: now,
                expiresAt: userTtl,
            },
            { merge: true }
        );

        transaction.set(
            projectQuotaRef,
            {
                dateKey: pacificDateKey,
                requestCount: (projectData?.requestCount || 0) + 1,
                minuteCounts: {
                    ...(projectData?.minuteCounts || {}),
                    [minuteKey]: currentMinuteProjectCount + 1,
                },
                updatedAt: now,
                expiresAt: projectTtl,
            },
            { merge: true }
        );

        return { allowed: true as const };
    });

    return result;
}

export const checkAndRecordAssistantUsage = checkAssistantAdmission;

/**
 * Marks project quota as daily-exhausted when confirmed by upstream 429 daily violation.
 */
export async function markDailyQuotaExhausted(
    db: FirebaseFirestore.Firestore,
    now = new Date()
): Promise<void> {
    const pacificDateKey = getPacificDateKey(now);
    const projectQuotaRef = db.collection('assistant_project_quota').doc(pacificDateKey);
    const projectTtl = admin.firestore.Timestamp.fromMillis(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    await projectQuotaRef.set(
        {
            dateKey: pacificDateKey,
            isDailyExhausted: true,
            exhaustedAt: now,
            expiresAt: projectTtl,
        },
        { merge: true }
    );
}
