import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readProjectFile(String path) => File(path).readAsStringSync();

void main() {
  group('security regression guards', () {
    test('web App Check is fully disabled for prelaunch testing', () {
      final mainDart = readProjectFile('lib/main.dart');

      expect(mainDart, isNot(contains('firebase_app_check')));
      expect(mainDart, isNot(contains('FirebaseAppCheck')));
      expect(mainDart, isNot(contains('FIREBASE_APPCHECK_RECAPTCHA_V3_SITE_KEY')));
    });

    test('appointment slot checks use deterministic lock documents', () {
      final functionsSource = readProjectFile('functions/src/index.ts');

      expect(functionsSource, contains('await db.runTransaction'));
      expect(functionsSource, contains("collection('appointment_slot_locks')"));
      expect(functionsSource, contains('lockAppointmentSlot(transaction'));
      expect(functionsSource, isNot(contains('appointmentSlotQuery')));
      expect(functionsSource, isNot(contains('assertNoSlotConflict')));
      expect(functionsSource, isNot(contains('doctorName: data.doctorName')));
      expect(functionsSource, isNot(contains('doctorName: data.doctorName ||')));
    });

    test('legacy medical document uploads still require file validation', () {
      final storageRules = readProjectFile('storage.rules');

      expect(
        storageRules,
        isNot(contains(
          'allow read, write, delete: if activeUser() && request.auth.uid == userId;',
        )),
      );
      expect(storageRules, contains('allow write: if activeUser() &&'));
      expect(storageRules, contains('validMedicalDocument();'));
    });
  });
}
