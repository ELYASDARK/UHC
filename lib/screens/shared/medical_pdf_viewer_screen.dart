import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../services/medical_document_service.dart';
import '../../l10n/app_localizations.dart';

/// Native rendering, using authenticated Storage reads rather than bearer URLs
/// or a remote PDF conversion service. Each opening fetches the current bytes.
class MedicalPdfViewerScreen extends StatefulWidget {
  final String documentId;
  final String url;
  final String storagePath;
  final String title;

  const MedicalPdfViewerScreen({
    super.key,
    this.documentId = '',
    required this.url,
    required this.storagePath,
    required this.title,
  });

  @override
  State<MedicalPdfViewerScreen> createState() => _MedicalPdfViewerScreenState();
}

class _MedicalPdfViewerScreenState extends State<MedicalPdfViewerScreen> {
  PdfControllerPinch? _controller;
  PdfController? _windowsController;
  PdfDocument? _document;
  Directory? _temporaryDirectory;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    Directory? directory;
    PdfDocument? document;
    try {
      final bytes = await MedicalDocumentService.read(widget.documentId);
      if (bytes.isEmpty) {
        throw const FormatException('Empty document');
      }
      // Own the private temporary file so it can be removed on close/error.
      // pdfx.openData would create an unmanaged copy in the platform cache.
      directory = await (await getTemporaryDirectory()).createTemp('uhc-pdf-');
      final file = File('${directory.path}/document.pdf');
      await file.writeAsBytes(bytes, flush: true);
      document = await PdfDocument.openFile(file.path);
      if (!mounted || generation != _generation) {
        await document.close();
        await directory.delete(recursive: true);
        return;
      }
      _document = document;
      _temporaryDirectory = directory;
      setState(() {
        // pdfx's pinch renderer does not support Windows. Its paged viewer does.
        if (Platform.isWindows) {
          _windowsController = PdfController(document: Future.value(document!));
        } else {
          _controller = PdfControllerPinch(document: Future.value(document!));
        }
      });
    } catch (_) {
      if (document != null && !document.isClosed) await document.close();
      if (directory != null) await directory.delete(recursive: true);
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  Future<void> _release(PdfDocument? document, Directory? directory) async {
    try {
      if (document != null && !document.isClosed) await document.close();
    } finally {
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    _windowsController?.dispose();
    unawaited(_release(_document, _temporaryDirectory));
    super.dispose();
  }

  Widget _error(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      key: const ValueKey('medical-pdf-error'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.picture_as_pdf_outlined, size: 56),
          const SizedBox(height: 16),
          Text(l10n.couldNotOpenDocument, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              final previousDocument = _document;
              final previousDirectory = _temporaryDirectory;
              setState(() {
                _failed = false;
                _controller?.dispose();
                _windowsController?.dispose();
                _controller = null;
                _windowsController = null;
                _document = null;
                _temporaryDirectory = null;
              });
              await _release(previousDocument, previousDirectory);
              if (mounted) await _load();
            },
            child: Text(l10n.retry),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.title,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: _failed
            ? _error(context)
            : _controller == null && _windowsController == null
                ? const Center(
                    key: ValueKey('medical-pdf-loading'),
                    child: CircularProgressIndicator())
                : _windowsController != null
                    ? PdfView(
                        controller: _windowsController!,
                        builders: PdfViewBuilders<DefaultBuilderOptions>(
                          options: const DefaultBuilderOptions(),
                          documentLoaderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          pageLoaderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          errorBuilder: (context, _) => _error(context),
                        ),
                      )
                    : PdfViewPinch(
                        key: const ValueKey('medical-pdf-pages'),
                        controller: _controller!,
                        maxScale: 8,
                        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                          options: const DefaultBuilderOptions(),
                          documentLoaderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          pageLoaderBuilder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                          errorBuilder: (context, _) => _error(context),
                        ),
                      ),
      );
}
