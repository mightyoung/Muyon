import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/backup_service.dart';
import 'package:muyon/screens/storage_status.dart';
import 'package:path/path.dart' as p;

/// Real file IO needs the real event loop; interleave it with frame pumps.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Directory tmp;
  late String root;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore-flow');
    root = p.join(tmp.path, 'data');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('StorageStatus.read reflects a healthy host', () async {
    final host = await MuyonHost.open(root);
    addTearDown(host.close);
    final status = StorageStatus.read(host);
    expect(status.rootPath, root);
    expect(status.catalog.map((row) => row.moduleId), contains('muyon'));
    expect(status.catalog.every((row) => !row.blocked), isTrue);
    expect(status.unavailableModules, isEmpty);
    expect(status.hasProblems, isFalse);
  });

  testWidgets('settings → 数据与存储 → restore swaps data and reopens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var host = (await tester.runAsync(() => MuyonHost.open(root)))!;
    final backup = p.join(tmp.path, 'backup');
    await tester.runAsync(() async {
      await host.workspaces.setSetting('marker', 'before');
      await BackupService.create(host.storage, backup);
      await host.workspaces.setSetting('marker', 'after');
    });
    MuyonHost? reopened;
    await tester.pumpWidget(
      MuyonApp(
        host: host,
        pickDirectory: (_) async => backup,
        openHost: (path) async => reopened = await MuyonHost.open(path),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('系统设置'));
    await tester.pumpAndSettle();
    final entry = find.text('数据与存储').first;
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final restore = find.text('从备份恢复');
    await tester.ensureVisible(restore);
    await tester.tap(restore);
    await _until(tester, () => find.text('关闭并恢复').evaluate().isNotEmpty);
    expect(find.text('关闭并恢复'), findsOneWidget);
    await tester.tap(find.text('关闭并恢复'));
    await tester.pump();
    await _until(
      tester,
      () => find.textContaining('已从备份恢复并重启').evaluate().isNotEmpty,
    );
    final fresh = reopened!;
    expect(fresh.workspaces.setting('marker'), 'before');
    expect(
      Directory(tmp.path)
          .listSync()
          .where((e) => p.basename(e.path).startsWith('data.before-restore-')),
      hasLength(1),
    );
    expect(find.textContaining('已从备份恢复并重启'), findsOneWidget);
    host = fresh;
    await tester.pumpWidget(const SizedBox());
    // The reopened host was created inside the fake-async zone, so closing it
    // needs frame pumps interleaved with real IO.
    var closed = false;
    host.close().then((_) => closed = true);
    await _until(tester, () => closed);
    expect(closed, isTrue);
  });
}
