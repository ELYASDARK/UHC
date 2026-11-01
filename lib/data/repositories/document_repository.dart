import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../services/firebase_callable.dart';
import '../../core/config/emulator_config.dart';
import '../models/medical_document_model.dart';

/// Repository for medical document Firestore + Storage operations
class DocumentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'medical_documents';

  CollectionReference<Map<String, dynamic>> get _docsRef =>
      _firestore.collection(_collection);

  /// Stream all documents for a user, ordered by uploadedAt descending
  Stream<List<MedicalDocumentModel>> streamDocuments(String userId) {
    return _docsRef
        .where('userId', isEqualTo: userId)
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final model = MedicalDocumentModel.fromFirestore(doc);
              final uri = Uri.tryParse(model.url);
              if (EmulatorConfig.isEmulatorEnabled &&
                  _firestore.app.options.projectId ==
                      EmulatorConfig.demoProjectId &&
                  uri?.host == '127.0.0.1' &&
                  uri?.port == 9199) {
                return model.copyWith(
                    url: uri!
                        .replace(host: EmulatorConfig.loopbackHost)
                        .toString());
              }
              return model;
            }).toList());
  }

  Future<String> createDocument(
      {required String userId,
      required String name,
      required DocumentType type,
      required String notes,
      required Uint8List bytes,
      required String fileName,
      String? appointmentId}) async {
    final id = const Uuid().v4();
    await invokeFirebaseCallable(
        FirebaseFunctions.instance, 'uploadMedicalDocument', {
      'action': 'create',
      'documentId': id,
      'patientId': userId,
      'metadata': {
        'name': name,
        'type': type.toFirestoreString(),
        'notes': notes
      },
      'fileName': fileName,
      'appointmentId': appointmentId,
      'bytes': base64Encode(bytes),
    });
    return id;
  }

  /// Update document metadata + set updatedAt
  Future<void> updateDocument(String docId, Map<String, dynamic> data) async {
    await _docsRef.doc(docId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stage immutable bytes, then atomically replace only an unchanged document.
  /// Cancellation resolves an ambiguous finish response before any cleanup.
  Future<void> replaceDocument({
    required String docId,
    required String expectedStoragePath,
    required Map<String, dynamic> metadata,
    required Uint8List bytes,
    required String fileName,
    required void Function(double) onProgress,
  }) async {
    if (bytes.isEmpty || bytes.length >= 20 * 1024 * 1024) {
      throw ArgumentError('Document must be between 1 byte and 20 MB.');
    }
    Future<dynamic> invoke(Map<String, dynamic> parameters) =>
        invokeFirebaseCallable(
            FirebaseFunctions.instance, 'replaceMedicalDocument', parameters);
    final operation = Map<String, dynamic>.from(await invoke({
      'action': 'begin',
      'docId': docId,
      'expectedStoragePath': expectedStoragePath,
      'metadata': metadata,
      'fileName': fileName,
    }) as Map);
    final operationId = operation['operationId'] as String;
    try {
      await invokeFirebaseCallable(
          FirebaseFunctions.instance, 'uploadMedicalDocument', {
        'action': 'stageReplacement',
        'operationId': operationId,
        'bytes': base64Encode(bytes),
      });
      await invoke({'action': 'finish', 'operationId': operationId});
    } catch (_) {
      // A timeout can follow a committed transaction. The server serializes
      // cancel with finish and never removes a committed candidate.
      final result =
          await invoke({'action': 'cancel', 'operationId': operationId});
      if ((result as Map)['committed'] != true) rethrow;
    }
    onProgress(1);
  }

  Future<void> deleteDocument(String docId, String storagePath) async {
    await invokeFirebaseCallable(FirebaseFunctions.instance,
        'deleteMedicalDocument', {'documentId': docId});
  }
}
