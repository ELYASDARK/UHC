import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/department_model.dart';

/// Repository for department-related Firestore operations
class DepartmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'departments';

  CollectionReference<Map<String, dynamic>> get _departmentsRef =>
      _firestore.collection(_collection);

  /// Get all active departments
  Future<List<DepartmentModel>> getAllDepartments() async {
    try {
      final snapshot = await _departmentsRef.get();
      final departments = snapshot.docs
          .map((doc) => DepartmentModel.fromFirestore(doc))
          .where((d) => d.isActive)
          .toList();
      // Sort by name
      departments.sort((a, b) => a.name.compareTo(b.name));
      return departments;
    } catch (e) {
      debugPrint('Error getting departments: $e');
      return [];
    }
  }

  /// Get department by ID
  Future<DepartmentModel?> getDepartmentById(String departmentId) async {
    try {
      final doc = await _departmentsRef.doc(departmentId).get();
      if (doc.exists) {
        return DepartmentModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting department: $e');
      return null;
    }
  }

  /// Create a new department
  Future<String> createDepartment(DepartmentModel department) async {
    try {
      final docRef = await _departmentsRef.add(department.toFirestore());
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating department: $e');
      rethrow;
    }
  }

  /// Update department
  Future<void> updateDepartment(
    String departmentId,
    Map<String, dynamic> updates,
  ) async {
    updates['updatedAt'] = Timestamp.fromDate(DateTime.now());
    await _departmentsRef.doc(departmentId).update(updates);
  }

  /// Delete department
  Future<void> deleteDepartment(String departmentId) async {
    await _departmentsRef.doc(departmentId).delete();
  }

  /// Stream all departments for real-time updates
  Stream<List<DepartmentModel>> streamDepartments() {
    return _departmentsRef.snapshots().map((snapshot) {
      final departments = snapshot.docs
          .map((doc) => DepartmentModel.fromFirestore(doc))
          .where((d) => d.isActive)
          .toList();
      departments.sort((a, b) => a.name.compareTo(b.name));
      return departments;
    });
  }
}
