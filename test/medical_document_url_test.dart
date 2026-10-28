import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/core/utils/medical_document_url.dart';

void main() {
  const options = FirebaseOptions(
    apiKey: 'synthetic',
    appId: 'synthetic',
    messagingSenderId: '0',
    projectId: 'demo-uhc-test',
    storageBucket: 'demo-uhc-test.appspot.com',
  );

  test('viewer accepts document namespaces in its own bucket only', () {
    final bucket = options.storageBucket!;
    for (final prefix in [
      'medical_documents/patient/self/file.png',
      'medical_document_replacement_files/document/operation'
    ]) {
      final path = Uri.encodeComponent(prefix);
      expect(
          isTrustedMedicalDocumentUrl(
              Uri.parse(
                'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$path?alt=media&token=synthetic',
              ),
              options),
          isTrue);
      for (final url in [
        'https://evil.example/v0/b/$bucket/o/$path',
        'https://firebasestorage.googleapis.com.evil.example/v0/b/$bucket/o/$path',
        'https://firebasestorage.googleapis.com/v0/b/another-bucket/o/$path',
        'http://firebasestorage.googleapis.com/v0/b/$bucket/o/$path',
        'http://127.0.0.1:9199/v0/b/$bucket/o/$path',
        'https://firebasestorage.googleapis.com/v0/b/$bucket/o/profile_images%2Ffile.png',
      ]) {
        expect(isTrustedMedicalDocumentUrl(Uri.parse(url), options), isFalse,
            reason: url);
      }
    }
  });
}
