import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
        .map((snapshot) => snapshot.docs
            .map((doc) => MedicalDocumentModel.fromFirestore(doc))
            .toList());
  }

  /// Add a new document to Firestore, then update with its own ID
  Future<String> addDocument(MedicalDocumentModel doc) async {
    final docRef = await _docsRef.add(doc.toFirestore());
    await docRef.update({'id': docRef.id});
    return docRef.id;
  }

  /// Update document metadata + set updatedAt
  Future<void> updateDocument(String docId, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _docsRef.doc(docId).update(data);
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
    String userId,
    Uint8List bytes,
    String fileName,
  ) async {
    final extension = fileName.split('.').last;
    final storagePath =
        'medical_documents/$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';

    final ref = _storage.ref().child(storagePath);
    await ref.putData(bytes);
    final url = await ref.getDownloadURL();

    return {'url': url, 'storagePath': storagePath};
  }

  /// Upload file bytes with progress tracking
  /// Returns UploadTask for progress listening + storagePath for Firestore
  ({UploadTask task, String storagePath}) uploadFileWithProgress(
    String userId,
    Uint8List bytes,
    String fileName,
  ) {
    final extension = fileName.split('.').last;
    final storagePath =
        'medical_documents/$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    final ref = _storage.ref().child(storagePath);
    return (task: ref.putData(bytes), storagePath: storagePath);
  }
}
