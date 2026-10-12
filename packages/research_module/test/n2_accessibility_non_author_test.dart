import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/research_module.dart';
import 'package:research_module/src/app/section_delete_preview.dart';
import 'package:sqlite3/sqlite3.dart';

import 'n2_independent_support.dart';

void main() {
  late Directory root;
  late Database db;
  late N2IndependentReader observer;
  late WorkbenchStore store;
  setUp(() {
    root = Directory.systemTemp.createTempSync('n2-a11y-review-');
    final path = '${root.path}/research.sqlite';
    db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL');
    for (final step in ResearchModule().schema.migrations) {
      step.migrate(db);
    }
    db.execute(
      "INSERT INTO projects(id,title,question,next_step) VALUES('p','P','',''),('q','Q','','')",
    );
    db.execute(
      "INSERT INTO sections VALUES('s','p','Native heading',1,1,'private argument','unassessed')",
    );
    for (var i = 0; i < 20; i++) {
      db.execute("INSERT INTO entries VALUES(?,'p','claim','Synthetic','{}')", [
        'native-$i',
      ]);
      db.execute("INSERT INTO outline VALUES(?,'p','Synthetic',?,'s')", [
        'link-$i',
        'native-$i',
      ]);
    }
    db.execute(
      "INSERT INTO entries VALUES('HIDDEN_CANARY_SQL_path','q','claim','Private','{}')",
    );
    db.execute(
      "INSERT INTO outline VALUES('HIDDEN_CANARY_LINK','p','Synthetic','HIDDEN_CANARY_SQL_path','s')",
    );
    store = WorkbenchStore.attach(
      rootPath: root.path,
      database: db,
      managed: N2IndependentDatabase(db),
    );
    observer = N2IndependentReader(path);
  });
  tearDown(() {
    observer.close();
    db.close();
    root.deleteSync(recursive: true);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    showDialog<void>(
      context: context,
      builder: (_) => SectionDeletePreviewDialog(
        store: store,
        projectId: 'p',
        sectionId: 's',
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'independent native reachability and two connection zero writes $width at 200%',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final before = observer.snapshot();
        final version = observer.dataVersion();
        final changes = db.select('SELECT total_changes() AS n').single['n'];
        await open(tester);
        expect(find.text('将移除 21 条证据关联'), findsOneWidget);
        await tester.ensureVisible(find.textContaining('证据 native-9'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('证据 native-9').hitTestable(),
          findsOneWidget,
        );
        expect(find.text('刷新预览').hitTestable(), findsOneWidget);
        expect(find.text('关闭').hitTestable(), findsOneWidget);
        final node = tester.getSemantics(
          find.byType(SectionDeletePreviewDialog),
        );
        expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
        expect(node.toStringDeep(), isNot(contains('HIDDEN_CANARY')));
        await tester.tap(find.text('刷新预览'));
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(find.byType(SectionDeletePreviewDialog), findsNothing);
        expect(tester.takeException(), isNull);
        expect(observer.snapshot(), before);
        expect(observer.dataVersion(), version);
        expect(db.select('SELECT total_changes() AS n').single['n'], changes);
      },
    );
  }
  testWidgets(
    'missing section marks stale then refusal on refresh, never unexpected read failure',
    (tester) async {
      await open(tester);
      final id = tester
          .getSemantics(find.byType(SectionDeletePreviewDialog))
          .id;
      db.execute("DELETE FROM outline WHERE section_id='s'");
      db.execute("DELETE FROM sections WHERE id='s'");
      final before = observer.snapshot();
      final version = observer.dataVersion();
      await tester.pump(const Duration(seconds: 2));
      var node = tester.getSemantics(find.byType(SectionDeletePreviewDialog));
      expect(node.id, id);
      expect(node.getSemanticsData().label, '只读预览，不是删除确认\n预览已过期，请刷新；不能用于删除确认');
      await tester.tap(find.text('刷新预览'));
      await tester.pump();
      node = tester.getSemantics(find.byType(SectionDeletePreviewDialog));
      expect(node.getSemanticsData().label, '只读预览，不是删除确认\n无法生成完整预览：超出预算或无权读取');
      expect(find.text('预览读取失败，请重试'), findsNothing);
      expect(observer.snapshot(), before);
      expect(observer.dataVersion(), version);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    },
  );
}
