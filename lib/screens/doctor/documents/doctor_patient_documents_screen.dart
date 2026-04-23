import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/document_provider.dart';
import '../../../data/models/medical_document_model.dart';
import '../../../l10n/app_localizations.dart';

/// Screen for doctors to view and manage a patient's medical documents
class DoctorPatientDocumentsScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String appointmentId;
  final String doctorId;
  final String doctorName;
  final bool isReadOnly;

  const DoctorPatientDocumentsScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    this.isReadOnly = false,
  });

  @override
  State<DoctorPatientDocumentsScreen> createState() =>
      _DoctorPatientDocumentsScreenState();
}

class _DoctorPatientDocumentsScreenState
    extends State<DoctorPatientDocumentsScreen> {
  late final Stream<List<MedicalDocumentModel>> _docsStream;

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
      {
        'id': 'medicine',
        'name': l10n.medicine,
        'icon': Icons.medication_liquid,
      },
      {'id': 'other', 'name': l10n.other, 'icon': Icons.folder},
    ];
  }

  @override
  void initState() {
    super.initState();
    _docsStream =
        context.read<DocumentProvider>().streamDocuments(widget.patientId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final docProvider = context.watch<DocumentProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.patientDocuments} — ${widget.patientName}'),
        centerTitle: true,
      ),
      floatingActionButton: widget.isReadOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: docProvider.isUploading
                  ? null
                  : () => _showUploadDialog(context),
              icon: docProvider.isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(
                  docProvider.isUploading ? l10n.loading : l10n.addDocument),
              backgroundColor: AppColors.primary,
              shape: const StadiumBorder(),
            ),
      body: Column(
        children: [
          // Upload Progress
          if (docProvider.isUploading)
            LinearProgressIndicator(
              value: docProvider.uploadProgress,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            ),

          // Read-only banner
          if (widget.isReadOnly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.orange.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.appointmentCompletedReadOnly,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Documents List
          Expanded(
            child: StreamBuilder<List<MedicalDocumentModel>>(
              stream: _docsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${l10n.errorLoadingDocuments}: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState(context, isDark);
                }

                final docs = snapshot.data!;
                return _buildDocsList(context, docs, isDark, l10n);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocsList(
    BuildContext context,
    List<MedicalDocumentModel> docs,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final documentTypes = _getDocumentTypes(l10n);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        return _buildDocumentCard(context, doc, isDark, documentTypes);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
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
            l10n.viewPatientDocuments,
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

  Widget _buildDocumentCard(
    BuildContext context,
    MedicalDocumentModel doc,
    bool isDark,
    List<Map<String, dynamic>> documentTypes,
  ) {
    final l10n = AppLocalizations.of(context);
    final typeInfo = documentTypes.firstWhere(
      (t) => t['id'] == doc.type.toFirestoreString(),
      orElse: () => documentTypes.last,
    );

    final isDoctorOwn = doc.addedBy == widget.doctorId;
    final isPatientDoc = doc.addedByRole == 'patient';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
        onTap: () => _viewDocument(context, doc.url),
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
          doc.name.isNotEmpty ? doc.name : l10n.other,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(typeInfo['name']),
            if (doc.uploadedAt != null)
              Text(
                DateFormat('MMM d, yyyy').format(doc.uploadedAt!),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondaryLight,
                ),
              ),
            // Attribution badge
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isPatientDoc
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPatientDoc
                      ? l10n.addedByPatient
                      : (isDoctorOwn ? l10n.myDocument : l10n.doctorDocument),
                  style: TextStyle(
                    fontSize: 11,
                    color: isPatientDoc ? Colors.green : Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                _viewDocument(context, doc.url);
                break;
              case 'edit':
                _showEditDialog(context, doc);
                break;
              case 'delete':
                _confirmDelete(context, doc.id, doc.storagePath);
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
            // Edit/Delete only for doctor's own docs and not read-only
            if (isDoctorOwn && !widget.isReadOnly)
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
            if (isDoctorOwn && !widget.isReadOnly)
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
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
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
                Text(
                  l10n.addDocument,
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
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (nameController.text.isEmpty || selectedType == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.pleaseFillRequiredFields),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(sheetContext);
                      _pickAndUploadFile(
                        context,
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
      ),
    );
  }

  void _showEditDialog(BuildContext context, MedicalDocumentModel doc) {
    String? selectedType = doc.type.toFirestoreString();
    final nameController = TextEditingController(text: doc.name);
    final notesController = TextEditingController(text: doc.notes);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    File? newFile;
    final l10n = AppLocalizations.of(context);
    String fileName = doc.fileName.isNotEmpty ? doc.fileName : l10n.currentFile;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
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
                Text(
                  l10n.updateDocument,
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
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.3)),
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
                            fontWeight:
                                newFile != null ? FontWeight.bold : null,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final result = await FilePicker.pickFiles(
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
                        child:
                            Text(newFile != null ? l10n.change : l10n.replace),
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
                          SnackBar(
                              content: Text(l10n.pleaseFillRequiredFields)),
                        );
                        return;
                      }
                      Navigator.pop(sheetContext);
                      _performUpdate(
                        context,
                        doc: doc,
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
      ),
    );
  }

  Future<void> _performUpdate(
    BuildContext context, {
    required MedicalDocumentModel doc,
    required String newName,
    required String newType,
    required String newNotes,
    File? newFile,
  }) async {
    final docProvider = context.read<DocumentProvider>();
    final l10n = AppLocalizations.of(context);

    bool success;

    if (newFile != null) {
      final bytes = await newFile.readAsBytes();
      final fileName = newFile.path.split(Platform.pathSeparator).last;

      success = await docProvider.updateDocumentWithFile(
        docId: doc.id,
        userId: widget.patientId,
        metaData: {
          'name': newName,
          'type': newType,
          'notes': newNotes,
        },
        bytes: bytes,
        fileName: fileName,
        oldStoragePath: doc.storagePath,
      );
    } else {
      success = await docProvider.updateDocument(doc.id, {
        'name': newName,
        'type': newType,
        'notes': newNotes,
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? l10n.documentUpdated : l10n.updateFailed),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _pickAndUploadFile(
    BuildContext context, {
    required String name,
    required String type,
    required String notes,
  }) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final bytes = await file.readAsBytes();

      if (!context.mounted) return;

      final docProvider = context.read<DocumentProvider>();
      final l10n = AppLocalizations.of(context);

      final success = await docProvider.uploadAndAddDocument(
        userId: widget.patientId,
        name: name,
        type: DocumentType.fromString(type),
        notes: notes,
        bytes: bytes,
        fileName: fileName,
        addedBy: widget.doctorId,
        addedByRole: 'doctor',
        addedByName: widget.doctorName,
        appointmentId: widget.appointmentId,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? l10n.documentUploaded : l10n.uploadFailed),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).uploadFailed}: ${e.toString()}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _viewDocument(BuildContext context, String? url) async {
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
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).couldNotOpenDocument),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
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

  Future<void> _confirmDelete(
    BuildContext context,
    String docId,
    String? storagePath,
  ) async {
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

    if (confirmed == true && context.mounted) {
      final docProvider = context.read<DocumentProvider>();

      final success =
          await docProvider.deleteDocument(docId, storagePath ?? '');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? AppLocalizations.of(context).documentDeleted
                  : AppLocalizations.of(context).somethingWentWrong,
            ),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
      }
    }
  }
}
