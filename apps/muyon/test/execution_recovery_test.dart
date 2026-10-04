import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/execution_store.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  test(
    'restart interrupts unfinished records and preserves terminal records',
    () async {
      final temp = Directory.systemTemp.createTempSync('execution-test');
      addTearDown(() => temp.deleteSync(recursive: true));
      var manager = StorageManager(temp.path);
      var store = ExecutionStore(
        await manager.open('muyon', WorkspaceRepository.schema),
      );
      final now = DateTime.now().toUtc();
      for (final id in ['queued', 'running', 'done']) {
        await store.create(
          AgentExecutionRecord(
            executionId: id,
            toolId: 'qa.answer',
            contextSnapshot: ContextRef(
              workspaceId: 'w',
              moduleId: 'research',
              nativeProjectId: 'p',
            ),
            executionDeviceId: 'device',
            state: ExecutionState.queued,
            stage: 'queued',
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await store.transition('running', ExecutionState.running);
      await store.transition(
        'done',
        ExecutionState.succeeded,
        answer: 'retained',
      );
      await manager.close();
      manager = StorageManager(temp.path);
      store = ExecutionStore(
        await manager.open('muyon', WorkspaceRepository.schema),
      );
      await store.recoverInterrupted();
      expect(store.get('queued')!.state, ExecutionState.interrupted);
      expect(store.get('running')!.state, ExecutionState.interrupted);
      expect(store.answer('done'), 'retained');
      expect(
        await store.transition(
          'running',
          ExecutionState.succeeded,
          answer: 'late',
        ),
        false,
      );
      expect(store.answer('running'), null);
      await manager.close();
    },
  );
}
