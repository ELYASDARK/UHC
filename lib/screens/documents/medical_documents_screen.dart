import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';

/// Medical document upload and management screen
class MedicalDocumentsScreen extends StatefulWidget {
  const MedicalDocumentsScreen({super.key});

  @override
  State<MedicalDocumentsScreen> createState() => _MedicalDocumentsScreenState();
}

class _MedicalDocumentsScreenState extends State<MedicalDocumentsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  bool _isUploading = false;
  double _uploadProgress = 0;

  List<Map<String, dynamic>> _getDocumentTypes(AppLocalizations l10n) {
    return [
      {'id': 'lab_results', 'name': l10n.labResults, 'icon': Icons.science},
      {
        'id': 'prescription',
        'name': l10n.prescription,
        'icon': Icons.medication,
      },
      {
        'id': 'medical_record',
        'name': l10n.medicalRecord,
        'icon': Icons.description,
      },
      {'id': 'imaging', 'name': l10n.imaging, 'icon': Icons.image},
      {'id': 'other', 'name': l10n.other, 'icon': Icons.folder},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = context.watch<AuthProvider>().user;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.medicalDocuments), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : () => _showUploadDialog(context),
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.upload_file),
        label: Text(_isUploading ? l10n.loading : l10n.uploadDocument),
        backgroundColor: AppColors.primary,
        shape: const StadiumBorder(),
      ),
      body: Column(
        children: [
          // Upload Progress
          if (_isUploading)
            LinearProgressIndicator(
              value: _uploadProgress,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            ),

          // Documents List
          Expanded(
            child: user == null
                ? const Center(child: Text('Please login'))
                : StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('medical_documents')
                        .where('userId', isEqualTo: user.id)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Error loading documents: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.error),
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return _buildEmptyState(isDark);
                      }

                      final docs = snapshot.data!.docs;
                      // Client-side sorting to avoid index requirement
                      docs.sort((a, b) {
                        final aTime =
                            (a.data() as Map<String, dynamic>)['uploadedAt']
                                as Timestamp?;
                        final bTime =
                            (b.data() as Map<String, dynamic>)['uploadedAt']
                                as Timestamp?;
                        if (aTime == null) return 1;
                        if (bTime == null) return -1;
                        return bTime.compareTo(aTime);
                      });

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildDocumentCard(doc.id, data, isDark);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noDocuments,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.uploadMedicalDocumentsDescription,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(String id, Map<String, dynamic> data, bool isDark) {
    final l10n = AppLocalizations.of(context);
    final documentTypes = _getDocumentTypes(l10n);
    final typeInfo = documentTypes.firstWhere(
      (t) => t['id'] == data['type'],
      orElse: () => documentTypes.last,
    );
    final uploadedAt = (data['uploadedAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: ListTile(
        onTap: () => _viewDocument(data['url']),
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(typeInfo['icon'], color: AppColors.primary),
        ),
        title: Text(
          data['name'] ?? 'Untitled',
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(typeInfo['name']),
            if (uploadedAt != null)
              Text(
                DateFormat('MMM d, yyyy').format(uploadedAt),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                _viewDocument(data['url']);
                break;
              case 'edit':
                _showEditDialog(context, id, data);
                break;
              case 'delete':
                _confirmDelete(id, data['storagePath']);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  const Icon(Icons.visibility, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.view),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.edit),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete, size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text(
                    l10n.delete,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadDialog(BuildContext context) {
    String? selectedType;
    final nameController = TextEditingController();
    final notesController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 20),
              Text(
                l10n.uploadDocument,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '${l10n.documentName} *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text('${l10n.documentType} *'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _getDocumentTypes(AppLocalizations.of(context)).map((
                  type,
                ) {
                  final isSelected = selectedType == type['id'];
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type['icon'],
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight),
                        ),
                        const SizedBox(width: 4),
                        Text(type['name']),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) =>
                        setSheetState(() => selectedType = type['id']),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: '${l10n.notes} (${l10n.optional})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (nameController.text.isEmpty || selectedType == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill required fields'),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    _pickAndUploadFile(
                      name: nameController.text,
                      type: selectedType!,
                      notes: notesController.text,
                    );
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(l10n.selectFile),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    String? selectedType = data['type'];
    final nameController = TextEditingController(text: data['name']);
    final notesController = TextEditingController(text: data['notes']);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    File? newFile;
    final l10n = AppLocalizations.of(context);
    String fileName = data['fileName'] ?? l10n.currentFile;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                l10n.updateDocument, // Title
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '${l10n.documentName} *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              Text('${l10n.documentType} *'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _getDocumentTypes(l10n).map((type) {
                  final isSelected = selectedType == type['id'];
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type['icon'],
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimaryLight),
                        ),
                        const SizedBox(width: 4),
                        Text(type['name']),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (_) =>
                        setSheetState(() => selectedType = type['id']),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimaryLight),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: '${l10n.notes} (${l10n.optional})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // File Replacement Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        newFile != null
                            ? newFile!.path.split(Platform.pathSeparator).last
                            : fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: newFile != null ? AppColors.primary : null,
                          fontWeight: newFile != null ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: [
                            'pdf',
                            'jpg',
                            'jpeg',
                            'png',
                            'doc',
                            'docx',
                          ],
                        );
                        if (result != null && result.files.isNotEmpty) {
                          setSheetState(() {
                            newFile = File(result.files.single.path!);
                          });
                        }
                      },
                      child: Text(newFile != null ? l10n.change : l10n.replace),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (nameController.text.isEmpty || selectedType == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.pleaseFillRequiredFields)),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    _performUpdate(
                      docId: docId,
                      oldData: data,
                      newName: nameController.text,
                      newType: selectedType!,
                      newNotes: notesController.text,
                      newFile: newFile,
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: Text(l10n.updateDocument),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _performUpdate({
    required String docId,
    required Map<String, dynamic> oldData,
    required String newName,
    required String newType,
    required String newNotes,
    File? newFile,
  }) async {
    try {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      Map<String, dynamic> updateData = {
        'name': newName,
        'type': newType,
        'notes': newNotes,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // If a new file is uploaded, handle storage operations
      if (newFile != null) {
        final user = context.read<AuthProvider>().user;
        if (user != null) {
          final fileName = newFile.path.split(Platform.pathSeparator).last;
          final extension = fileName.split('.').last;
          final storagePath =
              'medical_documents/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';

          final ref = _storage.ref().child(storagePath);
          final uploadTask = ref.putFile(newFile);

          uploadTask.snapshotEvents.listen((event) {
            setState(() {
              _uploadProgress = event.bytesTransferred / event.totalBytes;
            });
          });

          await uploadTask;
          final url = await ref.getDownloadURL();

          updateData['url'] = url;
          updateData['fileName'] = fileName;
          updateData['storagePath'] = storagePath;

          // Try to delete old file if it exists
          if (oldData['storagePath'] != null) {
            try {
              await _storage.ref().child(oldData['storagePath']).delete();
            } catch (_) {
              // Ignore deletion errors (file might be missing)
            }
          }
        }
      }

      await _firestore
          .collection('medical_documents')
          .doc(docId)
          .update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).documentUpdated),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).updateFailed}: ${e.toString()}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _pickAndUploadFile({
    required String name,
    required String type,
    required String notes,
  }) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final extension = fileName.split('.').last;
      final storagePath =
          'medical_documents/${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';

      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      // Upload to Firebase Storage
      final ref = _storage.ref().child(storagePath);
      final uploadTask = ref.putFile(file);

      uploadTask.snapshotEvents.listen((event) {
        setState(() {
          _uploadProgress = event.bytesTransferred / event.totalBytes;
        });
      });

      await uploadTask;
      final url = await ref.getDownloadURL();

      // Save to Firestore
      await _firestore.collection('medical_documents').add({
        'userId': user.id,
        'name': name,
        'type': type,
        'notes': notes,
        'fileName': fileName,
        'url': url,
        'storagePath': storagePath,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).documentUploaded),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).uploadFailed}: ${e.toString()}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<void> _viewDocument(String? url) async {
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).noURLProvided)),
      );
      return;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).couldNotOpenDocument),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).errorOpeningDocument}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(String docId, String? storagePath) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteDocument),
        content: Text(l10n.deleteDocumentConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete from Storage
        if (storagePath != null) {
          await _storage.ref().child(storagePath).delete();
        }
        // Delete from Firestore
        await _firestore.collection('medical_documents').doc(docId).delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).documentDeleted),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}
