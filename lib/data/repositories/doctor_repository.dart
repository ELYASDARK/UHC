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
}
