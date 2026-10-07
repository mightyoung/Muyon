import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

void main() {
  test('catalog routes disappear when the VM is not debug', () {
    if (const bool.fromEnvironment('dart.vm.profile'))
      expect(kDebugMode, isFalse);
    if (const bool.fromEnvironment('EXPECT_NONDEBUG'))
      expect(kDebugMode, isFalse);
    expect(muyonDebugRoutes().isEmpty, !kDebugMode);
  });
}
