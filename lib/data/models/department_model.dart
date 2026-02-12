import 'package:cloud_firestore/cloud_firestore.dart';

/// Department model with Firestore metadata
class DepartmentModel {
  final String id;
  final String key; // The departmentId used to match with doctors
  final String name;
  final String description;
  final String iconName;
  final String colorHex;
  final Map<String, dynamic> workingHours;
  final bool isActive;
  final int doctorCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  DepartmentModel({
    required this.id,
    this.key = '', // Will be auto-generated from name if not provided
    required this.name,
    required this.description,
    this.iconName = 'medical_services',
    this.colorHex = '#2196F3',
    this.workingHours = const {},
    this.isActive = true,
    this.doctorCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Generate a key from the name if not explicitly provided
  String get departmentKey {
    if (key.isNotEmpty) return key;
    // Convert "General Medicine" to "generalMedicine"
    final words = name.split(' ');
    if (words.isEmpty) return name.toLowerCase();
    return words.first.toLowerCase() +
        words
            .skip(1)
            .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join('');
  }

  /// Get working hours for a day as a display string.
  /// Handles both legacy string format ("8:00 AM - 5:00 PM")
  /// and new structured format ({start: "08:00", end: "18:00"}).
  String getWorkingHoursDisplay(String day) {
    final value = workingHours[day.toLowerCase()];
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      final start = value['start'] ?? '';
      final end = value['end'] ?? '';
      if (start.isEmpty && end.isEmpty) return '';
      return '$start - $end';
    }
    return value.toString();
  }

  /// Parse workingHours from Firestore, safely handling both formats:
  /// - Legacy string: { "monday": "8:00 AM - 5:00 PM" }
  /// - Structured map: { "monday": { "start": "08:00", "end": "18:00" } }
  static Map<String, dynamic> _parseWorkingHours(dynamic raw) {
    if (raw == null) return {};
    if (raw is! Map) return {};
    final result = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is String) {
        result[key] = value;
      } else if (value is Map) {
        result[key] = Map<String, dynamic>.from(value);
      } else {
        result[key] = value.toString();
      }
    }
    return result;
  }

  factory DepartmentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DepartmentModel(
      id: doc.id,
      key: data['key'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      iconName: data['iconName'] ?? 'medical_services',
      colorHex: data['colorHex'] ?? '#2196F3',
      workingHours: _parseWorkingHours(data['workingHours']),
      isActive: data['isActive'] ?? true,
      doctorCount: data['doctorCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'key': departmentKey, // Save the key for filtering
      'name': name,
      'description': description,
      'iconName': iconName,
      'colorHex': colorHex,
      'workingHours': workingHours,
      'isActive': isActive,
      'doctorCount': doctorCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  DepartmentModel copyWith({
    String? id,
    String? key,
    String? name,
    String? description,
    String? iconName,
    String? colorHex,
    Map<String, dynamic>? workingHours,
    bool? isActive,
    int? doctorCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DepartmentModel(
      id: id ?? this.id,
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
      workingHours: workingHours ?? this.workingHours,
      isActive: isActive ?? this.isActive,
      doctorCount: doctorCount ?? this.doctorCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
