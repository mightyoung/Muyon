import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/assistant_control/assistant_control_page.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/platform_shell.dart';

import 'conversation_shell_navigation_test.dart' show mountShell, select;
import 'support/conversation_workspace_fixture.dart';
import 'support/ui_navigation_fixture.dart';

String _authorizationBytes(NavigationFixture fixture) => jsonEncode({
  for (final table in ['assistant_grants', 'assistant_grant_audit'])
    table: [for (final row in fixture.host.foundation.database.raw.select('SELECT * FROM $table'))
      Map<String, Object?>.from(row)],
});

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('settings reaches read-only assistant control and returns width=$width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await NavigationFixture.open(tester);
      await mountShell(tester, f);
      addTearDown(() async {
        final shell = find.byType(PlatformShell, skipOffstage: false).evaluate();
        if (shell.isNotEmpty) {
          final navigator = Navigator.of(shell.first);
          await workspaceOperation(tester, () async { navigator.popUntil((route) => route.isFirst); });
        }
        await tester.pumpWidget(const SizedBox());
        await workspaceReady(tester);
      });
      final assistant = tester.state(find.byType(AssistantPage));
      final tasks = f.host.foundation.tasks().length;
      final calls = f.host.tools.history().length;
      final grants = _authorizationBytes(f);
      await select(tester, '设置');
      expect(find.text('助手控制中心'), findsOneWidget);
      await tester.tap(find.text('助手控制中心'));
      await workspaceVisible(tester, find.byType(AssistantControlPage));
      expect(find.text('已授权规则'), findsOneWidget);
      expect(find.text('暂无授权规则'), findsOneWidget);
      expect(Navigator.of(tester.element(find.byType(AssistantControlPage))).canPop(), isTrue);
      expect(_authorizationBytes(f), grants);
      expect(f.host.tools.history().length, calls);
      expect(f.host.foundation.tasks().length, tasks);
      await tester.pageBack();
      await workspaceGone(tester, find.byType(AssistantControlPage));
      expect(find.text('助手控制中心'), findsOneWidget);
      expect(Navigator.of(tester.element(find.byType(PlatformShell))).canPop(), isFalse);
      await select(tester, '助手');
      expect(tester.state(find.byType(AssistantPage)), same(assistant));
      expect(f.host.foundation.tasks().length, tasks);
      expect(f.host.tools.history().length, calls);
      expect(_authorizationBytes(f), grants);
      expect(tester.takeException(), isNull);
    });
  }
}
