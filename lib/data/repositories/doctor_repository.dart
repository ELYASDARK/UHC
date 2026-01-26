import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/doctor_model.dart';

/// Repository for doctor-related Firestore operations
class DoctorRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'doctors';

  CollectionReference<Map<String, dynamic>> get _doctorsRef =>
      _firestore.collection(_collection);

  /// Get all doctors
  Future<List<DoctorModel>> getAllDoctors() async {
    try {
      // Try simple query without ordering to avoid index issues
      final snapshot = await _doctorsRef.get();
      final doctors = snapshot.docs
          .map((doc) => DoctorModel.fromFirestore(doc))
          .where((d) => d.isAvailable)
          .toList();
      // Sort in-memory by rating
      doctors.sort((a, b) => b.rating.compareTo(a.rating));
      return doctors;
    } catch (e) {
      print('Error getting all doctors: $e');
      return [];
    }
  }

  /// Get doctor by ID
  Future<DoctorModel?> getDoctorById(String doctorId) async {
    final doc = await _doctorsRef.doc(doctorId).get();
    if (doc.exists) {
      return DoctorModel.fromFirestore(doc);
    }
    return null;
  }

  /// Get doctors by department
  Future<List<DoctorModel>> getDoctorsByDepartment(
    Department department,
  ) async {
    try {
      final snapshot = await _doctorsRef
          .where('department', isEqualTo: department.name)
          .get();
      final doctors = snapshot.docs
          .map((doc) => DoctorModel.fromFirestore(doc))
          .where((d) => d.isAvailable)
          .toList();
      doctors.sort((a, b) => b.rating.compareTo(a.rating));
      return doctors;
    } catch (e) {
      print('Error getting doctors by department: $e');
      return [];
    }
  }

  /// Search doctors by name
  Future<List<DoctorModel>> searchDoctors(String query) async {
    final queryLower = query.toLowerCase();
    final allDoctors = await getAllDoctors();
    return allDoctors
        .where(
          (doctor) =>
              doctor.name.toLowerCase().contains(queryLower) ||
              doctor.specialization.toLowerCase().contains(queryLower) ||
              doctor.departmentName.toLowerCase().contains(queryLower),
        )
        .toList();
  }

  /// Create doctor (admin)
  Future<String> createDoctor(DoctorModel doctor) async {
    final docRef = await _doctorsRef.add(doctor.toFirestore());
    return docRef.id;
  }

  /// Update doctor (admin)
  Future<void> updateDoctor(String doctorId, Map<String, dynamic> data) async {
    data['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await _doctorsRef.doc(doctorId).update(data);
  }

  /// Delete doctor (admin)
  Future<void> deleteDoctor(String doctorId) async {
    await _doctorsRef.doc(doctorId).delete();
  }

  /// Update doctor rating
  Future<void> updateDoctorRating(
    String doctorId,
    double newRating,
    int totalReviews,
  ) async {
    await _doctorsRef.doc(doctorId).update({
      'rating': newRating,
      'totalReviews': totalReviews,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Toggle doctor availability (admin)
  Future<void> toggleAvailability(String doctorId, bool isAvailable) async {
    await _doctorsRef.doc(doctorId).update({
      'isAvailable': isAvailable,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Stream all doctors for real-time updates
  Stream<List<DoctorModel>> streamDoctors() {
    return _doctorsRef.snapshots().map((snapshot) {
      final doctors = snapshot.docs
          .map((doc) => DoctorModel.fromFirestore(doc))
          .where((d) => d.isAvailable)
          .toList();
      doctors.sort((a, b) => b.rating.compareTo(a.rating));
      return doctors;
    });
  }

  /// Stream doctors by department
  Stream<List<DoctorModel>> streamDoctorsByDepartment(Department department) {
    return _doctorsRef
        .where('department', isEqualTo: department.name)
        .snapshots()
        .map((snapshot) {
          final doctors = snapshot.docs
              .map((doc) => DoctorModel.fromFirestore(doc))
              .where((d) => d.isAvailable)
              .toList();
          doctors.sort((a, b) => b.rating.compareTo(a.rating));
          return doctors;
        });
  }

  /// Add sample doctors to Firebase (for initial setup)
  Future<void> addSampleDoctors() async {
    final now = DateTime.now();

    // Common weekly schedule with 30-minute slots
    final weeklySchedule = {
      'Monday': [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '09:30', endTime: '10:00'),
        TimeSlot(startTime: '10:00', endTime: '10:30'),
        TimeSlot(startTime: '10:30', endTime: '11:00'),
        TimeSlot(startTime: '11:00', endTime: '11:30'),
        TimeSlot(startTime: '11:30', endTime: '12:00'),
        TimeSlot(startTime: '14:00', endTime: '14:30'),
        TimeSlot(startTime: '14:30', endTime: '15:00'),
        TimeSlot(startTime: '15:00', endTime: '15:30'),
        TimeSlot(startTime: '15:30', endTime: '16:00'),
        TimeSlot(startTime: '16:00', endTime: '16:30'),
      ],
      'Tuesday': [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '09:30', endTime: '10:00'),
        TimeSlot(startTime: '10:00', endTime: '10:30'),
        TimeSlot(startTime: '10:30', endTime: '11:00'),
        TimeSlot(startTime: '11:00', endTime: '11:30'),
        TimeSlot(startTime: '14:00', endTime: '14:30'),
        TimeSlot(startTime: '14:30', endTime: '15:00'),
        TimeSlot(startTime: '15:00', endTime: '15:30'),
      ],
      'Wednesday': [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '09:30', endTime: '10:00'),
        TimeSlot(startTime: '10:00', endTime: '10:30'),
        TimeSlot(startTime: '10:30', endTime: '11:00'),
        TimeSlot(startTime: '11:00', endTime: '11:30'),
        TimeSlot(startTime: '11:30', endTime: '12:00'),
        TimeSlot(startTime: '14:00', endTime: '14:30'),
        TimeSlot(startTime: '14:30', endTime: '15:00'),
        TimeSlot(startTime: '15:00', endTime: '15:30'),
        TimeSlot(startTime: '15:30', endTime: '16:00'),
      ],
      'Thursday': [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '09:30', endTime: '10:00'),
        TimeSlot(startTime: '10:00', endTime: '10:30'),
        TimeSlot(startTime: '10:30', endTime: '11:00'),
        TimeSlot(startTime: '14:00', endTime: '14:30'),
        TimeSlot(startTime: '14:30', endTime: '15:00'),
        TimeSlot(startTime: '15:00', endTime: '15:30'),
        TimeSlot(startTime: '15:30', endTime: '16:00'),
      ],
      'Friday': [
        TimeSlot(startTime: '09:00', endTime: '09:30'),
        TimeSlot(startTime: '09:30', endTime: '10:00'),
        TimeSlot(startTime: '10:00', endTime: '10:30'),
        TimeSlot(startTime: '10:30', endTime: '11:00'),
        TimeSlot(startTime: '11:00', endTime: '11:30'),
      ],
    };

    final sampleDoctors = [
      DoctorModel(
        id: '',
        userId: 'doctor1',
        name: 'Dr. Sarah Johnson',
        email: 'sarah.johnson@uhc.edu',
        photoUrl:
            'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=200',
        departmentId: 'generalMedicine',
        specialization: 'Family Medicine',
        bio:
            'Dr. Sarah Johnson is a dedicated family medicine physician with over 10 years of experience.',
        experienceYears: 10,
        rating: 4.8,
        totalReviews: 124,
        totalPatients: 850,
        qualifications: ['MD', 'FAAFP'],
        languages: ['English', 'Spanish'],
        isAvailable: true,
        weeklySchedule: weeklySchedule,
        createdAt: now,
        updatedAt: now,
      ),
      DoctorModel(
        id: '',
        userId: 'doctor2',
        name: 'Dr. Michael Chen',
        email: 'michael.chen@uhc.edu',
        photoUrl:
            'https://images.unsplash.com/photo-1612349317150-e413f6a5b16d?w=200',
        departmentId: 'dentistry',
        specialization: 'Orthodontics',
        bio:
            'Dr. Michael Chen specializes in orthodontics and cosmetic dentistry.',
        experienceYears: 8,
        rating: 4.9,
        totalReviews: 89,
        totalPatients: 620,
        qualifications: ['DDS', 'MS Orthodontics'],
        languages: ['English', 'Mandarin'],
        isAvailable: true,
        weeklySchedule: weeklySchedule,
        createdAt: now,
        updatedAt: now,
      ),
      DoctorModel(
        id: '',
        userId: 'doctor3',
        name: 'Dr. Emily Davis',
        email: 'emily.davis@uhc.edu',
        photoUrl:
            'https://images.unsplash.com/photo-1594824476967-48c8b964273f?w=200',
        departmentId: 'psychology',
        specialization: 'Clinical Psychology',
        bio:
            'Dr. Emily Davis is a licensed clinical psychologist specializing in anxiety and depression.',
        experienceYears: 12,
        rating: 4.7,
        totalReviews: 156,
        totalPatients: 480,
        qualifications: ['PhD Psychology', 'Licensed Clinical Psychologist'],
        languages: ['English'],
        isAvailable: true,
        weeklySchedule: weeklySchedule,
        createdAt: now,
        updatedAt: now,
      ),
      DoctorModel(
        id: '',
        userId: 'doctor4',
        name: 'Dr. James Wilson',
        email: 'james.wilson@uhc.edu',
        photoUrl:
            'https://images.unsplash.com/photo-1537368910025-700350fe46c7?w=200',
        departmentId: 'generalMedicine',
        specialization: 'Internal Medicine',
        bio:
            'Dr. James Wilson is an experienced internist with expertise in chronic disease management.',
        experienceYears: 15,
        rating: 4.6,
        totalReviews: 210,
        totalPatients: 1200,
        qualifications: ['MD', 'Board Certified Internal Medicine'],
        languages: ['English', 'French'],
        isAvailable: true,
        weeklySchedule: weeklySchedule,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    for (final doctor in sampleDoctors) {
      await createDoctor(doctor);
    }

    print('Sample doctors added successfully!');
  }

  /// Update all doctors with photo URLs
  Future<void> updateDoctorPhotos() async {
    try {
      final snapshot = await _doctorsRef.get();

      // Photo URLs for different doctor types
      final malePhotos = [
        'https://images.unsplash.com/photo-1612349317150-e413f6a5b16d?w=200',
        'https://images.unsplash.com/photo-1537368910025-700350fe46c7?w=200',
        'https://images.unsplash.com/photo-1622253692010-333f2da6031d?w=200',
      ];

      final femalePhotos = [
        'https://images.unsplash.com/photo-1559839734-2b71ea197ec2?w=200',
        'https://images.unsplash.com/photo-1594824476967-48c8b964273f?w=200',
        'https://images.unsplash.com/photo-1651008376811-b90baee60c1f?w=200',
      ];

      int maleIndex = 0;
      int femaleIndex = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String? ?? '';

        // Simple heuristic: check for female names
        final isFemale =
            name.contains('Sarah') ||
            name.contains('Emily') ||
            name.contains('Lisa') ||
            name.contains('Maria') ||
            name.contains('Jessica') ||
            name.contains('Jennifer') ||
            name.contains('Amanda') ||
            name.contains('Ashley');

        String photoUrl;
        if (isFemale) {
          photoUrl = femalePhotos[femaleIndex % femalePhotos.length];
          femaleIndex++;
        } else {
          photoUrl = malePhotos[maleIndex % malePhotos.length];
          maleIndex++;
        }

        // Update the document with photoUrl
        await doc.reference.update({
          'photoUrl': photoUrl,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });

        print('Updated photo for $name');
      }

      print('All doctor photos updated successfully!');
    } catch (e) {
      print('Error updating doctor photos: $e');
    }
  }
}
