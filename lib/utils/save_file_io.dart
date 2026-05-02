import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobile / desktop implementation – writes to temp dir and opens share sheet.
Future<void> saveAndShareFile(
  List<int> bytes,
  String fileName, {
  String? subject,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
      subject: subject,
    ),
  );
}
