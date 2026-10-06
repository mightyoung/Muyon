import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

import 'research_runtime_test.dart' show TestDatabase;

TestDatabase migrated({int version = 9}) {
  final db = TestDatabase(sqlite3.openInMemory());
  db.raw.execute('PRAGMA foreign_keys=ON');
  for (final step in ResearchModule().schema.migrations.take(version)) {
    step.migrate(db.raw);
  }
  return db;
}

void project(TestDatabase db, String id) => db.raw.execute(
  'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
  [id, id, '', ''],
);

ImportTarget target(String id, {bool create = true}) {
  final binding = WorkspaceBinding(
    workspaceId: 'workspace-$id',
    moduleId: 'research',
    nativeProjectId: id,
  );
  return create ? ImportTarget.create(binding) : ImportTarget.refresh(binding);
}

Future<ImportReceipt> commit(
  ResearchPackageExchange exchange,
  PreparedResearchPackage prepared,
  String operation,
) => exchange.commitImport(
  prepared,
  ImportIntent(
    operationId: operation,
    workspaceId: prepared.target.binding.workspaceId,
    moduleId: 'research',
    targetProjectId: prepared.target.binding.nativeProjectId,
    kind: prepared.target.kind,
    inputDigest: prepared.inputDigest,
    stagingToken: prepared.stagingToken,
  ),
);

void main() {
  test(
    'populated v8 upgrades to v9 preserving rows and seeding current objects',
    () async {
      final db = migrated(version: 8);
      addTearDown(db.raw.close);
      project(db, 'p');
      db.raw.execute(
        "INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES('d','p','paper.md','paper.md','hash')",
      );
      db.raw.execute(
        "INSERT INTO entries VALUES('e','p','claims','Evidence','{}')",
      );
      db.raw.execute(
        "INSERT INTO tasks VALUES('t',1,'p','Old','', '{}'),('t',2,'p','Latest','', '{}')",
      );
      db.raw.execute("INSERT INTO runs VALUES('r','t',2,'completed',1,'{}')");
      db.raw.execute(
        "INSERT INTO sections(id,project_id,heading,position) VALUES('s','p','Argument',1)",
      );
      db.raw.execute(
        "INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES('o','p','Argument','e','s')",
      );
      final cards = CardStore(db);
      final first = await cards.save(
        projectId: 'p',
        cardId: 'c',
        expectedHead: null,
        bodyMarkdown: 'Before upgrade',
      );
      final latest = await cards.save(
        projectId: 'p',
        cardId: 'c',
        expectedHead: first.revision.revisionId,
        bodyMarkdown: 'Current card',
      );
      await cards.registerDocument(
        projectId: 'p',
        localDocumentId: 'canonical',
        bytes: [1],
        fileName: 'old.pdf',
      );
      await cards.registerDocument(
        projectId: 'p',
        localDocumentId: 'canonical',
        bytes: [2],
        fileName: 'current.pdf',
      );
      final tables = [
        'projects',
        'documents',
        'entries',
        'tasks',
        'runs',
        'sections',
        'outline',
        'rk_cards',
        'rk_revisions',
        'rk_documents',
        'canonical_object_map',
      ];
      final before = {
        for (final t in tables)
          t: jsonEncode(
            db.raw
                .select('SELECT * FROM $t')
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
          ),
      };
      final schema = ResearchModule().schema;
      expect(
        schema.migrations.take(8).map((m) => m.definitionDigest),
        orderedEquals(List.generate(8, (i) => 'research-schema-${i + 1}')),
      );
      for (var i = 0; i < 6; i++) {
        expect(
          identical(schema.migrations[i].migrate, WorkbenchStore.migrations[i]),
          true,
        );
      }
      await db.write(schema.migrations.last.migrate);
      for (final t in tables) {
        expect(
          jsonEncode(
            db.raw
                .select('SELECT * FROM $t')
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
          ),
          before[t],
          reason: t,
        );
      }
      final changes = ModuleChangeLog.since(db.raw, 'research', 0);
      expect(changes, hasLength(8));
      expect(
        changes.every(
          (c) => c.ref.nativeProjectId == 'p' && c.op == ChangeOp.upsert,
        ),
        true,
      );
      final task = changes.singleWhere((c) => c.ref.objectType == 'task');
      expect(task.ref.objectId, 't');
      expect(task.ref.revisionRef, '2');
      expect(task.summary, 'Latest');
      final card = changes.singleWhere((c) => c.ref.objectType == 'card');
      expect(card.ref.objectId, 'c');
      expect(card.ref.revisionRef, latest.revision.revisionId);
      expect(card.ref.contentDigest, latest.revision.contentDigest);
      expect(card.summary, 'Current card');
      final document = changes.singleWhere(
        (c) => c.ref.objectId == 'canonical',
      );
      expect(document.summary, 'current.pdf');
      expect(document.ref.contentDigest, sha256.convert([2]).toString());
    },
  );

  test('canonical package import logs mapped identities inherited heads and receipt replay', () async {
    final first = migrated(), second = migrated();
    addTearDown(first.raw.close);
    addTearDown(second.raw.close);
    project(first, 'source');
    final source = CardStore(first), destination = CardStore(second);
    final sender = ResearchPackageExchange(source),
        receiver = ResearchPackageExchange(destination);
    final doc = await source.registerDocument(
      projectId: 'source',
      localDocumentId: 'original-doc',
      bytes: [1, 2],
      fileName: 'source.pdf',
    );
    final citation = CardCitation(
      citationId: 'citation',
      source: SourceRef(
        documentRef: doc,
        contentDigest: sha256.convert([1, 2]).toString(),
        pageIndex: 0,
        quote: 'quote',
      ),
    );
    final initial = await source.save(
      projectId: 'source',
      cardId: 'original-card',
      expectedHead: null,
      bodyMarkdown: 'Initial',
      citations: [citation],
    );
    final prepared = receiver.prepareBytes(
      await sender.exportBytes('source', ['original-card']),
      target('local'),
    );
    await commit(receiver, prepared, 'import');
    final mapping = second.raw.select(
      'SELECT local_object_id FROM canonical_object_map WHERE object_key=?',
      [initial.revision.objectKey.token],
    ).single;
    final localId = mapping['local_object_id'] as String;
    expect(localId, isNot('original-card'));
    var changes = ModuleChangeLog.since(second.raw, 'research', 0);
    expect(changes, hasLength(2));
    final card = changes.singleWhere((c) => c.ref.objectType == 'card');
    expect(card.ref.objectId, localId);
    expect(card.ref.nativeProjectId, 'local');
    expect(card.ref.revisionRef, initial.revision.revisionId);
    expect(card.ref.contentDigest, initial.revision.contentDigest);
    expect(card.summary, 'Initial');
    final document = changes.singleWhere((c) => c.ref.objectType == 'document');
    expect(document.ref.objectId, isNot('original-doc'));
    expect(document.ref.nativeProjectId, 'local');
    expect(document.ref.contentDigest, citation.source.contentDigest);
    await commit(receiver, prepared, 'import');
    expect(ModuleChangeLog.since(second.raw, 'research', 0), hasLength(2));
    final inherited = await source.save(
      projectId: 'source',
      cardId: 'original-card',
      expectedHead: initial.revision.revisionId,
      bodyMarkdown: 'Inherited',
      citations: [citation],
    );
    final next = receiver.prepareBytes(
      await sender.exportBytes('source', ['original-card']),
      target('local', create: false),
    );
    await commit(receiver, next, 'update');
    changes = ModuleChangeLog.since(second.raw, 'research', card.sequence);
    expect(changes.single.ref.objectId, localId);
    expect(changes.single.ref.revisionRef, inherited.revision.revisionId);
    expect(changes.single.summary, 'Inherited');
    final local = await destination.save(
      projectId: 'local',
      cardId: localId,
      expectedHead: inherited.revision.revisionId,
      bodyMarkdown: 'Local fork',
      citations: [citation],
    );
    final remote = await source.save(
      projectId: 'source',
      cardId: 'original-card',
      expectedHead: inherited.revision.revisionId,
      bodyMarkdown: 'Remote fork',
      citations: [citation],
    );
    final cursor = ModuleChangeLog.since(
      second.raw,
      'research',
      0,
    ).last.sequence;
    final fork = receiver.prepareBytes(
      await sender.exportBytes('source', ['original-card']),
      target('local', create: false),
    );
    final receipt = await commit(receiver, fork, 'fork');
    expect(receipt.result['conflicts'], 1);
    expect(
      destination.get('local', localId)!.revision.revisionId,
      local.revision.revisionId,
    );
    expect(
      second.raw
          .select('SELECT revision_id FROM rk_conflicts')
          .single['revision_id'],
      remote.revision.revisionId,
    );
    expect(
      ModuleChangeLog.since(second.raw, 'research', cursor),
      isEmpty,
      reason: 'A retained fork does not replace the projected current head',
    );
  });

  test('canonical import abort rolls back mapped objects logs and receipt together', () async {
    final first = migrated(), second = migrated();
    addTearDown(first.raw.close);
    addTearDown(second.raw.close);
    project(first, 'source');
    final source = CardStore(first);
    final sender = ResearchPackageExchange(source);
    final doc = await source.registerDocument(
      projectId: 'source',
      localDocumentId: 'doc',
      bytes: [1],
      fileName: 'rollback.pdf',
    );
    await source.save(
      projectId: 'source',
      cardId: 'card',
      expectedHead: null,
      bodyMarkdown: 'Will roll back',
      citations: [
        CardCitation(
          citationId: 'citation',
          source: SourceRef(
            documentRef: doc,
            contentDigest: sha256.convert([1]).toString(),
            pageIndex: 0,
            quote: 'quote',
          ),
        ),
      ],
    );
    final receiver = ResearchPackageExchange(CardStore(second));
    final prepared = receiver.prepareBytes(
      await sender.exportBytes('source', ['card']),
      target('local'),
    );
    second.raw.execute(
      "CREATE TRIGGER fail_import_receipt BEFORE INSERT ON rk_import_receipts BEGIN SELECT RAISE(ABORT,'test failure after object writes'); END",
    );
    await expectLater(
      commit(receiver, prepared, 'operation'),
      throwsA(isA<SqliteException>()),
    );
    for (final table in [
      'projects',
      'canonical_object_map',
      'rk_cards',
      'rk_revisions',
      'rk_documents',
      'rk_import_receipts',
      ModuleChangeLog.table,
    ]) {
      expect(second.raw.select('SELECT * FROM $table'), isEmpty, reason: table);
    }
    second.raw.execute('DROP TRIGGER fail_import_receipt');
    await commit(receiver, prepared, 'operation');
    expect(
      ModuleChangeLog.since(
        second.raw,
        'research',
        0,
      ).singleWhere((c) => c.ref.objectType == 'card').summary,
      'Will roll back',
    );
  });

  test(
    'delete ordering preserves tombstones and latest task falls back',
    () async {
      final db = migrated();
      addTearDown(db.raw.close);
      final temp = Directory.systemTemp.createTempSync('projection-delete-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final store = WorkbenchStore.attach(
        rootPath: temp.path,
        database: db.raw,
        managed: db,
      );
      project(db, 'p');
      db.raw.execute(
        "INSERT INTO entries VALUES('e','p','claims','Evidence','{}')",
      );
      final task1 = await store.write(
        () => store.saveTask(
          projectId: 'p',
          title: 'Original task',
          goal: '',
          spec: {},
        ),
      );
      final task2 = await store.write(
        () => store.saveTask(
          id: task1.id,
          projectId: 'p',
          title: 'Latest task',
          goal: '',
          spec: {},
        ),
      );
      final run = await store.write(() => store.startManualRun(task2));
      final section = await store.write(
        () => store.addSection('p', 'Argument'),
      );
      await store.write(() => store.cite(section.id, 'e'));
      final cards = CardStore(db);
      final card = await cards.save(
        projectId: 'p',
        cardId: 'c',
        expectedHead: null,
        bodyMarkdown: 'Card',
      );
      final doc = await cards.registerDocument(
        projectId: 'p',
        localDocumentId: 'd',
        bytes: [1],
        fileName: 'doc.pdf',
      );
      final cursor = ModuleChangeLog.since(db.raw, 'research', 0).last.sequence;
      await store.write(() {
        db.raw.execute('DELETE FROM runs WHERE id=?', [run.id]);
        store.deleteSection(section.id);
        db.raw.execute('DELETE FROM rk_cards WHERE object_key=?', [
          card.revision.objectKey.token,
        ]);
        db.raw.execute('DELETE FROM rk_revisions WHERE object_key=?', [
          card.revision.objectKey.token,
        ]);
        db.raw.execute('DELETE FROM canonical_object_map WHERE object_key=?', [
          card.revision.objectKey.token,
        ]);
        db.raw.execute('DELETE FROM rk_documents WHERE object_key=?', [
          doc.token,
        ]);
        db.raw.execute('DELETE FROM canonical_object_map WHERE object_key=?', [
          doc.token,
        ]);
        db.raw.execute('DELETE FROM tasks WHERE id=? AND revision=2', [
          task1.id,
        ]);
      });
      var changes = ModuleChangeLog.since(db.raw, 'research', cursor);
      for (final type in ['run', 'outline', 'section', 'card', 'document']) {
        final change = changes.singleWhere((c) => c.ref.objectType == type);
        expect(change.op, ChangeOp.delete, reason: type);
        expect(change.ref.nativeProjectId, 'p');
        expect(change.summary, isNotEmpty);
      }
      expect(changes.last.ref.objectType, 'task');
      expect(changes.last.op, ChangeOp.upsert);
      expect(changes.last.ref.revisionRef, '1');
      expect(changes.last.summary, 'Original task');
      await store.write(
        () => db.raw.execute('DELETE FROM tasks WHERE id=?', [task1.id]),
      );
      changes = ModuleChangeLog.since(
        db.raw,
        'research',
        changes.last.sequence,
      );
      expect(changes.single.op, ChangeOp.delete);
      expect(changes.single.ref.objectId, task1.id);
    },
  );
}
