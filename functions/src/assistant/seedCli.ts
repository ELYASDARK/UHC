import { seedSyntheticEmulatorData } from './seedEmulatorData';

async function run() {
    console.log('[SEED] Initializing synthetic emulator fixture seeding...');
    try {
        const result = await seedSyntheticEmulatorData();
        console.log('[SEED] Seeding completed successfully!');
        console.log(`[SEED] Departments: ${result.seededDepartments}`);
        console.log(`[SEED] Doctors:     ${result.seededDoctors}`);
        console.log(`[SEED] Patients:    ${result.seededPatients}`);
        console.log('[SEED] Test Account Credentials:');
        console.log('       Email:    synthetic.patient@demo.uhc.edu');
        console.log('       Password: TestPassword123!');
        process.exit(0);
    } catch (err) {
        console.error('[SEED] Error seeding emulator data:', (err as Error).message);
        process.exit(1);
    }
}

run();
