// Task-specific widget test for "Linux host startup and settings validation".
// This is a WIDGET test (flutter_test, headless). It does not launch the
// Linux desktop binary and is not evidence of real desktop interaction.
// Synthetic temp data only; no model is configured or called.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';

import 'support/conversation_workspace_fixture.dart';

const _key = UiPresentationPreference.key;

/// Drain real SQLite futures until [key] stores [expected] and no frame is
/// pending (same approach as theme_persistence_test.dart).
Future<void> _settingReaches(
    WidgetTester tester, MuyonHost host, Object? expected) async {
  var stable = 0;
  for (var turn = 0; turn < 2000; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    stable = host.workspaces.setting(_key) == expected &&
            !tester.binding.hasScheduledFrame
        ? stable + 1
        : 0;
    if (stable >= 2) return;
  }
  fail('Setting $_key did not reach $expected '
      '(actual ${host.workspaces.setting(_key)})');
}

Finder get _modeField =>
    find.byType(DropdownButtonFormField<UiPresentationMode>).hitTestable();

Future<void> _openSettings(WidgetTester tester, double width) async {
  final nav = width >= 900
      ? find.byType(NavigationRail)
      : find.byType(NavigationBar);
  expect(nav, findsOneWidget);
  await tester.tap(find.descendant(of: nav, matching: find.text('设置')));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'open settings @ $width');
  expect(_modeField, findsOneWidget);
  // The field label is drawn by InputDecorator (not hit-testable); check it
  // belongs to the visible settings field.
  expect(find.descendant(of: _modeField, matching: find.text('界面与可视化')),
      findsOneWidget);
}

Future<void> _choose(WidgetTester tester, MuyonHost host,
    UiPresentationMode mode, double width) async {
  await tester.runAsync(() => tester.tap(_modeField));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'menu open @ $width');
  // All three exact labels are offered in the open menu.
  for (final label in ['自动', '少用', '只用文字']) {
    expect(find.text(label), findsWidgets, reason: label);
  }
  await tester.runAsync(() => tester.tap(find.text(mode.label).last));
  await _settingReaches(tester, host, mode.storageValue);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'choose ${mode.name} @ $width');
  expect(host.personalAgent.presentationMode, mode);
  expect(
      tester.state<FormFieldState<UiPresentationMode>>(_modeField).value, mode);
}

void main() {
  // Minimal reproduction (RED at 9d8a411): with a stored non-text-only mode the
  // assistant page shows DropdownButton<UiPlanningMode>
  // (lib/screens/assistant_page.dart:738), which overflows at 390 px / 200 %.
  testWidgets('automatic_mode_assistant_page_390_at_text_scale_2_no_overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final root = Directory.systemTemp.createTempSync('linux-host-overflow-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host =
        (await tester.runAsync(() => MuyonHost.open('${root.path}/data')))!;
    try {
      await workspaceOperation(tester,
          () => host.personalAgent.savePresentationMode(UiPresentationMode.automatic));
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await workspaceOperation(tester, host.close);
    }
  });

  for (final (width, scale) in [(390.0, 2.0), (1280.0, 2.0), (390.0, 1.0)]) {
    testWidgets(
        'linux_host_settings_three_tiers_switch_persist_across_restart_'
        'at_text_scale_$scale ($width)', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      // System-level text scale, as a desktop font-scaling setting would feed it.
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final root = Directory.systemTemp.createTempSync('linux-host-settings-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final dataDir = '${root.path}/data';
      var host = (await tester.runAsync(() => MuyonHost.open(dataDir)))!;
      try {
        await tester.pumpWidget(MuyonApp(host: host));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first))
            .scale(10), 10 * scale);
        // Fresh store defaults to text-only (bootstrap missingDefault).
        expect(host.personalAgent.presentationMode, UiPresentationMode.textOnly);
        expect(host.workspaces.setting(_key), isNull);
        await _openSettings(tester, width);

        // Switch through all three tiers; each restarts the host on the same
        // directory and rebuilds the app before checking the restored value.
        for (final mode in [
          UiPresentationMode.automatic,
          UiPresentationMode.few,
          UiPresentationMode.textOnly,
        ]) {
          await _choose(tester, host, mode, width);
          await tester.pumpWidget(const SizedBox());
          await workspaceOperation(tester, host.close);
          host = (await tester.runAsync(() => MuyonHost.open(dataDir)))!;
          await tester.pumpWidget(MuyonApp(host: host));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'restart ${mode.name}');
          expect(host.personalAgent.presentationMode, mode,
              reason: 'restored after restart');
          expect(host.workspaces.setting(_key), mode.storageValue);
          await _openSettings(tester, width);
          expect(
              tester.state<FormFieldState<UiPresentationMode>>(_modeField).value,
              mode,
              reason: 'settings field shows restored ${mode.name}');
          expect(find.text(mode.label).hitTestable(), findsOneWidget);
        }
        // A presentation-preference change never grants or runs anything.
        expect(host.assistantGrants.list(), isEmpty);
        expect(host.tools.history(), isEmpty);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.pumpWidget(const SizedBox());
        await workspaceOperation(tester, host.close);
      }
    });
  }
}
