import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';

/// Script to update all doctors with new 30-minute time slots
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('Updating doctor time slots...');

  // New weekly schedule with 30-minute slots
  final weeklySchedule = {
    'monday': [
      {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
      {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
      {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
      {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
      {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
      {'startTime': '11:30', 'endTime': '12:00', 'isAvailable': true},
      {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
      {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
      {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
      {'startTime': '15:30', 'endTime': '16:00', 'isAvailable': true},
      {'startTime': '16:00', 'endTime': '16:30', 'isAvailable': true},
    ],
    'tuesday': [
      {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
      {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
      {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
      {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
      {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
      {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
      {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
      {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
    ],
    'wednesday': [
      {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
      {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
      {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
      {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
      {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
      {'startTime': '11:30', 'endTime': '12:00', 'isAvailable': true},
      {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
      {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
      {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
      {'startTime': '15:30', 'endTime': '16:00', 'isAvailable': true},
    ],
    'thursday': [
      {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
      {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
      {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
      {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
      {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
      {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
      {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
      {'startTime': '15:30', 'endTime': '16:00', 'isAvailable': true},
    ],
    'friday': [
      {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
      {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
      {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
      {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
      {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
    ],
  };

  try {
    // Get all doctors
    final doctorsSnapshot = await FirebaseFirestore.instance
        .collection('doctors')
        .get();

    print('Found ${doctorsSnapshot.docs.length} doctors');

    // Update each doctor with the new schedule
    for (final doc in doctorsSnapshot.docs) {
      await doc.reference.update({'weeklySchedule': weeklySchedule});
      print('Updated doctor: ${doc.data()['name']}');
    }

    print('\n✅ All doctors updated with new 30-minute time slots!');
  } catch (e) {
    print('Error: $e');
  }
}
