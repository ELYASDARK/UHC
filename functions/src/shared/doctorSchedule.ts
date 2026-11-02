import * as functions from 'firebase-functions';
import { isValidTimeFormat, normalizeTimeComponent, timeToMinutes, WEEKDAY_NAMES } from './appointmentHelpers';

export function validateWeeklySchedule(value: unknown): void {
    const invalid = () => { throw new functions.https.HttpsError('invalid-argument', 'Invalid weekly schedule.'); };
    if (!value || typeof value !== 'object' || Array.isArray(value)) return invalid();
    for (const [day, slots] of Object.entries(value)) {
        if (!(WEEKDAY_NAMES as readonly string[]).includes(day) || !Array.isArray(slots)) return invalid();
        for (const slot of slots) {
            if (!slot || typeof slot !== 'object' || Array.isArray(slot) || typeof slot.startTime !== 'string' ||
                (slot.isAvailable !== undefined && typeof slot.isAvailable !== 'boolean')) return invalid();
            const start = normalizeTimeComponent(slot.startTime);
            if (!isValidTimeFormat(start)) return invalid();
            if (slot.endTime !== undefined && slot.endTime !== null && slot.endTime !== '') {
                if (typeof slot.endTime !== 'string') return invalid();
                const end = normalizeTimeComponent(slot.endTime);
                if (!isValidTimeFormat(end) || timeToMinutes(end) <= timeToMinutes(start)) return invalid();
            }
        }
    }
}
