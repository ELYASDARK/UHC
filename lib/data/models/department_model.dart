import 'package:cloud_firestore/cloud_firestore.dart';

/// Department model with Firestore metadata
class DepartmentModel {
  final String id;
  final String key; // The departmentId used to match with doctors
  final String name;
  final String description;
  final String iconName;
  final String colorHex;
  final Map<String, String> workingHours;
  final bool isActive;
  final int doctorCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSampleData;

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
    this.isSampleData = false,
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

  factory DepartmentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DepartmentModel(
      id: doc.id,
      key: data['key'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      iconName: data['iconName'] ?? 'medical_services',
      colorHex: data['colorHex'] ?? '#2196F3',
      workingHours: Map<String, String>.from(data['workingHours'] ?? {}),
      isActive: data['isActive'] ?? true,
      doctorCount: data['doctorCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isSampleData: data['isSampleData'] ?? false,
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
      'isSampleData': isSampleData,
    };
  }

  DepartmentModel copyWith({
    String? id,
    String? key,
    String? name,
    String? description,
    String? iconName,
    String? colorHex,
    Map<String, String>? workingHours,
    bool? isActive,
    int? doctorCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSampleData,
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
      isSampleData: isSampleData ?? this.isSampleData,
    );
  }
}
