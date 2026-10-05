import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/src/cards/card_store.dart';
import 'package:research_module/src/exchange/research_package.dart';
import 'package:research_module/src/source_ref.dart';
import 'package:sqlite3/sqlite3.dart';

/// Independent device root, durable SQLite identity map and import receipts.
class _Device implements ManagedDatabase {
  _Device() : root = Directory.systemTemp.createTempSync('research-device-') {
    _open();
  }
  final Directory root;
  late Database _raw;
  @override
  Database get raw => _raw;
  CardStore get store => CardStore(this);
  ResearchPackageExchange get exchange => ResearchPackageExchange(store);

  void _open() {
    final path = '${root.path}/knowledge.sqlite';
    final initialize = !File(path).existsSync();
    _raw = sqlite3.open(path)..execute('PRAGMA foreign_keys=ON');
    if (initialize) {
      _raw.execute(
        'CREATE TABLE projects(id TEXT PRIMARY KEY,title TEXT,question TEXT,next_step TEXT)',
      );
      installResearchKnowledgeSchema(_raw);
    }
  }

  void reopen() {
    _raw.close();
    _open();
  }

  void dispose() {
    _raw.close();
    root.deleteSync(recursive: true);
  }

  void project(String id) => raw.execute(
    'INSERT INTO projects VALUES(?,?,?,?)',
    [id, 'Same title', '', ''],
  );

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

  List<Map<String, Object?>> mappings() => raw
      .select('SELECT * FROM canonical_object_map ORDER BY object_key')
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  Map<String, List<Map<String, Object?>>> snapshot() => {
    for (final table in [
      'projects',
      'rk_projects',
      'canonical_object_map',
      'rk_cards',
      'rk_revisions',
      'rk_documents',
      'rk_conflicts',
      'rk_import_receipts',
    ])
      table: raw
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((row) => Map<String, Object?>.from(row))
          .toList(),
  };
}

ImportTarget _target(String id, {bool create = false}) {
  final binding = WorkspaceBinding(
    workspaceId: 'workspace-$id',
    moduleId: 'research',
    nativeProjectId: id,
  );
  return create ? ImportTarget.create(binding) : ImportTarget.refresh(binding);
}

Future<ImportReceipt> _commit(
  _Device device,
  PreparedResearchPackage prepared,
  String operation,
) => device.exchange.commitImport(
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

Future<Uint8List> _transfer(
  _Device from,
  _Device to,
  String project,
  List<String> cards,
  String name,
) async {
  final exported = File('${from.root.path}/$name.researchpkg');
  await exported.writeAsBytes(await from.exchange.exportBytes(project, cards));
  final received = await exported.copy('${to.root.path}/$name.researchpkg');
  expect(received.path, isNot(exported.path));
  final bytes = await received.readAsBytes();
  expect(bytes, await exported.readAsBytes());
  return bytes;
}

Map<String, List<int>> _entries(List<int> bytes) => {
  for (final entry in ZipDecoder().decodeBytes(bytes))
    entry.name: List<int>.from(entry.content),
};
Map<String, dynamic> _manifest(List<int> bytes) =>
    jsonDecode(utf8.decode(_entries(bytes)['manifest.json']!))
        as Map<String, dynamic>;

Uint8List _mutate(
  List<int> bytes,
  void Function(Map<String, dynamic>, Map<String, List<int>>) change,
) {
  final entries = _entries(bytes);
  final manifest = _manifest(bytes);
  change(manifest, entries);
  entries['manifest.json'] = utf8.encode(jsonEncode(manifest));
  final archive = Archive();
  entries.forEach(
    (name, data) => archive.addFile(ArchiveFile(name, data.length, data)),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void _assertClosure(_Device device, String project, List<int> bytes) {
  final prepared = device.exchange.prepareBytes(bytes, _target(project));
  final documents = _manifest(bytes)['documents'] as List;
  for (final revision in prepared.revisions.values) {
    expect(
      device.store.revision(revision.revisionId)!.canonical,
      revision.canonical,
    );
    for (final parent in revision.parents) {
      expect(
        prepared.revisions[parent.revisionId]!.objectKey,
        parent.objectKey,
      );
    }
    for (final citation in revision.citations) {
      final source = citation.source;
      expect(
        documents.any(
          (d) =>
              ObjectKey.fromJson(
                    Map<String, Object?>.from(d['ObjectKey'] as Map),
                  ) ==
                  source.documentRef &&
              d['contentDigest'] == source.contentDigest,
        ),
        isTrue,
      );
      final original = device.store.citationDocument(project, source)!;
      expect(original.contentDigest, source.contentDigest);
      expect(sha256.convert(original.bytes).toString(), source.contentDigest);
    }
    for (final relation in revision.relations) {
      device.store.requireObject(project, relation.target);
      expect(
        relation.target.objectType == 'card'
            ? prepared.heads.containsKey(relation.target.token)
            : documents.any(
                (d) =>
                    ObjectKey.fromJson(
                      Map<String, Object?>.from(d['ObjectKey'] as Map),
                    ) ==
                    relation.target,
              ),
        isTrue,
      );
    }
  }
}

Future<ResearchCard> _sample(_Device device, String project) async {
  final bytes = utf8.encode('%PDF-1.7 original bytes\r\n');
  final doc = await device.store.registerDocument(
    projectId: project,
    localDocumentId: 'same-document-id',
    bytes: bytes,
    fileName: 'paper.pdf',
  );
  return device.store.save(
    projectId: project,
    cardId: 'same-card-id',
    expectedHead: null,
    bodyMarkdown: '# Same title\nHuman [cite:one]',
    citations: [
      CardCitation(
        citationId: 'one',
        source: SourceRef(
          documentRef: doc,
          contentDigest: sha256.convert(bytes).toString(),
          pageIndex: 0,
          quote: 'original quote',
        ),
      ),
    ],
    relations: [
      CardRelation(relationId: 'document', target: doc, kind: 'supports'),
    ],
  );
}

/// Ordinary source API sequence: H1-only historic citation, then restored H1
/// with an inherited document relation. No archive bytes are modified.
Future<
  ({
    ResearchCard original,
    ResearchCard descendant,
    ObjectKey document,
    List<int> h1,
    Uint8List bytes,
  })
>
_historicalRelationUpdate(_Device first, _Device second) async {
  final h1 = utf8.encode('%PDF-1.7 original H1');
  final document = await first.store.registerDocument(
    projectId: 'source',
    localDocumentId: 'same-document-id',
    bytes: h1,
    fileName: 'paper.pdf',
  );
  final original = await first.store.save(
    projectId: 'source',
    cardId: 'same-card-id',
    expectedHead: null,
    bodyMarkdown: 'Citation only [cite:h1]',
    citations: [
      CardCitation(
        citationId: 'h1',
        source: SourceRef(
          documentRef: document,
          contentDigest: sha256.convert(h1).toString(),
          pageIndex: 0,
          quote: 'Original H1',
        ),
      ),
    ],
  );
  await first.store.registerDocument(
    projectId: 'source',
    localDocumentId: 'same-document-id',
    bytes: utf8.encode('%PDF-1.7 replaced H2'),
    fileName: 'paper.pdf',
  );
  final historical = await _transfer(first, second, 'source', [
    original.cardId,
  ], 'historical-citation');
  final docManifest = (_manifest(historical)['documents'] as List).single;
  expect(docManifest['current'], isFalse);
  expect(docManifest['contentDigest'], sha256.convert(h1).toString());
  await _commit(
    second,
    second.exchange.prepareBytes(
      historical,
      _target('destination', create: true),
    ),
    'historical-citation',
  );
  second.reopen();
  expect(
    second.raw.select('SELECT deleted FROM rk_documents').single['deleted'],
    2,
  );
  expect(
    second.raw.select('SELECT * FROM rk_documents WHERE deleted=0'),
    isEmpty,
  );
  final restored = await first.store.registerDocument(
    projectId: 'source',
    localDocumentId: 'same-document-id',
    bytes: h1,
    fileName: 'paper.pdf',
  );
  expect(restored, document);
  final descendant = await first.store.save(
    projectId: 'source',
    cardId: original.cardId,
    expectedHead: original.revision.revisionId,
    bodyMarkdown: 'Restored relation [cite:h1]',
    citations: original.revision.citations,
    relations: [
      CardRelation(relationId: 'restored', target: document, kind: 'supports'),
    ],
  );
  first.reopen();
  final bytes = await _transfer(first, second, 'source', [
    original.cardId,
  ], 'restored-relation');
  expect((_manifest(bytes)['documents'] as List).single['current'], isTrue);
  return (
    original: original,
    descendant: descendant,
    document: document,
    h1: h1,
    bytes: bytes,
  );
}

void main() {
  late _Device first, second;
  setUp(() {
    first = _Device()..project('source');
    second = _Device();
    expect(first.root.path, isNot(second.root.path));
  });
  tearDown(() {
    first.dispose();
    second.dispose();
  });

  test(
    'durable two-root identity mapping fresh duplicates and inherited update',
    () async {
      final original = await _sample(first, 'source');
      final bytes = await _transfer(first, second, 'source', [
        'same-card-id',
      ], 'initial');
      expect(_manifest(bytes).containsKey('forks'), isFalse);
      final prepared = second.exchange.prepareBytes(
        bytes,
        _target('destination', create: true),
      );
      final receipt = await _commit(second, prepared, 'initial');
      second.reopen();
      final map = second.mappings();
      final imported = second.store.list('destination').single;
      expect(imported.cardId, isNot(original.cardId));
      expect(imported.revision.objectKey, original.revision.objectKey);
      expect(imported.revision.canonical, original.revision.canonical);
      expect(
        second.store.keyFor('destination', 'card', imported.cardId),
        original.revision.objectKey,
      );
      final replay = await _commit(second, prepared, 'initial');
      expect(replay.committedAt, receipt.committedAt);
      final before = second.snapshot();
      await _commit(
        second,
        second.exchange.prepareBytes(bytes, _target('destination')),
        'fresh-duplicate',
      );
      expect(second.mappings(), map);
      for (final table in before.keys.where((t) => t != 'rk_import_receipts')) {
        expect(second.snapshot()[table], before[table], reason: table);
      }
      final docKey = original.revision.citations.single.source.documentRef;
      final localDoc = map.singleWhere(
        (row) => row['object_key'] == docKey.token,
      )['local_object_id'];
      expect(localDoc, isNot('same-document-id'));
      expect(
        second.store.keyFor('destination', 'document', localDoc as String),
        docKey,
      );
      final edited = await second.store.save(
        projectId: 'destination',
        cardId: imported.cardId,
        expectedHead: imported.revision.revisionId,
        bodyMarkdown: 'Inherited edit',
        citations: imported.revision.citations,
        relations: imported.revision.relations,
      );
      expect(edited.revision.objectKey, original.revision.objectKey);
      expect(
        edited.revision.parents.single.revisionId,
        original.revision.revisionId,
      );
      second.reopen();
      final returned = await _transfer(second, first, 'destination', [
        imported.cardId,
      ], 'returned');
      final manifest = _manifest(returned);
      expect(
        manifest['originProjectKey'],
        original.revision.objectKey.originProjectKey,
      );
      expect(manifest['sourceProjectId'], 'destination');
      await _commit(
        first,
        first.exchange.prepareBytes(returned, _target('source')),
        'return',
      );
      first.reopen();
      expect(
        first.store.get('source', original.cardId)!.revision.canonical,
        edited.revision.canonical,
      );
      expect(
        first.store.revision(original.revision.revisionId)!.canonical,
        original.revision.canonical,
      );
      expect(first.store.list('source'), hasLength(1));
      _assertClosure(first, 'source', returned);
      expect(
        first.store
            .citationDocument(
              'source',
              original.revision.citations.single.source,
            )!
            .bytes,
        utf8.encode('%PDF-1.7 original bytes\r\n'),
      );
      await _commit(
        first,
        first.exchange.prepareBytes(bytes, _target('source')),
        'old-ancestor',
      );
      expect(
        first.store.get('source', original.cardId)!.revision.revisionId,
        edited.revision.revisionId,
      );
    },
  );

  test('independent origins with identical title local ids and object UUID stay separate', () async {
    second.project('source');
    Future<ResearchCard> seed(_Device device) => device.write((_) {
      final key = ObjectKey(
        originProjectKey: device.store.origin('source'),
        objectType: 'card',
        objectUuid: 'identical-object-uuid',
      );
      device.raw.execute('INSERT INTO canonical_object_map VALUES(?,?,?,?)', [
        key.token,
        'same-card-id',
        'source',
        'card',
      ]);
      final revision = CardRevision(
        objectKey: key,
        revisionId: '${key.originProjectKey}-revision',
        bodyMarkdown: '# Same title',
      );
      device.store.insertRevision(revision);
      device.raw.execute('INSERT INTO rk_cards VALUES(?,?)', [
        key.token,
        revision.revisionId,
      ]);
      return ResearchCard(cardId: 'same-card-id', revision: revision);
    });
    final a = await seed(first);
    final b = await seed(second);
    expect(a.cardId, b.cardId);
    expect(a.revision.objectKey.objectUuid, b.revision.objectKey.objectUuid);
    expect(
      a.revision.objectKey.originProjectKey,
      isNot(b.revision.objectKey.originProjectKey),
    );
    final bytes = await _transfer(second, first, 'source', [
      b.cardId,
    ], 'collision');
    await _commit(
      first,
      first.exchange.prepareBytes(bytes, _target('other-source', create: true)),
      'collision',
    );
    first.raw.execute('UPDATE projects SET title=? WHERE id=?', [
      'Same title',
      'other-source',
    ]);
    first.reopen();
    final imported = first.store.list('other-source').single;
    expect(
      first.store.get('source', a.cardId)!.revision.objectKey,
      a.revision.objectKey,
    );
    expect(imported.revision.objectKey, b.revision.objectKey);
    expect(imported.cardId, isNot(a.cardId));
    expect(
      first.raw.select('SELECT DISTINCT object_key FROM rk_cards'),
      hasLength(2),
    );
    final returned = await _transfer(first, second, 'other-source', [
      imported.cardId,
    ], 'collision-return');
    final prepared = second.exchange.prepareBytes(returned, _target('source'));
    expect(prepared.heads.keys.single, b.revision.objectKey.token);
    await _commit(second, prepared, 'collision-return');
    expect(
      second.store.get('source', b.cardId)!.revision.canonical,
      b.revision.canonical,
    );
    final before = first.snapshot();
    await expectLater(
      _commit(
        first,
        first.exchange.prepareBytes(bytes, _target('source')),
        'wrong-origin',
      ),
      throwsStateError,
    );
    expect(first.snapshot(), before);
    await expectLater(
      _commit(
        first,
        first.exchange.prepareBytes(bytes, _target('alias', create: true)),
        'alias',
      ),
      throwsStateError,
    );
    expect(first.snapshot(), before);
  });

  test('reachable cyclic card relations and document versions remain closed after re-export', () async {
    final a = await _sample(first, 'source');
    final b = await first.store.save(
      projectId: 'source',
      cardId: 'related',
      expectedHead: null,
      bodyMarkdown: 'Related',
      relations: [
        CardRelation(
          relationId: 'back',
          target: a.revision.objectKey,
          kind: 'supports',
        ),
      ],
    );
    final head = await first.store.save(
      projectId: 'source',
      cardId: a.cardId,
      expectedHead: a.revision.revisionId,
      bodyMarkdown: 'Updated [cite:one]',
      citations: a.revision.citations,
      relations: [
        ...a.revision.relations,
        CardRelation(
          relationId: 'card',
          target: b.revision.objectKey,
          kind: 'supports',
        ),
      ],
    );
    final newerBytes = utf8.encode('%PDF-1.7 replaced source');
    await first.store.registerDocument(
      projectId: 'source',
      localDocumentId: 'same-document-id',
      bytes: newerBytes,
      fileName: 'paper.pdf',
    );
    final bytes = await _transfer(first, second, 'source', [
      a.cardId,
    ], 'closure');
    final prepared = second.exchange.prepareBytes(
      bytes,
      _target('destination', create: true),
    );
    expect(prepared.heads.keys.toSet(), {
      a.revision.objectKey.token,
      b.revision.objectKey.token,
    });
    expect(prepared.revisions.keys.toSet(), {
      a.revision.revisionId,
      b.revision.revisionId,
      head.revision.revisionId,
    });
    expect(_manifest(bytes)['documents'] as List, hasLength(2));
    await _commit(second, prepared, 'closure');
    second.reopen();
    expect(
      second.store.sourceAvailability(
        'destination',
        a.revision.citations.single.source,
      ),
      SourceAvailability.replaced,
    );
    final imported = second.store
        .list('destination')
        .singleWhere((c) => c.revision.objectKey == a.revision.objectKey);
    final returned = await _transfer(second, first, 'destination', [
      imported.cardId,
    ], 'closure-return');
    expect(_manifest(returned)['documents'] as List, hasLength(2));
    _assertClosure(second, 'destination', returned);
    final archived = _entries(returned);
    final hashes = (_manifest(returned)['documents'] as List)
        .map((d) => d['sha256'])
        .toSet();
    expect(hashes, {
      a.revision.citations.single.source.contentDigest,
      sha256.convert(newerBytes).toString(),
    });
    for (final document in _manifest(returned)['documents'] as List) {
      expect(
        sha256.convert(archived[document['path']]!).toString(),
        document['sha256'],
      );
    }
  });

  test(
    'missing citation card or document closure rejects without durable writes',
    () async {
      final a = await _sample(first, 'source');
      final relationOnlyDoc = await first.store.registerDocument(
        projectId: 'source',
        localDocumentId: 'relation-only',
        bytes: [4, 5, 6],
        fileName: 'relation.pdf',
      );
      final b = await first.store.save(
        projectId: 'source',
        cardId: 'related',
        expectedHead: null,
        bodyMarkdown: 'Related',
      );
      await first.store.save(
        projectId: 'source',
        cardId: a.cardId,
        expectedHead: a.revision.revisionId,
        bodyMarkdown: 'Closed [cite:one]',
        citations: a.revision.citations,
        relations: [
          CardRelation(
            relationId: 'card',
            target: b.revision.objectKey,
            kind: 'supports',
          ),
          CardRelation(
            relationId: 'document',
            target: relationOnlyDoc,
            kind: 'supports',
          ),
        ],
      );
      final bytes = await _transfer(first, second, 'source', [
        a.cardId,
      ], 'missing');
      final before = second.snapshot();
      for (final key in [
        a.revision.citations.single.source.documentRef,
        b.revision.objectKey,
        relationOnlyDoc,
      ]) {
        final invalid = _mutate(bytes, (manifest, entries) {
          if (key.objectType == 'document') {
            final docs = manifest['documents'] as List;
            final removed = docs
                .where(
                  (d) =>
                      ObjectKey.fromJson(
                        Map<String, Object?>.from(d['ObjectKey'] as Map),
                      ) ==
                      key,
                )
                .toList();
            docs.removeWhere((d) => removed.contains(d));
            for (final doc in removed) {
              entries.remove(doc['path']);
            }
          } else {
            (manifest['objects'] as List).removeWhere(
              (o) =>
                  ObjectKey.fromJson(
                    Map<String, Object?>.from(o['ObjectKey'] as Map),
                  ) ==
                  key,
            );
          }
        });
        expect(
          () => second.exchange.prepareBytes(
            invalid,
            _target('destination', create: true),
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'closure error',
              key == a.revision.citations.single.source.documentRef
                  ? 'Missing citation source closure'
                  : 'Dangling relation',
            ),
          ),
        );
        second.reopen();
        expect(second.snapshot(), before);
      }
    },
  );

  test(
    'durable sibling forks re-export revisions and fork-only dependencies',
    () async {
      final original = await _sample(first, 'source');
      final bytes = await _transfer(first, second, 'source', [
        original.cardId,
      ], 'fork-start');
      await _commit(
        second,
        second.exchange.prepareBytes(
          bytes,
          _target('destination', create: true),
        ),
        'fork-start',
      );
      final imported = second.store.list('destination').single;
      final local = await first.store.save(
        projectId: 'source',
        cardId: original.cardId,
        expectedHead: original.revision.revisionId,
        bodyMarkdown: 'Local sibling',
      );
      final forkBytes = utf8.encode('%PDF-1.7 only on fork');
      final doc = await second.store.registerDocument(
        projectId: 'destination',
        localDocumentId: 'fork-document',
        bytes: forkBytes,
        fileName: 'fork.pdf',
      );
      final related = await second.store.save(
        projectId: 'destination',
        cardId: 'fork-related',
        expectedHead: null,
        bodyMarkdown: 'Fork related',
      );
      final remote = await second.store.save(
        projectId: 'destination',
        cardId: imported.cardId,
        expectedHead: original.revision.revisionId,
        bodyMarkdown: 'Remote sibling [cite:fork]',
        citations: [
          CardCitation(
            citationId: 'fork',
            source: SourceRef(
              documentRef: doc,
              contentDigest: sha256.convert(forkBytes).toString(),
              pageIndex: 0,
              quote: 'fork quote',
            ),
          ),
        ],
        relations: [
          CardRelation(
            relationId: 'fork-document',
            target: doc,
            kind: 'supports',
          ),
          CardRelation(
            relationId: 'fork-card',
            target: related.revision.objectKey,
            kind: 'supports',
          ),
        ],
      );
      second.reopen();
      final incoming = await _transfer(second, first, 'destination', [
        imported.cardId,
      ], 'fork-incoming');
      final incomingReceipt = await _commit(
        first,
        first.exchange.prepareBytes(incoming, _target('source')),
        'fork-incoming',
      );
      expect(incomingReceipt.result['conflicts'], 1);
      first.reopen();
      final before = first.snapshot();
      final duplicateReceipt = await _commit(
        first,
        first.exchange.prepareBytes(incoming, _target('source')),
        'fork-duplicate',
      );
      expect(duplicateReceipt.result['conflicts'], 0);
      expect(first.snapshot()['rk_conflicts'], before['rk_conflicts']);
      expect(
        first.store.get('source', original.cardId)!.revision.revisionId,
        local.revision.revisionId,
      );
      expect(
        first.store.revision(remote.revision.revisionId)!.canonical,
        remote.revision.canonical,
      );
      final outgoing = await _transfer(first, second, 'source', [
        original.cardId,
      ], 'fork-outgoing');
      final prepared = second.exchange.prepareBytes(
        outgoing,
        _target('destination'),
      );
      expect(prepared.revisions.keys, contains(remote.revision.revisionId));
      expect(
        prepared.revisions[remote.revision.revisionId]!.canonical,
        remote.revision.canonical,
      );
      expect(prepared.heads.keys, contains(related.revision.objectKey.token));
      _assertClosure(first, 'source', outgoing);
      final beforeInvalid = second.snapshot();
      for (final missing in [doc, related.revision.objectKey]) {
        final invalid = _mutate(outgoing, (manifest, entries) {
          if (missing.objectType == 'document') {
            final docs = manifest['documents'] as List;
            final removed = docs
                .where(
                  (d) =>
                      ObjectKey.fromJson(
                        Map<String, Object?>.from(d['ObjectKey'] as Map),
                      ) ==
                      missing,
                )
                .toList();
            docs.removeWhere((d) => removed.contains(d));
            for (final d in removed) {
              entries.remove(d['path']);
            }
          } else {
            (manifest['objects'] as List).removeWhere(
              (o) =>
                  ObjectKey.fromJson(
                    Map<String, Object?>.from(o['ObjectKey'] as Map),
                  ) ==
                  missing,
            );
          }
        });
        expect(
          () => second.exchange.prepareBytes(invalid, _target('destination')),
          throwsFormatException,
        );
        expect(second.snapshot(), beforeInvalid);
      }
      await _commit(second, prepared, 'fork-outgoing');
      second.reopen();
      expect(
        second.store.get('destination', imported.cardId)!.revision.revisionId,
        remote.revision.revisionId,
      );
      expect(
        second.store.revision(local.revision.revisionId)!.canonical,
        local.revision.canonical,
      );
      expect(
        second.raw
            .select('SELECT revision_id FROM rk_conflicts WHERE object_key=?', [
              original.revision.objectKey.token,
            ])
            .map((row) => row['revision_id']),
        [local.revision.revisionId],
      );
      final reexport = await _transfer(second, first, 'destination', [
        imported.cardId,
      ], 'fork-again');
      final finalPrepared = first.exchange.prepareBytes(
        reexport,
        _target('source'),
      );
      expect(finalPrepared.revisions.keys.toSet(), {
        original.revision.revisionId,
        local.revision.revisionId,
        remote.revision.revisionId,
        related.revision.revisionId,
      });
      await _commit(first, finalPrepared, 'fork-again');
      expect(
        first.store.get('source', original.cardId)!.revision.revisionId,
        local.revision.revisionId,
      );
      expect(first.snapshot()['rk_conflicts'], before['rk_conflicts']);
    },
  );

  test('advertised descendant fork stays a fork and validates identity closure', () async {
    final original = await _sample(first, 'source');
    final initial = await _transfer(first, second, 'source', [
      original.cardId,
    ], 'advertised-initial');
    await _commit(
      second,
      second.exchange.prepareBytes(
        initial,
        _target('destination', create: true),
      ),
      'advertised-initial',
    );
    final branch = await first.store.save(
      projectId: 'source',
      cardId: original.cardId,
      expectedHead: original.revision.revisionId,
      bodyMarkdown: 'Explicit fork',
    );
    final bytes = await _transfer(first, second, 'source', [
      original.cardId,
    ], 'advertised');
    final advertised = _mutate(bytes, (manifest, entries) {
      (manifest['objects'] as List).single['headRevisionId'] =
          original.revision.revisionId;
      manifest['forks'] = [
        RevisionRef(
          objectKey: branch.revision.objectKey,
          revisionId: branch.revision.revisionId,
        ).toJson(),
      ];
    });
    final prepared = second.exchange.prepareBytes(
      advertised,
      _target('destination'),
    );
    final receipt = await _commit(second, prepared, 'advertised');
    expect(receipt.result['conflicts'], 1);
    second.reopen();
    final imported = second.store.list('destination').single;
    expect(imported.revision.revisionId, original.revision.revisionId);
    expect(
      second.store.revision(branch.revision.revisionId)!.canonical,
      branch.revision.canonical,
    );
    expect(
      second.raw
          .select('SELECT revision_id FROM rk_conflicts')
          .single['revision_id'],
      branch.revision.revisionId,
    );
    final before = second.snapshot();
    final duplicate = await _commit(second, prepared, 'advertised-duplicate');
    expect(duplicate.result['conflicts'], 0);
    for (final table in before.keys.where((t) => t != 'rk_import_receipts')) {
      expect(second.snapshot()[table], before[table], reason: table);
    }
    final reexport = await _transfer(second, first, 'destination', [
      imported.cardId,
    ], 'advertised-return');
    expect(
      first.exchange.prepareBytes(reexport, _target('source')).revisions.keys,
      contains(branch.revision.revisionId),
    );
    // First already has the advertised fork as its active head: no self conflict.
    await _commit(
      first,
      first.exchange.prepareBytes(reexport, _target('source')),
      'advertised-return',
    );
    expect(first.raw.select('SELECT * FROM rk_conflicts'), isEmpty);
    final invalidChanges =
        <void Function(Map<String, dynamic>, Map<String, List<int>>)>[
          (m, e) => m['forks'] = null,
          (m, e) =>
              (m['forks'] as List).single['ObjectKey']['unexpected'] = true,
          (m, e) => (m['forks'] as List).single['ObjectKey']['objectUuid'] = 4,
          (m, e) => (m['forks'] as List).add((m['forks'] as List).single),
          (m, e) => (m['forks'] as List).single['revisionId'] = 'missing',
          (m, e) => (m['forks'] as List).single['revisionId'] =
              original.revision.revisionId,
          (m, e) =>
              (m['forks'] as List).single['ObjectKey']['originProjectKey'] =
                  'other-origin',
          (m, e) => (m['forks'] as List).single['ObjectKey']['objectUuid'] =
              'other-card',
          (m, e) => (m['forks'] as List).single['ObjectKey']['objectType'] =
              'document',
          (m, e) => (m['objects'] as List).clear(),
          (m, e) {
            (m['revisions'] as List).removeWhere(
              (r) => r['envelope']['revisionId'] == branch.revision.revisionId,
            );
            e.remove(
              'cards/${branch.revision.objectKey.objectUuid}/${branch.revision.revisionId}.md',
            );
          },
        ];
    final durableBefore = second.snapshot();
    for (final change in invalidChanges) {
      expect(
        () => second.exchange.prepareBytes(
          _mutate(advertised, change),
          _target('destination'),
        ),
        throwsFormatException,
      );
      expect(second.snapshot(), durableBefore);
    }
    second.reopen();
    expect(second.snapshot(), durableBefore);
  });

  test(
    'historical-only document relation rejects before any durable mutation',
    () async {
      final original = await _sample(first, 'source');
      final bytes = await _transfer(first, second, 'source', [
        original.cardId,
      ], 'historical-relation');
      final invalid = _mutate(bytes, (manifest, entries) {
        for (final doc in manifest['documents'] as List) {
          doc['current'] = false;
        }
      });
      final before = second.snapshot();
      expect(
        () => second.exchange.prepareBytes(
          invalid,
          _target('destination', create: true),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'closure error',
            'Dangling relation',
          ),
        ),
      );
      second.reopen();
      expect(second.snapshot(), before);
    },
  );

  test(
    'late revision conflict rolls back project mappings documents and receipts',
    () async {
      final original = await _sample(first, 'source');
      second.project('unrelated');
      await second.write((_) {
        final key = second.store.ensureKey('unrelated', 'card', 'existing');
        final conflicting = CardRevision(
          objectKey: key,
          revisionId: original.revision.revisionId,
          bodyMarkdown: 'Independent data',
        );
        second.store.insertRevision(conflicting);
        second.raw.execute('INSERT INTO rk_cards VALUES(?,?)', [
          key.token,
          conflicting.revisionId,
        ]);
      });
      final bytes = await _transfer(first, second, 'source', [
        original.cardId,
      ], 'late-conflict');
      final prepared = second.exchange.prepareBytes(
        bytes,
        _target('destination', create: true),
      );
      final before = second.snapshot();
      await expectLater(
        _commit(second, prepared, 'late-conflict'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'conflict',
            'Revision content conflict',
          ),
        ),
      );
      second.reopen();
      expect(second.snapshot(), before);
    },
  );

  for (final fork in [false, true]) {
    test(
      'restored historical bytes close a durable ${fork ? 'fork' : 'head'} document relation',
      () async {
        final update = await _historicalRelationUpdate(first, second);
        final imported = second.store.list('destination').single;
        final map = second.mappings();
        ResearchCard? local;
        if (fork) {
          local = await second.store.save(
            projectId: 'destination',
            cardId: imported.cardId,
            expectedHead: imported.revision.revisionId,
            bodyMarkdown: 'Local sibling',
            citations: imported.revision.citations,
          );
        }
        final prepared = second.exchange.prepareBytes(
          update.bytes,
          _target('destination'),
        );
        final receipt = await _commit(second, prepared, 'restored-relation');
        expect(receipt.result['conflicts'], fork ? 1 : 0);
        second.reopen();
        // The review trace fails here: a committed relation cannot re-export.
        final returned = await _transfer(second, first, 'destination', [
          imported.cardId,
        ], 'restored-return');
        final document = second.raw.select(
          'SELECT * FROM rk_documents WHERE object_key=?',
          [update.document.token],
        ).single;
        expect(document['deleted'], 0);
        expect(document['bytes'], update.h1);
        expect(document['digest'], sha256.convert(update.h1).toString());
        expect(second.mappings(), map);
        expect(
          second.store.get('destination', imported.cardId)!.revision.revisionId,
          fork
              ? local!.revision.revisionId
              : update.descendant.revision.revisionId,
        );
        expect(
          second.store.revision(update.original.revision.revisionId)!.canonical,
          update.original.revision.canonical,
        );
        expect(
          second.store
              .revision(update.descendant.revision.revisionId)!
              .canonical,
          update.descendant.revision.canonical,
        );
        expect(
          update.descendant.revision.parents.single.revisionId,
          update.original.revision.revisionId,
        );
        _assertClosure(second, 'destination', returned);
        expect(
          first.exchange
              .prepareBytes(returned, _target('source'))
              .revisions
              .keys,
          contains(update.descendant.revision.revisionId),
        );
        final before = second.snapshot();
        final duplicate = await _commit(
          second,
          second.exchange.prepareBytes(update.bytes, _target('destination')),
          'restored-duplicate',
        );
        expect(duplicate.result['conflicts'], 0);
        second.reopen();
        for (final table in before.keys.where(
          (t) => t != 'rk_import_receipts',
        )) {
          expect(second.snapshot()[table], before[table], reason: table);
        }
        await _commit(
          first,
          first.exchange.prepareBytes(returned, _target('source')),
          'restored-return',
        );
        first.reopen();
        expect(
          first.store
              .get('source', update.original.cardId)!
              .revision
              .revisionId,
          update.descendant.revision.revisionId,
        );
        final again = await _transfer(first, second, 'source', [
          update.original.cardId,
        ], 'restored-again');
        _assertClosure(first, 'source', again);
      },
    );
  }

  test(
    'restored incoming version preserves an existing local current document',
    () async {
      final update = await _historicalRelationUpdate(first, second);
      final localId =
          second.mappings().singleWhere(
                (m) => m['object_key'] == update.document.token,
              )['local_object_id']
              as String;
      final localBytes = utf8.encode('%PDF-1.7 independent local current');
      final localKey = await second.store.registerDocument(
        projectId: 'destination',
        localDocumentId: localId,
        bytes: localBytes,
        fileName: 'local.pdf',
      );
      expect(localKey, update.document);
      await _commit(
        second,
        second.exchange.prepareBytes(update.bytes, _target('destination')),
        'preserve-local-current',
      );
      second.reopen();
      final current = second.raw
          .select('SELECT * FROM rk_documents WHERE deleted=0')
          .single;
      expect(current['digest'], sha256.convert(localBytes).toString());
      expect(current['bytes'], localBytes);
      final historical = second.raw.select(
        'SELECT deleted FROM rk_documents WHERE digest=?',
        [sha256.convert(update.h1).toString()],
      ).single;
      expect(historical['deleted'], 2);
      final card = second.store.list('destination').single;
      final returned = await _transfer(second, first, 'destination', [
        card.cardId,
      ], 'local-current-return');
      expect(_manifest(returned)['documents'] as List, hasLength(2));
      _assertClosure(second, 'destination', returned);
    },
  );

  for (final fork in [false, true]) {
    test(
      'explicitly deleted source rolls back incoming ${fork ? 'fork' : 'head'} relation',
      () async {
        final update = await _historicalRelationUpdate(first, second);
        if (fork) {
          final card = second.store.list('destination').single;
          await second.store.save(
            projectId: 'destination',
            cardId: card.cardId,
            expectedHead: card.revision.revisionId,
            bodyMarkdown: 'Local sibling',
            citations: card.revision.citations,
          );
        }
        await second.store.deleteDocument('destination', update.document);
        second.reopen();
        final before = second.snapshot();
        expect(
          second.raw
              .select('SELECT deleted FROM rk_documents')
              .single['deleted'],
          1,
        );
        final prepared = second.exchange.prepareBytes(
          update.bytes,
          _target('destination'),
        );
        await expectLater(
          _commit(second, prepared, 'deleted-relation'),
          throwsStateError,
        );
        second.reopen();
        expect(second.snapshot(), before);
        expect(
          second.raw.select('SELECT * FROM rk_documents WHERE deleted=0'),
          isEmpty,
        );
      },
    );
  }

  test('explicitly deleted relation-only target rolls back new card', () async {
    final update = await _historicalRelationUpdate(first, second);
    await second.store.deleteDocument('destination', update.document);
    final related = await first.store.save(
      projectId: 'source',
      cardId: 'relation-only',
      expectedHead: null,
      bodyMarkdown: 'Document relation without citation',
      relations: [
        CardRelation(
          relationId: 'only-relation',
          target: update.document,
          kind: 'supports',
        ),
      ],
    );
    final bytes = await _transfer(first, second, 'source', [
      related.cardId,
    ], 'deleted-relation-only');
    final prepared = second.exchange.prepareBytes(
      bytes,
      _target('destination'),
    );
    expect(prepared.revisions.values.single.citations, isEmpty);
    final before = second.snapshot();
    await expectLater(
      _commit(second, prepared, 'deleted-relation-only'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'closure',
          'Document relation closure unavailable after import',
        ),
      ),
    );
    second.reopen();
    expect(second.snapshot(), before);
  });
}
