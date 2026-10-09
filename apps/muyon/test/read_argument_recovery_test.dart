import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  test('query invalid field has a typed invalidArguments receipt', () async {
    final root = Directory.systemTemp.createTempSync('read-arguments-');
    final host = await MuyonHost.open('${root.path}/data');
    try {
      final result = await host.tools.invoke(
        ToolCallRequest(
          invocationId: 'bad-query-field',
          toolId: 'inquiry.query',
          scope: const AssistantScope.global(),
          parameters: {
            'type': 'product',
            'where': [
              {'field': 'invented_field', 'op': 'eq', 'value': 'x'},
            ],
          },
        ),
      );
      expect(result.status.name, 'invalidArguments');
      expect(result.summary, contains('invented_field'));
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
}
