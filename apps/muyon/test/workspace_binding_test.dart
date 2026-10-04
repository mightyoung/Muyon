import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  test('bindings are unique, string IDs survive and no fallback', () async {
    final root = Directory.systemTemp.createTempSync('muyon-binding-');
    final host = await MuyonHost.open(root.path);
    try {
      final a = await host.workspaces.create('A');
      final b = await host.workspaces.create('B');
      final bindA = WorkspaceBinding(
        workspaceId: a.id,
        moduleId: 'research',
        nativeProjectId: 'native-string-a',
      );
      await host.workspaces.bind(bindA);
      expect(host.workspaces.binding(b.id, 'research'), isNull);
      await expectLater(
        host.workspaces.bind(
          WorkspaceBinding(
            workspaceId: b.id,
            moduleId: 'research',
            nativeProjectId: 'native-string-a',
          ),
        ),
        throwsA(anything),
      );
      expect(
        host.workspaces.binding(a.id, 'research')!.nativeProjectId,
        'native-string-a',
      );
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
}
