import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/doctor_model.dart';

/// Repository for seeding sample data into Firebase
class SampleDataRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sample doctors data
  List<Map<String, dynamic>> get _sampleDoctors => [
    // General Medicine
    {
      'name': 'Sarah Johnson',
      'email': 'sarah.johnson@uhc.edu',
      'department': Department.generalMedicine.name,
      'specialization': 'Internal Medicine',
      'bio':
          'Dr. Sarah Johnson specializes in internal medicine with over 10 years of experience in treating chronic conditions.',
      'experienceYears': 10,
      'rating': 4.8,
      'totalReviews': 124,
      'totalPatients': 450,
      'qualifications': ['MD', 'Board Certified Internal Medicine'],
      'languages': ['English', 'Spanish'],
      'isAvailable': true,
    },
    {
      'name': 'Michael Chen',
      'email': 'michael.chen@uhc.edu',
      'department': Department.generalMedicine.name,
      'specialization': 'Family Medicine',
      'bio':
          'Dr. Michael Chen provides comprehensive family medicine care for patients of all ages.',
      'experienceYears': 8,
      'rating': 4.7,
      'totalReviews': 98,
      'totalPatients': 380,
      'qualifications': ['MD', 'Family Medicine Specialist'],
      'languages': ['English', 'Mandarin'],
      'isAvailable': true,
    },
    // Dentistry
    {
      'name': 'Emily Davis',
      'email': 'emily.davis@uhc.edu',
      'department': Department.dentistry.name,
      'specialization': 'General Dentistry',
      'bio':
          'Dr. Emily Davis offers comprehensive dental care including preventive, restorative, and cosmetic dentistry.',
      'experienceYears': 7,
      'rating': 4.9,
      'totalReviews': 156,
      'totalPatients': 520,
      'qualifications': ['DDS', 'Certified in Invisalign'],
      'languages': ['English'],
      'isAvailable': true,
    },
    {
      'name': 'James Wilson',
      'email': 'james.wilson@uhc.edu',
      'department': Department.dentistry.name,
      'specialization': 'Orthodontics',
      'bio':
          'Dr. James Wilson is an orthodontist specializing in braces and teeth alignment for students.',
      'experienceYears': 12,
      'rating': 4.6,
      'totalReviews': 87,
      'totalPatients': 290,
      'qualifications': ['DDS', 'MS Orthodontics'],
      'languages': ['English', 'French'],
      'isAvailable': true,
    },
    // Psychology
    {
      'name': 'Lisa Brown',
      'email': 'lisa.brown@uhc.edu',
      'department': Department.psychology.name,
      'specialization': 'Clinical Psychology',
      'bio':
          'Dr. Lisa Brown provides counseling for anxiety, depression, and stress management for university students.',
      'experienceYears': 15,
      'rating': 4.9,
      'totalReviews': 203,
      'totalPatients': 680,
      'qualifications': ['PhD Clinical Psychology', 'Licensed Psychologist'],
      'languages': ['English'],
      'isAvailable': true,
    },
    {
      'name': 'Robert Taylor',
      'email': 'robert.taylor@uhc.edu',
      'department': Department.psychology.name,
      'specialization': 'Counseling',
      'bio':
          'Dr. Robert Taylor specializes in academic stress, relationships, and personal development counseling.',
      'experienceYears': 9,
      'rating': 4.7,
      'totalReviews': 145,
      'totalPatients': 410,
      'qualifications': ['PsyD', 'Licensed Counselor'],
      'languages': ['English', 'German'],
      'isAvailable': true,
    },
    // Pharmacy
    {
      'name': 'Amanda White',
      'email': 'amanda.white@uhc.edu',
      'department': Department.pharmacy.name,
      'specialization': 'Clinical Pharmacy',
      'bio':
          'Dr. Amanda White provides medication management and pharmaceutical care consultations.',
      'experienceYears': 6,
      'rating': 4.8,
      'totalReviews': 67,
      'totalPatients': 230,
      'qualifications': ['PharmD', 'Board Certified Pharmacotherapy'],
      'languages': ['English'],
      'isAvailable': true,
    },
    {
      'name': 'David Lee',
      'email': 'david.lee@uhc.edu',
      'department': Department.pharmacy.name,
      'specialization': 'Pharmacology',
      'bio':
          'Dr. David Lee specializes in drug interactions and medication optimization for complex cases.',
      'experienceYears': 11,
      'rating': 4.5,
      'totalReviews': 54,
      'totalPatients': 195,
      'qualifications': ['PharmD', 'PhD Pharmacology'],
      'languages': ['English', 'Korean'],
      'isAvailable': true,
    },
    // Cardiology
    {
      'name': 'Richard Martinez',
      'email': 'richard.martinez@uhc.edu',
      'department': Department.cardiology.name,
      'specialization': 'Interventional Cardiology',
      'bio':
          'Dr. Richard Martinez is an interventional cardiologist with expertise in cardiac catheterization and coronary interventions.',
      'experienceYears': 18,
      'rating': 4.9,
      'totalReviews': 245,
      'totalPatients': 890,
      'qualifications': [
        'MD',
        'Board Certified Cardiovascular Disease',
        'FACC',
      ],
      'languages': ['English', 'Spanish'],
      'isAvailable': true,
    },
    {
      'name': 'Jennifer Kim',
      'email': 'jennifer.kim@uhc.edu',
      'department': Department.cardiology.name,
      'specialization': 'General Cardiology',
      'bio':
          'Dr. Jennifer Kim provides comprehensive cardiovascular care including heart disease prevention and management.',
      'experienceYears': 12,
      'rating': 4.8,
      'totalReviews': 178,
      'totalPatients': 620,
      'qualifications': [
        'MD',
        'Board Certified Internal Medicine',
        'Board Certified Cardiology',
      ],
      'languages': ['English', 'Korean'],
      'isAvailable': true,
    },
  ];

  /// Sample departments data
  List<Map<String, dynamic>> get _sampleDepartments => [
    {
      'name': 'General',
      'description':
          'Comprehensive primary care services including routine check-ups, chronic disease management, and preventive care.',
      'iconName': 'medical_services',
      'colorHex': '#2196F3',
      'workingHours': {
        'monday': '8:00 AM - 5:00 PM',
        'tuesday': '8:00 AM - 5:00 PM',
        'wednesday': '8:00 AM - 5:00 PM',
        'thursday': '8:00 AM - 5:00 PM',
        'friday': '8:00 AM - 4:00 PM',
      },
      'isActive': true,
    },
    {
      'name': 'Dentistry',
      'description':
          'Complete dental care including cleanings, fillings, orthodontics, and oral surgery for students and staff.',
      'iconName': 'medical_information',
      'colorHex': '#9C27B0',
      'workingHours': {
        'monday': '9:00 AM - 5:00 PM',
        'tuesday': '9:00 AM - 5:00 PM',
        'wednesday': '9:00 AM - 5:00 PM',
        'thursday': '9:00 AM - 5:00 PM',
        'friday': '9:00 AM - 3:00 PM',
      },
      'isActive': true,
    },
    {
      'name': 'Psychology',
      'description':
          'Mental health services including counseling, therapy, and psychiatric care for academic and personal issues.',
      'iconName': 'psychology',
      'colorHex': '#4CAF50',
      'workingHours': {
        'monday': '8:00 AM - 6:00 PM',
        'tuesday': '8:00 AM - 6:00 PM',
        'wednesday': '8:00 AM - 6:00 PM',
        'thursday': '8:00 AM - 6:00 PM',
        'friday': '8:00 AM - 5:00 PM',
      },
      'isActive': true,
    },
    {
      'name': 'Pharmacy',
      'description':
          'Pharmaceutical services including prescription filling, medication counseling, and over-the-counter medications.',
      'iconName': 'local_pharmacy',
      'colorHex': '#FF5722',
      'workingHours': {
        'monday': '8:00 AM - 8:00 PM',
        'tuesday': '8:00 AM - 8:00 PM',
        'wednesday': '8:00 AM - 8:00 PM',
        'thursday': '8:00 AM - 8:00 PM',
        'friday': '8:00 AM - 6:00 PM',
        'saturday': '10:00 AM - 2:00 PM',
      },
      'isActive': true,
    },
    {
      'name': 'Cardiology',
      'description':
          'Comprehensive heart care including diagnosis and treatment of cardiovascular conditions, heart disease prevention, and cardiac rehabilitation.',
      'iconName': 'favorite',
      'colorHex': '#E91E63',
      'workingHours': {
        'monday': '8:00 AM - 5:00 PM',
        'tuesday': '8:00 AM - 5:00 PM',
        'wednesday': '8:00 AM - 5:00 PM',
        'thursday': '8:00 AM - 5:00 PM',
        'friday': '8:00 AM - 4:00 PM',
      },
      'isActive': true,
    },
  ];

  /// Seed sample doctors into Firebase
  Future<int> seedSampleDoctors() async {
    int count = 0;
    final batch = _firestore.batch();
    final now = DateTime.now();

    for (final doctor in _sampleDoctors) {
      final docRef = _firestore.collection('doctors').doc();
      batch.set(docRef, {
        ...doctor,
        'userId': 'sample_${doctor['email']}',
        'weeklySchedule': _generateDefaultSchedule(),
        'isSampleData': true,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      count++;
    }

    await batch.commit();
    return count;
  }

  /// Generate default weekly schedule for doctors
  /// Schedule with 30-minute time slots:
  /// Mon: 09:00-12:00, 14:00-16:30
  /// Tue: 09:00-11:30, 14:00-15:30
  /// Wed: 09:00-12:00, 14:00-16:00
  /// Thu: 09:00-11:00, 14:00-16:00
  /// Fri: 09:00-11:30 (morning only)
  Map<String, List<Map<String, dynamic>>> _generateDefaultSchedule() {
    return {
      'monday': [
        // Morning: 09:00 - 12:00 (6 slots)
        {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
        {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
        {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
        {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
        {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
        {'startTime': '11:30', 'endTime': '12:00', 'isAvailable': true},
        // Afternoon: 14:00 - 16:30 (5 slots)
        {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
        {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
        {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
        {'startTime': '15:30', 'endTime': '16:00', 'isAvailable': true},
        {'startTime': '16:00', 'endTime': '16:30', 'isAvailable': true},
      ],
      'tuesday': [
        // Morning: 09:00 - 11:30 (5 slots)
        {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
        {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
        {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
        {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
        {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
        // Afternoon: 14:00 - 15:30 (3 slots)
        {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
        {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
        {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
      ],
      'wednesday': [
        // Morning: 09:00 - 12:00 (6 slots)
        {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
        {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
        {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
        {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
        {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
        {'startTime': '11:30', 'endTime': '12:00', 'isAvailable': true},
        // Afternoon: 14:00 - 16:00 (4 slots)
        {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
        {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
        {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
        {'startTime': '15:30', 'endTime': '16:00', 'isAvailable': true},
      ],
      'thursday': [
        // Morning: 09:00 - 11:00 (4 slots)
        {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
        {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
        {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
        {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
        // Afternoon: 14:00 - 16:00 (4 slots)
        {'startTime': '14:00', 'endTime': '14:30', 'isAvailable': true},
        {'startTime': '14:30', 'endTime': '15:00', 'isAvailable': true},
        {'startTime': '15:00', 'endTime': '15:30', 'isAvailable': true},
        {'startTime': '15:30', 'endTime': '16:00', 'isAvailable': true},
      ],
      'friday': [
        // Morning only: 09:00 - 11:30 (5 slots)
        {'startTime': '09:00', 'endTime': '09:30', 'isAvailable': true},
        {'startTime': '09:30', 'endTime': '10:00', 'isAvailable': true},
        {'startTime': '10:00', 'endTime': '10:30', 'isAvailable': true},
        {'startTime': '10:30', 'endTime': '11:00', 'isAvailable': true},
        {'startTime': '11:00', 'endTime': '11:30', 'isAvailable': true},
        // No afternoon slots on Friday
      ],
      'saturday': [], // Closed
      'sunday': [], // Closed
    };
  }

  /// Seed sample appointments into Firebase
  Future<int> seedSampleAppointments() async {
    // First get existing doctors
    final doctorsSnapshot = await _firestore
        .collection('doctors')
        .limit(4)
        .get();
    if (doctorsSnapshot.docs.isEmpty) {
      throw Exception('No doctors found. Please seed doctors first.');
    }

    // Get a sample user ID (admin or first user)
    final usersSnapshot = await _firestore.collection('users').limit(1).get();
    String patientId = 'sample_patient';
    String patientName = 'Sample Student';
    String patientEmail = 'student@university.edu';

    if (usersSnapshot.docs.isNotEmpty) {
      final userData = usersSnapshot.docs.first.data();
      patientId = usersSnapshot.docs.first.id;
      patientName = userData['displayName'] ?? 'Sample Student';
      patientEmail = userData['email'] ?? 'student@university.edu';
    }

    int count = 0;
    final batch = _firestore.batch();
    final now = DateTime.now();

    final types = ['regularCheckup', 'followUp', 'consultation'];
    final timeSlots = [
      '09:00 - 09:30',
      '10:00 - 10:30',
      '11:00 - 11:30',
      '14:00 - 14:30',
      '15:00 - 15:30',
      '16:00 - 16:30',
    ];

    for (int i = 0; i < 18; i++) {
      final doctor = doctorsSnapshot.docs[i % doctorsSnapshot.docs.length];
      final doctorData = doctor.data();

      // Determine date based on status
      DateTime appointmentDate;
      String status;

      if (i < 5) {
        // Pending - future dates
        appointmentDate = now.add(Duration(days: i + 1));
        status = 'pending';
      } else if (i < 10) {
        // Confirmed - future dates
        appointmentDate = now.add(Duration(days: i + 5));
        status = 'confirmed';
      } else if (i < 15) {
        // Completed - past dates
        appointmentDate = now.subtract(Duration(days: i - 5));
        status = 'completed';
      } else {
        // Cancelled
        appointmentDate = now.add(Duration(days: i - 10));
        status = 'cancelled';
      }

      final docRef = _firestore.collection('appointments').doc();
      batch.set(docRef, {
        'patientId': patientId,
        'patientName': patientName,
        'patientEmail': patientEmail,
        'doctorId': doctor.id,
        'doctorName': doctorData['name'] ?? 'Unknown Doctor',
        'department': doctorData['department'] ?? 'generalMedicine',
        'appointmentDate': Timestamp.fromDate(appointmentDate),
        'timeSlot': timeSlots[i % timeSlots.length],
        'type': types[i % types.length],
        'status': status,
        'notes': 'Sample appointment ${i + 1}',
        'isCheckedIn': status == 'completed',
        'isSampleData': true,
        'reminderSent24h': false,
        'reminderSent1h': false,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      count++;
    }

    await batch.commit();
    return count;
  }

  /// Seed sample departments into Firebase
  Future<int> seedSampleDepartments() async {
    int count = 0;
    final batch = _firestore.batch();
    final now = DateTime.now();

    for (final dept in _sampleDepartments) {
      // Use department name as document ID for consistency
      final docId = dept['name'].toString().toLowerCase().replaceAll(' ', '_');
      final docRef = _firestore.collection('departments').doc(docId);
      batch.set(docRef, {
        ...dept,
        'doctorCount': 2,
        'isSampleData': true,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      count++;
    }

    await batch.commit();
    return count;
  }

  /// Clear all sample data from Firebase
  Future<Map<String, int>> clearSampleData() async {
    final results = <String, int>{
      'doctors': 0,
      'appointments': 0,
      'departments': 0,
    };

    // Clear sample doctors
    final doctorsSnapshot = await _firestore
        .collection('doctors')
        .where('isSampleData', isEqualTo: true)
        .get();
    for (final doc in doctorsSnapshot.docs) {
      await doc.reference.delete();
      results['doctors'] = results['doctors']! + 1;
    }

    // Clear sample appointments
    final appointmentsSnapshot = await _firestore
        .collection('appointments')
        .where('isSampleData', isEqualTo: true)
        .get();
    for (final doc in appointmentsSnapshot.docs) {
      await doc.reference.delete();
      results['appointments'] = results['appointments']! + 1;
    }

    // Clear sample departments
    final departmentsSnapshot = await _firestore
        .collection('departments')
        .where('isSampleData', isEqualTo: true)
        .get();
    for (final doc in departmentsSnapshot.docs) {
      await doc.reference.delete();
      results['departments'] = results['departments']! + 1;
    }

    return results;
  }

  /// Get current sample data statistics
  Future<Map<String, int>> getSampleDataStats() async {
    final stats = <String, int>{};

    // Count sample doctors
    final doctorsCount = await _firestore
        .collection('doctors')
        .where('isSampleData', isEqualTo: true)
        .count()
        .get();
    stats['doctors'] = doctorsCount.count ?? 0;

    // Count sample appointments
    final appointmentsCount = await _firestore
        .collection('appointments')
        .where('isSampleData', isEqualTo: true)
        .count()
        .get();
    stats['appointments'] = appointmentsCount.count ?? 0;

    // Count sample departments
    final departmentsCount = await _firestore
        .collection('departments')
        .where('isSampleData', isEqualTo: true)
        .count()
        .get();
    stats['departments'] = departmentsCount.count ?? 0;

    return stats;
  }
}
