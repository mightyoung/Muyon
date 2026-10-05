import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/src/cards/card_store.dart';
import 'package:research_module/src/source_ref.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

class CitationDatabase implements ManagedDatabase {
  CitationDatabase(String path) : raw = sqlite3.open(path) {
    raw.execute(
      'CREATE TABLE projects(id TEXT PRIMARY KEY,title TEXT,author TEXT);',
    );
    installResearchKnowledgeSchema(raw);
    raw.execute(
      "INSERT INTO projects(id,title,author) VALUES('p','title','author'),('other','other','other');",
    );
  }
  @override
  final Database raw;
  @override
  Future<T> write<T>(T Function(Database) body) async {
    raw.execute('BEGIN IMMEDIATE');
    try {
      final value = body(raw);
      raw.execute('COMMIT');
      return value;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }
}

void main() {
  late Directory directory;
  late CitationDatabase db;
  late CardStore store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('citation-test-');
    db = CitationDatabase('${directory.path}/test.sqlite');
    store = CardStore(db);
  });
  tearDown(() {
    db.raw.close();
    directory.deleteSync(recursive: true);
  });
  test(
    'missing original digest is missing even when a newer source exists',
    () async {
      final key = await store.registerDocument(
        projectId: 'p',
        localDocumentId: 'doc',
        bytes: [1, 2, 3],
        fileName: 'paper.pdf',
      );
      final ref = SourceRef(
        documentRef: key,
        contentDigest: 'a' * 64,
        pageIndex: 0,
        quote: 'q',
      );
      expect(store.sourceAvailability('p', ref), SourceAvailability.missing);
    },
  );
  test('persisted source bytes must still prove their stored digest', () async {
    final bytes = [1, 2, 3];
    final key = await store.registerDocument(
      projectId: 'p',
      localDocumentId: 'doc',
      bytes: bytes,
      fileName: 'paper.pdf',
    );
    final ref = SourceRef(
      documentRef: key,
      contentDigest: sha256.convert(bytes).toString(),
      pageIndex: 0,
      quote: 'q',
    );
    db.raw.execute('UPDATE rk_documents SET bytes=? WHERE object_key=?', [
      [9],
      key.token,
    ]);
    expect(store.sourceAvailability('p', ref), SourceAvailability.missing);
  });
  test('SourceRef round trips optional normalized boxes', () {
    final legacy = SourceRef(
      documentRef: ObjectKey(
        originProjectKey: 'p',
        objectType: 'document',
        objectUuid: 'doc',
      ),
      contentDigest: 'a' * 64,
      pageIndex: 0,
      quote: 'q',
    ).toJson();
    final extended = {
      ...legacy,
      'coordinates': [
        {'left': .1, 'top': .2, 'right': .4, 'bottom': .3},
      ],
    };
    expect(SourceRef.fromJson(extended).toJson(), extended);
  });
  test('SourceRef rejects invalid coordinate data without clamping', () {
    final legacy = SourceRef(
      documentRef: ObjectKey(
        originProjectKey: 'p',
        objectType: 'document',
        objectUuid: 'doc',
      ),
      contentDigest: 'a' * 64,
      pageIndex: 0,
      quote: 'q',
    ).toJson();
    for (final box in [
      {'left': -.1, 'top': .2, 'right': .4, 'bottom': .3},
      {'left': .5, 'top': .2, 'right': .4, 'bottom': .3},
      {'left': .1, 'top': double.nan, 'right': .4, 'bottom': .3},
      {'left': .1, 'top': .2, 'right': 1.1, 'bottom': .3},
    ]) {
      expect(
        () => SourceRef.fromJson({
          ...legacy,
          'coordinates': [box],
        }),
        throwsFormatException,
      );
    }
  });
  test('malformed coordinate fields reject with a format error', () {
    final legacy = SourceRef(
      documentRef: ObjectKey(
        originProjectKey: 'p',
        objectType: 'document',
        objectUuid: 'doc',
      ),
      contentDigest: 'a' * 64,
      pageIndex: 0,
      quote: 'q',
    ).toJson();
    for (final box in [
      {'left': 'wrong', 'top': .2, 'right': .4, 'bottom': .3},
      {'left': .1, 'right': .4, 'bottom': .3},
      {'left': .1, 'top': .2, 'right': .4, 'bottom': double.infinity},
      {'left': .1, 'top': .3, 'right': .4, 'bottom': .2},
      {'left': .1, 'top': .2, 'right': .1, 'bottom': .3},
    ]) {
      expect(
        () => SourceRef.fromJson({
          ...legacy,
          'coordinates': [box],
        }),
        throwsFormatException,
      );
    }
  });
}
