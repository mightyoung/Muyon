import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:path/path.dart' as p;
import 'package:prototype_module/prototype_module.dart';

import 'support/conversation_workspace_fixture.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('proto-wiring'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  testWidgets('shell data destination opens the prototype module', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      // Open the database on the real event loop first; the tap then only
      // navigates.
      await tester.runAsync(host.activatePrototype);
      await tester.pumpWidget(
        MaterialApp(
          home: PlatformShell(
            host: host,
            themeMode: ThemeMode.light,
            onTheme: (_) {},
            onRestore: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('资料')));
      await tester.pumpAndSettle();
      final entry = find.widgetWithText(ListTile, '原型页面');
      final dataScroll = find.descendant(of: find.byType(ListView), matching: find.byWidgetPredicate(
        (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ));
      expect(dataScroll, findsOneWidget);
      await tester.scrollUntilVisible(entry, 100, scrollable: dataScroll);
      await tester.pumpAndSettle();
      expect(entry.hitTestable(), findsOneWidget);
      await workspaceOperation(tester, () => tester.tap(entry.hitTestable()));
      await workspaceVisible(tester, find.byType(PrototypeHome));
      expect(find.byType(PrototypeHome), findsOneWidget);
      expect(find.textContaining('不代表完整业务系统'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
    }
  });

  test('a broken prototype database disables only that module', () async {
    final dir = Directory(p.join(root.path, 'modules', 'prototype'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'prototype.sqlite')).writeAsStringSync('not sqlite');
    final host = await MuyonHost.open(root.path);
    addTearDown(host.close);
    await host.activatePrototype();
    expect(host.prototype, isNull);
    expect(host.prototypeError, isNotNull);
    final status = host.workspaces.database.raw.select(
      "SELECT status FROM module_registry WHERE module_id='prototype'",
    );
    expect(status.single['status'], 'failed');
    // Host and the other modules are unaffected.
    expect(host.registry.unavailable, isEmpty);
    await host.activateResearch();
    expect(host.research, isNotNull);
    expect(host.researchError, isNull);
  });

  test('a healthy host activates the prototype module once', () async {
    final host = await MuyonHost.open(root.path);
    addTearDown(host.close);
    await host.activatePrototype();
    await host.activatePrototype();
    expect(host.prototypeError, isNull);
    expect(host.prototype!.store.pages(), isEmpty);
  });
}
