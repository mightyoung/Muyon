import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'support/ui_navigation_fixture.dart';
import 'support/conversation_workspace_fixture.dart';

void main() {
  const ref = ObjectRef(moduleId: 'removed-plugin', objectType: 'item', objectId: 'saved');

  testWidgets('resize_moves_one_surface_without_duplicate_controller_or_dispatch', (tester) async {
    final f = await NavigationFixture.open(tester);
    var events = 0;
    WorkspaceOpener? open;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (context, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    final workspace = DynamicWorkspace(repository: f.host.foundation, host: f.host,
      taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref),
      originalAnswer: '原对话回答', onEvent: (_) async { events++; });
    await open!(workspace);
    await open!(workspace);
    await workspaceReady(tester);
    expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    await tester.enterText(find.byType(TextField).first, '37');
    await tester.runAsync(c.flush);
    c.surface.lockRecoveredOperations(['pending-existing']);
    final node = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'quantity');
    for (final width in [1280.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      await workspaceReady(tester);
      expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
      expect(tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller, same(c));
      expect(c.surface.session.userOverrides['quantity'], width == 1280 ? '37' : '38');
      expect(c.surface.operationRefs, contains('pending-existing'));
      expect(c.surface.current.plan.nodes.firstWhere((n) => n.id == 'quantity'), same(node));
      await tester.enterText(find.byType(TextField).first, width == 1280 ? '38' : '39');
      await tester.runAsync(c.flush);
      expect(tester.takeException(), isNull);
    }
    expect(c.surface.session.userOverrides['quantity'], '39');
    expect(events, 0); // Local editing never invokes the model/business port.
    final detail = c.surface.current.plan.nodes.firstWhere((n) => n.id == 'detail');
    final event = c.surface.eventFor(detail, 'tap');
    await tester.runAsync(() => c.surface.dispatch(event));
    await tester.runAsync(() => c.surface.dispatch(event));
    expect(events, 1);
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceReady(tester);
    expect(find.text('父对话'), findsOneWidget);
    expect(find.byType(ConversationWorkspaceBody), findsNothing);
    expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!.displayValues['quantity'], '39');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resize_restores_measured_scroll_and_focused_field_selection', (tester) async {
    final f = await NavigationFixture.open(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 500);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison',
      plan: f.plan(ref), originalAnswer: List.filled(40, '固定完整回答，用于真实滚动验证。').join('\n')));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    await tester.enterText(find.byType(TextField).first, '12345');
    EditableText editor() => tester.widget<EditableText>(find.descendant(of: find.byKey(const ValueKey('quantity-field')), matching: find.byType(EditableText)));
    editor().controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    editor().focusNode.requestFocus();
    await tester.pump();
    final scroller = find.descendant(of: find.byType(ConversationWorkspaceBody), matching: find.byType(SingleChildScrollView));
    await tester.drag(scroller, const Offset(0, -30));
    await tester.pumpAndSettle();
    await tester.runAsync(c.flush);
    final before = tester.widget<SingleChildScrollView>(scroller).controller!.offset;
    expect(before, greaterThan(0));
    expect(editor().focusNode.hasFocus, isTrue);
    for (final width in [1280.0, 390.0]) {
      tester.view.physicalSize = Size(width, 500);
      await workspaceReady(tester);
      final scroll = tester.widget<SingleChildScrollView>(scroller).controller!;
      expect(scroll.offset, before.clamp(0.0, scroll.position.maxScrollExtent));
      expect(c.scrollOffset, scroll.offset);
      expect(editor().controller.text, '12345');
      expect(editor().controller.selection, const TextSelection(baseOffset: 1, extentOffset: 3));
      expect(editor().focusNode.hasFocus, isTrue);
    }
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'continued-edit');
    await tester.runAsync(c.flush);
    expect(c.surface.session.userOverrides['quantity'], 'continued-edit');
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceReady(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop_opening_another_surface_replaces_disposed_view_owner', (tester) async {
    final f = await NavigationFixture.open(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    final original = f.plan(ref);
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison', plan: original));
    await workspaceReady(tester);
    final first = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    await tester.enterText(find.byType(TextField).first, '41');
    await tester.runAsync(first.flush);
    // Open B immediately after closing A, before a frame removes A's subtree.
    // The new session key must replace its late-final state owner.
    final prior = original.plan;
    final secondPlan = validateUiPlan(UIPlan(surfaceId: 'other-surface', revision: prior.revision,
      catalogVersion: prior.catalogVersion, snapshotRef: prior.snapshotRef,
      intentRef: prior.intentRef, root: prior.root, nodes: prior.nodes),
      original.snapshot, original.intent, original.catalog).validatedPlan!;
    await tester.runAsync(() => open!(DynamicWorkspace(repository: f.host.foundation,
      taskId: 'task', surfaceId: 'other-surface', plan: secondPlan)));
    await workspaceReady(tester);
    final second = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    expect(second, isNot(same(first)));
    expect(second.surface.current.plan.surfaceId, 'other-surface');
    await tester.enterText(find.byType(TextField).first, '42');
    await tester.runAsync(second.flush);
    expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!.displayValues['quantity'], '41');
    expect((await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('other-surface'))!.displayValues['quantity'], '42');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceReady(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop_close_checkpoints_before_dispose', (tester) async {
    final f = await NavigationFixture.open(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    await open!(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref)));
    await workspaceReady(tester);
    final c = tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller;
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() { if (!release.isCompleted) release.complete(); });
    final blocked = (f.host.foundation.database as ExclusiveDatabase).exclusiveAsync((db) async {
      entered.complete();
      await release.future;
    });
    await tester.runAsync(() => entered.future);
    // A presentation checkpoint field is not auto-flushed by a surface edit.
    c.step = 'review-before-close';
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await tester.pump();
    expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
    expect(tester.widget<ConversationWorkspaceBody>(find.byType(ConversationWorkspaceBody)).controller, same(c));
    release.complete();
    await tester.runAsync(() => blocked);
    await workspaceReady(tester);
    expect(find.byType(ConversationWorkspaceBody), findsNothing);
    final saved = (await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!;
    expect(saved.step, 'review-before-close');
    expect(saved.nodeIds, contains('quantity'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
