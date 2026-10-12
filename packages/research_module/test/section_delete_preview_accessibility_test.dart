import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/src/app/section_delete_preview.dart';
import 'package:research_module/src/core/store.dart';
import 'package:sqlite3/sqlite3.dart';

import 'change_log_test.dart' show migrated, project;
import 'research_runtime_test.dart' show TestDatabase;

const _refused = '无法生成完整预览：超出预算或无权读取';
const _failed = '预览读取失败，请重试';
const _stale = '预览已过期，请刷新；不能用于删除确认';
const _canary =
    'N2_ACCESS_CANARY path=/private/not-real/body.md '
    'uri=file:///not-real/evidence handle=secret-handle evidence=secret-id 正文secret-body';

void main() {
  late Directory root;
  late TestDatabase db;
  late WorkbenchStore store;
  late String sectionId;

  setUp(() {
    root = Directory.systemTemp.createTempSync('n2-accessibility-');
    db = migrated(version: 10);
    project(db, 'p');
    project(db, 'q');
    store = WorkbenchStore.attach(
      rootPath: root.path,
      database: db.raw,
      managed: db,
    );
    sectionId = store.addSection('p', '合成章节').id;
  });
  tearDown(() {
    db.raw.close();
    root.deleteSync(recursive: true);
  });

  void link(String id, {String projectId = 'p'}) {
    db.raw.execute(
      'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
      [id, projectId, 'claims', 'Synthetic', '{}'],
    );
    db.raw.execute(
      'INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES(?,?,?,?,?)',
      ['link-$id', 'p', 'Synthetic', id, sectionId],
    );
  }

  SectionDeletePreviewDialog dialog({
    int maxLinks = 500,
    WorkbenchStore? scoped,
  }) => SectionDeletePreviewDialog(
    store: scoped ?? store,
    projectId: 'p',
    sectionId: sectionId,
    maxLinks: maxLinks,
  );
  Widget host({double scale = 1, int maxLinks = 500, WorkbenchStore? scoped}) =>
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: dialog(maxLinks: maxLinks, scoped: scoped),
        ),
      );
  String semantics(WidgetTester tester) =>
      '${tester.getSemantics(find.byType(SectionDeletePreviewDialog)).toStringDeep()}\n'
      '${tester.semantics.simulatedAccessibilityTraversal().map((node) => node.getSemanticsData().label).join('\n')}';
  void assertNoCanary(WidgetTester tester) {
    expect(find.textContaining('N2_ACCESS_CANARY'), findsNothing);
    final labels = semantics(tester);
    for (final secret in [
      'N2_ACCESS_CANARY',
      '/private/not-real',
      'file:///',
      'secret-handle',
      'secret-id',
      'secret-body',
    ]) {
      expect(labels, isNot(contains(secret)));
    }
  }

  void failReads() => db.raw.createFunction(
    functionName: 'length',
    argumentCount: const AllowedArgumentCount(1),
    function: (_) => throw StateError(_canary),
  );
  void restoreReads() => db.raw.createFunction(
    functionName: 'length',
    argumentCount: const AllowedArgumentCount(1),
    function: (args) => (args.single as List<int>).length,
  );

  testWidgets(
    'current to stale updates a real live semantics region without remounting',
    (tester) async {
      await tester.pumpWidget(host());
      final before = tester.getSemantics(
        find.byType(SectionDeletePreviewDialog),
      );
      final beforeId = before.id;
      expect(before.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(before.getSemanticsData().label, contains('只读预览'));
      link('new');
      await tester.pump(const Duration(seconds: 2));
      final after = tester.getSemantics(
        find.byType(SectionDeletePreviewDialog),
      );
      expect(after.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(after.getSemanticsData().label, contains(_stale));
      expect(after.id, beforeId);
      expect(find.text(_stale), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unexpected capture error uses a fixed distinct label and hides its canary',
    (tester) async {
      failReads();
      final diagnostics = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        await tester.pumpWidget(host());
        expect(diagnostics, hasLength(1));
        expect(
          diagnostics.single.exceptionAsString(),
          contains('N2_ACCESS_CANARY'),
        );
        expect(find.text(_failed), findsOneWidget);
        expect(find.text(_refused), findsNothing);
        expect(semantics(tester), contains(_failed));
        assertNoCanary(tester);
        expect(find.byType(TextButton), findsNWidgets(2));
        restoreReads();
        await tester.tap(find.text('刷新预览'));
        await tester.pump();
        expect(find.text(_failed), findsNothing);
        expect(find.text('将移除 0 条证据关联'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      } finally {
        FlutterError.onError = previous;
      }
    },
  );

  testWidgets(
    'unexpected freshness error is announced as a read failure and stale',
    (tester) async {
      await tester.pumpWidget(host());
      failReads();
      final diagnostics = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        await tester.pump(const Duration(seconds: 2));
        expect(diagnostics, hasLength(1));
        expect(
          diagnostics.single.exceptionAsString(),
          contains('N2_ACCESS_CANARY'),
        );
        final node = tester.getSemantics(
          find.byType(SectionDeletePreviewDialog),
        );
        expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
        expect(node.getSemanticsData().label, contains(_failed));
        expect(node.getSemanticsData().label, contains(_stale));
        assertNoCanary(tester);
        restoreReads();
        await tester.tap(find.text('刷新预览'));
        await tester.pump();
        expect(semantics(tester), isNot(contains(_failed)));
        expect(semantics(tester), isNot(contains(_stale)));
        await tester.pumpWidget(const SizedBox());
      } finally {
        FlutterError.onError = previous;
      }
    },
  );

  for (final cause in ['budget', 'scope']) {
    testWidgets('$cause refusal stays distinct from unexpected errors', (
      tester,
    ) async {
      link(_canary);
      final diagnostics = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        await tester.pumpWidget(
          host(
            maxLinks: cause == 'budget' ? 0 : 500,
            scoped: cause == 'scope' ? store.scoped('q') : null,
          ),
        );
        expect(find.text(_refused), findsOneWidget);
        expect(find.text(_failed), findsNothing);
        expect(diagnostics, isEmpty);
        assertNoCanary(tester);
        await tester.pumpWidget(const SizedBox());
      } finally {
        FlutterError.onError = previous;
      }
    });
  }

  testWidgets(
    'restricted association identifiers stay out of the actual semantics tree',
    (tester) async {
      link(_canary, projectId: 'q');
      await tester.pumpWidget(host());
      expect(find.text('受限关联：详情不可读取'), findsOneWidget);
      expect(semantics(tester), contains('受限关联'));
      assertNoCanary(tester);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [280.0, 320.0]) {
    testWidgets(
      'narrow $width short window long title scrolls at 200 percent',
      (tester) async {
        tester.view.physicalSize = Size(width, 420);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        db.raw.execute('UPDATE sections SET heading=? WHERE id=?', [
          List.filled(50, '合成的长章节标题').join(),
          sectionId,
        ]);
        for (var i = 0; i < 20; i++) {
          link('allowed-$i');
        }
        await tester.pumpWidget(host(scale: 2));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.textContaining('证据 allowed-9'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('证据 allowed-9').hitTestable(),
          findsOneWidget,
        );
        expect(find.text('刷新预览').hitTestable(), findsOneWidget);
        expect(find.text('关闭').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'keyboard reaches refresh and close and no business confirmation action',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => dialog(),
                ),
                child: const Text('打开预览'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开预览'));
      await tester.pumpAndSettle();
      final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
      expect(
        buttons.map((b) => (b.child! as Text).data),
        unorderedEquals(['刷新预览', '关闭']),
      );
      final businessButtons = tester.semantics
          .simulatedAccessibilityTraversal()
          .where(
            (n) =>
                n.getSemanticsData().flagsCollection.isButton &&
                RegExp('删除|确认|保存|提交').hasMatch(n.getSemanticsData().label),
          );
      expect(businessButtons, isEmpty);
      link('after-open');
      for (
        var i = 0;
        i < 10 && !Focus.of(tester.element(find.text('刷新预览'))).hasFocus;
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(Focus.of(tester.element(find.text('刷新预览'))).hasFocus, isTrue);
      final before = db.raw.select('SELECT total_changes() AS n').single['n'];
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('将移除 1 条证据关联'), findsOneWidget);
      expect(db.raw.select('SELECT total_changes() AS n').single['n'], before);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(Focus.of(tester.element(find.text('关闭'))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SectionDeletePreviewDialog), findsNothing);
      expect(store.sections('p'), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
