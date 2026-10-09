import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/dynamic_ui.dart';

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
    // A presentation checkpoint field is not auto-flushed by a surface edit.
    c.step = 'review-before-close';
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceReady(tester);
    expect(find.byType(ConversationWorkspaceBody), findsNothing);
    final saved = (await HostUiWorkspaceStore(f.host.foundation, taskId: 'task').load('comparison'))!;
    expect(saved.step, 'review-before-close');
    expect(saved.nodeIds, contains('quantity'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
