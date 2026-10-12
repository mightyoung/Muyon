// Linux N2 validation (task/linux-n2-preview-validation, candidate da5b482).
//
// Widget/semantics-level validation of the research section delete-impact
// preview on a Linux host WITHOUT a Linux desktop toolchain (no clang/cmake/
// ninja/pkg-config/GTK headers, no apps/muyon/linux runner). These tests are
// NOT a desktop interaction pass; they run under flutter_test on the Linux VM
// with TargetPlatform.linux where platform behavior matters.
//
// Tests that pin an observed shortcoming are named "FINDING:" and assert the
// behavior as observed at da5b482 so the suite stays a faithful record.
//
// Optional evidence: set N2_EVIDENCE_DIR to write rendered PNGs (synthetic
// data only, no user paths) using the system Noto CJK font when available.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/research_module.dart';
import 'package:research_module/src/app/section_delete_preview.dart';
import 'package:research_module/src/app/writing_page.dart';
import 'package:research_module/src/core/section_delete_preview.dart';

import 'change_log_test.dart' show migrated, project;
import 'research_runtime_test.dart' show TestDatabase;

const _stale = '预览已过期，请刷新；不能用于删除确认';
const _readOnly = '只读预览，不是删除确认';
const _retained = '证据实体本身会保留';
const _restricted = '受限关联：详情不可读取';
const _failure = '无法生成完整预览：超出预算或无权读取';
const _scrollKey = Key('section-delete-preview-scroll');
final _longTitle =
    '长标题章节：${List.filled(12, '多模态检索增强生成在低资源语言科研写作中的证据链可追溯性评估').join('')}';

String? get _evidenceDir => Platform.environment['N2_EVIDENCE_DIR'];
bool _fontsLoaded = false;

Future<void> _loadEvidenceFonts(WidgetTester tester) async {
  if (_fontsLoaded || _evidenceDir == null) return;
  await tester.runAsync(() async {
    for (final (family, path) in [
      ('N2Cjk', '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),
      (
        'MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  _fontsLoaded = true;
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = _evidenceDir;
  if (dir == null) return;
  final boundary = tester.renderObject(
    find.byKey(const Key('n2-shot')),
  ) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  late Directory root;
  late TestDatabase db;
  late WorkbenchStore store;
  late OutlineSection normal, mixed, longSection;

  void entry(String id, {String projectId = 'p'}) => db.raw.execute(
    "INSERT INTO entries(id,project_id,title,kind,data) VALUES(?,?,?,'claim','{\"body\":\"private body\"}')",
    [id, projectId, 'title $id'],
  );
  void link(
    String linkId,
    String? evidenceId,
    OutlineSection section, {
    String projectId = 'p',
  }) => db.raw.execute(
    'INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES(?,?,?,?,?)',
    [linkId, projectId, section.heading, evidenceId, section.id],
  );

  Map<String, List<Map<String, Object?>>> snapshot() => {
    for (final t in db.raw.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      t['name'] as String: [
        for (final r in db.raw.select('SELECT * FROM "${t['name']}"'))
          Map<String, Object?>.from(r),
      ],
  };

  setUp(() {
    root = Directory.systemTemp.createTempSync('linux-n2-preview-');
    db = migrated(version: 1 << 20); // all migrations
    project(db, 'p');
    project(db, 'q');
    store = WorkbenchStore.attach(
      rootPath: root.path,
      database: db.raw,
      managed: db,
    );
    // Synthetic research project fixture.
    normal = store.addSection('p', '普通关联章节');
    entry('ev-normal');
    link('link-normal', 'ev-normal', normal);

    mixed = store.addSection('p', '混合关联章节');
    for (var i = 0; i < 12; i++) {
      entry('ev-multi-$i');
      link('link-multi-${i.toString().padLeft(2, '0')}', 'ev-multi-$i', mixed);
    }
    entry('ev-other-project', projectId: 'q');
    // Cross-project link row (restricted in this project's view).
    link('link-restricted-secret', 'ev-other-project', mixed, projectId: 'q');
    // Link whose evidence entity no longer exists.
    link('link-missing-secret', 'ev-missing-secret', mixed);
    // Link without any evidence id.
    link('link-null-secret', null, mixed);

    longSection = store.addSection('p', _longTitle);
    entry('ev-long');
    link('link-long', 'ev-long', longSection);
  });
  tearDown(() {
    try {
      db.raw.close();
    } catch (_) {}
    root.deleteSync(recursive: true);
  });

  ThemeData theme() => ThemeData(
    fontFamily: _evidenceDir == null ? null : 'N2Cjk',
    useMaterial3: true,
  );

  Widget dialogHost(OutlineSection section, {double scale = 1}) => MaterialApp(
    theme: theme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(key: const Key('n2-shot'), child: child!),
    ),
    home: Scaffold(
      body: SectionDeletePreviewDialog(
        store: store,
        projectId: 'p',
        sectionId: section.id,
      ),
    ),
  );

  Widget pageHost({double scale = 1}) => MaterialApp(
    theme: theme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: RepaintBoundary(key: const Key('n2-shot'), child: child!),
    ),
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
  );

  void viewSize(WidgetTester tester, Size logical, {double dpr = 1}) {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = logical * dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder scrollable() => find.descendant(
    of: find.byKey(_scrollKey),
    matching: find.byType(Scrollable),
  );

  Finder cardButton(OutlineSection section, String tooltip) => find.descendant(
    of: find
        .ancestor(of: find.text(section.heading), matching: find.byType(Card))
        .first,
    matching: find.byTooltip(tooltip),
  );

  Future<void> openFromPage(WidgetTester tester, OutlineSection section) async {
    final heading = find.text(section.heading);
    await tester.scrollUntilVisible(
      heading,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final button = cardButton(section, '预览删除影响');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SectionDeletePreviewDialog), findsOneWidget);
  }

  group('counts, retention and restricted IDs', () {
    testWidgets('normal section: one link, full IDs, retention copy', (
      tester,
    ) async {
      await _loadEvidenceFonts(tester);
      viewSize(tester, const Size(1280, 800));
      await tester.pumpWidget(dialogHost(normal));
      expect(find.text('将移除 1 条证据关联'), findsOneWidget);
      expect(find.text('完整关联列表'), findsOneWidget);
      expect(find.text(_retained), findsOneWidget);
      expect(find.text(_readOnly), findsOneWidget);
      expect(find.textContaining('关联 link-normal'), findsOneWidget);
      expect(find.textContaining('证据 ev-normal'), findsOneWidget);
      expect(find.textContaining('private body'), findsNothing);
      await _shot(tester, '01-normal-1280x800');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'mixed section: total counts restricted/missing/null links, IDs hidden',
      (tester) async {
        await _loadEvidenceFonts(tester);
        viewSize(tester, const Size(1280, 800));
        await tester.pumpWidget(dialogHost(mixed));
        expect(find.text('将移除 15 条证据关联'), findsOneWidget);
        // 3 restricted rows: cross-project, missing entity, null evidence id.
        expect(find.text(_restricted), findsNWidgets(3));
        for (final secret in [
          'link-restricted-secret',
          'ev-other-project',
          'link-missing-secret',
          'ev-missing-secret',
          'link-null-secret',
        ]) {
          expect(find.textContaining(secret), findsNothing, reason: secret);
        }
        // All 12 normal links are present in the (non-lazy) column.
        for (var i = 0; i < 12; i++) {
          expect(
            find.textContaining('ev-multi-$i\n', skipOffstage: false),
            findsOneWidget,
          );
        }
        await _shot(tester, '02-mixed-1280x800');
        await tester.pumpWidget(const SizedBox());
      },
    );

    test('FINDING: restricted model of core preview hides IDs; canReadEvidence denial', () {
      final denied = captureSectionDeletePreview(
        store,
        'p',
        mixed.id,
        canReadEvidence: (type, id) => id != 'ev-multi-3',
      );
      final model = denied.toModel();
      expect(model['totalLinks'], 15);
      final links = model['links']! as List;
      expect(
        links.where((l) => (l as Map)['status'] == 'restricted'),
        hasLength(4),
      );
      expect(model.toString(), isNot(contains('ev-multi-3')));
      expect(model.toString(), isNot(contains('secret')));
      expect(model.toString(), isNot(contains(root.path)));
      // The dialog has no canReadEvidence parameter, so in the UI "restricted"
      // only arises from cross-project/missing/null evidence links; a missing
      // evidence entity is shown with the same copy as a permission restriction.
    });

    testWidgets(
      'long title wraps without overflow at 200% in a 480x360 window',
      (tester) async {
        await _loadEvidenceFonts(tester);
        viewSize(tester, const Size(480, 360));
        await tester.pumpWidget(dialogHost(longSection, scale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(_longTitle, skipOffstage: false), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('ev-long'),
          200,
          scrollable: scrollable(),
        );
        expect(find.textContaining('ev-long').hitTestable(), findsOneWidget);
        expect(find.text('刷新预览').hitTestable(), findsOneWidget);
        expect(find.text('关闭').hitTestable(), findsOneWidget);
        await _shot(tester, '03-long-title-200pct-480x360');
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('window sizes x text scale (no overflow, actions reachable, list scrolls)', () {
    for (final (size, dpr) in [
      (const Size(1920, 1200), 1.0),
      (const Size(1280, 800), 1.5),
      (const Size(800, 600), 1.0),
      (const Size(480, 360), 2.0),
      (const Size(320, 480), 1.0),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '${size.width.toInt()}x${size.height.toInt()} dpr$dpr text${scale}x',
          (tester) async {
            await _loadEvidenceFonts(tester);
            viewSize(tester, size, dpr: dpr);
            await tester.pumpWidget(pageHost(scale: scale));
            await tester.pumpAndSettle();
            await openFromPage(tester, mixed);
            expect(tester.takeException(), isNull);
            expect(find.text('刷新预览').hitTestable(), findsOneWidget);
            expect(find.text('关闭').hitTestable(), findsOneWidget);
            // Last link must be reachable by scrolling.
            await tester.scrollUntilVisible(
              find.textContaining('ev-multi-11\n'),
              150,
              scrollable: scrollable(),
            );
            await tester.pumpAndSettle();
            final viewport = tester.getRect(scrollable());
            final item = tester.getRect(find.textContaining('ev-multi-11\n'));
            final scrollState = tester.state<ScrollableState>(scrollable());
            debugPrint(
              'N2 layout ${size.width.toInt()}x${size.height.toInt()} '
              'text${scale}x: listViewport=${viewport.size} '
              'item=${item.size} maxScroll='
              '${scrollState.position.maxScrollExtent.toStringAsFixed(0)}',
            );
            // The item must at least intersect the visible list viewport.
            expect(viewport.overlaps(item), isTrue);
            if (item.height > viewport.height) {
              debugPrint(
                'N2 FINDING: one link (${item.height}px) is taller than the '
                'visible list viewport (${viewport.height}px)',
              );
            } else {
              expect(
                find.textContaining('ev-multi-11\n').hitTestable(),
                findsOneWidget,
              );
            }
            final pos = tester.state<ScrollableState>(scrollable()).position;
            pos.jumpTo(pos.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(find.text(_restricted).last.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (scale == 2.0 && (size.width <= 480 || size.width == 1920)) {
              await _shot(
                tester,
                '04-page-dialog-${size.width.toInt()}x${size.height.toInt()}-text2x',
              );
            }
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  });

  group('staleness and refresh after synthetic data changes', () {
    testWidgets(
      'add link -> stale; refresh -> new count; stale only after change',
      (tester) async {
        await _loadEvidenceFonts(tester);
        viewSize(tester, const Size(1280, 800));
        await tester.pumpWidget(dialogHost(normal));
        await tester.pump(const Duration(seconds: 3));
        expect(find.text(_stale), findsNothing, reason: 'no change, no stale');
        entry('ev-added');
        link('link-added', 'ev-added', normal);
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.text(_stale), findsOneWidget);
        // Old frozen numbers remain visible while stale.
        expect(find.text('将移除 1 条证据关联'), findsOneWidget);
        await _shot(tester, '05-stale-banner');
        await tester.tap(find.text('刷新预览'));
        await tester.pump();
        expect(find.text(_stale), findsNothing);
        expect(find.text('将移除 2 条证据关联'), findsOneWidget);
        await _shot(tester, '06-after-refresh');
        // A second change after refresh is detected again.
        db.raw.execute('DELETE FROM outline WHERE id=?', ['link-added']);
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.text(_stale), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'evidence entity deleted (digest unchanged) -> stale via status',
      (tester) async {
        await tester.pumpWidget(dialogHost(normal));
        db.raw.execute("DELETE FROM entries WHERE id='ev-normal'");
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.text(_stale), findsOneWidget);
        await tester.tap(find.text('刷新预览'));
        await tester.pump();
        expect(find.text(_restricted), findsOneWidget);
        expect(find.textContaining('ev-normal'), findsNothing);
        expect(find.text('将移除 1 条证据关联'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('heading edit -> stale; refresh shows new heading', (
      tester,
    ) async {
      await tester.pumpWidget(dialogHost(normal));
      db.raw.execute('UPDATE sections SET heading=? WHERE id=?', [
        '改名后章节',
        normal.id,
      ]);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text(_stale), findsOneWidget);
      await tester.tap(find.text('刷新预览'));
      await tester.pump();
      expect(find.text('改名后章节'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'FINDING: section deleted elsewhere -> refresh shows budget/permission copy',
      (tester) async {
        await tester.pumpWidget(dialogHost(normal));
        store.deleteSection(normal.id);
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.text(_stale), findsOneWidget);
        await tester.tap(find.text('刷新预览'));
        await tester.pump();
        // Observed: a deleted section is reported as "超出预算或无权读取".
        expect(find.text(_failure), findsOneWidget);
        expect(find.textContaining(normal.id), findsNothing);
        await _shot(tester, '07-section-deleted-refresh');
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('preview is not a deletion authorization', () {
    testWidgets('dialog offers only refresh/close; closing changes nothing; '
        'page delete still needs its own confirm', (tester) async {
      viewSize(tester, const Size(1280, 800));
      final before = snapshot();
      await tester.pumpWidget(pageHost());
      await openFromPage(tester, mixed);
      final dialog = find.byType(SectionDeletePreviewDialog);
      final buttons = find.descendant(
        of: dialog,
        matching: find.byWidgetPredicate(
          (w) => w is ButtonStyleButton || w is IconButton,
        ),
      );
      expect(buttons, findsNWidgets(2));
      expect(
        find.descendant(of: dialog, matching: find.text('删除')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(FilledButton)),
        findsNothing,
      );
      await tester.tap(find.text('刷新预览'));
      await tester.pump();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(snapshot(), before);
      // Real deletion still goes through the separate confirmation dialog.
      await tester.tap(cardButton(mixed, '删除段落'));
      await tester.pumpAndSettle();
      expect(find.text('删除段落'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(snapshot(), before);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('keyboard (TargetPlatform.linux)', () {
    testWidgets('Tab reaches refresh/close, Enter activates, Escape closes', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        viewSize(tester, const Size(1280, 800));
        final before = snapshot();
        await tester.pumpWidget(pageHost());
        await openFromPage(tester, mixed);
        final seen = <String>[];
        for (var i = 0; i < 4; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final focus = FocusManager.instance.primaryFocus;
          final label = focus?.context == null
              ? 'none'
              : (focus!.context!
                                .findAncestorWidgetOfExactType<TextButton>()
                                ?.child
                            as Text?)
                        ?.data ??
                    focus.debugLabel ??
                    'unknown';
          seen.add(label);
        }
        // Focus stays trapped in the dialog and cycles over its 2 actions.
        expect(seen, containsAll(['刷新预览', '关闭']));
        expect(
          seen.toSet().difference({'刷新预览', '关闭'}),
          isEmpty,
          reason: '$seen',
        );
        // Activate refresh with Enter while focused on it.
        while ((FocusManager.instance.primaryFocus?.context
                        ?.findAncestorWidgetOfExactType<TextButton>()
                        ?.child
                    as Text?)
                ?.data !=
            '刷新预览') {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.byType(SectionDeletePreviewDialog), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(SectionDeletePreviewDialog), findsNothing);
        expect(snapshot(), before);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('FINDING: keyboard-only scroll of the impact list', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        viewSize(tester, const Size(800, 600));
        await tester.pumpWidget(pageHost(scale: 2));
        await openFromPage(tester, mixed);
        final state = tester.state<ScrollableState>(scrollable());
        expect(state.position.maxScrollExtent, greaterThan(0));
        final results = <String, double>{};
        // Focus on a dialog action first, as a keyboard user would.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final key in [
          LogicalKeyboardKey.pageDown,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.end,
          LogicalKeyboardKey.space,
        ]) {
          state.position.jumpTo(0);
          await tester.pump();
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
          results[key.keyLabel] = state.position.pixels;
        }
        debugPrint(
          'N2 keyboard scroll offsets (max '
          '${state.position.maxScrollExtent.toStringAsFixed(0)}): $results',
        );
        // Record observation; the scroll view is not focusable and has no
        // PrimaryScrollController on desktop, so keys may not scroll it.
        final scrolled = results.values.any((v) => v > 0);
        debugPrint('N2 keyboard scroll reachable: $scrolled');
        // Observed at da5b482: none of these keys move the impact list.
        expect(scrolled, isFalse);
        // Mouse wheel over the list does scroll it.
        state.position.jumpTo(0);
        await tester.pump();
        final pointer = TestPointer(1, ui.PointerDeviceKind.mouse);
        pointer.hover(tester.getCenter(scrollable()));
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
        await tester.pumpAndSettle();
        debugPrint('N2 mouse wheel offset: ${state.position.pixels}');
        expect(state.position.pixels, greaterThan(0));
        if (find.byType(SectionDeletePreviewDialog).evaluate().isNotEmpty) {
          await tester.pumpWidget(const SizedBox());
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('semantics', () {
    testWidgets('dialog semantics: route name, buttons, texts, restricted rows', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        viewSize(tester, const Size(1280, 800));
        await tester.pumpWidget(pageHost());
        await openFromPage(tester, mixed);
        for (final label in ['刷新预览', '关闭']) {
          expect(
            tester.getSemantics(find.text(label)),
            matchesSemantics(
              label: label,
              isButton: true,
              hasTapAction: true,
              isFocusable: true,
              hasEnabledState: true,
              isEnabled: true,
              hasFocusAction: true,
            ),
            reason: label,
          );
        }
        expect(find.bySemanticsLabel('删除章节影响预览'), findsOneWidget);
        expect(find.bySemanticsLabel(_readOnly), findsOneWidget);
        expect(find.bySemanticsLabel(_retained), findsOneWidget);
        expect(find.bySemanticsLabel('将移除 15 条证据关联'), findsOneWidget);
        expect(find.bySemanticsLabel(_restricted), findsNWidgets(3));
        expect(find.bySemanticsLabel(RegExp('secret')), findsNothing);
        // Route naming / scoping of the dialog.
        final routes = <SemanticsNode>[];
        void walk(SemanticsNode n) {
          final d = n.getSemanticsData();
          if (d.flagsCollection.namesRoute || d.flagsCollection.scopesRoute) {
            routes.add(n);
          }
          n.visitChildren((c) {
            walk(c);
            return true;
          });
        }

        walk(
          tester
              .binding
              .renderViews
              .first
              .owner!
              .semanticsOwner!
              .rootSemanticsNode!,
        );
        debugPrint(
          'N2 route semantics: ${[for (final r in routes) '${r.getSemanticsData().label}|namesRoute=${r.getSemanticsData().flagsCollection.namesRoute}|scopesRoute=${r.getSemanticsData().flagsCollection.scopesRoute}']}',
        );
        expect(routes, isNotEmpty);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
        handle.dispose();
      }
    });

    testWidgets('FINDING: stale notice is not a live region', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(dialogHost(normal));
        link('link-late', null, normal);
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.text(_stale), findsOneWidget);
        final data = tester.getSemantics(find.text(_stale)).getSemanticsData();
        debugPrint('N2 stale liveRegion=${data.flagsCollection.isLiveRegion}');
        expect(data.flagsCollection.isLiveRegion, isFalse);
        await tester.pumpWidget(const SizedBox());
      } finally {
        handle.dispose();
      }
    });
  });

  group('error copy does not leak DB errors or paths', () {
    testWidgets('broken outline table -> fixed copy only', (tester) async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      try {
        db.raw.execute('DROP TABLE outline');
        await tester.pumpWidget(dialogHost(mixed));
        expect(find.text(_failure), findsOneWidget);
        for (final leak in [
          'no such table',
          'SqliteException',
          'outline',
          root.path,
          Directory.systemTemp.path,
          '/home/',
          'secret',
        ]) {
          expect(find.textContaining(leak), findsNothing, reason: leak);
        }
        expect(reported, isNotEmpty, reason: 'diagnostics go to logs, not UI');
        await _shot(tester, '08-db-error-fixed-copy');
        await tester.pumpWidget(const SizedBox());
      } finally {
        FlutterError.onError = previous;
      }
    });

    testWidgets('out-of-scope project -> fixed copy, no heading', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionDeletePreviewDialog(
              store: store.scoped('q'),
              projectId: 'p',
              sectionId: mixed.id,
            ),
          ),
        ),
      );
      expect(find.text(_failure), findsOneWidget);
      expect(find.text('混合关联章节'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('over budget -> fixed copy, no IDs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionDeletePreviewDialog(
              store: store,
              projectId: 'p',
              sectionId: mixed.id,
              maxLinks: 5,
            ),
          ),
        ),
      );
      expect(find.text(_failure), findsOneWidget);
      expect(find.textContaining('link-'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
