// Conditional export: web uses package:web, IO uses dart:io + path_provider
export 'save_file_stub.dart'
    if (dart.library.js_interop) 'save_file_web.dart'
    if (dart.library.io) 'save_file_io.dart';
