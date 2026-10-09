import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/platform_shell.dart';

import 'support/ui_navigation_fixture.dart';

Future<void> select(WidgetTester tester, String label) async {
  final nav = find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar) : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: nav, matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> mountShell(WidgetTester tester, NavigationFixture f) async {
  await tester.pumpWidget(MaterialApp(home: PlatformShell(
    host: f.host, themeMode: ThemeMode.light,
    onTheme: (_) {}, onRestore: (_) async {},
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('switching_destinations_keeps_unsent_parent_draft_and_scroll', (tester) async {
    final f = await NavigationFixture.open(tester);
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await f.host.foundation.appendMessage(f.conversationId, 'assistant', '固定公开历史 $i\n用于验证实际滚动位置');
      }
    });
    await mountShell(tester, f);
    final rootState = tester.state(find.byType(AssistantPage));
    final history = find.descendant(of: find.byType(AssistantPage), matching: find.byType(ListView));
    await tester.drag(history, const Offset(0, -400));
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(history).controller!;
    final offset = controller.offset;
    expect(offset, greaterThan(0));
    await tester.enterText(find.widgetWithText(TextField, '输入消息'), '尚未发送的人工输入');
    final tasks = f.host.foundation.tasks().length;
    final calls = f.host.tools.history().length;
    final messages = f.host.foundation.messages(f.conversationId).length;
    for (final label in ['任务', '资料', '设置', '助手']) {
      await select(tester, label);
    }
    expect(tester.state(find.byType(AssistantPage)), same(rootState));
    expect(find.text('尚未发送的人工输入'), findsOneWidget);
    expect(controller.offset, offset);
    // Resizing also keeps the same mounted assistant and controllers.
    for (final width in [1280.0, 390.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AssistantPage)), same(rootState));
      expect(find.text('尚未发送的人工输入'), findsOneWidget);
      expect(controller.offset, offset);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(f.host.foundation.tasks().length, tasks);
    expect(f.host.tools.history().length, calls);
    expect(f.host.foundation.messages(f.conversationId).length, messages);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy_entries_remain_reachable', (tester) async {
    final f = await NavigationFixture.open(tester);
    await mountShell(tester, f);
    await select(tester, '任务');
    for (final label in ['执行面板', '消息中心', '数据交换']) {
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    await select(tester, '资料');
    expect(find.text('查找业务对象'), findsOneWidget);
    expect(find.text('业务页面与工作区'), findsOneWidget);
    await select(tester, '设置');
    for (final label in ['设备聊天', '记忆与整理', '设备与通信', '个人中心']) {
      final entry = find.text(label);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    await select(tester, '助手');
    expect(find.byType(AssistantPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
