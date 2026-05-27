import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin notification target chips set explicit light and dark colors',
      () {
    final source = File(
      'lib/screens/admin/notifications/admin_notification_sender_screen.dart',
    ).readAsStringSync();

    expect(source, contains('checkmarkColor: titleColor'));
    expect(source, contains('AppColors.textPrimaryDark'));
    expect(source, contains('AppColors.textPrimaryLight'));
    expect(source, contains('AppColors.primaryLight'));
    expect(source, contains('style: TextStyle(color: titleColor)'));
  });
}
