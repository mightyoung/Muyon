import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_catalog.dart';
import 'package:muyon/platform/backup_service.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'support/ui_navigation_fixture.dart';
import 'support/conversation_workspace_fixture.dart';
import 'support/fake_v2_module.dart';

Future<void> _unmountRecovery(WidgetTester tester) async {
  final workspaces = find.byType(DynamicWorkspace, skipOffstage: false).evaluate();
  if (workspaces.isNotEmpty) {
    final navigator = Navigator.of(workspaces.first);
    // Complete pushed-route futures so their registered object leases reach
    // UiReferenceNavigation.finally before the host is closed.
    await workspaceOperation(tester, () async {
      navigator.popUntil((route) => route.isFirst);
    });
    await tester.pumpAndSettle();
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void _registerRecoveryCleanup(WidgetTester tester, NavigationFixture fixture) {
  addTearDown(() async {
    await _unmountRecovery(tester);
    await workspaceOperation(tester, fixture.host.close);
  });
}

class _ReceiptSession extends DynamicWorkspaceSession {
  _ReceiptSession(super.widget);
  int queries = 0;
  @override
  Future<UiOperationRecovery> receipt(String ref) async {
    queries++;
    return UiOperationRecovery.unknown; // Simulated host receipt, no write port.
  }
}

class _GenerationLeaseRuntime extends FakeRuntime implements ObjectPages {
  _GenerationLeaseRuntime(super.resources);
  int released = 0;
  Completer<void>? releaseBarrier;
  @override
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref) async => ObjectPageLease(
    title: '宿主换代插件页', page: const Text('注册插件租用页'),
    dispose: () async {
      await releaseBarrier?.future;
      released++;
    },
  );
}

FakeV2Module _leaseModule() => FakeV2Module('lease', features: {ModuleFeature.objectPages},
  runtimeFactory: _GenerationLeaseRuntime.new);

void main() {
  const ref = ObjectRef(moduleId: 'removed-plugin', objectType: 'item', objectId: 'saved');
  for (final name in ['pending_receipt_reload_queries_once_and_never_replays', 'unknown_receipt_remains_locked_and_not_success']) {
    testWidgets(name, (tester) async {
      final f = await NavigationFixture.open(tester);
      _registerRecoveryCleanup(tester, f);
      var actions = 0;
      final workspace = DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison',
        plan: f.plan(ref), onEvent: (_) async { actions++; });
      final original = DynamicWorkspaceSession(workspace);
      await workspaceOperation(tester, original.ensureLoaded);
      original.controller!.surface.lockRecoveredOperations(['public-qty']);
      await workspaceOperation(tester, original.checkpoint);
      original.dispose();
      final restored = _ReceiptSession(workspace);
      await workspaceOperation(tester, restored.ensureLoaded);
      await workspaceOperation(tester, restored.ensureLoaded);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DynamicWorkspace(repository: f.host.foundation,
        taskId: 'task', surfaceId: 'comparison', session: restored, embedded: true))));
      await tester.pumpAndSettle();
      final c = restored.controller!;
      expect(restored.queries, 1);
      expect(c.recoveredOperations['public-qty'], UiOperationRecovery.unknown);
      final confirm = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'confirm');
      expect(c.surface.canConfirm(confirm), isFalse);
      await workspaceOperation(tester, () => c.surface.dispatch(c.surface.eventFor(confirm, 'confirm')));
      expect(actions, 0);
      expect(find.textContaining('unknown · 未自动重放'), findsOneWidget);
      expect(find.textContaining('succeeded'), findsNothing);
      expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!.operationRefs, ['public-qty']);
      await tester.pumpWidget(const SizedBox());
      restored.dispose();
    });
  }

  testWidgets('host_generation_replaces_old_listeners_and_leases', (tester) async {
    final module = _leaseModule();
    final f = await NavigationFixture.open(tester, extra: [module]);
    _registerRecoveryCleanup(tester, f);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await workspaceOperation(tester, () => f.host.foundation.database.write((db) => db.execute(
      "UPDATE execution_records SET payload=json_set(payload,'\$.prompt','公开父任务','\$.stage','paused','\$.executionDeviceId','local','\$.state','paused') WHERE id='task'",
    )));
    final backup = '${f.root.path}/backup';
    await workspaceOperation(tester, () async {
      await f.host.workspaces.setSetting('marker', 'before');
      await BackupService.create(f.host.storage, backup);
      await f.host.workspaces.setSetting('marker', 'after');
    });
    MuyonHost? fresh;
    addTearDown(() async {
      await _unmountRecovery(tester);
      if (fresh != null) await workspaceOperation(tester, fresh!.close);
    });
    await tester.pumpWidget(MuyonApp(host: f.host, openHost: (root) async =>
      fresh = await MuyonHost.open(root, modules: [_leaseModule(), ...moduleCatalog()])));
    await tester.pumpAndSettle();
    final shell = tester.widget<PlatformShell>(find.byType(PlatformShell));
    final open = tester.widget<AssistantPage>(find.byType(AssistantPage)).onOpenWorkspace!;
    const object = ObjectRef(moduleId: 'lease', objectType: 'note', objectId: 'registered-note');
    await open(DynamicWorkspace(repository: f.host.foundation, host: f.host, taskId: 'task',
      surfaceId: 'comparison', plan: f.plan(object)));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    final oldSurface = c.surface;
    final node = oldSurface.current.plan.nodes.firstWhere((n) => n.id == 'quantity');
    final event = oldSurface.eventFor(node, 'change', '91');
    await tester.tap(find.text('查看对象 · lease'));
    await workspaceVisible(tester, find.text('注册插件租用页'));
    final runtime = module.runtime! as _GenerationLeaseRuntime;
    final leaseRelease = Completer<void>();
    runtime.releaseBarrier = leaseRelease;
    addTearDown(() { if (!leaseRelease.isCompleted) leaseRelease.complete(); });
    expect(runtime.released, 0);
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() { if (!release.isCompleted) release.complete(); });
    Future<void>? blocked;
    await workspaceOperation(tester, () async {
      blocked = (f.host.foundation.database as ExclusiveDatabase).exclusiveAsync((_) async {
        entered.complete(); await release.future;
      });
      await entered.future;
    });
    c.step = 'restore-checkpoint';
    Future<void>? restoring;
    // Exercise the actual MuyonApp restore callback with an object route still
    // leased. This bypasses only the separately tested confirmation dialog.
    await workspaceOperation(tester, () async { restoring = shell.onRestore(backup); });
    await tester.pump();
    expect(fresh, isNull);
    expect(find.text('注册插件租用页'), findsOneWidget);
    expect(runtime.released, 0);
    release.complete();
    await workspaceOperation(tester, () => blocked!);
    await workspaceGone(tester, find.text('注册插件租用页'));
    // The object route popped, but its asynchronous lease is not released yet.
    // Restore must still retain the current host until that disposal finishes.
    expect(fresh, isNull);
    expect(f.host.workspaces.setting('marker'), 'after');
    expect(runtime.released, 0);
    leaseRelease.complete();
    await workspaceVisible(tester, find.textContaining('已从备份恢复并重启'));
    await workspaceOperation(tester, () => restoring!);
    expect(fresh, isNotNull);
    expect(fresh!.workspaces.setting('marker'), 'before');
    expect(runtime.released, 1);
    expect(await oldSurface.dispatch(event), UiDispatchOutcome.stale);
    final reopenedShell = tester.widget<PlatformShell>(find.byType(PlatformShell));
    expect(reopenedShell.host, same(fresh));
    final nextOpen = tester.widget<AssistantPage>(find.byType(AssistantPage)).onOpenWorkspace!;
    await nextOpen(DynamicWorkspace(repository: fresh!.foundation, host: fresh, taskId: 'task',
      surfaceId: 'comparison', plan: f.plan(object)));
    await workspaceReady(tester);
    final replacement = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    expect(replacement.surface, isNot(same(oldSurface)));
    expect(replacement.surface.session.userOverrides, isEmpty);
    expect(runtime.released, 1);
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('incompatible_catalog_workspace_keeps_manual_draft_without_rewrite', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerRecoveryCleanup(tester, f);
    var actions = 0;
    final workspace = DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison',
      plan: f.plan(ref), originalAnswer: '完整原回答', onEvent: (_) async { actions++; });
    final original = DynamicWorkspaceSession(workspace);
    await workspaceOperation(tester, original.ensureLoaded);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'comparison', session: original, embedded: true))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '人工保留');
    await workspaceOperation(tester, original.checkpoint);
    await tester.pumpWidget(const SizedBox());
    original.dispose();
    final key = 'ui-workspace:${jsonEncode(['task', 'comparison'])}';
    final prior = f.host.foundation.database.raw.select('SELECT value FROM settings WHERE key=?', [key]).single['value'] as String;
    final incompatible = jsonDecode(prior) as Map<String, dynamic>;
    incompatible['catalogVersion'] = 'unknown-future-catalog';
    final bytes = jsonEncode(incompatible);
    await workspaceOperation(tester, () => f.host.foundation.database.write((db) => db.execute(
      'UPDATE settings SET value=? WHERE key=?', [bytes, key],
    )));
    final restored = DynamicWorkspaceSession(workspace);
    await workspaceOperation(tester, restored.ensureLoaded);
    expect(restored.controller!.readOnly, isTrue);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'comparison', session: restored, embedded: true, originalAnswer: '完整原回答'))));
    await tester.pumpAndSettle();
    expect(find.text('quantity: 人工保留'), findsOneWidget);
    expect(find.text('完整原回答'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final c = restored.controller!;
    final confirm = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'confirm');
    expect(c.surface.canConfirm(confirm), isFalse);
    await workspaceOperation(tester, () => c.surface.dispatch(c.surface.eventFor(confirm, 'confirm')));
    await workspaceOperation(tester, restored.checkpoint);
    expect(actions, 0);
    expect(f.host.foundation.database.raw.select('SELECT value FROM settings WHERE key=?', [key]).single['value'], bytes);
    await tester.pumpWidget(const SizedBox());
    restored.dispose();
  });

  testWidgets('corrupt_or_incompatible_workspace_is_readable_without_rewrite', (tester) async {
    final f = await NavigationFixture.open(tester);
    _registerRecoveryCleanup(tester, f);
    final key = 'ui-workspace:${jsonEncode(['task', 'comparison'])}';
    const bytes = '{broken-workspace';
    await workspaceOperation(tester, () => f.host.foundation.database.write((db) => db.execute(
      'INSERT INTO settings(key,value) VALUES(?,?)', [key, bytes],
    )));
    final session = DynamicWorkspaceSession(DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref), originalAnswer: '完整原回答'));
    await workspaceOperation(tester, session.ensureLoaded);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'comparison', session: session, embedded: true, originalAnswer: '完整原回答'))));
    await workspaceVisible(tester, find.textContaining('读取失败，保存内容未删除'));
    expect(find.textContaining('读取失败，保存内容未删除'), findsOneWidget);
    expect(find.text('完整原回答'), findsOneWidget);
    expect(find.byType(ConversationWorkspaceBody), findsNothing);
    await workspaceOperation(tester, session.checkpoint);
    expect(f.host.foundation.database.raw.select('SELECT value FROM settings WHERE key=?', [key]).single['value'], bytes);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
