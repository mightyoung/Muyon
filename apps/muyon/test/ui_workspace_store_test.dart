import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;

void main() {
  late Directory root;
  late StorageManager storage;
  late FoundationRepository repo;
  late HostUiWorkspaceStore store;
  Future<void> open() async {
    storage = StorageManager(root.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    store = HostUiWorkspaceStore(repo, taskId: 'task');
  }

  StoredUiWorkspace value(int revision, {String qty = '12', String? scope}) =>
      StoredUiWorkspace(
        taskId: 'task',
        surfaceId: 'surface',
        scopeKey: scope ?? store.scopeKey!,
        revision: revision,
        schemaVersion: 1,
        catalogVersion: 'v1',
        snapshotRef: const SnapshotRef('s', 1),
        intentRef: 'i',
        planRevision: 1,
        draftRevision: 1,
        extracted: {'qty': '11'},
        userOverrides: {'qty': qty},
        nodeIds: ['qty'],
        selectedRecords: ['record-a'],
        step: 'review',
      );
  setUp(() async {
    root = Directory.systemTemp.createTempSync('ui3b-store-');
    await open();
    await repo.database.write(
      (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
        'task',
        'paused',
        jsonEncode({
          'kind': 'personal',
          'executionId': 'task',
          'scope': AssistantScope.workspace('w1').toJson(),
        }),
      ]),
    );
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });
  test(
    'edited value survives SQLite close reopen with version and selection',
    () async {
      expect(await store.save(value(1), expectedRevision: 0), isTrue);
      await storage.close();
      await open();
      final restored = (await store.load('surface'))!;
      expect(restored.displayValues['qty'], '12');
      expect(restored.selectedRecords, ['record-a']);
      expect(restored.revision, 1);
      expect(repo.database.raw.userVersion, 12);
    },
  );
  test('concurrent compare and swap permits one writer and rollback retains old data', () async {
    await store.save(value(1), expectedRevision: 0);
    final results = await Future.wait([
      store.save(value(2, qty: '13'), expectedRevision: 1),
      store.save(value(2, qty: '14'), expectedRevision: 1),
    ]);
    expect(results.where((v) => v), hasLength(1));
    final before = (await store.load('surface'))!.toJson();
    repo.database.raw.execute(
      "CREATE TEMP TRIGGER fail_ui BEFORE UPDATE ON settings BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    await expectLater(
      store.save(value(3), expectedRevision: 2),
      throwsA(anything),
    );
    expect((await store.load('surface'))!.toJson(), before);
  });
  test('scope changes cannot widen restore or overwrite old draft', () async {
    final old = value(1);
    await store.save(old, expectedRevision: 0);
    await repo.database.write(
      (db) => db.execute(
        "UPDATE execution_records SET payload=json_set(payload,'\$.scope',json(?)) WHERE id='task'",
        [jsonEncode(const AssistantScope.global().toJson())],
      ),
    );
    expect(await store.load('surface'), isNull);
    expect(
      await store.save(old.copyWith(revision: 2), expectedRevision: 1),
      isFalse,
    );
    expect(await store.save(value(2), expectedRevision: 1), isFalse);
  });
  test('two_real_store_instances_reject_losing_projection_and_keep_input', () async {
    final plan = actionPlan();
    final firstStore = HostUiWorkspaceStore(repo, taskId: 'task');
    final secondStore = HostUiWorkspaceStore(repo, taskId: 'task');
    final first = await UiWorkspaceController.open(
      store: firstStore, taskId: 'task', scopeKey: firstStore.scopeKey!, plan: plan,
    );
    final second = await UiWorkspaceController.open(
      store: secondStore, taskId: 'task', scopeKey: secondStore.scopeKey!, plan: plan,
      onEvent: (_) async => fail('A conflicting projection must never dispatch'),
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final field = plan.plan.nodes.firstWhere((n) => n.component == 'Field');
    await first.surface.dispatch(first.surface.eventFor(field, 'change', 'winner'));
    await first.flush();
    final committed = (await firstStore.load(plan.plan.surfaceId))!.toJson();
    await second.surface.dispatch(second.surface.eventFor(field, 'change', 'unsaved loser'));
    await expectLater(second.flush(), throwsStateError);
    expect(second.readOnly, isTrue);
    expect(second.saveError, isNotNull);
    expect(second.surface.session.userOverrides['quantity'], 'unsaved loser');
    expect((await secondStore.load(plan.plan.surfaceId))!.toJson(), committed);
  });

}
