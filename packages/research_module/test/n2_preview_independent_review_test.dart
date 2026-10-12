import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:research_module/src/core/section_delete_preview.dart';
import 'package:sqlite3/sqlite3.dart';

class _NoWrites implements ManagedDatabase {
  _NoWrites(this.raw);
  @override
  final Database raw;
  int attempts = 0;
  @override
  Future<T> write<T>(T Function(Database) body) {
    attempts++;
    throw StateError('Preview must not invoke managed writes');
  }
}

void main() {
  late Directory root;
  late Database a, b;
  late _NoWrites managed;
  late WorkbenchStore store;
  String snapshot(Database connection) => jsonEncode({
    for (final table in connection.select(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    ))
      table['name'] as String: [
        for (final row in connection.select(
          'SELECT * FROM "${table['name']}" ORDER BY rowid',
        ))
          Map<String, Object?>.from(row),
      ],
  });
  int changes(Database connection) =>
      connection.select('SELECT total_changes() AS n').single['n'] as int;

  setUp(() {
    root = Directory.systemTemp.createTempSync('n2-independent-');
    final path = '${root.path}/host.sqlite';
    a = sqlite3.open(path);
    a.execute('PRAGMA foreign_keys=ON');
    a.execute('PRAGMA journal_mode=WAL');
    for (final migration in ResearchModule().schema.migrations) {
      migration.migrate(a);
    }
    for (final id in ['p', 'q']) {
      a.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        [id, id, '', ''],
      );
    }
    a.execute(
      "INSERT INTO sections VALUES('s','p','Section',1,1,'','unassessed')",
    );
    a.execute(
      "INSERT INTO sections VALUES('other','p','Other',1,2,'','unassessed')",
    );
    for (final id in ['e1', 'e2']) {
      a.execute("INSERT INTO entries VALUES(?,'p','claim','title','{}')", [id]);
    }
    a.execute("INSERT INTO outline VALUES('local','p','Section','e1','s')");
    // The deletion SQL removes this malformed project association too.
    a.execute("INSERT INTO outline VALUES('foreign','q','Section','e2','s')");
    a.execute("INSERT INTO outline VALUES('keep','p','Other','e1','other')");
    b = sqlite3.open(path);
    b.execute('PRAGMA foreign_keys=ON');
    managed = _NoWrites(a);
    store = WorkbenchStore.attach(
      rootPath: root.path,
      database: a,
      managed: managed,
    );
  });
  tearDown(() {
    b.close();
    a.close();
    root.deleteSync(recursive: true);
  });

  test('independent observer sees no changes for capture refusal freshness and revoked visibility', () {
    final before = snapshot(b);
    final aChanges = changes(a), bChanges = changes(b);
    var readable = true;
    final preview = captureSectionDeletePreview(
      store.scoped('p'),
      'p',
      's',
      canReadEvidence: (_, _) => readable,
    );
    expect(sectionDeletePreviewIsCurrent(store, preview), isTrue);
    readable = false;
    expect(sectionDeletePreviewIsCurrent(store, preview), isFalse);
    expect(
      () => captureSectionDeletePreview(store.scoped('q'), 'p', 's'),
      throwsStateError,
    );
    expect(
      () => captureSectionDeletePreview(store, 'p', 's', maxLinks: 1),
      throwsStateError,
    );
    expect(
      () => captureSectionDeletePreview(store, 'p', 's', maxBytes: 1),
      throwsStateError,
    );
    expect(
      snapshot(b),
      before,
      reason: 'All persisted business, change-log and receipt tables must stay byte equivalent',
    );
    expect(
      changes(a),
      aChanges,
      reason: 'Also rejects transient write then rollback',
    );
    expect(changes(b), bChanges);
    expect(managed.attempts, 0);
    expect(a.autocommit, isTrue);
  });

  test('full preview count exactly matches real deletion while evidence and unrelated links survive', () {
    final preview = captureSectionDeletePreview(store.scoped('p'), 'p', 's');
    final affected = b.select(
      "SELECT id FROM outline WHERE section_id='s' ORDER BY id",
    );
    expect(preview.totalLinks, affected.length);
    expect(preview.links.map((l) => l.status), ['restricted', 'unknown']);
    final evidence = jsonEncode([
      for (final row in b.select('SELECT * FROM entries ORDER BY id'))
        Map<String, Object?>.from(row),
    ]);
    b.execute('BEGIN IMMEDIATE');
    WorkbenchStore.attach(
      rootPath: root.path,
      database: b,
    ).scoped('p').deleteSection('s');
    b.execute('COMMIT');
    expect(b.select("SELECT id FROM sections WHERE id='s'"), isEmpty);
    expect(b.select("SELECT id FROM outline WHERE section_id='s'"), isEmpty);
    expect(b.select("SELECT id FROM outline WHERE id='keep'"), hasLength(1));
    expect(
      jsonEncode([
        for (final row in b.select('SELECT * FROM entries ORDER BY id'))
          Map<String, Object?>.from(row),
      ]),
      evidence,
    );
    expect(sectionDeletePreviewIsCurrent(store, preview), isFalse);
    expect(
      preview.totalLinks,
      2,
      reason: 'Snapshot does not silently mutate after deletion',
    );
    expect(managed.attempts, 0);
  });
}
