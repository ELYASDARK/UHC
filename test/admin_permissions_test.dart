import 'package:flutter_test/flutter_test.dart';
import 'package:uhc/data/models/admin_permissions_model.dart';

void main() {
  test('an admin with no saved permission map receives no permissions', () {
    final permissions = AdminPermissions.fromMap(null);

    for (final key in AdminPermissions.allKeys) {
      expect(permissions.getByKey(key), isFalse, reason: key);
    }
  });

  test('a partial permission map grants only explicitly enabled permissions', () {
    final permissions = AdminPermissions.fromMap({
      'users.view': true,
      'users.manageNonAdmin': false,
    });

    for (final key in AdminPermissions.allKeys) {
      expect(permissions.getByKey(key), key == 'users.view', reason: key);
    }
  });
}
