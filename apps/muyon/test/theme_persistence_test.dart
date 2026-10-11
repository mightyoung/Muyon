import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';

import 'support/conversation_workspace_fixture.dart';

/// Drain real SQLite/plugin futures until [key] stores [expected] and the
/// app has no frame left to build (copied from settings_controls_test.dart).
Future<void> _settingReaches(
  WidgetTester tester,
  MuyonHost host,
  String key,
  Object? expected,
) async {
  var stable = 0;
  for (var turn = 0; turn < 2000; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    stable =
        host.workspaces.setting(key) == expected &&
            !tester.binding.hasScheduledFrame
        ? stable + 1
        : 0;
    if (stable >= 2) return;
  }
  fail('Setting $key did not reach $expected');
}

void main() {
  testWidgets('stored_dark_theme_is_applied_on_open', (tester) async {
    final root = Directory.systemTemp.createTempSync('theme-persistence');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.runAsync(() => host.workspaces.setSetting('theme', 'dark'));
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      await workspaceOperation(tester, host.close);
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('choosing_light_theme_is_saved_and_applied', (tester) async {
    final root = Directory.systemTemp.createTempSync('theme-persistence');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<ThemeMode>, '外观'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('light').last);
      await _settingReaches(tester, host, 'theme', 'light');
      expect(host.workspaces.setting('theme'), 'light');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      await workspaceOperation(tester, host.close);
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('unknown_stored_theme_falls_back_to_system', (tester) async {
    final root = Directory.systemTemp.createTempSync('theme-persistence');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.runAsync(
        () => host.workspaces.setSetting('theme', 'purple'),
      );
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await workspaceOperation(tester, host.close);
      root.deleteSync(recursive: true);
    }
  });
}
