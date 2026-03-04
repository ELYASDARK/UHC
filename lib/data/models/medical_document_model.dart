import 'package:cloud_firestore/cloud_firestore.dart';

/// Document types for medical documents
enum DocumentType {
  labResults,
  prescription,
  medicalRecord,
  imaging,
  medicine,
  other;

  /// Convert from Firestore string to enum
  static DocumentType fromString(String? value) {
    switch (value) {
      case 'lab_results':
        return DocumentType.labResults;
      case 'prescription':
        return DocumentType.prescription;
      case 'medical_record':
        return DocumentType.medicalRecord;
      case 'imaging':
        return DocumentType.imaging;
      case 'medicine':
        return DocumentType.medicine;
      default:
        return DocumentType.other;
    }
  }

  /// Convert enum to Firestore string
  String toFirestoreString() {
    switch (this) {
      case DocumentType.labResults:
        return 'lab_results';
      case DocumentType.prescription:
        return 'prescription';
      case DocumentType.medicalRecord:
        return 'medical_record';
      case DocumentType.imaging:
        return 'imaging';
      case DocumentType.medicine:
        return 'medicine';
      case DocumentType.other:
        return 'other';
    }
  }
}

/// Medical document model
class MedicalDocumentModel {
  final String id;
  final String userId;
  final String name;
  final DocumentType type;
  final String notes;
  final String fileName;
  final String url;
  final String storagePath;
  final DateTime? uploadedAt;
  final DateTime? updatedAt;
  final String addedBy;
  final String addedByRole; // 'patient' or 'doctor'
  final String addedByName;
  final String? appointmentId;

  MedicalDocumentModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    this.notes = '',
    required this.fileName,
    required this.url,
    required this.storagePath,
    this.uploadedAt,
    this.updatedAt,
    required this.addedBy,
    required this.addedByRole,
    this.addedByName = '',
    this.appointmentId,
  });

  /// Create from Firestore document snapshot
  /// Handles backward compatibility for old documents missing new fields
  factory MedicalDocumentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MedicalDocumentModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      type: DocumentType.fromString(data['type']),
      notes: data['notes'] ?? '',
      fileName: data['fileName'] ?? '',
      url: data['url'] ?? '',
      storagePath: data['storagePath'] ?? '',
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      // Backward compat: old docs default addedBy to userId, role to 'patient'
      addedBy: data['addedBy'] ?? data['userId'] ?? '',
      addedByRole: data['addedByRole'] ?? 'patient',
      addedByName: data['addedByName'] ?? '',
      appointmentId: data['appointmentId'],
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'type': type.toFirestoreString(),
      'notes': notes,
      'fileName': fileName,
      'url': url,
      'storagePath': storagePath,
      'uploadedAt': uploadedAt != null
          ? Timestamp.fromDate(uploadedAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
      'addedBy': addedBy,
      'addedByRole': addedByRole,
      'addedByName': addedByName,
      'appointmentId': appointmentId,
    };
  }

  /// Copy with updated fields
  MedicalDocumentModel copyWith({
    String? id,
    String? userId,
    String? name,
    DocumentType? type,
    String? notes,
    String? fileName,
    String? url,
    String? storagePath,
    DateTime? uploadedAt,
    DateTime? updatedAt,
    String? addedBy,
    String? addedByRole,
    String? addedByName,
    String? appointmentId,
  }) {
    return MedicalDocumentModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      notes: notes ?? this.notes,
      fileName: fileName ?? this.fileName,
      url: url ?? this.url,
      storagePath: storagePath ?? this.storagePath,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      addedBy: addedBy ?? this.addedBy,
      addedByRole: addedByRole ?? this.addedByRole,
      addedByName: addedByName ?? this.addedByName,
      appointmentId: appointmentId ?? this.appointmentId,
    );
  }
}
