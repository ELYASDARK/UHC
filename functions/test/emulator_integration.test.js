const assert = require('node:assert/strict');
const { test, before, after } = require('node:test');
const child_process = require('node:child_process');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

// Set demo project and emulator environment
const PROJECT_ID = 'demo-uhc-test';
process.env.GCLOUD_PROJECT = PROJECT_ID;

// Enforce loopback host
const defaultHost = '127.0.0.1';
const defaultPort = 8085;
let host = defaultHost;
let port = defaultPort;
if (process.env.FIRESTORE_EMULATOR_HOST) {
    const [h, p] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
    if (h === 'localhost' || h === '127.0.0.1') {
        host = h;
    }
    if (p) {
        const parsedPort = Number.parseInt(p, 10);
        if (!Number.isNaN(parsedPort) && parsedPort > 0) {
            port = parsedPort;
        }
    }
}
const EMULATOR_HOST = host;
const EMULATOR_PORT = port;
process.env.FIRESTORE_EMULATOR_HOST = `${EMULATOR_HOST}:${EMULATOR_PORT}`;

let emulatorProcess = null;

// Dynamic emulator discovery without hardcoded user paths
function discoverFirestoreEmulatorJar() {
    const envOverride = process.env.FIRESTORE_EMULATOR_JAR || process.env.FIREBASE_FIRESTORE_EMULATOR_JAR;
    if (envOverride && fs.existsSync(envOverride)) {
        return envOverride;
    }

    const searchDirs = [
        path.join(os.homedir(), '.cache', 'firebase', 'emulators'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'firebase', 'emulators') : null,
        process.env.XDG_CACHE_HOME ? path.join(process.env.XDG_CACHE_HOME, 'firebase', 'emulators') : null,
    ].filter(Boolean);

    for (const dir of searchDirs) {
        if (fs.existsSync(dir)) {
            try {
                const files = fs.readdirSync(dir);
                const jars = files
                    .filter((f) => /^cloud-firestore-emulator.*\.jar$/i.test(f))
                    .sort()
                    .reverse();
                if (jars.length > 0) {
                    return path.join(dir, jars[0]);
                }
            } catch {
                // Continue searching other candidate directories
            }
        }
    }
    return null;
}

// Load and assert repo's rules even if an emulator already runs
async function loadAndAssertRules(rulesPath) {
    if (!fs.existsSync(rulesPath)) {
        throw new Error(`firestore.rules not found at ${rulesPath}`);
    }
    const rulesContent = fs.readFileSync(rulesPath, 'utf8');
    assert.ok(rulesContent && rulesContent.length > 0, 'firestore.rules content must not be empty');

    return new Promise((resolve, reject) => {
        const body = JSON.stringify({
            rules: {
                files: [
                    {
                        name: 'firestore.rules',
                        content: rulesContent,
                    },
                ],
            },
        });

        const req = http.request(
            `http://${EMULATOR_HOST}:${EMULATOR_PORT}/emulator/v1/projects/${PROJECT_ID}:securityRules`,
            {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(body),
                },
                timeout: 5000,
            },
            (res) => {
                let data = '';
                res.on('data', (c) => (data += c));
                res.on('end', () => {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        console.log('[TEST] Security rules successfully loaded into emulator.');
                        resolve(true);
                    } else {
                        reject(new Error(`Failed to load security rules into emulator: HTTP ${res.statusCode}: ${data}`));
                    }
                });
            }
        );

        req.on('timeout', () => {
            req.destroy();
            reject(new Error('Timed out loading security rules into emulator.'));
        });
        req.on('error', reject);
        req.write(body);
        req.end();
    });
}

// Helper to spawn emulator if not already running
async function ensureEmulatorRunning() {
    const rulesPath = path.resolve(__dirname, '../../firestore.rules');

    const isRunning = await checkEmulatorHealth();
    if (isRunning) {
        console.log('[TEST] Reusing existing Firestore emulator on ' + process.env.FIRESTORE_EMULATOR_HOST);
        await loadAndAssertRules(rulesPath);
        return;
    }

    const emulatorJar = discoverFirestoreEmulatorJar();
    if (!emulatorJar) {
        throw new Error(
            `Firestore emulator is not running and emulator jar could not be discovered under ${os.homedir()}/.cache/firebase/emulators. Set FIRESTORE_EMULATOR_JAR to override.`
        );
    }

    console.log('[TEST] Spawning Firestore emulator with rules:', rulesPath);
    emulatorProcess = child_process.spawn('java', [
        '-jar', emulatorJar,
        '--host', EMULATOR_HOST,
        '--port', String(EMULATOR_PORT),
        '--project_id', PROJECT_ID,
        '--rules', rulesPath,
    ], { stdio: ['ignore', 'pipe', 'pipe'] });

    emulatorProcess.stdout.on('data', (d) => {
        const str = d.toString();
        if (str.includes('Dev App Server is now running')) {
            console.log('[EMULATOR] Started successfully.');
        }
    });

    emulatorProcess.on('error', (err) => {
        console.error('[EMULATOR] Process error:', err);
    });

    for (let i = 0; i < 30; i++) {
        if (await checkEmulatorHealth()) {
            console.log('[TEST] Connected to Firestore emulator!');
            await loadAndAssertRules(rulesPath);
            return;
        }
        await new Promise((r) => setTimeout(r, 500));
    }
    throw new Error('Failed to start Firestore emulator within 15 seconds.');
}

function checkEmulatorHealth() {
    return new Promise((resolve) => {
        const req = http.get(`http://${EMULATOR_HOST}:${EMULATOR_PORT}/`, (res) => {
            resolve(res.statusCode === 200);
        });
        req.on('error', () => resolve(false));
    });
}

async function clearEmulatorData() {
    return new Promise((resolve, reject) => {
        const req = http.request(
            `http://${EMULATOR_HOST}:${EMULATOR_PORT}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
            { method: 'DELETE' },
            (res) => {
                res.on('data', () => {});
                res.on('end', () => resolve());
            }
        );
        req.on('error', reject);
        req.end();
    });
}

// Global hook
before(async () => {
    await ensureEmulatorRunning();
});

after(async () => {
    // 1. Terminate Firestore database connection
    try {
        if (db && typeof db.terminate === 'function') {
            await db.terminate();
            console.log('[TEST] Firestore db connection terminated.');
        }
    } catch (e) {
        console.warn('[TEST] Warning terminating db:', e.message);
    }

    // 2. Delete all Firebase Admin apps
    try {
        if (admin && admin.apps && admin.apps.length > 0) {
            await Promise.all(
                admin.apps.map((app) => (app ? app.delete() : Promise.resolve()))
            );
            console.log('[TEST] Firebase admin apps deleted.');
        }
    } catch (e) {
        console.warn('[TEST] Warning deleting admin apps:', e.message);
    }

    // 3. Gracefully terminate child process if spawned by this test
    if (emulatorProcess) {
        await new Promise((resolve) => {
            const pid = emulatorProcess.pid;
            let exited = false;
            let timeoutId = null;

            const onExit = () => {
                if (timeoutId) {
                    clearTimeout(timeoutId);
                    timeoutId = null;
                }
                if (!exited) {
                    exited = true;
                    try {
                        if (emulatorProcess.stdout) emulatorProcess.stdout.destroy();
                        if (emulatorProcess.stderr) emulatorProcess.stderr.destroy();
                    } catch {}
                    console.log('[TEST] Firestore emulator terminated.');
                    resolve();
                }
            };

            emulatorProcess.once('exit', onExit);
            emulatorProcess.once('close', onExit);

            try {
                if (process.platform === 'win32' && pid) {
                    child_process.exec(`taskkill /pid ${pid} /T /F`, () => {
                        onExit();
                    });
                } else {
                    emulatorProcess.kill('SIGTERM');
                }
            } catch {
                onExit();
            }

            timeoutId = setTimeout(() => {
                try {
                    if (emulatorProcess && !emulatorProcess.killed) {
                        emulatorProcess.kill('SIGKILL');
                    }
                } catch {}
                onExit();
            }, 3000);
            if (timeoutId && timeoutId.unref) {
                timeoutId.unref();
            }
        });
        emulatorProcess = null;
    }
});

// Import backend modules AFTER emulator host env is set
const { auth, db, admin } = require('../lib/firebase');

// Mock auth.getUser so getCallerUserDoc succeeds for seeded test users without network
auth.getUser = async (uid) => {
    return {
        uid,
        email: `${uid}@uhc.edu`,
        providerData: [{ providerId: 'google.com' }],
    };
};

const {
    createAppointmentCore,
    rescheduleAppointment,
    cancelAppointment,
    updateAppointmentStatus,
} = require('../lib/appointments');
const {
    reserveAssistantTurn,
    commitAssistantTurn,
    clearPatientChat,
    refreshPatientChatHistory,
    getPatientChatDoc,
} = require('../lib/assistant/chatService');
const {
    sendAssistantMessage,
    getAssistantHistory,
    confirmAssistantAppointment,
} = require('../lib/assistant/index');
const {
    canonicalAppointmentSlotLockRef,
} = require('../lib/shared/appointmentHelpers');
const {
    getPacificDateKey,
} = require('../lib/assistant/quota');

// Dynamic upcoming Monday fixture to prevent frozen clock drift and past-date assertion failures
function getUpcomingMonday(fromDate = new Date()) {
    const target = new Date(fromDate);
    for (let i = 1; i <= 8; i++) {
        target.setDate(target.getDate() + 1);
        const dayKey = new Intl.DateTimeFormat('en-CA', {
            timeZone: 'Asia/Baghdad',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
        }).format(target);
        const [y, m, d] = dayKey.split('-').map(Number);
        const utcDate = new Date(Date.UTC(y, m - 1, d));
        if (utcDate.getUTCDay() === 1) { // Monday
            return {
                dateKey: dayKey,
                year: y,
                month: m,
                day: d,
                isoAt: (timeStr) => `${dayKey}T${timeStr}:00Z`,
            };
        }
    }
    throw new Error('Failed to compute upcoming Monday fixture');
}

const upcomingMonday = getUpcomingMonday();

// Helper to seed active department and doctor
async function seedDoctorAndDepartment(doctorId = 'doc_cardio_test', deptKey = 'cardiology') {
    await db.collection('departments').doc(`dept_${deptKey}`).set({
        key: deptKey,
        name: 'Cardiology Care',
        isActive: true,
        createdAt: admin.firestore.Timestamp.now(),
    });

    await db.collection('doctors').doc(doctorId).set({
        name: 'Dr. Heart Specialist',
        department: deptKey,
        isActive: true,
        isAvailable: true,
        weeklySchedule: {
            monday: [
                { startTime: '09:00', endTime: '09:30', isAvailable: true },
                { startTime: '09:30', endTime: '10:00', isAvailable: true },
                { startTime: '10:00', endTime: '10:30', isAvailable: true },
                { startTime: '11:00', endTime: '11:30', isAvailable: true },
            ],
        },
        createdAt: admin.firestore.Timestamp.now(),
    });
}

// Helper to seed a valid patient user account
async function seedPatientUser(uid, role = 'student') {
    await db.collection('users').doc(uid).set({
        role,
        isActive: true,
        fullName: `Test Patient ${uid}`,
        email: `${uid}@student.uhc.edu`,
        createdAt: admin.firestore.Timestamp.now(),
    });
}

function createEmulatorToken(uid) {
    const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({
        sub: uid,
        user_id: uid,
        aud: 'demo-uhc-test',
        iss: 'https://securetoken.google.com/demo-uhc-test',
    })).toString('base64url');
    return `${header}.${payload}.`;
}

// ---------------------------------------------------------------------------
// 1. Competing same-start slot booking (concurrency test)
// ---------------------------------------------------------------------------
test('Scenario 1: Two concurrent same-start booking requests yield exactly ONE appointment and ONE lock in real Firestore', async () => {
    await clearEmulatorData();
    await seedDoctorAndDepartment('doc_c1', 'cardiology');

    const patient1 = 'patient_u1';
    const patient2 = 'patient_u2';

    const req1 = createAppointmentCore(patient1, { fullName: 'User One', role: 'student', isActive: true }, {
        patientId: patient1,
        doctorId: 'doc_c1',
        department: 'cardiology',
        appointmentDate: upcomingMonday.isoAt('09:00'),
        timeSlot: '09:00 - 09:30',
        idempotencyKey: 'idem_u1_same_start',
    });

    const req2 = createAppointmentCore(patient2, { fullName: 'User Two', role: 'student', isActive: true }, {
        patientId: patient2,
        doctorId: 'doc_c1',
        department: 'cardiology',
        appointmentDate: upcomingMonday.isoAt('09:00'),
        timeSlot: '09:00 - 09:30',
        idempotencyKey: 'idem_u2_same_start',
    });

    const results = await Promise.allSettled([req1, req2]);
    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');

    assert.equal(fulfilled.length, 1, 'Exactly one concurrent booking must succeed');
    assert.equal(rejected.length, 1, 'Exactly one concurrent booking must be rejected');
    assert.equal(fulfilled[0].value.success, true);
    assert.ok(rejected[0].reason.message.includes('booked') || rejected[0].reason.code === 'already-exists');

    // Verify real Firestore persistence
    const apptsSnap = await db.collection('appointments').where('doctorId', '==', 'doc_c1').get();
    assert.equal(apptsSnap.docs.length, 1);

    const locksSnap = await db.collection('appointment_slot_locks').get();
    assert.equal(locksSnap.docs.length, 1);
});

// ---------------------------------------------------------------------------
// 2. Competing start-only vs range slot collision
// ---------------------------------------------------------------------------
test('Scenario 2: Competing start-only vs range format collision is serialized and rejected', async () => {
    await clearEmulatorData();
    await seedDoctorAndDepartment('doc_c2', 'cardiology');

    const patient1 = 'patient_start_only';
    const patient2 = 'patient_range';

    const req1 = createAppointmentCore(patient1, { fullName: 'Start Only', role: 'student', isActive: true }, {
        patientId: patient1,
        doctorId: 'doc_c2',
        department: 'cardiology',
        appointmentDate: upcomingMonday.isoAt('09:00'),
        timeSlot: '09:00', // legacy start-only string
        idempotencyKey: 'idem_start_only',
    });

    const req2 = createAppointmentCore(patient2, { fullName: 'Range User', role: 'student', isActive: true }, {
        patientId: patient2,
        doctorId: 'doc_c2',
        department: 'cardiology',
        appointmentDate: upcomingMonday.isoAt('09:00'),
        timeSlot: '09:00 - 09:30', // range format
        idempotencyKey: 'idem_range',
    });

    const results = await Promise.allSettled([req1, req2]);
    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');

    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
});

// ---------------------------------------------------------------------------
// 3. Overlapping different starts serialized by day coordination
// ---------------------------------------------------------------------------
test('Scenario 3: Overlapping different starts (09:00-10:00 vs 09:30-10:00) serialized by day coordination', async () => {
    await clearEmulatorData();

    // Doctor with overlapping multi-duration schedule slots
    await db.collection('departments').doc('dept_special').set({ key: 'special', name: 'Specialty', isActive: true });
    await db.collection('doctors').doc('doc_overlap').set({
        name: 'Dr. Overlap',
        department: 'special',
        isActive: true,
        isAvailable: true,
        weeklySchedule: {
            monday: [
                { startTime: '09:00', endTime: '10:00', isAvailable: true },
                { startTime: '09:30', endTime: '10:00', isAvailable: true },
            ],
        },
    });

    const p1 = createAppointmentCore('p1', { fullName: 'P1', role: 'student', isActive: true }, {
        patientId: 'p1',
        doctorId: 'doc_overlap',
        department: 'special',
        appointmentDate: upcomingMonday.isoAt('09:00'),
        timeSlot: '09:00 - 10:00',
        idempotencyKey: 'idem_p1_overlap',
    });

    const p2 = createAppointmentCore('p2', { fullName: 'P2', role: 'student', isActive: true }, {
        patientId: 'p2',
        doctorId: 'doc_overlap',
        department: 'special',
        appointmentDate: upcomingMonday.isoAt('09:30'),
        timeSlot: '09:30 - 10:00',
        idempotencyKey: 'idem_p2_overlap',
    });

    const results = await Promise.allSettled([p1, p2]);
    const fulfilled = results.filter((r) => r.status === 'fulfilled');
    const rejected = results.filter((r) => r.status === 'rejected');

    assert.equal(fulfilled.length, 1, 'Exactly one of overlapping bookings must succeed');
    assert.equal(rejected.length, 1, 'The other overlapping booking must be rejected');
    assert.ok(rejected[0].reason.message.includes('booked') || rejected[0].reason.code === 'already-exists');
});

// ---------------------------------------------------------------------------
// 4. Reschedule collision prevention & unowned lock safety
// ---------------------------------------------------------------------------
test('Scenario 4: Reschedule cannot collide with existing slot and releases only caller-owned lock', async () => {
    await clearEmulatorData();
    await seedPatientUser('patient_a');
    await seedPatientUser('patient_b');
    await seedDoctorAndDepartment('doc_resched', 'cardiology');

    // Create Appt A at 09:00 - 09:30
    const apptA = await createAppointmentCore('patient_a', { fullName: 'Patient A', role: 'student', isActive: true }, {
        patientId: 'patient_a',
        doctorId: 'doc_resched',
        department: 'cardiology',
        appointmentDate: upcomingMonday.isoAt('09:00'),
        timeSlot: '09:00 - 09:30',
        idempotencyKey: 'idem_a_resched',
    });

    // Create Appt B at 10:00 - 10:30
    const apptB = await createAppointmentCore('patient_b', { fullName: 'Patient B', role: 'student', isActive: true }, {
        patientId: 'patient_b',
        doctorId: 'doc_resched',
        department: 'cardiology',
        appointmentDate: upcomingMonday.isoAt('10:00'),
        timeSlot: '10:00 - 10:30',
        idempotencyKey: 'idem_b_resched',
    });

    // Patient A tries to reschedule into occupied slot 10:00 -> MUST FAIL
    await assert.rejects(
        rescheduleAppointment.run({
            auth: { uid: 'patient_a' },
            data: {
                appointmentId: apptA.appointmentId,
                appointmentDate: upcomingMonday.isoAt('10:00'),
                timeSlot: '10:00 - 10:30',
            },
        }),
        (err) => err.code === 'already-exists'
    );

    // Patient A reschedules to open slot 11:00 - 11:30 -> MUST SUCCEED
    const reschedResult = await rescheduleAppointment.run({
        auth: { uid: 'patient_a' },
        data: {
            appointmentId: apptA.appointmentId,
            appointmentDate: upcomingMonday.isoAt('11:00'),
            timeSlot: '11:00 - 11:30',
        },
    });
    assert.equal(reschedResult.success, true);

    // Verify lock state: 09:00 lock deleted; 11:00 lock created for A; 10:00 lock for B STILL EXISTS!
    const locks = await db.collection('appointment_slot_locks').get();
    const lockMap = new Map(locks.docs.map((d) => [d.id, d.data()]));

    const lockAOld = canonicalAppointmentSlotLockRef('doc_resched', new Date(upcomingMonday.isoAt('09:00')), '09:00', db);
    const lockB = canonicalAppointmentSlotLockRef('doc_resched', new Date(upcomingMonday.isoAt('10:00')), '10:00', db);
    const lockANew = canonicalAppointmentSlotLockRef('doc_resched', new Date(upcomingMonday.isoAt('11:00')), '11:00', db);

    assert.equal(lockMap.has(lockAOld.id), false, 'Old lock 09:00 must be released');
    assert.equal(lockMap.has(lockANew.id), true, 'New lock 11:00 must be acquired');
    assert.equal(lockMap.get(lockANew.id).appointmentId, apptA.appointmentId);
    assert.equal(lockMap.has(lockB.id), true, 'Appt B lock at 10:00 must NOT be released');
    assert.equal(lockMap.get(lockB.id).appointmentId, apptB.appointmentId);
});

// ---------------------------------------------------------------------------
// 5. Legacy no-lock start-only appointment blocks actual overlapping schedule
// ---------------------------------------------------------------------------
test('Scenario 5: Legacy no-lock start-only appointment blocks actual overlapping schedule using doctor duration', async () => {
    await clearEmulatorData();

    await db.collection('departments').doc('dept_gm').set({ key: 'generalMedicine', name: 'General', isActive: true });
    await db.collection('doctors').doc('doc_legacy').set({
        name: 'Dr. Legacy Duration',
        department: 'generalMedicine',
        isActive: true,
        isAvailable: true,
        weeklySchedule: {
            monday: [
                { startTime: '09:00', endTime: '10:00', isAvailable: true },
                { startTime: '09:30', endTime: '10:00', isAvailable: true },
            ],
        },
    });

    // Seed a legacy appointment with start-only '09:00' and NO lock document
    const [y, m, d] = [upcomingMonday.year, upcomingMonday.month, upcomingMonday.day];
    const apptDateUtc = Date.UTC(y, m - 1, d, 6, 0, 0); // 09:00 Baghdad = 06:00 UTC
    await db.collection('appointments').doc('legacy_appt_1').set({
        patientId: 'patient_legacy_prior',
        doctorId: 'doc_legacy',
        department: 'generalMedicine',
        appointmentDate: admin.firestore.Timestamp.fromMillis(apptDateUtc),
        timeSlot: '09:00', // legacy start-only format
        status: 'confirmed',
        createdAt: admin.firestore.Timestamp.now(),
    });

    // Ensure slot locks collection is empty
    const initialLocks = await db.collection('appointment_slot_locks').get();
    assert.equal(initialLocks.docs.length, 0);

    // Proposed new booking at 09:30 - 10:00 must detect overlap with 09:00-10:00 schedule duration
    await assert.rejects(
        createAppointmentCore('patient_new', { fullName: 'New Patient', role: 'student', isActive: true }, {
            patientId: 'patient_new',
            doctorId: 'doc_legacy',
            department: 'generalMedicine',
            appointmentDate: upcomingMonday.isoAt('09:30'),
            timeSlot: '09:30 - 10:00',
            idempotencyKey: 'idem_legacy_block_check',
        }),
        (err) => err.code === 'already-exists'
    );
});

// ---------------------------------------------------------------------------
// 6. Lost receipt retry returns same booking after offer consumption/expiry
// ---------------------------------------------------------------------------
test('Scenario 6: Lost receipt retry returns original booking after offer consumption in chat document', async () => {
    await clearEmulatorData();
    await seedDoctorAndDepartment('doc_receipt', 'cardiology');

    const patientId = 'patient_receipt_retry';
    await seedPatientUser(patientId);

    const offerId = 'offer_test_receipt_123';

    // Seed chat doc with offer
    await db.collection('assistant_chats').doc(patientId).set({
        patientId,
        generationId: 'gen_receipt_1',
        revision: 2,
        messages: [{ id: 'msg_1', sender: 'assistant', text: 'Slot offered', offerIds: [offerId], status: 'ready', createdAt: new Date().toISOString() }],
        offers: [{
            offerId,
            doctorId: 'doc_receipt',
            doctorName: 'Dr. Heart Specialist',
            department: 'cardiology',
            appointmentDate: upcomingMonday.dateKey,
            timeSlot: '09:00 - 09:30',
            expiresAt: new Date(Date.now() + 600000).toISOString(),
            isAvailable: true,
        }],
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 7 * 86400000),
    });

    // 1. Confirm appointment
    const firstConfirm = await confirmAssistantAppointment.run({
        auth: { uid: patientId },
        data: { offerId, confirmed: true, notes: 'First confirmation' },
    });
    assert.equal(firstConfirm.success, true);
    assert.ok(firstConfirm.appointmentId);
    assert.ok(firstConfirm.bookingReference);

    // Verify chat doc has consumed the offer (offer removed from offers array)
    const chatSnap = await db.collection('assistant_chats').doc(patientId).get();
    const offersAfter = chatSnap.data()?.offers || [];
    assert.equal(offersAfter.some((o) => o.offerId === offerId), false, 'Offer must be consumed from active offers');

    // 2. Retry with the same offerId (simulating client network drop / retry)
    const retryConfirm = await confirmAssistantAppointment.run({
        auth: { uid: patientId },
        data: { offerId, confirmed: true, notes: 'First confirmation' },
    });
    assert.equal(retryConfirm.success, true);
    assert.equal(retryConfirm.isExisting, true);
    assert.equal(retryConfirm.appointmentId, firstConfirm.appointmentId);
    assert.equal(retryConfirm.bookingReference, firstConfirm.bookingReference);

    // Exactly one appointment doc in Firestore
    const appts = await db.collection('appointments').where('patientId', '==', patientId).get();
    assert.equal(appts.docs.length, 1);
});

// ---------------------------------------------------------------------------
// 7. Confirmed omitted or false cannot book
// ---------------------------------------------------------------------------
test('Scenario 7: confirmAssistantAppointment rejects request where confirmed is omitted or false', async () => {
    await clearEmulatorData();
    await seedPatientUser('p_unconfirmed');

    // 1. confirmed is false
    await assert.rejects(
        confirmAssistantAppointment.run({
            auth: { uid: 'p_unconfirmed' },
            data: { offerId: 'any_offer', confirmed: false },
        }),
        (err) => err.code === 'invalid-argument' && err.message.includes('confirmed')
    );

    // 2. confirmed is omitted
    await assert.rejects(
        confirmAssistantAppointment.run({
            auth: { uid: 'p_unconfirmed' },
            data: { offerId: 'any_offer' },
        }),
        (err) => err.code === 'invalid-argument' && err.message.includes('confirmed')
    );
});

// ---------------------------------------------------------------------------
// 8. Chat clear then late model commit rejected
// ---------------------------------------------------------------------------
test('Scenario 8: Chat clear then late model commit is rejected and does not resurrect messages', async () => {
    await clearEmulatorData();
    const patientId = 'p_clear_race';

    // 1. Reserve turn
    const reservation = await reserveAssistantTurn(db, {
        patientId,
        userMessage: 'Schedule checkup',
        clientRequestId: 'req_clear_test',
    });
    assert.equal(reservation.deduplicated, false);
    assert.ok(reservation.turnId);

    // 2. User clears chat while model is supposedly running
    const clearRes = await clearPatientChat(db, patientId);
    assert.ok(clearRes.revision > reservation.reservedRevision);

    // 3. Model finishes and attempts commit with old turn credentials
    const commitRes = await commitAssistantTurn(db, {
        patientId,
        generationId: reservation.generationId,
        reservedRevision: reservation.reservedRevision,
        turnId: reservation.turnId,
        assistantMessage: 'Here are your slots',
        status: 'ready',
        replyLanguage: 'en',
        offers: [],
    });

    assert.equal(commitRes.committed, false, 'Late commit must be rejected after chat clear');

    // Chat document remains empty
    const chatDoc = await getPatientChatDoc(db, patientId);
    assert.deepEqual(chatDoc.doc.messages, []);
    assert.deepEqual(chatDoc.doc.offers, []);
});

// ---------------------------------------------------------------------------
// 9. Reserve A complete then B in-flight retry cannot return A; competing in-flight turn rejected
// ---------------------------------------------------------------------------
test('Scenario 9: In-flight turn reservation clears previous result; duplicate in-flight throws already-exists, competing throws failed-precondition', async () => {
    await clearEmulatorData();
    const patientId = 'p_inflight_lease';

    // 1. Reserve and complete turn A
    const turnA = await reserveAssistantTurn(db, {
        patientId,
        userMessage: 'Turn A message',
        clientRequestId: 'req_A',
    });
    await commitAssistantTurn(db, {
        patientId,
        generationId: turnA.generationId,
        reservedRevision: turnA.reservedRevision,
        turnId: turnA.turnId,
        assistantMessage: 'Turn A response',
        status: 'ready',
        replyLanguage: 'en',
        offers: [{
            offerId: 'offer_A',
            doctorId: 'doc_1',
            doctorName: 'Dr. One',
            department: 'dept',
            appointmentDate: upcomingMonday.dateKey,
            timeSlot: '09:00',
            expiresAt: new Date(Date.now() + 60000).toISOString(),
            isAvailable: true,
        }],
    });

    // 2. Reserve turn B with clientRequestId B -> previous lastResult is cleared!
    const turnB = await reserveAssistantTurn(db, {
        patientId,
        userMessage: 'Turn B message',
        clientRequestId: 'req_B',
    });
    assert.equal(turnB.deduplicated, false);

    // Chat document in-flight state verification
    const chatSnap = await db.collection('assistant_chats').doc(patientId).get();
    assert.equal(chatSnap.data()?.inFlightTurnId, turnB.turnId);
    assert.equal(chatSnap.data()?.lastResult, null, 'Previous completed result must be cleared during in-flight reservation');

    // 3. Concurrent retry with same clientRequestId req_B throws already-exists
    await assert.rejects(
        reserveAssistantTurn(db, {
            patientId,
            userMessage: 'Turn B message',
            clientRequestId: 'req_B',
        }),
        (err) => err.code === 'already-exists'
    );

    // 4. Competing send with different clientRequestId req_C throws failed-precondition
    await assert.rejects(
        reserveAssistantTurn(db, {
            patientId,
            userMessage: 'Turn C message',
            clientRequestId: 'req_C',
        }),
        (err) => err.code === 'failed-precondition'
    );
});

// ---------------------------------------------------------------------------
// 10. Refresh and clear race CAS integrity
// ---------------------------------------------------------------------------
test('Scenario 10: Concurrent chat clear during refresh CAS prevents offer resurrection', async () => {
    await clearEmulatorData();
    await seedDoctorAndDepartment('doc_cas', 'cardiology');

    const patientId = 'patient_cas_race';
    const expiredOffer = {
        offerId: 'offer_cas_expired',
        doctorId: 'doc_cas',
        doctorName: 'Dr. Heart Specialist',
        department: 'cardiology',
        appointmentDate: upcomingMonday.dateKey,
        timeSlot: '09:00 - 09:30',
        expiresAt: new Date(Date.now() - 60000).toISOString(), // expired
        isAvailable: true,
    };

    await db.collection('assistant_chats').doc(patientId).set({
        patientId,
        generationId: 'gen_initial',
        revision: 2,
        messages: [{ id: 'm1', sender: 'assistant', text: 'Expired', status: 'ready', createdAt: new Date().toISOString() }],
        offers: [expiredOffer],
        searchPreferences: {
            departmentKey: 'cardiology',
            doctorId: 'doc_cas',
            preferredDate: upcomingMonday.dateKey,
        },
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 7 * 86400000),
    });

    const departments = [{ key: 'cardiology', name: 'Cardiology' }];
    const doctors = [{ id: 'doc_cas', data: (await db.collection('doctors').doc('doc_cas').get()).data() }];

    // Clear chat concurrently
    await clearPatientChat(db, patientId);

    // Now call refreshPatientChatHistory: must return empty state without resurrecting offers
    const refreshed = await refreshPatientChatHistory(db, patientId, departments, doctors, new Date());
    assert.deepEqual(refreshed.messages, []);
    assert.deepEqual(refreshed.offers, []);
});

// ---------------------------------------------------------------------------
// 11. Gate disabled returns disabled without DB write & daily quota recovery on history reload
// ---------------------------------------------------------------------------
test('Scenario 11: Gate disabled returns disabled without DB writes; daily quota exhaustion reflects on history reload', async () => {
    await clearEmulatorData();
    const patientId = 'patient_gate_test';
    await seedPatientUser(patientId);

    // 1. Gate disabled: verify 0 DB writes
    delete process.env.AI_ASSISTANT_ENABLED;
    delete process.env.AI_PRIVACY_RELEASE_GATE_ACCEPTED;

    const disabledRes = await sendAssistantMessage.run({
        auth: { uid: patientId },
        data: { message: 'Need doctor appointment', locale: 'en' },
    });
    assert.equal(disabledRes.success, true);
    assert.equal(disabledRes.status, 'disabled');
    assert.equal(disabledRes.reasonCode, 'assistant_disabled');

    // No documents created in assistant_chats
    const chatDoc = await db.collection('assistant_chats').doc(patientId).get();
    assert.equal(chatDoc.exists, false);

    // 2. Project daily quota exhaustion recovery on history reload
    const now = new Date();
    const pacificDateKey = getPacificDateKey(now);

    await db.collection('assistant_project_quota').doc(pacificDateKey).set({
        pacificDateKey,
        isDailyExhausted: true,
        requestCount: 50,
        updatedAt: admin.firestore.Timestamp.now(),
    });

    const historyRes = await getAssistantHistory.run({
        auth: { uid: patientId },
        data: {},
    });
    assert.equal(historyRes.success, true);
    assert.equal(historyRes.status, 'daily_limit');
    assert.equal(historyRes.reasonCode, 'upstream_daily_limit_reached');
    assert.ok(historyRes.resetAt, 'resetAt must be returned on daily limit status');
});

// ---------------------------------------------------------------------------
// 12. Firestore Security Rules deny cross-user and direct client writes
// ---------------------------------------------------------------------------
test('Scenario 12: Firestore security rules deny direct client reads/writes on internal collections and cross-user chats', async () => {
    const rawRestRequest = (method, path, body = null, userUid = null) => {
        return new Promise((resolve) => {
            const headers = { 'Content-Type': 'application/json' };
            if (userUid) {
                headers['Authorization'] = `Bearer ${createEmulatorToken(userUid)}`;
            }

            const req = http.request(
                `http://${EMULATOR_HOST}:${EMULATOR_PORT}/v1/projects/demo-uhc-test/databases/(default)/documents${path}`,
                { method, headers },
                (res) => {
                    let data = '';
                    res.on('data', (c) => (data += c));
                    res.on('end', () => resolve({ statusCode: res.statusCode, body: data }));
                }
            );
            req.on('error', (err) => resolve({ statusCode: 500, error: err }));
            if (body) req.write(JSON.stringify(body));
            req.end();
        });
    };

    // 1. Direct write to appointment_day_coordination: MUST BE DENIED (403)
    const dayCoordRes = await rawRestRequest('POST', '/appointment_day_coordination', {
        fields: { doctorId: { stringValue: 'doc1' } },
    }, 'patient_direct');
    assert.equal(dayCoordRes.statusCode, 403, 'Client write to appointment_day_coordination must be denied by rules');

    // 2. Direct write to doctor_availability_usage: MUST BE DENIED (403)
    const availUsageRes = await rawRestRequest('POST', '/doctor_availability_usage', {
        fields: { doctorId: { stringValue: 'doc1' } },
    }, 'patient_direct');
    assert.equal(availUsageRes.statusCode, 403, 'Client write to doctor_availability_usage must be denied by rules');

    // 3. Direct write to assistant_project_quota: MUST BE DENIED (403)
    const quotaRes = await rawRestRequest('PATCH', `/assistant_project_quota/${upcomingMonday.dateKey}`, {
        fields: { requestCount: { integerValue: '999' } },
    }, 'patient_direct');
    assert.equal(quotaRes.statusCode, 403, 'Client write to assistant_project_quota must be denied by rules');

    // 4. Direct read/write to assistant_chats: MUST BE DENIED (403) even for owner because assistant is server-only
    await db.collection('assistant_chats').doc('patient_user_b').set({
        patientId: 'patient_user_b',
        generationId: 'gen_b',
        revision: 1,
        messages: [],
        offers: [],
        createdAt: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000),
    });

    const directChatRead = await rawRestRequest('GET', '/assistant_chats/patient_user_b', null, 'patient_user_b');
    assert.equal(directChatRead.statusCode, 403, 'Direct client read of assistant_chats must be denied by rules even for owner');

    const directChatWrite = await rawRestRequest('POST', '/assistant_chats', { fields: {} }, 'patient_user_b');
    assert.equal(directChatWrite.statusCode, 403, 'Direct client write of assistant_chats must be denied by rules');

    // 5. Cross-user read on users collection is denied (403), while self profile get is allowed (200)
    await seedPatientUser('patient_user_b');
    const crossProfileRead = await rawRestRequest('GET', '/users/patient_user_b', null, 'patient_user_a');
    assert.equal(crossProfileRead.statusCode, 403, 'Cross-user profile read must be denied by rules');

    const ownProfileRead = await rawRestRequest('GET', '/users/patient_user_b', null, 'patient_user_b');
    assert.equal(ownProfileRead.statusCode, 200, 'User reading their own profile doc must be allowed by rules');
});

// ---------------------------------------------------------------------------
// 13. Reactivation to pending rejected over different-start overlap and preserves locks
// ---------------------------------------------------------------------------
test('Scenario 13: updateAppointmentStatus rejects reactivating cancelled appointment to pending over overlapping active booking and preserves locks', async () => {
    await clearEmulatorData();

    // Doctor with overlapping multi-duration schedule slots on Monday:
    // 09:00 - 10:00 (1 hour)
    // 09:30 - 10:00 (30 mins)
    await db.collection('departments').doc('dept_ortho').set({
        key: 'orthopedics',
        name: 'Orthopedics',
        isActive: true,
        createdAt: admin.firestore.Timestamp.now(),
    });

    const doctorId = 'doc_reactivate_overlap';
    await db.collection('doctors').doc(doctorId).set({
        name: 'Dr. Bones',
        department: 'orthopedics',
        userId: 'doctor_user_uid',
        isActive: true,
        isAvailable: true,
        weeklySchedule: {
            monday: [
                { startTime: '09:00', endTime: '10:00', isAvailable: true },
                { startTime: '09:30', endTime: '10:00', isAvailable: true },
            ],
        },
        createdAt: admin.firestore.Timestamp.now(),
    });

    await seedPatientUser('patient_first');
    await seedPatientUser('patient_second');
    await seedPatientUser('doctor_user_uid', 'doctor');

    // 1. Patient First books 09:00 - 10:00
    const appt1 = await createAppointmentCore('patient_first', { fullName: 'Patient First', role: 'student', isActive: true }, {
        patientId: 'patient_first',
        doctorId,
        department: 'orthopedics',
        appointmentDate: upcomingMonday.isoAt('09:00'),
        timeSlot: '09:00 - 10:00',
        idempotencyKey: 'idem_first_reactivate_test',
    });
    assert.equal(appt1.success, true);

    // Cancel Appt 1 (simulating cancellation freeing the slot)
    const cancelRes = await cancelAppointment.run({
        auth: { uid: 'patient_first' },
        data: {
            appointmentId: appt1.appointmentId,
            reason: 'Scheduling conflict',
        },
    });
    assert.equal(cancelRes.success, true);

    const appt1SnapAfterCancel = await db.collection('appointments').doc(appt1.appointmentId).get();
    assert.equal(appt1SnapAfterCancel.data()?.status, 'cancelled');

    // 2. Patient Second books overlapping 09:30 - 10:00
    const appt2 = await createAppointmentCore('patient_second', { fullName: 'Patient Second', role: 'student', isActive: true }, {
        patientId: 'patient_second',
        doctorId,
        department: 'orthopedics',
        appointmentDate: upcomingMonday.isoAt('09:30'),
        timeSlot: '09:30 - 10:00',
        idempotencyKey: 'idem_second_overlap_active',
    });
    assert.equal(appt2.success, true);

    // Verify Appt 2 owns the 09:30 lock
    const lockRef2 = canonicalAppointmentSlotLockRef(
        doctorId,
        new Date(upcomingMonday.isoAt('09:30')),
        '09:30',
        db
    );
    const lock2Before = await db.collection('appointment_slot_locks').doc(lockRef2.id).get();
    assert.equal(lock2Before.exists, true);
    assert.equal(lock2Before.data()?.appointmentId, appt2.appointmentId);

    // Verify 09:00 lock does NOT exist currently
    const lockRef1 = canonicalAppointmentSlotLockRef(
        doctorId,
        new Date(upcomingMonday.isoAt('09:00')),
        '09:00',
        db
    );
    const lock1Before = await db.collection('appointment_slot_locks').doc(lockRef1.id).get();
    assert.equal(lock1Before.exists, false);

    // 3. Attempt to reactivate Appt 1 back to 'pending' via updateAppointmentStatus
    await assert.rejects(
        updateAppointmentStatus.run({
            auth: { uid: 'doctor_user_uid' },
            data: {
                appointmentId: appt1.appointmentId,
                status: 'pending',
            },
        }),
        (err) => err.code === 'failed-precondition' && err.message.includes('pending')
    );

    // 4. Invariants after failed reactivation:
    // - Appt 1 MUST remain cancelled
    const appt1SnapFinal = await db.collection('appointments').doc(appt1.appointmentId).get();
    assert.equal(appt1SnapFinal.data()?.status, 'cancelled');

    // - Appt 2 MUST remain pending
    const appt2SnapFinal = await db.collection('appointments').doc(appt2.appointmentId).get();
    assert.equal(appt2SnapFinal.data()?.status, 'pending');

    // - Lock for 09:30 MUST still exist and belong to Appt 2 (preserve owned locks)
    const lock2After = await db.collection('appointment_slot_locks').doc(lockRef2.id).get();
    assert.equal(lock2After.exists, true);
    assert.equal(lock2After.data()?.appointmentId, appt2.appointmentId);

    // - Lock for 09:00 MUST still NOT exist (preserve unowned locks)
    const lock1After = await db.collection('appointment_slot_locks').doc(lockRef1.id).get();
    assert.equal(lock1After.exists, false);
});
