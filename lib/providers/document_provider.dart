import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/repositories/document_repository.dart';
import '../data/models/medical_document_model.dart';

/// Provider for managing medical documents state
class DocumentProvider extends ChangeNotifier {
  final DocumentRepository _repo = DocumentRepository();

  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;

  // Track upload subscription to cancel on dispose
  StreamSubscription? _uploadSubscription;

  bool get isUploading => _isUploading;
  double get uploadProgress => _uploadProgress;
  String? get error => _error;

  /// Stream documents for a user (passthrough to repo)
  Stream<List<MedicalDocumentModel>> streamDocuments(String userId) {
    return _repo.streamDocuments(userId);
  }

  /// Upload file and create Firestore document
  /// Returns true on success, false on failure
  Future<bool> uploadAndAddDocument({
    required String userId,
    required String name,
    required DocumentType type,
    required String notes,
    required Uint8List bytes,
    required String fileName,
    required String addedBy,
    required String addedByRole,
    String addedByName = '',
    String? appointmentId,
  }) async {
    try {
      _isUploading = true;
      _uploadProgress = 0;
      _error = null;
      notifyListeners();

      // Upload with progress tracking
      final upload = _repo.uploadFileWithProgress(userId, bytes, fileName);

      // Listen to progress
      _uploadSubscription?.cancel();
      _uploadSubscription = upload.task.snapshotEvents.listen((event) {
        _uploadProgress = event.bytesTransferred / event.totalBytes;
        notifyListeners();
      });

      // Wait for upload to complete
      await upload.task;
      _uploadSubscription = null;
      final url = await upload.task.snapshot.ref.getDownloadURL();

      // Create Firestore document
      final doc = MedicalDocumentModel(
        id: '',
        userId: userId,
        name: name,
        type: type,
        notes: notes,
        fileName: fileName,
        url: url,
        storagePath: upload.storagePath,
        addedBy: addedBy,
        addedByRole: addedByRole,
        addedByName: addedByName,
        appointmentId: appointmentId,
      );

      await _repo.addDocument(doc);

      _isUploading = false;
      _uploadProgress = 0;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isUploading = false;
      _uploadProgress = 0;
      notifyListeners();
      return false;
    }
  }

  /// Update document metadata
  /// Returns true on success, false on failure
  Future<bool> updateDocument(String docId, Map<String, dynamic> data) async {
    try {
      _error = null;
      await _repo.updateDocument(docId, data);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update document with file replacement
  /// Returns true on success, false on failure
  Future<bool> updateDocumentWithFile({
    required String docId,
    required String userId,
    required Map<String, dynamic> metaData,
    required Uint8List bytes,
    required String fileName,
    String? oldStoragePath,
  }) async {
    try {
      _isUploading = true;
      _uploadProgress = 0;
      _error = null;
      notifyListeners();

      // Upload new file with progress
      final upload = _repo.uploadFileWithProgress(userId, bytes, fileName);

      _uploadSubscription?.cancel();
      _uploadSubscription = upload.task.snapshotEvents.listen((event) {
        _uploadProgress = event.bytesTransferred / event.totalBytes;
        notifyListeners();
      });

      await upload.task;
      _uploadSubscription = null;
      final url = await upload.task.snapshot.ref.getDownloadURL();

      // Merge file info into metadata
      metaData['url'] = url;
      metaData['fileName'] = fileName;
      metaData['storagePath'] = upload.storagePath;

      // Update Firestore doc
      await _repo.updateDocument(docId, metaData);

      // Delete old file from storage if it exists
      if (oldStoragePath != null && oldStoragePath.isNotEmpty) {
        await _repo.deleteStorageFile(oldStoragePath);
      }

      _isUploading = false;
      _uploadProgress = 0;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isUploading = false;
      _uploadProgress = 0;
      notifyListeners();
      return false;
    }
  }

  /// Delete document (Firestore + Storage)
  /// Returns true on success, false on failure
  Future<bool> deleteDocument(String docId, String storagePath) async {
    try {
      _error = null;
      await _repo.deleteDocument(docId, storagePath);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _uploadSubscription?.cancel();
    super.dispose();
  }
}
