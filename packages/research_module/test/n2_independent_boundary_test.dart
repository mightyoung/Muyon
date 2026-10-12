// N2-A independent boundary tests for the read-only section deletion preview.
//
// Baseline: da5b482619fde2dbaca0c84603135b1b81e94f13. Tests only; no production
// code is touched. Every database is a real temporary SQLite *file* migrated
// through ResearchModule().schema; previews come from the production
// `captureSectionDeletePreview` / `sectionDeletePreviewIsCurrent` /
// `SectionDeletePreviewDialog`; real deletions go through the registered
// research `delete_section` handler and `WorkbenchStore.deleteSection`.
// The preview algorithm is never re-implemented here: expectations are the
// *observed* effect of the production deletion on an isolated copy.
// All data is synthetic.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:research_module/src/app/section_delete_preview.dart';
import 'package:research_module/src/core/section_delete_preview.dart';
import 'package:sqlite3/sqlite3.dart';

import 'n2_independent_support.dart';

// Fixture: section `s` in project p carries seven links that exercise every
// classification branch. `s2` (p) and `sq` (q) carry links that must survive.
const sectionId = 's-target';
const readableLinks = {'l-dup', 'l-e1', 'l-note', 'l-xproj'};
const restrictedLinks = {'l-foreign', 'l-ghost', 'l-xmeta'};
const allTargetLinks = {...readableLinks, ...restrictedLinks};
// Identifiers that must never leave the preview for a restricted row.
const restrictedSecrets = [
  'l-foreign', 'l-ghost', 'l-xmeta', // link ids
  'e-q', 'ghost-evidence', 'e-2', // evidence ids behind restricted rows
];

void seed(Database db, {bool reverse = false}) {
  void run(String sql, [List<Object?> args = const []]) =>
      db.execute(sql, args);
  for (final p in ['p', 'q']) {
    run('INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)', [
      p,
      'Project $p',
      '',
      '',
    ]);
  }
  run(
    "INSERT INTO documents(id,project_id,relative_path) VALUES('d-p','p','a.md')",
  );
  run(
    "INSERT INTO documents(id,project_id,relative_path) VALUES('d-q','q','b.md')",
  );
  void entry(String id, String project) => run(
    'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
    [id, project, 'claims', 'title-$id', '{"quote":"private quote $id"}'],
  );
  void note(String id, String document) => run(
    'INSERT INTO notes(id,document_id,locator,text) VALUES(?,?,?,?)',
    [id, document, 'p1', 'private note $id'],
  );
  entry('e-1', 'p');
  entry('e-2', 'p');
  entry('e-q', 'q');
  // Uncited local evidence, used to add a genuinely new citation.
  entry('e-3', 'p');
  // Same ID as two current types inside p.
  entry('dup', 'p');
  run(
    "INSERT INTO tasks(id,revision,project_id,title,goal,spec) VALUES('t',1,'p','task','goal','{}')",
  );
  run(
    "INSERT INTO runs(id,task_id,task_revision,status,accepted,data) VALUES('dup','t',1,'completed',1,'{}')",
  );
  note('n-p', 'd-p');
  // Same ID: a foreign entry (q) and a local note (p).
  entry('xproj', 'q');
  note('xproj', 'd-p');

  final sections = [
    [sectionId, 'p', 'Target heading', 1, 1, 'private argument', 'unassessed'],
    ['s-sibling', 'p', 'Sibling', 1, 2, '', 'unassessed'],
    ['s-q', 'q', 'Q section', 1, 1, '', 'unassessed'],
  ];
  for (final s in reverse ? sections.reversed : sections) {
    run(
      'INSERT INTO sections(id,project_id,heading,level,position,argument,support) VALUES(?,?,?,?,?,?,?)',
      s,
    );
  }
  final links = [
    ['l-e1', 'p', 'Target heading', 'e-1', sectionId],
    ['l-note', 'p', 'Target heading', 'n-p', sectionId],
    ['l-dup', 'p', 'Target heading', 'dup', sectionId],
    ['l-ghost', 'p', 'Target heading', 'ghost-evidence', sectionId],
    ['l-foreign', 'p', 'Target heading', 'e-q', sectionId],
    // Link metadata in another project although the evidence is local to p.
    ['l-xmeta', 'q', 'Target heading', 'e-2', sectionId],
    ['l-xproj', 'p', 'Target heading', 'xproj', sectionId],
    ['l-sib', 'p', 'Sibling', 'e-1', 's-sibling'],
    ['l-q', 'q', 'Q section', 'e-q', 's-q'],
  ];
  if (reverse) {
    // Different physical insertion order and rowids for the same semantic set.
    run(
      "INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('tmp','p','x','e-1','s-sibling')",
    );
    run("DELETE FROM outline WHERE id='tmp'");
  }
  for (final l in reverse ? links.reversed : links) {
    run(
      'INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES(?,?,?,?,?)',
      l,
    );
  }
}

Future<N2IndependentWorkspace> workspace(
  String label, {
  bool reverse = false,
}) async {
  final ws = await N2IndependentWorkspace.create(label);
  seed(ws.raw, reverse: reverse);
  return ws;
}

ObjectRef currentSectionRef(
  N2IndependentWorkspace ws, [
  String id = sectionId,
]) => ws.runtime
    .resolveCurrent(
      ObjectRef(
        moduleId: 'research',
        objectType: 'section',
        objectId: id,
        nativeProjectId: 'p',
      ),
    )!
    .ref;

var _invocation = 0;

/// Calls the production `delete_section` write handler exactly as registered
/// by ResearchModule.registerTools. Host approval/receipts are out of scope;
/// the handler's own same-transaction digest recheck is what is exercised.
Future<ToolCallResult> deleteViaTool(
  N2IndependentWorkspace ws,
  String expectedDigest,
) {
  final registrar = N2IndependentRegistrar();
  ResearchModule().registerTools(registrar);
  final ref = currentSectionRef(ws);
  final request = ToolCallRequest(
    invocationId: 'n2-independent-${++_invocation}',
    toolId: 'research.delete_section',
    parameters: {'section_id': sectionId, 'expected_digest': expectedDigest},
    scope: AssistantScope.selectedObjects([ref]),
  );
  final call = ToolCallContext(
    request: request,
    resolvedScope: ResolvedAssistantScope(
      requested: request.scope,
      objects: [ref],
    ),
    cancellation: ToolCancellationToken(),
  );
  return registrar.handlers['delete_section']!(
    N2IndependentToolContext(call, ws.runtime),
  );
}

Map<String, Object?> decode(String row) =>
    jsonDecode(row) as Map<String, Object?>;

void main() {
  final opened = <N2IndependentWorkspace>[];
  final readers = <N2IndependentReader>[];
  Future<N2IndependentWorkspace> open(
    String label, {
    bool reverse = false,
  }) async => (await workspace(label, reverse: reverse))..let(opened.add);
  N2IndependentReader reader(N2IndependentWorkspace ws) =>
      N2IndependentReader(ws.path)..let(readers.add);
  tearDown(() {
    for (final r in readers) {
      r.close();
    }
    readers.clear();
    for (final ws in opened) {
      ws.close();
    }
    opened.clear();
  });

  group('1. preview vs. real deletion on an isolated copy', () {
    // Mutations caught: preview outline query narrowed (e.g. `AND project_id=?`
    // or a JOIN on evidence) -> totalLinks/linkIds diverge from rows actually
    // removed; deleteSection widened to evidence tables -> evidence diff;
    // preview digest computed from a different snapshot -> digest equality.
    for (final path in [
      'delete_section tool',
      'WorkbenchStore.deleteSection',
    ]) {
      test(
        'preview link set equals rows removed by $path; evidence preserved',
        () async {
          final a = await open('preview');
          final b = await a.isolatedCopy('delete');
          opened.add(b);
          expect(
            n2IndependentRowSets(b.raw),
            n2IndependentRowSets(a.raw),
            reason: 'isolated copy starts identical',
          );

          final preview = captureSectionDeletePreview(a.store, 'p', sectionId);
          expect(
            preview.deleteDigest,
            sectionDeleteDigest(b.store, 'p', sectionId),
          );

          final before = n2IndependentRowSets(b.raw);
          if (path == 'delete_section tool') {
            final result = await deleteViaTool(b, preview.deleteDigest);
            expect(result.status, ToolCallStatus.succeeded);
          } else {
            b.store.deleteSection(sectionId);
          }
          final after = n2IndependentRowSets(b.raw);

          final removed = {
            for (final t in before.keys)
              if (before[t]!.difference(after[t] ?? {}).isNotEmpty)
                t: before[t]!.difference(after[t] ?? {}),
          };
          final added = {
            for (final t in after.keys)
              if (after[t]!.difference(before[t] ?? {}).isNotEmpty) t,
          };
          // Only the section row and its cascade disappear.
          expect(removed.keys.toSet(), {'sections', 'outline'});
          expect(removed['sections']!.map((r) => decode(r)['id']).toSet(), {
            sectionId,
          });
          final removedLinkIds = removed['outline']!
              .map((r) => decode(r)['id'])
              .toSet();
          expect(removedLinkIds, allTargetLinks);
          // Complete association set: count equals reality, readable ids are
          // exactly the removed ids minus the restricted ones.
          expect(preview.totalLinks, removedLinkIds.length);
          expect(preview.links.length, removedLinkIds.length);
          expect(preview.complete, isTrue);
          final previewIds = preview.links
              .map((l) => l.linkId)
              .whereType<String>()
              .toSet();
          expect(previewIds, readableLinks);
          expect(previewIds.difference(removedLinkIds), isEmpty);
          expect(
            preview.links.where((l) => l.status == 'restricted').length,
            restrictedLinks.length,
          );
          // Evidence entities claimed preserved really are preserved.
          expect(preview.evidencePreserved, isTrue);
          for (final t in [
            'entries',
            'notes',
            'runs',
            'tasks',
            'documents',
            'projects',
          ]) {
            expect(after[t], before[t], reason: '$t must be untouched');
          }
          // Sibling and foreign-project links survive.
          expect(
            b.raw
                .select('SELECT id FROM outline ORDER BY id')
                .map((r) => r['id']),
            ['l-q', 'l-sib'],
          );
          // The only additions are change-log rows (no hidden ledger writes).
          expect(added, {ModuleChangeLog.table});
          // The preview side stayed untouched.
          expect(n2IndependentRowSets(a.raw), before);
        },
      );
    }
  });

  group('2. same-ID types, missing types, cross-project links', () {
    // Mutations caught: dropping `link['project_id'] != projectId`
    // (section_delete_preview.dart:130) -> l-xmeta becomes readable;
    // dropping `AND project_id=?` / `d.project_id=?` in _localEvidenceTypes
    // (:176-189) -> l-foreign readable and ('entry','xproj') is asked;
    // `types.isNotEmpty &&` removed (:134) -> l-ghost readable;
    // `every` -> `any` (:135) -> l-dup readable when only run is denied.
    test('classification and leak-free projection', () async {
      final ws = await open('classify');
      final asked = <String>{};
      final preview = captureSectionDeletePreview(
        ws.store,
        'p',
        sectionId,
        canReadEvidence: (type, id) {
          asked.add('$type:$id');
          return true;
        },
      );
      expect(preview.links.map((l) => l.linkId), [
        'l-dup',
        'l-e1',
        null,
        null,
        'l-note',
        null,
        'l-xproj',
      ]);
      expect(preview.links.map((l) => l.status), [
        'unknown',
        'unknown',
        'restricted',
        'restricted',
        'unknown',
        'restricted',
        'unknown',
      ]);
      expect(preview.links.map((l) => l.evidenceId), [
        'dup',
        'e-1',
        null,
        null,
        'n-p',
        null,
        'xproj',
      ]);
      // A bare ID never acquires a type, even when unambiguous.
      expect(preview.links.map((l) => l.type), everyElement(isNull));
      // Permission is asked only for current local types; never for the
      // foreign twin of `xproj`, never for missing/foreign/cross-meta rows.
      expect(asked, {
        'entry:dup',
        'run:dup',
        'entry:e-1',
        'note:n-p',
        'note:xproj',
      });

      final model = jsonEncode(preview.toModel());
      for (final secret in restrictedSecrets) {
        expect(model, isNot(contains('"$secret"')), reason: secret);
      }
      for (final restricted in preview.links.where(
        (l) => l.status == 'restricted',
      )) {
        expect(restricted.toModel(), {'status': 'restricted'});
      }
    });

    test('denying one of two same-ID types restricts the whole row', () async {
      final ws = await open('dup-deny');
      final preview = captureSectionDeletePreview(
        ws.store,
        'p',
        sectionId,
        canReadEvidence: (type, _) => type != 'run',
      );
      final dup = preview.links.first;
      expect(dup.status, 'restricted');
      expect(dup.linkId, isNull);
      expect(dup.evidenceId, isNull);
      expect(jsonEncode(preview.toModel()), isNot(contains('"dup"')));
      // Unrelated readable rows unaffected.
      expect(preview.links.map((l) => l.linkId).whereType<String>().toSet(), {
        'l-e1',
        'l-note',
        'l-xproj',
      });
    });

    test(
      'scope refusal happens before any detail; foreign scoped store refused',
      () async {
        final ws = await open('scope');
        expect(
          () =>
              captureSectionDeletePreview(ws.store.scoped('q'), 'p', sectionId),
          throwsA(isA<SectionDeletePreviewRefused>()),
        );
        // Section from q requested under p: unavailable, no detail.
        expect(
          () => captureSectionDeletePreview(ws.store, 'p', 's-q'),
          throwsA(isA<SectionDeletePreviewRefused>()),
        );
        expect(ws.raw.autocommit, isTrue);
      },
    );

    testWidgets(
      'rendered dialog and semantics reveal no restricted identifiers',
      (tester) async {
        final ws = await open('ui-leak');
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SectionDeletePreviewDialog(
                store: ws.store,
                projectId: 'p',
                sectionId: sectionId,
              ),
            ),
          ),
        );
        expect(find.text('将移除 7 条证据关联'), findsOneWidget);
        expect(find.text('受限关联：详情不可读取'), findsNWidgets(3));
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .join('\n');
        final semantics = tester.getSemantics(
          find.byType(SectionDeletePreviewDialog),
        );
        final labels = <String>[];
        void walk(SemanticsNode node) {
          labels.add(node.label);
          node.visitChildren((child) {
            walk(child);
            return true;
          });
        }

        walk(semantics);
        final allSemantics = labels.join('\n');
        for (final secret in restrictedSecrets) {
          expect(texts, isNot(contains(secret)), reason: 'text $secret');
          expect(
            allSemantics,
            isNot(contains(secret)),
            reason: 'semantics $secret',
          );
        }
        handle.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('3. budget and order', () {
    // Mutations caught: `>` -> `>=` on the link budget
    // (section_delete_preview.dart:105) -> exact budget refused; removing the
    // budget check, or truncating the link list to maxLinks (e.g. `LIMIT`)
    // -> an over-budget call returns a "complete" preview with fewer rows.
    test(
      'every budget either refuses or returns the full set, never partial',
      () async {
        final ws = await open('budget');
        for (var maxLinks = 0; maxLinks <= 9; maxLinks++) {
          for (final maxBytes in [1, 1024, 2048, 4096, 8192, 1024 * 1024]) {
            SectionDeletePreview? preview;
            try {
              preview = captureSectionDeletePreview(
                ws.store,
                'p',
                sectionId,
                maxLinks: maxLinks,
                maxBytes: maxBytes,
              );
            } on SectionDeletePreviewRefused {
              preview = null;
            }
            expect(ws.raw.autocommit, isTrue);
            if (preview == null) continue;
            expect(preview.complete, isTrue);
            expect(
              preview.totalLinks,
              allTargetLinks.length,
              reason: 'maxLinks=$maxLinks maxBytes=$maxBytes',
            );
            expect(preview.links.length, allTargetLinks.length);
          }
        }
        expect(
          () => captureSectionDeletePreview(
            ws.store,
            'p',
            sectionId,
            maxLinks: 6,
          ),
          throwsA(isA<SectionDeletePreviewRefused>()),
        );
        expect(
          captureSectionDeletePreview(
            ws.store,
            'p',
            sectionId,
            maxLinks: 7,
          ).totalLinks,
          7,
        );
      },
    );

    testWidgets('over-budget dialog claims neither a count nor completeness', (
      tester,
    ) async {
      final ws = await open('budget-ui');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionDeletePreviewDialog(
              store: ws.store,
              projectId: 'p',
              sectionId: sectionId,
              maxLinks: 6,
            ),
          ),
        ),
      );
      expect(find.text('无法生成完整预览：超出预算或无权读取'), findsOneWidget);
      expect(find.text('完整关联列表'), findsNothing);
      expect(find.textContaining('将移除'), findsNothing);
      expect(find.textContaining('关联 l-'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    // Contract: outline_store.dart:166-170 "Sort by stable link identity:
    // insertion order is not part of the snapshot, while replacing an
    // otherwise identical citation must invalidate approval."
    // Mutations caught: dropping `ORDER BY id` from sectionDeleteDigest
    // (outline_store.dart:188) or from the preview list
    // (section_delete_preview.dart:126) -> digest/model differ between the
    // two physical orders; dropping link id from the snapshot -> replacement
    // no longer changes the digest.
    test('physical insertion order does not change digest or model', () async {
      final x = await open('order-x');
      final y = await open('order-y', reverse: true);
      // Precondition: physical order really differs.
      expect(
        x.raw
            .select(
              "SELECT id FROM outline WHERE section_id=? ORDER BY rowid",
              [sectionId],
            )
            .map((r) => r['id'])
            .toList(),
        isNot(
          y.raw
              .select(
                "SELECT id FROM outline WHERE section_id=? ORDER BY rowid",
                [sectionId],
              )
              .map((r) => r['id'])
              .toList(),
        ),
      );
      final px = captureSectionDeletePreview(x.store, 'p', sectionId);
      final py = captureSectionDeletePreview(y.store, 'p', sectionId);
      expect(py.deleteDigest, px.deleteDigest);
      expect(jsonEncode(py.toModel()), jsonEncode(px.toModel()));
      expect(
        sectionDeleteDigest(y.store, 'p', sectionId),
        sectionDeleteDigest(x.store, 'p', sectionId),
      );
    });

    test('replacing an identical citation with a new id changes the digest; '
        'unrelated rows do not', () async {
      final ws = await open('replace');
      final base = captureSectionDeletePreview(
        ws.store,
        'p',
        sectionId,
      ).deleteDigest;
      // Unrelated: sibling links, foreign sections, evidence content.
      ws.raw.execute("DELETE FROM outline WHERE id='l-sib'");
      ws.raw.execute("UPDATE entries SET title='changed' WHERE id='e-1'");
      ws.raw.execute("UPDATE sections SET heading='Q2' WHERE id='s-q'");
      expect(
        captureSectionDeletePreview(ws.store, 'p', sectionId).deleteDigest,
        base,
      );
      ws.raw.execute("DELETE FROM outline WHERE id='l-e1'");
      ws.raw.execute(
        "INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('l-e1b','p','Target heading','e-1',?)",
        [sectionId],
      );
      expect(
        captureSectionDeletePreview(ws.store, 'p', sectionId).deleteDigest,
        isNot(base),
      );
    });
  });

  group('4. independent read-only connection snapshot', () {
    // Mutations caught: any write inside capture/freshness (e.g. an
    // `UPDATE sections SET heading=heading` before BEGIN, persisting a
    // preview/receipt row, `ROLLBACK` -> `COMMIT` after a write) changes the
    // reader's data_version and/or row snapshot (incl. muyon_change_log via
    // the section/outline triggers).
    test('preview, failures and freshness commit nothing visible to another connection', () async {
      final ws = await open('reader');
      final r = reader(ws);
      final snapshot = r.snapshot();
      final version = r.dataVersion();
      final mainDigest = n2IndependentFileDigest(ws.path);
      final walDigest = n2IndependentFileDigest('${ws.path}-wal');

      final preview = captureSectionDeletePreview(ws.store, 'p', sectionId);
      captureSectionDeletePreview(
        ws.store,
        'p',
        sectionId,
        canReadEvidence: (_, _) => false,
      );
      expect(sectionDeletePreviewIsCurrent(ws.store, preview), isTrue);
      for (final refused in <void Function()>[
        () =>
            captureSectionDeletePreview(ws.store, 'p', sectionId, maxLinks: 0),
        () =>
            captureSectionDeletePreview(ws.store, 'p', sectionId, maxBytes: 1),
        () => captureSectionDeletePreview(ws.store, 'p', 'no-such-section'),
        () => captureSectionDeletePreview(ws.store.scoped('q'), 'p', sectionId),
        () =>
            captureSectionDeletePreview(ws.store, 'p', sectionId, maxLinks: -1),
      ]) {
        expect(refused, throwsA(isA<SectionDeletePreviewRefused>()));
      }
      expect(ws.raw.autocommit, isTrue);

      expect(r.dataVersion(), version);
      expect(r.snapshot(), snapshot);
      expect(n2IndependentFileDigest(ws.path), mainDigest);
      expect(n2IndependentFileDigest('${ws.path}-wal'), walDigest);

      // Positive control: the probe does see a real commit from the writer.
      ws.store.addSection('p', 'control');
      expect(r.dataVersion(), isNot(version));
      final changed = r.snapshot();
      expect(changed['rows:sections'], isNot(snapshot['rows:sections']));
      expect(
        changed['rows:${ModuleChangeLog.table}'],
        isNot(snapshot['rows:${ModuleChangeLog.table}']),
      );
    });

    testWidgets('dialog open, refresh and freshness ticks commit nothing', (
      tester,
    ) async {
      final ws = await open('reader-ui');
      final r = reader(ws);
      final snapshot = r.snapshot();
      final version = r.dataVersion();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SectionDeletePreviewDialog(
              store: ws.store,
              projectId: 'p',
              sectionId: sectionId,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('刷新预览'));
      await tester.pump(const Duration(seconds: 2));
      expect(r.dataVersion(), version);
      expect(r.snapshot(), snapshot);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('5. stale preview is never a valid deletion confirmation', () {
    // Boundary: no production execution entry consumes a SectionDeletePreview
    // (dialog actions are refresh/close only; WritingPage._delete calls
    // store.deleteSection without a digest; delete_section takes
    // expected_digest from read_object/outline_sections). These tests prove
    // (a) the preview reports itself stale, and (b) the digest value it
    // exposes - identical to sectionDeleteDigest - is refused by the real
    // delete_section same-transaction recheck once the cascade changed.
    // Mutations caught: removing the digest comparison in
    // sectionDeletePreviewIsCurrent (:208) or the status loop (:211-213);
    // removing `_requireExpected` in _outlineWrite (module_tools.dart:1679).
    final changes = <String, void Function(N2IndependentWorkspace ws)>{
      'link added via cite': (ws) => ws.store.cite(sectionId, 'e-3'),
      'link removed': (ws) => ws.store.removeOutline('l-e1'),
      'section edited (cascade heading)': (ws) => ws.store.updateSection(
        sectionId,
        heading: 'Renamed',
        level: 1,
        argument: 'x',
        support: 'unassessed',
      ),
      'identical citation replaced with new id': (ws) {
        ws.raw.execute("DELETE FROM outline WHERE id='l-e1'");
        ws.raw.execute(
          "INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('l-e1b','p','Target heading','e-1',?)",
          [sectionId],
        );
      },
      'restricted link metadata moved into scope': (ws) => ws.raw.execute(
        "UPDATE outline SET project_id='p' WHERE id='l-xmeta'",
      ),
    };
    for (final entry in changes.entries) {
      test('${entry.key}: stale and refused by delete_section', () async {
        final ws = await open('stale');
        final preview = captureSectionDeletePreview(ws.store, 'p', sectionId);
        expect(sectionDeletePreviewIsCurrent(ws.store, preview), isTrue);
        entry.value(ws);
        expect(sectionDeletePreviewIsCurrent(ws.store, preview), isFalse);

        final r = reader(ws);
        final snapshot = r.snapshot();
        final version = r.dataVersion();
        await expectLater(
          deleteViaTool(ws, preview.deleteDigest),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Outline changed; confirm again',
            ),
          ),
        );
        expect(r.dataVersion(), version);
        expect(r.snapshot(), snapshot);
        expect(
          ws.raw.select('SELECT 1 FROM sections WHERE id=?', [sectionId]),
          hasLength(1),
        );

        // Positive control: a fresh digest is accepted by the same handler.
        final fresh = captureSectionDeletePreview(ws.store, 'p', sectionId);
        expect(fresh.deleteDigest, isNot(preview.deleteDigest));
        final ok = await deleteViaTool(ws, fresh.deleteDigest);
        expect(ok.status, ToolCallStatus.succeeded);
        expect(
          ws.raw.select('SELECT 1 FROM sections WHERE id=?', [sectionId]),
          isEmpty,
        );
      });
    }

    test('evidence removed or permission revoked: display goes stale even '
        'though the cascade digest is unchanged', () async {
      final ws = await open('stale-status');
      var allowed = true;
      final preview = captureSectionDeletePreview(
        ws.store,
        'p',
        sectionId,
        canReadEvidence: (_, _) => allowed,
      );
      allowed = false;
      expect(sectionDeletePreviewIsCurrent(ws.store, preview), isFalse);
      allowed = true;
      expect(sectionDeletePreviewIsCurrent(ws.store, preview), isTrue);
      ws.raw.execute("DELETE FROM notes WHERE id='n-p'");
      expect(
        sectionDeleteDigest(ws.store, 'p', sectionId),
        preview.deleteDigest,
      );
      expect(sectionDeletePreviewIsCurrent(ws.store, preview), isFalse);
    });

    test('section or project gone: stale, never current', () async {
      final ws = await open('stale-gone');
      final preview = captureSectionDeletePreview(ws.store, 'p', sectionId);
      ws.store.deleteSection(sectionId);
      expect(sectionDeletePreviewIsCurrent(ws.store, preview), isFalse);
    });

    testWidgets(
      'dialog marks stale after a change and offers no delete action',
      (tester) async {
        final ws = await open('stale-ui');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SectionDeletePreviewDialog(
                store: ws.store,
                projectId: 'p',
                sectionId: sectionId,
              ),
            ),
          ),
        );
        expect(find.text('预览已过期，请刷新；不能用于删除确认'), findsNothing);
        ws.store.cite(sectionId, 'e-3');
        await tester.pump(const Duration(milliseconds: 1100));
        expect(find.text('预览已过期，请刷新；不能用于删除确认'), findsOneWidget);
        expect(find.text('只读预览，不是删除确认'), findsOneWidget);
        final buttons = tester
            .widgetList<ButtonStyleButton>(
              find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .map((b) => (b.child as Text).data)
            .toList();
        expect(buttons, ['刷新预览', '关闭']);
        expect(find.text('删除'), findsNothing);
        // Section still present: the stale dialog never deleted anything.
        expect(
          ws.raw.select('SELECT 1 FROM sections WHERE id=?', [sectionId]),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}

extension<T> on T {
  void let(void Function(T) f) => f(this);
}
