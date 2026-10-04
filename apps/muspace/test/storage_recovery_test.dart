import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muspace/app/bootstrap.dart';
import 'package:muspace/workspace/import_coordinator.dart';
import 'package:muspace_module_api/muspace_module_api.dart';

void main() {
  test(
    'domain commit interrupted before host activation repairs once on restart',
    () async {
      final root = Directory.systemTemp.createTempSync('muspace-recovery-');
      final source = Directory.systemTemp.createTempSync('muspace-research-');
      File('${source.path}/report.md')
          .writeAsStringSync('# Real input snapshot\nResearch text.');
      var host = await MuSpaceHost.open(root.path);
      try {
        await host.activateResearch();
        expect(host.researchError, isNull);
        final workspace = await host.workspaces.create('Research');
        final binding = WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'research',
          nativeProjectId: 'research-preassigned',
        );
        final prepared = await host.research!.prepareImport(
          SelectedInput(path: source.path, displayName: 'Research'),
          ImportTarget.create(binding),
        );
        final coordinator = ImportCoordinator(host.workspaces);
        final intent = await coordinator.record(
          prepared,
          operationId: 'operation-1',
        );
        await expectLater(
          coordinator.commit(
            host.research!,
            prepared,
            intent,
            interruptBeforeActivation: true,
          ),
          throwsStateError,
        );
        expect(host.workspaces.binding(workspace.id, 'research'), isNull);
        expect(host.research!.store.projects(), hasLength(1));
        await host.close();
        host = await MuSpaceHost.open(root.path);
        await host.activateResearch();
        expect(host.researchError, isNull);
        expect(
          host.workspaces.binding(workspace.id, 'research')!.nativeProjectId,
          'research-preassigned',
        );
        expect(host.research!.store.projects(), hasLength(1));
        final replay = await host.research!.commitImport(prepared, intent);
        expect(replay.operationId, 'operation-1');
        expect(host.research!.store.projects(), hasLength(1));
        final conflicting = ImportIntent(
          operationId: intent.operationId,
          workspaceId: intent.workspaceId,
          moduleId: intent.moduleId,
          targetProjectId: intent.targetProjectId,
          kind: intent.kind,
          inputDigest: 'changed',
          stagingToken: intent.stagingToken,
        );
        await expectLater(
          host.research!.commitImport(
            PreparedImport(
              target: prepared.target,
              inputDigest: 'changed',
              stagingToken: prepared.stagingToken,
            ),
            conflicting,
          ),
          throwsStateError,
        );
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
        source.deleteSync(recursive: true);
      }
    },
  );

  test('pending frozen input can retry after external input changes', () async {
    final root = Directory.systemTemp.createTempSync('muspace-retry-');
    final source = Directory.systemTemp.createTempSync('muspace-research-');
    File('${source.path}/report.md').writeAsStringSync('Frozen original');
    var host = await MuSpaceHost.open(root.path);
    try {
      await host.activateResearch();
      final workspace = await host.workspaces.create('Research');
      final binding = WorkspaceBinding(
        workspaceId: workspace.id,
        moduleId: 'research',
        nativeProjectId: 'frozen-project',
      );
      final prepared = await host.research!.prepareImport(
        SelectedInput(path: source.path, displayName: 'Research'),
        ImportTarget.create(binding),
      );
      final intent = await ImportCoordinator(host.workspaces).record(prepared);
      File('${source.path}/report.md').writeAsStringSync('Changed external');
      await host.close();
      host = await MuSpaceHost.open(root.path);
      await host.activateResearch();
      await ImportCoordinator(host.workspaces)
          .commit(host.research!, prepared, intent);
      final document = host.research!.store
          .documents(binding.nativeProjectId)
          .single;
      expect(File(document.absolutePath).readAsStringSync(), 'Frozen original');
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
      source.deleteSync(recursive: true);
    }
  });
}
