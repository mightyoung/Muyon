import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/platform/ui_navigation_anchors.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'support/ui_navigation_fixture.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart';

void main() {
  late Directory root;
  late StorageManager storage;
  late FoundationRepository repo;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('ui3b-return-');
    storage = StorageManager(root.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
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
  testWidgets('shell_object_return_restores_manual_value_node_scroll_and_revision', (tester) async {
    final f = await NavigationFixture.open(tester);
    final ref = await f.seedObject(tester, 'research');
    final plan = f.plan(ref);
    Future<void> show(MuyonHost host) async {
      await tester.pumpWidget(MaterialApp(home: DynamicWorkspace(
        repository: host.foundation, taskId: 'task', surfaceId: plan.plan.surfaceId,
        plan: plan, originalAnswer: List.filled(80, '原回答保留').join('\n'), host: host,
      )));
      await tester.pumpAndSettle();
    }
    await show(f.host);
    await tester.enterText(find.byType(TextField).first, 'manually edited');
    final c = tester.widget<UiWorkspaceView>(find.byType(UiWorkspaceView)).controller;
    c.selectedRecords = ['record-a'];
    c.step = 'review';
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -30));
    await tester.pumpAndSettle();
    expect(c.scrollOffset, greaterThan(0));
    // Keep the reference target visible while retaining a nonzero offset.
    await tester.tap(find.text('查看对象 · research'));
    await tester.pumpAndSettle();
    expect(find.text('真实研究对象'), findsWidgets);
    final store = HostUiWorkspaceStore(f.host.foundation, taskId: 'task');
    final saved = (await store.load(plan.plan.surfaceId))!;
    final anchor = (await store.loadNavigationAnchor(plan.plan.surfaceId))!;
    expect(saved.userOverrides['quantity'], 'manually edited');
    expect(saved.draftRevision, greaterThan(0));
    expect(saved.nodeIds, contains(anchor.nodeId));
    expect(anchor.objectRef, ref);
    expect(anchor.taskId, 'task');
    expect(anchor.surfaceId, plan.plan.surfaceId);
    expect(anchor.conversationId, f.conversationId);
    expect(anchor.scrollOffset, saved.scrollOffset);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'manually edited');
    expect(c.selectedRecords, saved.selectedRecords);
    expect(c.step, saved.step);
    expect(c.scrollOffset, saved.scrollOffset);
    await tester.runAsync(c.flush);
    final committed = (await store.load(plan.plan.surfaceId))!;
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(f.host.close);
    final reopenedHost = (await tester.runAsync(() => MuyonHost.open('${f.root.path}/data')))!;
    try {
      final reopenedStore = HostUiWorkspaceStore(reopenedHost.foundation, taskId: 'task');
      expect((await reopenedStore.load(plan.plan.surfaceId))!.toJson(), committed.toJson());
      await show(reopenedHost);
      final restored = tester.widget<UiWorkspaceView>(find.byType(UiWorkspaceView)).controller;
      expect(restored.surface.session.userOverrides, committed.userOverrides);
      expect(restored.surface.session.draftRevision, committed.draftRevision);
      expect(restored.returnAnchor, committed.returnAnchor);
      expect(restored.selectedRecords, committed.selectedRecords);
      expect(restored.surface.current.plan.nodes.map((n) => n.id), committed.nodeIds);
      expect(restored.scrollOffset, committed.scrollOffset);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(reopenedHost.close);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('snapshot_refresh_keeps_user_override_and_marks_version_change', (tester) async {
    final f = await NavigationFixture.open(tester);
    final ref = await f.seedObject(tester, 'research');
    final old = f.plan(ref);
    Future<void> showVersion(ValidatedUiPlan plan) async {
      await tester.pumpWidget(MaterialApp(home: DynamicWorkspace(
        repository: f.host.foundation, host: f.host, taskId: 'task',
        surfaceId: plan.plan.surfaceId, plan: plan, originalAnswer: '原对话回答',
      )));
      await tester.pumpAndSettle();
    }
    await showVersion(old);
    await tester.enterText(find.byType(TextField).first, 'manual priority');
    final c = tester.widget<UiWorkspaceView>(find.byType(UiWorkspaceView)).controller;
    await tester.runAsync(c.flush);
    await tester.pumpWidget(const SizedBox());
    final snapshot = DataSnapshot(
      ref: SnapshotRef(old.snapshot.ref.id, old.snapshot.ref.revision + 1),
      facts: old.snapshot.facts,
      initialUiState: {'quantity': 'new extracted suggestion', 'sort': 'original'},
      sources: old.snapshot.sources, sourceDigests: old.snapshot.sourceDigests,
    );
    final intent = InteractionIntent(
      id: old.intent.id, purpose: old.intent.purpose, snapshotRef: snapshot.ref,
      requiredBindings: old.intent.requiredBindings,
      mandatoryStates: old.intent.mandatoryStates,
      allowedActionRefs: old.intent.allowedActionRefs,
    );
    final candidate = old.plan.copyWith(
      snapshotRef: snapshot.ref, revision: old.plan.revision + 1,
      nodes: [for (final n in old.plan.nodes)
        n.id == 'confirm' ? n.copyWith(events: {'cancel': ActionBinding(actionRef: 'cancel')}) : n],
    );
    final next = validateUiPlan(candidate, snapshot, intent, old.catalog).validatedPlan!;
    await showVersion(next);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'manual priority');
    expect(find.textContaining('数据版本已变化'), findsWidgets);
    final restored = tester.widget<UiWorkspaceView>(find.byType(UiWorkspaceView)).controller;
    await tester.runAsync(restored.flush);
    final saved = (await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load(next.plan.surfaceId))!;
    expect(saved.extracted['quantity'], 'new extracted suggestion');
    expect(saved.userOverrides['quantity'], 'manual priority');
    expect(saved.snapshotRef, snapshot.ref);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused_checkpoint_reopen_preserves_committed_projection', (tester) async {
    final plan = actionPlan();
    await tester.pumpWidget(MaterialApp(home: DynamicWorkspace(
      repository: repo, taskId: 'task', surfaceId: plan.plan.surfaceId,
      plan: plan, originalAnswer: '已定稿原回答',
    )));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'committed before background');
    final c = tester.widget<UiWorkspaceView>(find.byType(UiWorkspaceView)).controller;
    await c.flush();
    // These presentation fields do not notify the surface; only the lifecycle
    // checkpoint can commit them. No manual flush after paused.
    c.step = 'background checkpoint';
    c.selectedRecords = ['background-selection'];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Resume painting after simulating background events; the checkpoint is
    // still the only writer of the presentation fields above.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final store = HostUiWorkspaceStore(repo, taskId: 'task');
    final committed = (await store.load(plan.plan.surfaceId))!;
    expect(committed.step, 'background checkpoint');
    expect(committed.selectedRecords, ['background-selection']);
    expect(committed.userOverrides['quantity'], 'committed before background');
    await tester.pumpWidget(const SizedBox());
    await storage.close();
    storage = StorageManager(root.path);
    repo = (await tester.runAsync(() async => FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    )))!;
    expect((await HostUiWorkspaceStore(repo, taskId: 'task').load(plan.plan.surfaceId))!.toJson(), committed.toJson());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(home: DynamicWorkspace(
      repository: repo, taskId: 'task', surfaceId: plan.plan.surfaceId,
      plan: plan, originalAnswer: '已定稿原回答',
    )));
    await tester.pumpAndSettle();
    expect(find.text('继续步骤：background checkpoint'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'committed before background');
    expect(find.text('已定稿原回答'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

}
