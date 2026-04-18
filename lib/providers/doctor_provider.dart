import 'package:flutter/material.dart';
import '../data/models/doctor_model.dart';
import '../data/repositories/doctor_repository.dart';

/// Provider for managing doctors state
class DoctorProvider extends ChangeNotifier {
  final DoctorRepository _doctorRepo = DoctorRepository();

  List<DoctorModel> _doctors = [];
  List<DoctorModel> _filteredDoctors = [];
  DoctorModel? _selectedDoctor;
  Department? _selectedDepartment;
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';

  // Getters
  List<DoctorModel> get doctors =>
      _filteredDoctors.isEmpty && _searchQuery.isEmpty
          ? _doctors
          : _filteredDoctors;
  List<DoctorModel> get allDoctors => _doctors;
  DoctorModel? get selectedDoctor => _selectedDoctor;
  Department? get selectedDepartment => _selectedDepartment;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  /// Load all doctors
  Future<void> loadDoctors() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _doctors = await _doctorRepo.getAllDoctors();
      _filteredDoctors = [];
      _searchQuery = '';
      _selectedDepartment = null;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load doctors by department
  Future<void> loadDoctorsByDepartment(Department department) async {
    _isLoading = true;
    _error = null;
    _selectedDepartment = department;
    notifyListeners();

    try {
      _filteredDoctors = await _doctorRepo.getDoctorsByDepartment(department);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search doctors (from cached list to avoid re-fetching entire collection)
  Future<void> searchDoctors(String query) async {
    _searchQuery = query;

    if (query.isEmpty) {
      _filteredDoctors = [];
      notifyListeners();
      return;
    }

    // If doctors aren't loaded yet, fetch them first
    if (_doctors.isEmpty) {
      _isLoading = true;
      notifyListeners();
      try {
        _doctors = await _doctorRepo.getAllDoctors();
      } catch (e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
        return;
      }
    }

    // Filter locally from cached data instead of re-fetching
    final queryLower = query.toLowerCase();
    _filteredDoctors = _doctors
        .where(
          (doctor) =>
              doctor.name.toLowerCase().contains(queryLower) ||
              doctor.specialization.toLowerCase().contains(queryLower) ||
              doctor.departmentName.toLowerCase().contains(queryLower),
        )
        .toList();
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Get doctor by ID
  Future<DoctorModel?> getDoctorById(String doctorId) async {
    try {
      _selectedDoctor = await _doctorRepo.getDoctorById(doctorId);
      notifyListeners();
      return _selectedDoctor;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Select a doctor
  void selectDoctor(DoctorModel doctor) {
    _selectedDoctor = doctor;
    notifyListeners();
  }

  /// Clear selection
  void clearSelection() {
    _selectedDoctor = null;
    notifyListeners();
  }

  /// Clear filters
  void clearFilters() {
    _filteredDoctors = [];
    _searchQuery = '';
    _selectedDepartment = null;
    notifyListeners();
  }

  /// Filter by department (local filter)
  void filterByDepartment(Department? department) {
    _selectedDepartment = department;

    if (department == null) {
      _filteredDoctors = [];
    } else {
      _filteredDoctors =
          _doctors.where((d) => d.department == department).toList();
    }
    notifyListeners();
  }
}
