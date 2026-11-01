import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../core/config/emulator_config.dart';

/// Reads current document bytes after the server checks current access.
/// Stored download URLs are deliberately never used.
class MedicalDocumentService {
  static const maxBytes = 20 * 1024 * 1024;

  static Future<Uint8List> read(String documentId) async {
    if (!RegExp(r'^[\w-]{1,128}$').hasMatch(documentId)) {
      throw const FormatException('Invalid document identifier.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in to open this document.');
    final token = await user.getIdToken();
    if (token == null) throw StateError('Sign in to open this document.');
    final project = Firebase.app().options.projectId;
    final base = EmulatorConfig.isEmulatorEnabled &&
            project == EmulatorConfig.demoProjectId
        ? 'http://${EmulatorConfig.loopbackHost}:5001/$project/us-central1'
        : 'https://us-central1-$project.cloudfunctions.net';
    final client = http.Client();
    try {
      final request = http.Request(
          'GET',
          Uri.parse('$base/readMedicalDocument')
              .replace(queryParameters: {'documentId': documentId}))
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer $token';
      final response =
          await client.send(request).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 ||
          (response.contentLength ?? 0) >= maxBytes) {
        throw StateError('Document is unavailable.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 60))) {
        if (bytes.length + chunk.length >= maxBytes) {
          throw StateError('Document is too large.');
        }
        bytes.add(chunk);
      }
      if (bytes.isEmpty) throw StateError('Document is empty.');
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  }
}
