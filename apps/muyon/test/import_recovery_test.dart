import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart' hide Invocation;

/// Module side of the protocol: receipts exist only for committed imports.
class _Runtime implements ModuleRuntime {
  final Map<String, ImportReceipt> receipts = {};
  void commit(ImportIntent intent) =>
      receipts[intent.operationId] = ImportReceipt(
        intent: intent,
        result: const {},
        committedAt: DateTime.now(),
      );

  @override
  Future<ImportReceipt?> receipt(String operationId) async =>
      receipts[operationId];
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory root;
  late StorageManager storage;
  late WorkspaceRepository workspaces;
  late ImportCoordinator coordinator;
  late _Runtime runtime;

  Future<ImportIntent> intend(String workspaceId, String project) =>
      coordinator.record(
        PreparedImport(
          target: ImportTarget.create(
            WorkspaceBinding(
              workspaceId: workspaceId,
              moduleId: 'notes',
              nativeProjectId: project,
            ),
          ),
          inputDigest: 'digest-$project',
          stagingToken: 'stage-$project',
        ),
      );
  String status(String op) =>
      workspaces.database.raw.select(
            'SELECT status FROM import_intents WHERE operation_id=?',
            [op],
          ).single['status']
          as String;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('muyon-import-');
    storage = StorageManager(root.path);
    workspaces = WorkspaceRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    coordinator = ImportCoordinator(workspaces);
    runtime = _Runtime();
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'recover binds committed imports once and leaves uncommitted pending',
    () async {
      final a = await workspaces.create('A');
      final b = await workspaces.create('B');
      final committed = await intend(a.id, 'p1');
      final uncommitted = await intend(b.id, 'p2');
      runtime.commit(committed);

      final first = await coordinator.recover('notes', runtime);
      expect(first.activated, [committed.operationId]);
      expect(first.awaitingCommit, [uncommitted.operationId]);
      expect(first.conflicts, isEmpty);
      expect(workspaces.binding(a.id, 'notes')!.nativeProjectId, 'p1');
      expect(workspaces.binding(b.id, 'notes'), isNull);

      final again = await coordinator.recover('notes', runtime);
      expect(again.activated, isEmpty);
      expect(status(committed.operationId), 'complete');
    },
  );

  test(
    'one conflicting intent is recorded and does not block the rest',
    () async {
      final a = await workspaces.create('A');
      final b = await workspaces.create('B');
      final c = await workspaces.create('C');
      final clash = await intend(a.id, 'shared');
      final fine = await intend(c.id, 'p3');
      // Another workspace took the project after the intent was recorded.
      await workspaces.bind(
        WorkspaceBinding(
          workspaceId: b.id,
          moduleId: 'notes',
          nativeProjectId: 'shared',
        ),
      );
      runtime.commit(clash);
      runtime.commit(fine);

      final result = await coordinator.recover('notes', runtime);
      expect(result.conflicts.keys, [clash.operationId]);
      expect(result.conflicts.values.single, contains('another workspace'));
      expect(result.activated, [fine.operationId]);
      expect(status(clash.operationId), 'conflict');
      expect(workspaces.binding(a.id, 'notes'), isNull);
      // The workspace is free for a new import attempt.
      await intend(a.id, 'p4');
    },
  );

  test(
    'abandon frees the workspace only when the module never committed',
    () async {
      final a = await workspaces.create('A');
      final stuck = await intend(a.id, 'p1');
      await expectLater(intend(a.id, 'p2'), throwsStateError);

      runtime.commit(stuck);
      await expectLater(
        coordinator.abandon('notes', runtime, stuck.operationId),
        throwsStateError,
      );
      expect(status(stuck.operationId), 'pending');

      runtime.receipts.clear();
      await coordinator.abandon('notes', runtime, stuck.operationId);
      expect(status(stuck.operationId), 'abandoned');
      await intend(a.id, 'p2');
    },
  );
}
