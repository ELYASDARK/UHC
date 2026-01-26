// Run this script once to add Cardiology department to Firebase
// Execute with: flutter run -t lib/scripts/add_cardiology.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  print('Adding Cardiology department to Firebase...');

  final now = DateTime.now();

  await FirebaseFirestore.instance.collection('departments').add({
    'name': 'Cardiology',
    'description': 'Heart and cardiovascular care services',
    'iconName': 'favorite',
    'colorHex': '#E91E63',
    'isActive': true,
    'doctorCount': 0,
    'createdAt': Timestamp.fromDate(now),
    'updatedAt': Timestamp.fromDate(now),
    'isSampleData': true,
  });

  print('Cardiology department added successfully!');

  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Cardiology added!\nYou can close this app.')),
      ),
    ),
  );
}
