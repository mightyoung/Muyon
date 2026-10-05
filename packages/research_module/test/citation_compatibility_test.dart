import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/src/cards/card_store.dart';
import 'package:research_module/src/exchange/research_package.dart';
import 'package:research_module/src/source_ref.dart';

import 'cards_test.dart' show TestKnowledgeDatabase;

const legacyCanonical =
    r'''{"ObjectKey":{"objectType":"card","objectUuid":"card","originProjectKey":"origin"},"bodyMarkdown":"Human [cite:one]","citationRefs":[{"citationId":"one","source":{"contentDigest":"039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81","contextAfter":"后","contextBefore":"前","documentRef":{"objectType":"document","objectUuid":"doc","originProjectKey":"origin"},"pageIndex":0,"parserVersion":null,"quote":"研究😀"}}],"parents":[],"relations":[],"revisionId":"legacy-revision","schemaVersion":1}''';
const legacyDigest =
    'fda284d221b9ac10a049e5b054cbbac121401c4835b4c7f873a0070260bc687a';

void main() {
  late TestKnowledgeDatabase firstDb, secondDb;
  late CardStore first, second;
  late CardRevision legacy;
  setUp(() async {
    firstDb = TestKnowledgeDatabase()..project('p');
    secondDb = TestKnowledgeDatabase();
    first = CardStore(firstDb);
    second = CardStore(secondDb);
    legacy = CardRevision.fromJson(
      Map<String, Object?>.from(jsonDecode(legacyCanonical) as Map),
    );
    final doc = legacy.citations.single.source.documentRef;
    firstDb.raw.execute('INSERT INTO rk_projects VALUES(?,?)', ['p', 'origin']);
    firstDb.raw.execute('INSERT INTO canonical_object_map VALUES(?,?,?,?)', [
      doc.token,
      'doc',
      'p',
      'document',
    ]);
    firstDb.raw.execute('INSERT INTO canonical_object_map VALUES(?,?,?,?)', [
      legacy.objectKey.token,
      'card',
      'p',
      'card',
    ]);
    await first.registerDocument(
      projectId: 'p',
      localDocumentId: 'doc',
      bytes: [1, 2, 3],
      fileName: 'paper.pdf',
    );
    await firstDb.write((_) {
      first.insertRevision(legacy);
      firstDb.raw.execute('INSERT INTO rk_cards VALUES(?,?)', [
        legacy.objectKey.token,
        legacy.revisionId,
      ]);
    });
  });
  tearDown(() {
    firstDb.raw.close();
    secondDb.raw.close();
  });
  test('pre-C3 literal revision has unchanged canonical bytes and SHA256', () {
    expect(legacy.canonical, legacyCanonical);
    expect(legacy.contentDigest, legacyDigest);
    expect(
      sha256.convert(utf8.encode(legacyCanonical)).toString(),
      legacyDigest,
    );
    expect(
      legacy.citations.single.source.toJson().containsKey('coordinates'),
      isFalse,
    );
    expect(first.revision('legacy-revision')!.canonical, legacyCanonical);
  });
  Future<void> transfer() async {
    final bytes = await ResearchPackageExchange(first)
        .exportBytes('p', ['card']);
    const binding = WorkspaceBinding(
      workspaceId: 'import-workspace',
      moduleId: 'research',
      nativeProjectId: 'imported',
    );
    final exchange = ResearchPackageExchange(second);
    final prepared = exchange.prepareBytes(
      bytes,
      const ImportTarget.create(binding),
    );
    await exchange.commitImport(
      prepared,
      ImportIntent(
        operationId: 'import-op',
        workspaceId: binding.workspaceId,
        moduleId: 'research',
        targetProjectId: 'imported',
        kind: ImportKind.create,
        inputDigest: prepared.inputDigest,
        stagingToken: prepared.stagingToken,
      ),
    );
  }

  test(
    'real researchpkg closure preserves legacy revision hash and source fields',
    () async {
      await transfer();
      final imported = second.list('imported').single.revision;
      expect(imported.canonical, legacyCanonical);
      expect(imported.contentDigest, legacyDigest);
      final ref = imported.citations.single.source;
      expect(
        second.sourceAvailability('imported', ref),
        SourceAvailability.pageLevel,
      );
      expect(second.citationDocument('imported', ref)!.bytes, [1, 2, 3]);
    },
  );
  test('real researchpkg roundtrip preserves optional boxes and historical legacy hash', () async {
    final source = SourceRef.fromJson({
      ...legacy.citations.single.source.toJson(),
      'coordinates': [
        {'left': .1, 'top': .2, 'right': .3, 'bottom': .4},
      ],
    });
    final edited = await first.save(
      projectId: 'p',
      cardId: 'card',
      expectedHead: legacy.revisionId,
      bodyMarkdown: 'new [cite:one]',
      citations: [CardCitation(citationId: 'one', source: source)],
    );
    await transfer();
    final imported = second.list('imported').single.revision;
    expect(imported.contentDigest, edited.revision.contentDigest);
    expect(imported.citations.single.source.toJson(), source.toJson());
    expect(second.revision('legacy-revision')!.canonical, legacyCanonical);
    expect(second.revision('legacy-revision')!.contentDigest, legacyDigest);
  });
}
