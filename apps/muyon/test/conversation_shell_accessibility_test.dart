import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/ui_navigation_fixture.dart';
import 'support/conversation_workspace_fixture.dart';

void main() {
  const ref = ObjectRef(moduleId: 'removed-plugin', objectType: 'item', objectId: 'saved');
  testWidgets('keyboard_focus_returns_to_source_node', (tester) async {
    final f = await NavigationFixture.open(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = FocusNode();
    addTearDown(source.dispose);
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
    await workspaceReady(tester);
    expect(source.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('text_only_keeps_answer_and_fixed_page_fallback_without_new_actions', (tester) async {
    final f = await NavigationFixture.open(tester);
    var actions = 0;
    WorkspaceOpener? open;
    await tester.pumpWidget(MaterialApp(home: ConversationWorkspaceHost(allowInteractive: false, builder: (_, opener) {
      open = opener;
      return const Scaffold(body: Text('父对话'));
    })));
    await open!(DynamicWorkspace(repository: f.host.foundation, host: f.host,
      taskId: 'task', surfaceId: 'comparison', plan: f.plan(ref),
      originalAnswer: '完整原回答，不截断。', onEvent: (_) async { actions++; }));
    await workspaceReady(tester);
    expect(find.text('完整原回答，不截断。'), findsOneWidget);
    expect(find.byType(DynamicUiSurface), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('查看对象 · removed-plugin'));
    await workspaceVisible(tester, find.textContaining('对象或插件当前不可用'));
    await tester.pageBack();
    await workspaceReady(tester);
    expect(find.text('完整原回答，不截断。'), findsOneWidget);
    expect(actions, 0);
    await tester.tap(find.byTooltip('关闭工作区 / 返回'));
    await workspaceReady(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
