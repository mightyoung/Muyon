import 'dart:convert';
import 'dart:io';

import 'support/conversation_workspace_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart';
import '../../../packages/muyon_ui/test/aiui5_revision2_review_test.dart' show reviewPlan;
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
  test('library2 collection and edited stable IDs survive actual SQLite close reopen', () async {
    final plan = reviewPlan('Choice');
    final c = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: store.scopeKey!,
      plan: plan,
      schemaVersion: 2,
    );
    c.surface.session.edit('k', ['b']);
    expect(c.surface.session.selections['k'], ['b']);
    await c.flush();
    c.dispose();
    await storage.close();
    await open();
    final restored = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: store.scopeKey!,
      plan: plan,
      schemaVersion: 2,
    );
    addTearDown(restored.dispose);
    expect(restored.readOnly, isFalse);
    expect(restored.surface.session.selections['k'], ['b']);
    expect(restored.surface.session.selectionOverrides, contains('k'));
    expect(restored.surface.session.draftRevision, 1);
  });
  for (final damage in ['future-kind', 'future-schema', 'duplicate-ids']) {
    test('damaged schema2 $damage retains original SQLite bytes and readable IDs read only', () async {
      final plan = reviewPlan('Choice');
      final c = await UiWorkspaceController.open(store: store, taskId: 'task', scopeKey: store.scopeKey!, plan: plan);
      c.surface.session.edit('k', ['b']); await c.flush(); c.dispose();
      final key = 'ui-workspace:${jsonEncode(['task', 's'])}';
      final raw = jsonDecode(repo.database.raw.select('SELECT value FROM settings WHERE key=?', [key]).single['value'] as String) as Map<String,dynamic>;
      if (damage == 'future-kind') {
        (raw['presentation']['nodes'] as List).firstWhere((n) => n['id']=='target')['bindings']['options']['kind'] = 'future_collection';
      } else if (damage == 'future-schema') {
        raw['schemaVersion'] = 3;
      } else { raw['selections']['k'] = ['b','b']; }
      final bytes = jsonEncode(raw);
      await repo.database.write((db) => db.execute('UPDATE settings SET value=? WHERE key=?', [bytes,key]));
      var calls = 0;
      final restored = await UiWorkspaceController.open(store: store, taskId:'task',scopeKey:store.scopeKey!,plan:plan,onEvent:(_) async { calls++; });
      addTearDown(restored.dispose);
      expect(restored.readOnly,isTrue); expect(restored.saveError,'workspace_codec');
      expect(restored.readableDraft!['k'], damage=='duplicate-ids' ? ['b','b'] : ['b']);
      expect(restored.surface.session.selections['k'], ['a']);
      final submit=restored.surface.current.plan.nodes.firstWhere((n)=>n.id=='approval');
      expect(await restored.surface.dispatch(restored.surface.eventFor(submit,'submit')),UiDispatchOutcome.stale); expect(calls,0);
      await expectLater(restored.flush(), throwsStateError);
      expect(repo.database.raw.select('SELECT value FROM settings WHERE key=?',[key]).single['value'],bytes);
    });
  }
  test('oversized new checkpoint refuses write and retains the existing SQLite revision', () async {
    await store.save(value(1),expectedRevision:0);
    final before=(await store.load('surface'))!.toJson();
    await expectLater(store.save(value(2,qty:'x' * UiWorkspaceLimits.bytes),expectedRevision:1),throwsArgumentError);
    expect((await store.load('surface'))!.toJson(),before);
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

  testWidgets('shell_checkpoint_cas_conflict_does_not_pop_or_overwrite', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await workspaceOperation(tester, storage.close);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? openWorkspace;
    var businessCalls = 0;
    final plan = actionPlan();
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, open) {
      openWorkspace = open;
      return const Scaffold(body: Text('parent conversation'));
    })));
    await openWorkspace!(DynamicWorkspace(
      repository: repo, taskId: 'task', surfaceId: plan.plan.surfaceId, plan: plan,
      onEvent: (_) async { businessCalls++; },
    ));
    await workspaceReady(tester);
    final body = find.byType(ConversationWorkspaceBody);
    final c = tester.widget<ConversationWorkspaceBody>(body).controller;
    await workspaceOperation(tester, c.flush);
    final competingStore = HostUiWorkspaceStore(repo, taskId: 'task');
    final competing = await workspaceOperation(tester, () => UiWorkspaceController.open(
      store: competingStore, taskId: 'task', scopeKey: competingStore.scopeKey!, plan: plan,
    ));
    competing.step = 'winner projection';
    await workspaceOperation(tester, competing.flush);
    final winner = (await competingStore.load(plan.plan.surfaceId))!.toJson();
    competing.dispose();
    await tester.enterText(find.byType(TextField).first, 'losing input retained');
    await workspaceOperation(tester, () async {
      try { await c.flush(); } catch (_) { /* expected CAS failure */ }
    });
    await tester.pumpAndSettle();
    expect(c.readOnly, isTrue);
    expect(find.textContaining('losing input retained'), findsWidgets);
    expect(find.textContaining('未保存'), findsWidgets);
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await tester.pumpAndSettle();
    expect(body, findsOneWidget);
    expect(find.textContaining('losing input retained'), findsWidgets);
    expect((await competingStore.load(plan.plan.surfaceId))!.toJson(), winner);
    expect(businessCalls, 0);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

}
