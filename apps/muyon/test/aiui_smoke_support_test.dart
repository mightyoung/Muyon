import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/north_star_settings.dart';

void main() {
  test('formal smoke refuses missing real model configuration with a stable code', () {
    // The existing device settings reader permits fixture mode. A formal smoke
    // must reject that outcome rather than silently running offline evidence.
    expect(
      NorthStarModelSettings.fromEnvironment,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'stable error code',
          'real_model_configuration_missing',
        ),
      ),
    );
  });
}
