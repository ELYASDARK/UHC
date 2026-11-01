import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/repositories/document_repository.dart';
import '../data/models/medical_document_model.dart';

/// Provider for managing medical documents state
class DocumentProvider extends ChangeNotifier {
  final DocumentRepository _repo;

  DocumentProvider({DocumentRepository? repository})
      : _repo = repository ?? DocumentRepository();

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;

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
    if (_isUploading) return false;
    try {
      _isUploading = true;
      _uploadProgress = 0;
      _error = null;
      notifyListeners();

      await _repo.createDocument(
          userId: userId,
          name: name,
          type: type,
          notes: notes,
          bytes: bytes,
          fileName: fileName,
          appointmentId: appointmentId);

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
    String? appointmentId,
  }) async {
    if (_isUploading) return false;
    try {
      _isUploading = true;
      _uploadProgress = 0;
      _error = null;
      notifyListeners();

      await _repo.replaceDocument(
        docId: docId,
        expectedStoragePath: oldStoragePath ?? '',
        metadata: Map.of(metaData),
        bytes: bytes,
        fileName: fileName,
        onProgress: (progress) {
          _uploadProgress = progress;
          notifyListeners();
        },
      );

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
    _disposed = true;
    super.dispose();
  }
}
