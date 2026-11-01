import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/data/repositories/doctor_repository.dart';

// The Firestore SDK boundary supplies immutable snapshots in production.
// ignore: subtype_of_sealed_class
class DoctorSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  DoctorSnapshot(this.id, this.fields);
  @override
  final String id;
  final Map<String, dynamic> fields;
  @override
  Map<String, dynamic> data() => fields;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('corrupt doctor fields cannot suppress healthy directory entries', () {
    final valid = <String, dynamic>{
      'name': 'Synthetic doctor',
      'weeklySchedule': {
        'monday': [
          {'startTime': '09:00'},
          {'startTime': '10:00', 'endTime': '10:30'}
        ]
      }
    };
    final corruptions = [
      {'weeklySchedule': 0},
      {
        'weeklySchedule': {'monday': 0}
      },
      {
        'weeklySchedule': {
          'monday': [0]
        }
      },
      {
        'weeklySchedule': {
          'monday': [
            {'startTime': 0}
          ]
        }
      },
      {'name': []},
      {
        'qualifications': [0]
      },
      {'experienceYears': 'bad'},
    ];
    for (final corruption in corruptions) {
      final doctors = DoctorRepository.parseDoctors([
        DoctorSnapshot('healthy-a', valid),
        DoctorSnapshot('corrupt', {...valid, ...corruption}),
        DoctorSnapshot('healthy-b', valid),
      ]).toList();
      expect(doctors.map((doctor) => doctor.id), ['healthy-a', 'healthy-b']);
      expect(doctors.first.weeklySchedule['monday']!.first.isValid, isTrue);
      expect(doctors.last.weeklySchedule['monday']!.last.endTime, '10:30');
    }
  });
}
