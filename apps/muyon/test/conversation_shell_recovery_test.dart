import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'support/ui_navigation_fixture.dart';

class _ReceiptSession extends DynamicWorkspaceSession {
  _ReceiptSession(super.widget);
  int queries = 0;
  @override
  Future<UiOperationRecovery> receipt(String ref) async {
    queries++;
    return UiOperationRecovery.unknown; // Simulated host receipt, no write port.
  }
}

void main() {
  const ref = ObjectRef(moduleId: 'removed-plugin', objectType: 'item', objectId: 'saved');
  for (final name in ['pending_receipt_reload_queries_once_and_never_replays', 'unknown_receipt_remains_locked_and_not_success']) {
    testWidgets(name, (tester) async {
      final f = await NavigationFixture.open(tester);
      var actions = 0;
      final workspace = DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison',
        plan: f.plan(ref), onEvent: (_) async { actions++; });
      final original = DynamicWorkspaceSession(workspace);
      await tester.runAsync(original.ensureLoaded);
      original.controller!.surface.lockRecoveredOperations(['public-qty']);
      await tester.runAsync(original.checkpoint);
      original.dispose();
      final restored = _ReceiptSession(workspace);
      await tester.runAsync(restored.ensureLoaded);
      await tester.runAsync(restored.ensureLoaded);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DynamicWorkspace(repository: f.host.foundation,
        taskId: 'task', surfaceId: 'comparison', session: restored, embedded: true))));
      await tester.pumpAndSettle();
      final c = restored.controller!;
      expect(restored.queries, 1);
      expect(c.recoveredOperations['public-qty'], UiOperationRecovery.unknown);
      final confirm = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'confirm');
      expect(c.surface.canConfirm(confirm), isFalse);
      await tester.runAsync(() => c.surface.dispatch(c.surface.eventFor(confirm, 'confirm')));
      expect(actions, 0);
      expect(find.textContaining('unknown · 未自动重放'), findsOneWidget);
      expect(find.textContaining('succeeded'), findsNothing);
      expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!.operationRefs, ['public-qty']);
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
    });
  }

  testWidgets('host_generation_replaces_old_listeners_and_leases', (tester) async {
    final f = await NavigationFixture.open(tester);
    final workspace = DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref));
    final old = DynamicWorkspaceSession(workspace);
    await tester.runAsync(old.ensureLoaded);
    final oldSurface = old.controller!.surface;
    final node = oldSurface.current.plan.nodes.firstWhere((n) => n.id == 'quantity');
    final event = oldSurface.eventFor(node, 'change', '91');
    old.dispose();
    old.dispose();
    final replacement = DynamicWorkspaceSession(workspace);
    await tester.runAsync(replacement.ensureLoaded);
    expect(replacement.controller!.surface, isNot(same(oldSurface)));
    expect(await oldSurface.dispatch(event), UiDispatchOutcome.stale);
    expect(replacement.controller!.surface.session.userOverrides, isEmpty);
    replacement.dispose();
    // Real registered object-page lease disposal is independently covered by
    // object_page_lease_released_once_and_anchor_restores_from_store.
  });

  testWidgets('corrupt_or_incompatible_workspace_is_readable_without_rewrite', (tester) async {
    final f = await NavigationFixture.open(tester);
    final key = 'ui-workspace:${jsonEncode(['task', 'comparison'])}';
    const bytes = '{broken-workspace';
    await tester.runAsync(() => f.host.foundation.database.write((db) => db.execute(
      'INSERT INTO settings(key,value) VALUES(?,?)', [key, bytes],
    )));
    final session = DynamicWorkspaceSession(DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref), originalAnswer: '完整原回答'));
    await tester.runAsync(session.ensureLoaded);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'comparison', session: session, embedded: true, originalAnswer: '完整原回答'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('读取失败，保存内容未删除'), findsOneWidget);
    expect(find.text('完整原回答'), findsOneWidget);
    expect(find.byType(ConversationWorkspaceBody), findsNothing);
    await tester.runAsync(session.checkpoint);
    expect(f.host.foundation.database.raw.select('SELECT value FROM settings WHERE key=?', [key]).single['value'], bytes);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
