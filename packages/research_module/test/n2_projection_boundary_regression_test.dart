import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/research_module.dart';
import 'package:research_module/src/core/section_delete_preview.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late Database source, clone;
  late WorkbenchStore store;
  const entryId = 'N2_ENTRY_ID_CANARY_94a7';
  const noteId = 'N2_NOTE_ID_CANARY_47c8';
  const runId = 'N2_RUN_ID_CANARY_80b3';
  String table(Database db, String name) => jsonEncode([
    for (final row in db.select('SELECT * FROM "$name" ORDER BY rowid'))
      Map<String, Object?>.from(row),
  ]);
  Map<String, String> all(Database db) => {
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    ))
      row['name'] as String: table(db, row['name'] as String),
  };
  setUp(() {
    root = Directory.systemTemp.createTempSync('n2-boundary-clone-');
    final path = '${root.path}/source.sqlite';
    var db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys=ON');
    for (final migration in ResearchModule().schema.migrations) {
      migration.migrate(db);
    }
    db.execute(
      "INSERT INTO projects(id,title,question,next_step) VALUES('p','P','',''),('q','Q','','')",
    );
    db.execute(
      "INSERT INTO sections VALUES('s','p','Section',1,1,'private argument','unassessed'),('keep','p','Other',1,2,'','unassessed')",
    );
    db.execute(
      "INSERT INTO entries VALUES(?,'p','claim','private entry','{\"price\":\"N2_PRICE_CANARY_64ba\"}')",
      [entryId],
    );
    db.execute(
      "INSERT INTO documents(id,project_id,relative_path,sha256) VALUES('d','p','private-relative','private-hash')",
    );
    db.execute(
      "INSERT INTO notes(id,document_id,locator,text) VALUES(?,'d','private locator','private quote')",
      [noteId],
    );
    db.execute(
      "INSERT INTO tasks VALUES('t',1,'p','private task','private goal','{}')",
    );
    db.execute(
      "INSERT INTO runs VALUES(?,'t',1,'completed',1,'{\"value\":\"private run\"}')",
      [runId],
    );
    for (final pair in {
      'entry-link': entryId,
      'note-link': noteId,
      'run-link': runId,
    }.entries) {
      db.execute("INSERT INTO outline VALUES(?,'p','Section',?,'s')", [
        pair.key,
        pair.value,
      ]);
    }
    db.execute(
      "INSERT INTO outline VALUES('foreign-metadata','q','Section',?,'s')",
      [entryId],
    );
    db.execute("INSERT INTO outline VALUES('unrelated','p','Other',?,'keep')", [
      entryId,
    ]);
    db.close();
    File(path).copySync('${root.path}/clone.sqlite');
    source = sqlite3.open(path);
    clone = sqlite3.open('${root.path}/clone.sqlite');
    source.execute('PRAGMA foreign_keys=ON');
    clone.execute('PRAGMA foreign_keys=ON');
    store = WorkbenchStore.attach(
      rootPath: '${root.path}/source-root',
      database: source,
    );
  });
  tearDown(() {
    clone.close();
    source.close();
    root.deleteSync(recursive: true);
  });

  test('actual isolated clone deletion exactly matches preview and preserves every evidence kind', () {
    final beforeSource = all(source), beforeClone = all(clone);
    expect(beforeClone, beforeSource);
    final preview = captureSectionDeletePreview(store.scoped('p'), 'p', 's');
    final digest = sectionDeleteDigest(store, 'p', 's');
    expect(preview.deleteDigest, digest);
    final cloneStore = WorkbenchStore.attach(
      rootPath: '${root.path}/clone-root',
      database: clone,
    ).scoped('p');
    expect(sectionDeleteDigest(cloneStore, 'p', 's'), digest);
    final affected = [
      for (final row in clone.select(
        "SELECT id FROM outline WHERE section_id='s' ORDER BY id",
      ))
        row['id'],
    ];
    expect(affected, [
      'entry-link',
      'foreign-metadata',
      'note-link',
      'run-link',
    ]);
    expect(preview.totalLinks, affected.length);
    expect(preview.links.length, affected.length);
    clone.execute('BEGIN IMMEDIATE');
    cloneStore.deleteSection('s');
    clone.execute('COMMIT');
    expect(clone.select("SELECT * FROM outline WHERE section_id='s'"), isEmpty);
    expect(clone.select("SELECT * FROM sections WHERE id='s'"), isEmpty);
    expect(
      clone.select("SELECT id FROM outline WHERE id='unrelated'"),
      hasLength(1),
    );
    expect(
      clone.select("SELECT id FROM sections WHERE id='keep'"),
      hasLength(1),
    );
    for (final name in [
      'entries',
      'documents',
      'notes',
      'tasks',
      'runs',
      'paper_bindings',
      'task_imports',
      'import_receipts',
    ]) {
      expect(
        table(clone, name),
        beforeClone[name],
        reason:
            'Actual deletion must preserve $name byte-equivalent row projection',
      );
    }
    expect(
      all(source),
      beforeSource,
      reason:
          'A distinct copied database is deleted, never the source snapshot',
    );
    expect(preview.complete, isTrue);
    expect(preview.evidencePreserved, isTrue);
  });

  test('default model projection hides identifiers while native preview retains readable identifiers', () {
    final preview = captureSectionDeletePreview(store.scoped('p'), 'p', 's');
    expect(
      preview.links.where((l) => l.evidenceId != null).map((l) => l.evidenceId),
      [entryId, noteId, runId],
    );
    final encoded = jsonEncode(preview.toModel());
    for (final id in [
      entryId,
      noteId,
      runId,
      'entry-link',
      'note-link',
      'run-link',
      'foreign-metadata',
    ]) {
      expect(
        encoded,
        isNot(contains(id)),
        reason: 'Native read access is not a model disclosure grant',
      );
    }
    expect(preview.toModel()['links'], [
      for (var i = 0; i < 4; i++) {'status': 'restricted'},
    ]);
    expect(preview.toModel()['totalLinks'], 4);
    expect(preview.toModel().containsKey('deleteDigest'), isFalse);
  });

  test('native canReadEvidence callback does not confer model disclosure permission', () {
    final preview = captureSectionDeletePreview(
      store.scoped('p'),
      'p',
      's',
      canReadEvidence: (_, _) => true,
    );
    expect(preview.links.first.evidenceId, entryId);
    final encoded = jsonEncode(preview.toModel());
    expect(encoded, isNot(contains(entryId)));
    expect(
      jsonEncode(preview.links.first.toModel()),
      isNot(contains(entryId)),
      reason: 'The public link model serializer must fail closed too',
    );
  });
  test('model projection excludes the digest of hidden section and association data', () {
    final preview = captureSectionDeletePreview(store.scoped('p'), 'p', 's');
    expect(preview.deleteDigest, sectionDeleteDigest(store, 'p', 's'));
    expect(preview.toModel().containsKey('deleteDigest'), isFalse);
    expect(
      jsonEncode(preview.toModel()),
      isNot(contains(preview.deleteDigest)),
    );
  });
}
