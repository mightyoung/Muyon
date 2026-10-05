import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/devices_page.dart';

/// The devices page for a received research task: what each state offers and
/// says. The flow itself is covered by research_task_flow_test.dart.
void main() {
  late Directory root;
  late MuyonHost host;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('devices-research-ui-');
    host = await MuyonHost.open('${root.path}/h');
  });
  tearDown(() async {
    await host.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> seed(String state) async {
    final bytes = utf8.encode('not really a zip');
    await host.tasks.receive({
      'muyon': 'muyon-task-v1',
      'type': 'offer',
      'taskId': 'task-1',
      'inputRevision': '1',
      'idempotencyKey': 'k',
      'deviceId': 'origin',
      'attachment': {
        'kind': 'research-task',
        'name': 'task.zip',
        'sha256': sha256.convert(bytes).toString(),
        'dataBase64': base64Encode(bytes),
      },
    });
    host.workspaces.database.raw.execute(
      "UPDATE transfer_tasks SET state=?, owner_device_id=? WHERE task_id='task-1'",
      [state, host.workspaces.setting('deviceId')],
    );
  }

  Widget page() => MaterialApp(
    home: Scaffold(body: DevicesPage(host: host)),
  );

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(page());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'an offered research task says nothing has run or been imported',
    (tester) async {
      await tester.runAsync(() => seed('offered'));
      await show(tester);
      expect(find.textContaining('已提议'), findsWidgets);
      expect(find.text('授权导入科研'), findsNothing);
      expect(find.text('提交结果'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('an accepted research task offers import, not execution', (
    tester,
  ) async {
    await tester.runAsync(() => seed('accepted'));
    await show(tester);
    expect(find.text('授权导入科研'), findsOneWidget);
    expect(find.text('授权执行'), findsNothing);
    await tester.tap(find.text('授权导入科研'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会运行任何东西'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(host.tasks.stateOf('task-1', '1'), 'accepted');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a running research task is not shown as running work and can submit',
    (tester) async {
      await tester.runAsync(() => seed('running'));
      await show(tester);
      expect(find.textContaining('等待你完成并回传结果（没有在运行）'), findsOneWidget);
      expect(find.text('提交结果'), findsOneWidget);
      expect(find.text('授权导入科研'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
