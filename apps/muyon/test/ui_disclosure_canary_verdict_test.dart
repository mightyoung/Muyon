import 'package:flutter_test/flutter_test.dart';

import 'support/ui_disclosure_independent_helpers.dart';

// C6-FIX-1 M-1: an unknown-field canary proves nothing unless the public store
// kept the field. Without that precondition the verdict is "unwired", never a
// pass, so a clean prompt cannot hide a missing canary.
void main() {
  test('an unstored canary is unwired even when nothing leaked', () {
    expect(canaryVerdict(stored: false, leaked: false), CanaryVerdict.unwired);
  });

  test('a stored canary that leaked fails', () {
    expect(canaryVerdict(stored: true, leaked: true), CanaryVerdict.leaked);
  });

  test('a stored canary that did not leak passes', () {
    expect(canaryVerdict(stored: true, leaked: false), CanaryVerdict.pass);
  });
}
