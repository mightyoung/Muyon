import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:inquiry_module/src/features/exchange/exchange_page.dart';
import 'package:inquiry_module/src/features/exchange/import_flow.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

import 'host_attachment_test.dart' show HostSecrets;

void main() {
  late Directory directory;
  late Database db, jobsDb;
  late AppState state;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('inquiry-backup-labels');
    db = sqlite3.openInMemory();
    jobsDb = sqlite3.openInMemory();
    createSchema(db);
    AiJobStore.initializeSchema(jobsDb);
    state = AppState.attach(
      store: Store.attach(
        db,
        device: 'host',
        backgroundExecutor: <T>(action) async => await action(),
      ),
      dataDir: directory,
      aiJobs: AiJobStore.attach(jobsDb),
      secrets: HostSecrets(),
    );
  });
  tearDown(() async {
    await state.shutdown();
    state.dispose();
    db.close();
    jobsDb.close();
    directory.deleteSync(recursive: true);
  });
  testWidgets('host exchange labels identify inquiry-only business snapshots', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExchangePage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('完整应用备份由 Muyon 宿主管理'), findsOneWidget);
    expect(find.text('从交换快照替换询价资料'), findsOneWidget);
    expect(find.text('从备份恢复整个资料库'), findsNothing);
  });
  testWidgets(
    'host replacement preview explicitly limits replacement to inquiry',
    (tester) async {
      final snapshot = '${directory.path}/business.siq';
      state.store.exportTo(snapshot);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => reviewAndRestore(context, state, snapshot),
                child: const Text('review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('review'));
      await tester.pumpAndSettle();
      expect(find.text('询价资料替换预览'), findsOneWidget);
      expect(
        find.text('继续后，仅替换本机询价业务资料，不会恢复其他模块、AI任务或应用设置；现有询价AI任务会失效，共享文件夹同步将暂停。'),
        findsOneWidget,
      );
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.text('确认替换询价资料？'), findsOneWidget);
      expect(find.textContaining('不会恢复其他模块、AI任务或应用设置'), findsOneWidget);
      expect(find.text('确认整库恢复'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );
}
