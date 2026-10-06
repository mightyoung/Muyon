import 'dart:io';
import 'dart:async';

import 'package:muyon/app/bootstrap.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/execution_store.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  test('host close drains platform operation rejects new work and persists outcome', () async {
    final root = Directory.systemTemp.createTempSync('host-operation-drain');
    final host = await MuyonHost.open(root.path);
    final entered = Completer<void>(), release = Completer<void>();
    try {
      final running = host.runPlatformOperation('transfer', () async {
        entered.complete();
        await release.future;
        return 'completed transfer';
      });
      await entered.future;
      final taskId = host.foundation.tasks().single.id;
      var closed = false;
      final closing = host.close().then((_) {
        closed = true;
      });
      await expectLater(
        host.trackOperation(() async => 'late'),
        throwsStateError,
      );
      await expectLater(
        host.runPlatformOperation('late', () async => 'late'),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      release.complete();
      expect(await running, 'completed transfer');
      await closing;
      final reopen = StorageManager(root.path);
      try {
        final repo = FoundationRepository(
          await reopen.open('muyon', WorkspaceRepository.schema),
        );
        expect(repo.task(taskId)!.state, PersonalTaskState.succeeded);
        expect(repo.task(taskId)!.summary, 'completed transfer');
      } finally {
        await reopen.close();
      }
    } finally {
      if (!release.isCompleted) release.complete();
      await host.close();
      root.deleteSync(recursive: true);
    }
  });

  test('host v1 upgrades in place preserving workspace settings legacy task and authority', () async {
    final root = Directory.systemTemp.createTempSync('foundation-upgrade');
    var manager = StorageManager(root.path);
    try {
      final v1 = ModuleSchema(
        version: 1,
        definitionDigest: 'muyon-host-v1',
        migrations: [WorkspaceRepository.schema.migrations.first],
      );
      var db = await manager.open('muyon', v1);
      var workspaces = WorkspaceRepository(db);
      final workspace = await workspaces.create('Existing workspace');
      await workspaces.setSetting('deviceId', 'original-device');
      await workspaces.setSetting('theme', 'dark');
      final now = DateTime.now().toUtc();
      await ExecutionStore(db).create(
        AgentExecutionRecord(
          executionId: 'legacy-qa',
          toolId: 'qa.answer',
          contextSnapshot: ContextRef(
            workspaceId: workspace.id,
            moduleId: 'research',
            nativeProjectId: 'project',
          ),
          executionDeviceId: 'original-device',
          state: ExecutionState.queued,
          stage: 'queued',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final legacyPayload = db.raw
          .select("SELECT payload FROM execution_records WHERE id='legacy-qa'")
          .single['payload'];
      await manager.close();
      manager = StorageManager(root.path);
      db = await manager.open('muyon', WorkspaceRepository.schema);
      workspaces = WorkspaceRepository(db);
      expect(db.raw.userVersion, WorkspaceRepository.schema.version);
      expect(workspaces.all().single.id, workspace.id);
      expect(workspaces.setting('deviceId'), 'original-device');
      expect(workspaces.setting('theme'), 'dark');
      expect(
        db.raw
            .select(
              "SELECT payload FROM execution_records WHERE id='legacy-qa'",
            )
            .single['payload'],
        legacyPayload,
      );
      final foundation = FoundationRepository(db);
      final conversation = await foundation.createConversation(
        scope: AssistantScope.workspace(workspace.id),
      );
      await foundation.appendMessage(
        conversation.id,
        'user',
        'Retained context',
      );
      await foundation.createTask(
        PersonalTask({
          'kind': 'personal',
          'executionId': 'personal-task',
          'conversationId': conversation.id,
          'prompt': 'hello',
          'scope': conversation.scope.toJson(),
          'state': 'queued',
          'stage': 'queued',
          'executionDeviceId': 'original-device',
          'updatedAt': now.toIso8601String(),
        }),
      );
      expect(ExecutionStore(db).all().single.executionId, 'legacy-qa');
      expect(foundation.tasks().single.id, 'personal-task');
      expect(db.raw.select('SELECT id FROM execution_records').length, 2);
      final tables = db.raw
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      for (final duplicate in [
        'tasks',
        'personal_tasks',
        'assistant_tasks',
        'devices',
        'assistant_settings',
        'assistant_workspaces',
      ]) {
        expect(tables, isNot(contains(duplicate)));
      }
      expect(
        db.raw
            .select('SELECT version FROM schema_migrations ORDER BY version')
            .map((r) => r['version']),
        [for (final m in WorkspaceRepository.schema.migrations) m.version],
      );
      await manager.close();
      manager = StorageManager(root.path);
      db = await manager.open('muyon', WorkspaceRepository.schema);
      expect(
        FoundationRepository(db).messages(conversation.id).single.content,
        'Retained context',
      );
      expect(ExecutionStore(db).all().single.executionId, 'legacy-qa');
    } finally {
      await manager.close();
      root.deleteSync(recursive: true);
    }
  });
}
