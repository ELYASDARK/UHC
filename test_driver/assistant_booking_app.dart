import 'package:flutter/foundation.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:uhc/core/config/emulator_config.dart';
import 'package:uhc/main.dart' as app;

void main() {
  if (!kDebugMode || !EmulatorConfig.isEmulatorEnabled) {
    throw StateError('Assistant UI automation requires debug emulator mode.');
  }
  enableFlutterDriverExtension();
  app.main();
}
