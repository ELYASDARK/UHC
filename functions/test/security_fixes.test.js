const assert = require('node:assert/strict');
const { test } = require('node:test');
const { resolveTrustedSlotFromSchedule } = require('../lib/shared/appointmentHelpers');
const { validateWeeklySchedule } = require('../lib/shared/doctorSchedule');

test('legacy booking cannot choose a duration; trusted modern duration remains authoritative', () => {
    const legacy = { weeklySchedule: { monday: [{ startTime: '09:00' }] } };
    assert.equal(resolveTrustedSlotFromSchedule(legacy, '2026-11-02', '09:00').canonicalSlot, '09:00');
    for (const forged of ['09:00 - 09:01', '09:00 - 23:59', '9:00-23:59']) {
        assert.throws(() => resolveTrustedSlotFromSchedule(legacy, '2026-11-02', forged), error => error.code === 'invalid-argument');
    }
    const modern = { weeklySchedule: { monday: [{ startTime: '09:00', endTime: '09:30' }] } };
    for (const slot of ['09:00', '09:00 - 09:30']) {
        assert.equal(resolveTrustedSlotFromSchedule(modern, '2026-11-02', slot).canonicalSlot, '09:00 - 09:30');
    }
});

test('schedule validation rejects corrupt containers and slot types without removing legacy support', () => {
    for (const schedule of [0, [], { monday: 0 }, { monday: [0] }, { monday: [{ startTime: 0 }] },
        { monday: [{ startTime: '09:00', endTime: 0 }] }, { monday: [{ startTime: '09:00', isAvailable: 'true' }] },
        { monday: [{ startTime: '09:00', endTime: '08:00' }] }]) {
        assert.throws(() => validateWeeklySchedule(schedule), error => error.code === 'invalid-argument');
    }
    for (const schedule of [{}, { monday: [] }, { monday: [{ startTime: '9:00' }] },
        { monday: [{ startTime: '09:00', endTime: '09:30', isAvailable: false }] }]) {
        assert.doesNotThrow(() => validateWeeklySchedule(schedule));
    }
});
