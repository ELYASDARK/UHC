import 'package:firebase_core/firebase_core.dart';

import '../config/emulator_config.dart';

/// Only the configured bucket and the app's document namespaces are viewable.
bool isTrustedMedicalDocumentUrl(Uri uri, FirebaseOptions options) {
  final parts = uri.pathSegments;
  if (parts.length != 5 ||
      parts[0] != 'v0' ||
      parts[1] != 'b' ||
      parts[2] != options.storageBucket ||
      parts[3] != 'o' ||
      !(parts[4].startsWith('medical_documents/') ||
          parts[4].startsWith('medical_document_replacement_files/'))) {
    return false;
  }
  if (uri.scheme == 'https' &&
      uri.host == 'firebasestorage.googleapis.com' &&
      uri.port == 443) {
    return true;
  }
  return EmulatorConfig.isEmulatorEnabled &&
      options.projectId == EmulatorConfig.demoProjectId &&
      uri.scheme == 'http' &&
      uri.host == EmulatorConfig.loopbackHost &&
      uri.port == 9199;
}
