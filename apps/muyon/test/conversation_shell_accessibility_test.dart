import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'conversation_shell_navigation_test.dart' show mountShell, select;
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/ui_navigation_fixture.dart';
import 'support/conversation_workspace_fixture.dart';

void main() {
  const ref = ObjectRef(moduleId: 'removed-plugin', objectType: 'item', objectId: 'saved');
  testWidgets('navigation_workspace_and_back_have_48_targets_and_selected_semantics', (tester) async {
    final f = await NavigationFixture.open(tester);
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      await mountShell(tester, f);
      final nav = width >= 900 ? find.byType(NavigationRail) : find.byType(NavigationBar);
      for (final label in ['助手', '任务', '资料', '设置']) {
        await select(tester, label);
        final target = find.descendant(of: nav, matching: find.byWidgetPredicate((widget) =>
          widget is Semantics && widget.properties.selected == true));
        expect(target, findsOneWidget, reason: 'selected semantics for $label at $width');
        expect(find.descendant(of: target, matching: find.text(label)), findsOneWidget);
        expect(tester.getSemantics(target).flagsCollection.isSelected, Tristate.isTrue);
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await select(tester, '助手');
      final open = tester.widget<AssistantPage>(find.byType(AssistantPage)).onOpenWorkspace!;
      await open(DynamicWorkspace(repository: f.host.foundation, taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref)));
      await workspaceReady(tester);
      final back = find.byTooltip('关闭工作区 / 返回');
      expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
      final semanticBack = find.bySemanticsLabel('关闭工作区 / 返回');
      expect(semanticBack, findsOneWidget);
      final node = tester.getSemantics(semanticBack);
      expect(node.label, contains('关闭工作区 / 返回'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(back);
      await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
      expect(find.byType(ConversationWorkspaceBody), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard_focus_returns_to_source_node', (tester) async {
    final f = await NavigationFixture.open(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = FocusNode();
    addTearDown(source.dispose);
    // Registered after source.dispose: unmount its Focus widget before
    // disposing the node, and close SQLite while fake callbacks can advance.
    addTearDown(() async {
      try {
        await tester.pumpWidget(const SizedBox());
        await workspaceReady(tester);
      } finally {
        await workspaceOperation(tester, f.host.close);
      }
    });
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(builder: (_, open) => Scaffold(body: TextButton(
      focusNode: source,
      onPressed: () => open(DynamicWorkspace(repository: f.host.foundation,
        taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref))),
      child: const Text('打开工作区'),
    )))));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(source.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await workspaceReady(tester);
    expect(find.byType(ConversationWorkspaceBody), findsOneWidget);
    final close = find.byTooltip('关闭工作区 / 返回');
    expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
    await tester.tap(close);
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    expect(source.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('text_only_keeps_answer_and_fixed_page_fallback_without_new_actions', (tester) async {
    final f = await NavigationFixture.open(tester);
    var actions = 0;
    await mountShell(tester, f, allowInteractiveWorkspace: false);
    final open = tester.widget<AssistantPage>(find.byType(AssistantPage)).onOpenWorkspace!;
    await open(DynamicWorkspace(repository: f.host.foundation, host: f.host,
      taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref),
      originalAnswer: '完整原回答，不截断。', onEvent: (_) async { actions++; }));
    await workspaceReady(tester);
    expect(find.text('完整原回答，不截断。'), findsOneWidget);
    expect(find.byType(DynamicUiSurface), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await workspaceOperation(tester, () => tester.tap(find.text('查看对象 · removed-plugin')));
    await workspaceVisible(tester, find.textContaining('对象或插件当前不可用'));
    await workspaceOperation(tester, tester.pageBack);
    await workspaceVisible(tester, find.text('完整原回答，不截断。'));
    expect(find.text('完整原回答，不截断。'), findsOneWidget);
    expect(actions, 0);
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceGone(tester, find.byType(ConversationWorkspaceBody));
    await tester.pumpWidget(const SizedBox());
  });
}
