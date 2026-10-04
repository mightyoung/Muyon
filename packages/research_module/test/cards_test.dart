import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:research_module/src/cards/card_store.dart';
import 'package:research_module/src/source_ref.dart';
import 'package:sqlite3/sqlite3.dart';

class TestKnowledgeDatabase implements ManagedDatabase {
  TestKnowledgeDatabase() {
    raw.execute(
      'PRAGMA foreign_keys=ON; CREATE TABLE projects(id TEXT PRIMARY KEY,title TEXT,question TEXT,next_step TEXT);',
    );
    installResearchKnowledgeSchema(raw);
  }
  @override
  final Database raw = sqlite3.openInMemory();
  @override
  Future<T> write<T>(T Function(Database) body) async {
    raw.execute('BEGIN IMMEDIATE');
    try {
      final result = body(raw);
      raw.execute('COMMIT');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  void project(String id) =>
      raw.execute('INSERT INTO projects(id) VALUES(?)', [id]);
}

void main() {
  late TestKnowledgeDatabase db;
  late CardStore store;
  setUp(() {
    db = TestKnowledgeDatabase()..project('p');
    store = CardStore(db);
  });
  tearDown(() => db.raw.close());
  test('expectedHead preserves draft and immutable history', () async {
    final first = await store.save(
      projectId: 'p',
      cardId: 'card',
      expectedHead: null,
      bodyMarkdown: 'first',
    );
    final second = await store.save(
      projectId: 'p',
      cardId: 'card',
      expectedHead: first.revision.revisionId,
      bodyMarkdown: 'second',
    );
    await expectLater(
      store.save(
        projectId: 'p',
        cardId: 'card',
        expectedHead: first.revision.revisionId,
        bodyMarkdown: 'my draft',
      ),
      throwsA(isA<CardConflict>().having((e) => e.draft, 'draft', 'my draft')),
    );
    expect(
      store.get('p', 'card')!.revision.revisionId,
      second.revision.revisionId,
    );
    expect(store.revision(first.revision.revisionId)!.bodyMarkdown, 'first');
    expect(
      second.revision.parents.single.revisionId,
      first.revision.revisionId,
    );
  });
  test(
    'citations survive source deletion with explicit missing status',
    () async {
      final bytes = [1, 2, 3];
      final key = await store.registerDocument(
        projectId: 'p',
        localDocumentId: 'doc',
        bytes: bytes,
        fileName: 'paper.pdf',
      );
      final source = SourceRef(
        documentRef: key,
        contentDigest: sha256.convert(bytes).toString(),
        pageIndex: 2,
        quote: 'quote',
      );
      final saved = await store.save(
        projectId: 'p',
        cardId: 'card',
        expectedHead: null,
        bodyMarkdown: '[cite:one]',
        citations: [CardCitation(citationId: 'one', source: source)],
      );
      await store.deleteDocument('p', key);
      expect(store.sourceAvailability('p', source), SourceAvailability.missing);
      expect(
        store.get('p', 'card')!.revision.citations.single.source.quote,
        'quote',
      );
      await store.save(
        projectId: 'p',
        cardId: 'card',
        expectedHead: saved.revision.revisionId,
        bodyMarkdown: 'retained',
        citations: saved.revision.citations,
      );
    },
  );
  test(
    'cross project citations are rejected and transaction leaves no card',
    () async {
      db.project('other');
      final bytes = [1];
      final key = await store.registerDocument(
        projectId: 'other',
        localDocumentId: 'doc',
        bytes: bytes,
        fileName: 'x.pdf',
      );
      await expectLater(
        store.save(
          projectId: 'p',
          cardId: 'card',
          expectedHead: null,
          bodyMarkdown: 'bad',
          citations: [
            CardCitation(
              citationId: 'one',
              source: SourceRef(
                documentRef: key,
                contentDigest: sha256.convert(bytes).toString(),
                pageIndex: 0,
                quote: 'q',
              ),
            ),
          ],
        ),
        throwsStateError,
      );
      expect(store.get('p', 'card'), isNull);
    },
  );
}
