import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../services/firebase_callable.dart';
import '../../core/config/emulator_config.dart';
import '../models/medical_document_model.dart';

/// Repository for medical document Firestore + Storage operations
class DocumentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
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

  /// Create the record with its ID in a single write.
  Future<String> addDocument(MedicalDocumentModel doc) async {
    final docRef = _docsRef.doc();
    await docRef.set({...doc.toFirestore(), 'id': docRef.id});
    return docRef.id;
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
    StreamSubscription<TaskSnapshot>? progress;
    try {
      final task = _storage
          .ref(operation['storagePath'] as String)
          .putData(bytes, _metadataFor(fileName));
      progress = task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
      await task;
      await invoke({'action': 'finish', 'operationId': operationId});
    } catch (_) {
      // A timeout can follow a committed transaction. The server serializes
      // cancel with finish and never removes a committed candidate.
      final result =
          await invoke({'action': 'cancel', 'operationId': operationId});
      if ((result as Map)['committed'] != true) rethrow;
    } finally {
      await progress?.cancel();
    }
  }

  /// Delete Firestore doc + Storage file
  Future<void> deleteDocument(String docId, String storagePath) async {
    // Delete from Storage (ignore errors if file already missing)
    if (storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(storagePath).delete();
      } catch (_) {
        // File may already be deleted from storage
      }
    }
    // Delete from Firestore
    await _docsRef.doc(docId).delete();
  }

  /// Delete only the Storage file (no Firestore delete)
  Future<void> deleteStorageFile(String storagePath) async {
    if (storagePath.isNotEmpty) {
      try {
        await _storage.ref().child(storagePath).delete();
      } catch (_) {
        // File may already be deleted from storage
      }
    }
  }

  /// Upload file bytes to Firebase Storage
  /// Returns {'url': downloadUrl, 'storagePath': path}
  Future<Map<String, String>> uploadFile(
      String userId, Uint8List bytes, String fileName,
      {String? appointmentId}) async {
    final extension = fileName.split('.').last;
    final scope = appointmentId?.isNotEmpty == true ? appointmentId! : 'self';
    final storagePath =
        'medical_documents/$userId/$scope/${const Uuid().v4()}.$extension';

    final ref = _storage.ref().child(storagePath);
    await ref.putData(bytes, _metadataFor(fileName));
    final url = await ref.getDownloadURL();

    return {'url': url, 'storagePath': storagePath};
  }

  /// Upload file bytes with progress tracking
  /// Returns UploadTask for progress listening + storagePath for Firestore
  ({UploadTask task, String storagePath}) uploadFileWithProgress(
      String userId, Uint8List bytes, String fileName,
      {String? appointmentId}) {
    final extension = fileName.split('.').last;
    final scope = appointmentId?.isNotEmpty == true ? appointmentId! : 'self';
    final storagePath =
        'medical_documents/$userId/$scope/${const Uuid().v4()}.$extension';
    final ref = _storage.ref().child(storagePath);
    return (
      task: ref.putData(bytes, _metadataFor(fileName)),
      storagePath: storagePath
    );
  }

  SettableMetadata _metadataFor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      _ => 'application/octet-stream',
    };
    return SettableMetadata(contentType: contentType);
  }
}
