// Run this script once to add sample departments to Firebase
// Execute with: flutter run -t lib/scripts/add_departments.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../data/repositories/department_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('Adding sample departments to Firebase...');

  final repo = DepartmentRepository();
  await repo.addSampleDepartments();

  print('Done! You can now close this.');

  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Departments added successfully!\nYou can close this app.',
          ),
        ),
      ),
    ),
  );
}
