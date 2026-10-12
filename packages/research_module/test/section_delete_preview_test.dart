import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/src/core/section_delete_preview.dart';
import 'package:research_module/src/core/store.dart';
import 'package:sqlite3/sqlite3.dart';

import 'change_log_test.dart' show migrated, project;
import 'research_runtime_test.dart' show TestDatabase;

void main() {
  late Directory root;
  late TestDatabase database;
  late WorkbenchStore store;
  setUp(() {
    root = Directory.systemTemp.createTempSync('n2-preview-');
    database = migrated(version: 10);
    store = WorkbenchStore.attach(rootPath: root.path, database: database.raw, managed: database);
    project(database, 'p');
    project(database, 'q');
    database.raw.execute("INSERT INTO sections VALUES('s','p','Frozen heading',1,1,'private body','unassessed')");
  });
  tearDown(() {
    database.raw.close();
    root.deleteSync(recursive: true);
  });

  void entry(String id, [String projectId = 'p']) => database.raw.execute(
    'INSERT INTO entries VALUES(?,?,?,?,?)',
    [id, projectId, 'claims', 'private title', '{"commercial":"secret-price","quote":"private quote","path":"/secret/file"}'],
  );
  void link(String id, String evidence, [String projectId = 'p']) => database.raw.execute(
    'INSERT INTO outline(id,project_id,heading,evidence_id,section_id) VALUES(?,?,?,?,?)',
    [id, projectId, 'private link heading', evidence, 's'],
  );
  String rows() => jsonEncode({
    for (final table in database.raw.select("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"))
      table['name'] as String: [
        for (final row in database.raw.select('SELECT * FROM "${table['name']}"')) Map<String,Object?>.from(row),
      ],
  });

  test('zero links is complete and reuses the existing delete digest', () {
    final preview = captureSectionDeletePreview(store, 'p', 's');
    expect(preview.complete, isTrue);
    expect(preview.evidencePreserved, isTrue);
    expect(preview.totalLinks, 0);
    expect(preview.links, isEmpty);
    expect(preview.deleteDigest, sectionDeleteDigest(store, 'p', 's'));
    expect(preview.section.heading, 'Frozen heading');
  });

  test('complete cascade is stable frozen and matches the existing digest', () {
    entry('one'); entry('two'); entry('foreign', 'q');
    link('z', 'one'); link('a', 'two'); link('m', 'foreign', 'q');
    final preview = captureSectionDeletePreview(store, 'p', 's');
    expect(preview.totalLinks, 3);
    expect(preview.links.map((l) => l.linkId), ['a', null, 'z']);
    expect(preview.links.map((l) => l.status), ['unknown', 'restricted', 'unknown']);
    expect(preview.deleteDigest, sectionDeleteDigest(store, 'p', 's'));
    final before = jsonEncode(preview.toModel());
    database.raw.execute("UPDATE sections SET heading='new' WHERE id='s'");
    database.raw.execute("DELETE FROM outline WHERE id='z'");
    expect(preview.section.heading, 'Frozen heading');
    expect(jsonEncode(preview.toModel()), before);
    expect(() => preview.links.clear(), throwsUnsupportedError);
    expect(sectionDeletePreviewIsCurrent(store, preview), isFalse);
  });

  test('bare IDs never invent a historical type including same-ID ambiguity', () {
    entry('x');
    database.raw.execute("INSERT INTO tasks VALUES('t',1,'p','task','goal','{}')");
    database.raw.execute("INSERT INTO runs VALUES('x','t',1,'completed',1,'{}')");
    link('l', 'x');
    final preview = captureSectionDeletePreview(store, 'p', 's');
    expect(preview.links.single.type, isNull);
    expect(preview.links.single.status, 'unknown');
    database.raw.execute("DELETE FROM runs WHERE id='x'");
    expect(captureSectionDeletePreview(store, 'p', 's').links.single.type, isNull);
  });

  test('foreign unavailable and denied evidence reveal no identifiers', () {
    entry('foreign', 'q'); entry('allowed');
    link('foreign-link', 'foreign'); link('missing-link', 'missing'); link('denied-link', 'allowed');
    final preview = captureSectionDeletePreview(store.scoped('p'), 'p', 's', canReadEvidence: (_, _) => false);
    expect(preview.totalLinks, 3);
    for (final row in preview.links) {
      expect(row.status, 'restricted');
      expect(row.linkId, isNull); expect(row.evidenceId, isNull); expect(row.type, isNull);
    }
    final model = jsonEncode(preview.toModel());
    for (final secret in ['foreign', 'missing', 'denied-link', 'allowed']) {
      expect(model, isNot(contains(secret)));
    }
  });

  test('section project authorization fails before any detail is returned', () {
    expect(() => captureSectionDeletePreview(store.scoped('q'), 'p', 's'), throwsStateError);
    expect(() => captureSectionDeletePreview(store, 'q', 's'), throwsStateError);
    expect(database.raw.autocommit, isTrue);
  });

  test('budget counts every actual cascade row including hidden metadata', () {
    entry('e'); link('a', 'e'); link('b', 'e', 'q');
    expect(() => captureSectionDeletePreview(store, 'p', 's', maxLinks: 1), throwsStateError);
    expect(database.raw.autocommit, isTrue);
    final preview = captureSectionDeletePreview(store, 'p', 's', maxLinks: 2);
    expect(preview.complete, isTrue); expect(preview.totalLinks, 2);
    expect(preview.links.length, 2);
  });

  test('byte budget refuses large section or link fields before full digest', () {
    database.raw.execute('UPDATE sections SET argument=? WHERE id=?', ['x' * 1000, 's']);
    expect(() => captureSectionDeletePreview(store, 'p', 's', maxBytes: 100), throwsStateError);
    database.raw.execute("UPDATE sections SET argument='' WHERE id='s'");
    entry('e'); link('l', 'e');
    database.raw.execute('UPDATE outline SET heading=? WHERE id=?', ['x' * 2000, 'l']);
    expect(() => captureSectionDeletePreview(store, 'p', 's', maxBytes: 1500), throwsStateError);
    expect(database.raw.autocommit, isTrue);
  });

  test('model projection excludes body quote path and commercial values', () {
    entry('e'); link('l', 'e');
    final preview = captureSectionDeletePreview(store, 'p', 's');
    final model = jsonEncode(preview.toModel());
    for (final secret in ['private body', 'Frozen heading', 'private title', 'private link heading', 'private quote', '/secret/file', 'secret-price', 'commercial']) {
      expect(model, isNot(contains(secret)));
    }
    expect(model, contains(preview.deleteDigest));
    expect(model, contains('"evidenceId":"e"'));
  });

  test('read preview including failures and freshness writes no business rows logs or ledgers', () {
    entry('e'); link('l', 'e');
    final before = rows();
    final changes = database.raw.select('SELECT total_changes() AS n').single['n'];
    final preview = captureSectionDeletePreview(store, 'p', 's');
    expect(sectionDeletePreviewIsCurrent(store, preview), isTrue);
    expect(() => captureSectionDeletePreview(store, 'p', 's', maxLinks: 0), throwsStateError);
    expect(rows(), before);
    expect(database.raw.select('SELECT total_changes() AS n').single['n'], changes);
  });

  test('nested read does not commit or rollback the caller transaction', () {
    database.raw.execute('BEGIN');
    database.raw.execute("UPDATE sections SET heading='transaction heading' WHERE id='s'");
    final preview = captureSectionDeletePreview(store, 'p', 's');
    expect(preview.section.heading, 'transaction heading');
    expect(database.raw.autocommit, isFalse);
    database.raw.execute('ROLLBACK');
    expect(store.sections('p').single.heading, 'Frozen heading');
  });

  test('section list and delete digest share a real read snapshot during another writer', () {
    final path = '${root.path}/snapshot.sqlite';
    final a = sqlite3.open(path);
    a.execute('PRAGMA journal_mode=WAL');
    for (final sql in database.raw.select("SELECT sql FROM sqlite_master WHERE type='table' AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%'")) {
      a.execute(sql['sql'] as String);
    }
    a.execute("INSERT INTO projects VALUES('p','p','','')");
    a.execute("INSERT INTO sections VALUES('s','p','A',1,1,'','unassessed')");
    a.execute("INSERT INTO entries VALUES('e','p','claims','A','{}')");
    a.execute("INSERT INTO outline VALUES('a','p','A','e','s')");
    final scoped = WorkbenchStore.attach(rootPath: root.path, database: a);
    final oldDigest = sectionDeleteDigest(scoped, 'p', 's');
    final b = sqlite3.open(path);
    var changed = false;
    try {
      final preview = captureSectionDeletePreview(scoped, 'p', 's', canReadEvidence: (_, _) {
        if (!changed) {
          changed = true;
          b.execute("UPDATE sections SET heading='B' WHERE id='s'");
          b.execute("INSERT INTO outline VALUES('b','p','B','e','s')");
        }
        return true;
      });
      expect(changed, isTrue);
      expect(preview.section.heading, 'A');
      expect(preview.totalLinks, 1);
      expect(preview.deleteDigest, oldDigest);
      expect(sectionDeleteDigest(scoped, 'p', 's'), isNot(oldDigest));
    } finally { b.close(); a.close(); }
  });
}
