import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';

import 'conversation_shell_navigation_test.dart' show mountShell, select;
import 'support/conversation_workspace_fixture.dart';
import 'support/ui_navigation_fixture.dart';

/// Drain real SQLite/plugin futures until [key] stores [expected] and the
/// shell has no frame left to build, mirroring the fixture settle loop.
Future<void> _settingReaches(
  WidgetTester tester,
  NavigationFixture f,
  String key,
  Object? expected,
) async {
  var stable = 0;
  for (var turn = 0; turn < 2000; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    stable =
        f.host.workspaces.setting(key) == expected &&
            !tester.binding.hasScheduledFrame
        ? stable + 1
        : 0;
    if (stable >= 2) return;
  }
  fail('Setting $key did not reach $expected');
}

void main() {
  Future<NavigationFixture> openShell(
    WidgetTester tester, {
    Future<void> Function(NavigationFixture f)? beforeMount,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = await NavigationFixture.open(tester);
    if (beforeMount != null) await beforeMount(f);
    await mountShell(tester, f);
    addTearDown(() async {
      final shell = find.byType(PlatformShell, skipOffstage: false).evaluate();
      if (shell.isNotEmpty) {
        final navigator = Navigator.of(shell.first);
        await workspaceOperation(tester, () async {
          navigator.popUntil((route) => route.isFirst);
        });
      }
      await tester.pumpWidget(const SizedBox());
      await workspaceReady(tester);
    });
    return f;
  }

  testWidgets('settings_tools_entry_opens_and_returns_without_tool_calls', (
    tester,
  ) async {
    final f = await openShell(tester);
    await select(tester, '设置');
    final calls = f.host.tools.history().length;
    final entry = find.widgetWithText(ListTile, '接口与工具');
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await workspaceVisible(tester, find.widgetWithText(AppBar, '接口与工具'));
    await tester.pageBack();
    await workspaceGone(tester, find.widgetWithText(AppBar, '接口与工具'));
    expect(find.widgetWithText(ListTile, '接口与工具'), findsOneWidget);
    expect(f.host.tools.history().length, calls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings_reduce_motion_switch_persists_true_then_false', (
    tester,
  ) async {
    final f = await openShell(tester);
    await select(tester, '设置');
    expect(f.host.workspaces.setting('reduceMotion'), isNot(true));
    final toggle = find.widgetWithText(SwitchListTile, '减少动态效果');
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await _settingReaches(tester, f, 'reduceMotion', true);
    expect(f.host.workspaces.setting('reduceMotion'), isTrue);
    await tester.tap(toggle);
    await _settingReaches(tester, f, 'reduceMotion', false);
    expect(f.host.workspaces.setting('reduceMotion'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings_primary_chat_model_selects_and_clears', (tester) async {
    final profile = ModelProfile(
      id: 'oc1-chat',
      endpoint: Uri.parse('http://127.0.0.1:1/v1'),
      location: ModelLocation.local,
      modelId: 'oc1-fixture',
      endpointIdentity: 'oc1-chat-setup',
    );
    final f = await openShell(
      tester,
      beforeMount: (f) => workspaceOperation(
        tester,
        () => ProfileRepository(f.host.workspaces).save(profile),
      ),
    );
    await select(tester, '设置');
    final dropdown = find.widgetWithText(
      DropdownButtonFormField<String>,
      '主对话模型（Folio 共用）',
    );
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('oc1-chat-setup').last);
    await _settingReaches(tester, f, 'activeModelProfileId', profile.id);
    expect(f.host.workspaces.setting('activeModelProfileId'), profile.id);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('未指定 · 离线工具可用').last);
    await _settingReaches(tester, f, 'activeModelProfileId', '');
    expect(f.host.workspaces.setting('activeModelProfileId'), '');
    expect(tester.takeException(), isNull);
  });
}
