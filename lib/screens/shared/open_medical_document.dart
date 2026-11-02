import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/medical_document_model.dart';
import '../../services/medical_document_service.dart';
import 'medical_document_viewer_screen.dart';
import 'medical_pdf_viewer_screen.dart';

Future<void> openMedicalDocument(
    BuildContext context, MedicalDocumentModel doc) async {
  final extension = doc.fileName.split('.').last.toLowerCase();
  if (['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => MedicalDocumentViewerScreen(
                imageUrl: '', documentId: doc.id, title: doc.name)));
  } else if (extension == 'pdf' && !kIsWeb) {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => MedicalPdfViewerScreen(
                url: '',
                storagePath: '',
                documentId: doc.id,
                title: doc.name)));
  } else {
    final bytes = await MedicalDocumentService.read(doc.id);
    if (!context.mounted) return;
    // Save authenticated bytes locally. Never hand a public bearer URL to a viewer.
    await FilePicker.saveFile(
        fileName: doc.fileName.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_'),
        bytes: bytes,
        mimeType: extension == 'pdf'
            ? 'application/pdf'
            : extension == 'doc'
                ? 'application/msword'
                : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  }
}
