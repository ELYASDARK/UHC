import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Web implementation – triggers a browser download.
Future<void> saveAndShareFile(
  List<int> bytes,
  String fileName, {
  String? subject,
}) async {
  final uint8 = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [uint8.toJS].toJS,
    web.BlobPropertyBag(
      type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
