import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/department_model.dart';
import '../../core/utils/session_read_cache.dart';

/// Repository for department-related Firestore operations
class DepartmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'departments';
  static int debugServerReads = 0;
  static final _cache = SessionReadCache<List<DepartmentModel>>(
    retention: const Duration(minutes: 2),
  );

  static void bindSession(String? session) => _cache.bindSession(session);
  static final _changes = ValueNotifier<int>(0);
  static Listenable get cacheChanges => _changes;
  static void invalidateCache() {
    _cache.invalidate();
    _changes.value++;
  }

  static List<DepartmentModel>? get cachedDepartments => _cache.value;

  CollectionReference<Map<String, dynamic>> get _departmentsRef =>
      _firestore.collection(_collection);

  /// Get all active departments
  Future<List<DepartmentModel>> getAllDepartments(
          {bool forceRefresh = false}) =>
      _cache.read(() async {
        assert(() {
          debugServerReads++;
          return true;
        }());
        final snapshot = await _departmentsRef.get(
          const GetOptions(source: Source.server),
        );
        final departments = snapshot.docs
            .map((doc) => DepartmentModel.fromFirestore(doc))
            .where((d) => d.isActive)
            .toList();
        // Sort by name
        departments.sort((a, b) => a.name.compareTo(b.name));
        return List.unmodifiable(departments);
      }, forceRefresh: forceRefresh);

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
      invalidateCache();
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
    invalidateCache();
  }

  /// Delete department
  Future<void> deleteDepartment(String departmentId) async {
    await _departmentsRef.doc(departmentId).delete();
    invalidateCache();
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
