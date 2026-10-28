// ignore_for_file: depend_on_referenced_packages
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/l10n/app_localizations.dart';
import 'package:uhc/screens/shared/medical_pdf_viewer_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  testWidgets('untrusted PDF fails visibly, can retry and return to the list',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const MedicalPdfViewerScreen(
                                  url: 'https://example.invalid/private.pdf',
                                  storagePath:
                                      'medical_documents/synthetic/self/document.pdf',
                                  title: 'Synthetic document',
                                ))),
                    child: const Text('Open document')),
              )),
    ));
    await tester.tap(find.text('Open document'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medical-pdf-error')), findsOneWidget);
    expect(find.text('Could not open the document'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('medical-pdf-error')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open document'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
