import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/research_module.dart';
import 'package:research_module/src/app/section_delete_preview.dart';
import 'package:research_module/src/app/writing_page.dart';

import 'change_log_test.dart' show migrated, project;
import 'research_runtime_test.dart' show TestDatabase;

void main() {
  late Directory root;
  late TestDatabase db;
  late WorkbenchStore store;
  late OutlineSection section;

  setUp(() {
    root = Directory.systemTemp.createTempSync('delete-preview-ui-');
    db = migrated(version: 10);
    project(db, 'p');
    project(db, 'q');
    store = WorkbenchStore.attach(
      rootPath: root.path,
      database: db.raw,
      managed: db,
    );
    section = store.addSection('p', '章节');
  });
  tearDown(() {
    db.raw.close();
    root.deleteSync(recursive: true);
  });

  void link(String id) {
    db.raw.execute(
      'INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES(?,?,?,?,?)',
      ['link-$id', 'p', '章节', id, section.id],
    );
    db.raw.execute(
      "INSERT INTO entries(id,project_id,title,kind,data) VALUES(?,?,?,'claim','{\"body\":\"private body\"}')",
      [id, 'p', id],
    );
  }

  Widget host({double scale = 1, int maxLinks = 500, WorkbenchStore? scoped}) =>
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SectionDeletePreviewDialog(
            store: scoped ?? store,
            projectId: 'p',
            sectionId: section.id,
            maxLinks: maxLinks,
          ),
        ),
      );

  List<Map<String, Object?>> rows(String table) => [
    for (final row in db.raw.select('SELECT * FROM $table'))
      Map<String, Object?>.from(row),
  ];

  testWidgets(
    'zero links explains evidence retention and cannot confirm deletion',
    (tester) async {
      final before = rows('sections');
      await tester.pumpWidget(host());
      expect(find.text('将移除 0 条证据关联'), findsOneWidget);
      expect(find.text('证据实体本身会保留'), findsOneWidget);
      expect(find.text('只读预览，不是删除确认'), findsOneWidget);
      expect(find.text('删除'), findsNothing);
      expect(rows('sections'), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets('complete list scrolls at $width and 200% font', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (var i = 0; i < 30; i++) {
        link('evidence-$i');
      }
      await tester.pumpWidget(host(scale: 2));
      expect(find.text('将移除 30 条证据关联'), findsOneWidget);
      expect(find.textContaining('类型未知'), findsWidgets);
      await tester.scrollUntilVisible(
        find.textContaining('evidence-9'),
        500,
        scrollable: find.descendant(
          of: find.byKey(const Key('section-delete-preview-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('evidence-9').hitTestable(), findsOneWidget);
      expect(find.textContaining('private body'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('mutation marks frozen preview stale and refresh replaces it', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    link('new-evidence');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('预览已过期，请刷新；不能用于删除确认'), findsOneWidget);
    expect(find.text('将移除 0 条证据关联'), findsOneWidget);
    await tester.tap(find.text('刷新预览'));
    await tester.pump();
    expect(find.text('将移除 1 条证据关联'), findsOneWidget);
    expect(find.text('预览已过期，请刷新；不能用于删除确认'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('over budget and scope failures expose only a fixed error', (
    tester,
  ) async {
    link('secret-id');
    await tester.pumpWidget(host(maxLinks: 0));
    expect(find.text('无法生成完整预览：超出预算或无权读取'), findsOneWidget);
    expect(find.textContaining('secret-id'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(scoped: store.scoped('q')));
    expect(find.text('无法生成完整预览：超出预算或无权读取'), findsOneWidget);
    expect(find.text('章节'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unexpected database failure reports sanitized diagnostics', (
    tester,
  ) async {
    link('secret-diagnostic-id');
    db.raw.execute('DROP TABLE outline');
    final diagnostics = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = diagnostics.add;
    try {
      await tester.pumpWidget(host());
      expect(diagnostics, isNotEmpty);
      expect(diagnostics.first.stack, isNotNull);
      expect(find.text('无法生成完整预览：超出预算或无权读取'), findsOneWidget);
      expect(find.textContaining('secret-diagnostic-id'), findsNothing);
      expect(find.textContaining('private body'), findsNothing);
      expect(find.textContaining('no such table'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    } finally {
      FlutterError.onError = previous;
    }
  });

  for (final phase in ['initial capture', 'freshness timer']) {
    testWidgets('closed database $phase reports unexpected StateError', (
      tester,
    ) async {
      final separateDb = migrated(version: 10);
      var closed = false;
      addTearDown(() {
        if (!closed) separateDb.raw.close();
      });
      project(separateDb, 'p');
      final separateStore = WorkbenchStore.attach(
        rootPath: root.path,
        database: separateDb.raw,
        managed: separateDb,
      );
      final separateSection = separateStore.addSection('p', 'private heading');
      final diagnostics = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        if (phase == 'initial capture') {
          separateDb.raw.close();
          closed = true;
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SectionDeletePreviewDialog(
                store: separateStore,
                projectId: 'p',
                sectionId: separateSection.id,
              ),
            ),
          ),
        );
        if (phase == 'freshness timer') {
          separateDb.raw.close();
          closed = true;
          await tester.pump(const Duration(seconds: 2));
          expect(find.text('预览已过期，请刷新；不能用于删除确认'), findsOneWidget);
        } else {
          expect(find.text('无法生成完整预览：超出预算或无权读取'), findsOneWidget);
          expect(find.text('private heading'), findsNothing);
        }
        expect(diagnostics, isNotEmpty);
        expect(diagnostics.first.exception, isA<StateError>());
        expect(diagnostics.first.stack, isNotNull);
        expect(find.textContaining('closed'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        FlutterError.onError = previous;
      }
    });
  }

  testWidgets('writing page preview entry leaves all business rows unchanged', (
    tester,
  ) async {
    final tables = db.raw.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    final before = {
      for (final table in tables)
        table['name'] as String: rows(table['name'] as String),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WritingPage(
            store: store,
            projectId: 'p',
            onExportReport: () {},
            onPickEvidence: () {},
            onShowEntry: (_) {},
            onOpenDocument: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('预览删除影响'));
    await tester.pumpAndSettle();
    expect(find.byType(SectionDeletePreviewDialog), findsOneWidget);
    expect(find.text('只读预览，不是删除确认'), findsOneWidget);
    for (final table in before.keys) {
      expect(rows(table), before[table], reason: table);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
