import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/src/cards/card_store.dart';
import 'package:research_module/src/cards/canonical_json.dart';
import 'package:research_module/src/exchange/research_package.dart';
import 'package:research_module/src/source_ref.dart';

import 'cards_test.dart' show TestKnowledgeDatabase;

void main() {
  test('ZIP declared length cannot hide expanded bytes', () {
    final db = TestKnowledgeDatabase();
    try {
      final archive = Archive()
        ..addFile(ArchiveFile('payload', 100000, List<int>.filled(100000, 65)));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i + 46 < bytes.length; i++) {
        final signature = view.getUint32(i, Endian.little);
        if (signature == 0x04034b50) view.setUint32(i + 22, 1, Endian.little);
        if (signature == 0x02014b50) view.setUint32(i + 24, 1, Endian.little);
      }
      const binding = WorkspaceBinding(
        workspaceId: 'w',
        moduleId: 'research',
        nativeProjectId: 'p',
      );
      expect(
        () =>
            ResearchPackageExchange(CardStore(db))
                .prepareBytes(bytes, const ImportTarget.create(binding)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'bounded expansion',
            'Expanded bytes exceed declared bound',
          ),
        ),
      );
    } finally {
      db.raw.close();
    }
  });
  test('RFC8785 appendix B official IEEE754 serialization vectors', () {
    const vectors = {
      '0000000000000000': '0',
      '8000000000000000': '0',
      '0000000000000001': '5e-324',
      '8000000000000001': '-5e-324',
      '7fefffffffffffff': '1.7976931348623157e+308',
      'ffefffffffffffff': '-1.7976931348623157e+308',
      '4340000000000000': '9007199254740992',
      'c340000000000000': '-9007199254740992',
      '4430000000000000': '295147905179352830000',
      '44b52d02c7e14af5': '9.999999999999997e+22',
      '44b52d02c7e14af6': '1e+23',
      '44b52d02c7e14af7': '1.0000000000000001e+23',
      '444b1ae4d6e2ef4e': '999999999999999700000',
      '444b1ae4d6e2ef4f': '999999999999999900000',
      '444b1ae4d6e2ef50': '1e+21',
      '3eb0c6f7a0b5ed8c': '9.999999999999997e-7',
      '3eb0c6f7a0b5ed8d': '0.000001',
      '41b3de4355555553': '333333333.3333332',
      '41b3de4355555554': '333333333.33333325',
      '41b3de4355555555': '333333333.3333333',
      '41b3de4355555556': '333333333.3333334',
      '41b3de4355555557': '333333333.33333343',
      'becbf647612f3696': '-0.0000033333333333333333',
      '43143ff3c1cb0959': '1424953923781206.2',
    };
    for (final entry in vectors.entries) {
      final bytes = ByteData(8)
        ..setUint32(0, int.parse(entry.key.substring(0, 8), radix: 16))
        ..setUint32(4, int.parse(entry.key.substring(8), radix: 16));
      expect(
        canonicalJson(bytes.getFloat64(0)),
        entry.value,
        reason: entry.key,
      );
    }
  });
  test(
    'JCS rejects duplicate keys lone surrogates and unsafe integer literals',
    () {
      for (final invalid in [
        r'{"a":1,"\u0061":2}',
        r'{"a":"\ud800"}',
        '{"a":9007199254740992}',
        '{"a":1e999}',
        '{"a":NaN}',
        '[1,]',
      ]) {
        expect(
          () => strictJsonDecode(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
      expect(() => canonicalJson(double.nan), throwsFormatException);
      expect(() => canonicalJson(double.infinity), throwsFormatException);
      expect(
        canonicalJson({
          '€': 1,
          '\r': 2,
          '😀': 3,
          '1': 4,
          'ö': 5,
          'דּ': 6,
          '\u0080': 7,
        }),
        '{"\\r":2,"1":4,"\u0080":7,"ö":5,"€":1,"😀":3,"דּ":6}',
      );
      expect(canonicalJson({'s': 'e\u0301\r\n'}), '{"s":"e\u0301\\r\\n"}');
    },
  );

  late TestKnowledgeDatabase firstDb, secondDb;
  late CardStore first, second;
  late ResearchPackageExchange sender, receiver;
  setUp(() {
    firstDb = TestKnowledgeDatabase()..project('mac-project');
    secondDb = TestKnowledgeDatabase();
    first = CardStore(firstDb);
    second = CardStore(secondDb);
    sender = ResearchPackageExchange(first);
    receiver = ResearchPackageExchange(second);
  });
  tearDown(() {
    firstDb.raw.close();
    secondDb.raw.close();
  });
  ImportTarget target(String project, {bool create = true}) {
    final binding = WorkspaceBinding(
      workspaceId: 'workspace-$project',
      moduleId: 'research',
      nativeProjectId: project,
    );
    return create
        ? ImportTarget.create(binding)
        : ImportTarget.refresh(binding);
  }

  Future<ImportReceipt> commit(
    ResearchPackageExchange exchange,
    PreparedResearchPackage prepared,
    String op,
  ) => exchange.commitImport(
    prepared,
    ImportIntent(
      operationId: op,
      workspaceId: prepared.target.binding.workspaceId,
      moduleId: 'research',
      targetProjectId: prepared.target.binding.nativeProjectId,
      kind: prepared.target.kind,
      inputDigest: prepared.inputDigest,
      stagingToken: prepared.stagingToken,
    ),
  );
  Future<ResearchCard> sample() async {
    final bytes = utf8.encode('%PDF-1.7 original bytes');
    final doc = await first.registerDocument(
      projectId: 'mac-project',
      localDocumentId: 'same-local-id',
      bytes: bytes,
      fileName: 'paper.pdf',
    );
    return first.save(
      projectId: 'mac-project',
      cardId: 'local-card',
      expectedHead: null,
      bodyMarkdown: 'Human [cite:one]',
      citations: [
        CardCitation(
          citationId: 'one',
          source: SourceRef(
            documentRef: doc,
            contentDigest: sha256.convert(bytes).toString(),
            pageIndex: 1,
            quote: 'original quote',
          ),
        ),
      ],
      relations: [
        CardRelation(relationId: 'rel', target: doc, kind: 'supports'),
      ],
    );
  }

  test(
    'roundtrip remaps local IDs retains canonical parents and bytes',
    () async {
      final original = await sample();
      final bytes = await sender.exportBytes('mac-project', ['local-card']);
      final prepared = receiver.prepareBytes(bytes, target('android-project'));
      await commit(receiver, prepared, 'in');
      await commit(receiver, prepared, 'in');
      final imported = second.list('android-project').single;
      expect(imported.cardId, isNot('local-card'));
      expect(imported.revision.contentDigest, original.revision.contentDigest);
      final edited = await second.save(
        projectId: 'android-project',
        cardId: imported.cardId,
        expectedHead: imported.revision.revisionId,
        bodyMarkdown: 'Android edit',
        citations: imported.revision.citations,
        relations: imported.revision.relations,
      );
      final returned = await receiver.exportBytes('android-project', [
        imported.cardId,
      ]);
      await commit(
        sender,
        sender.prepareBytes(returned, target('mac-project', create: false)),
        'return',
      );
      expect(first.list('mac-project'), hasLength(1));
      expect(
        first.get('mac-project', 'local-card')!.revision.contentDigest,
        edited.revision.contentDigest,
      );
      expect(
        edited.revision.parents.single.revisionId,
        original.revision.revisionId,
      );
      expect(
        firstDb.raw.select('SELECT bytes FROM rk_documents').single['bytes'],
        utf8.encode('%PDF-1.7 original bytes'),
      );
      // Older ancestor must not replace the newer local head.
      await commit(
        sender,
        sender.prepareBytes(bytes, target('mac-project', create: false)),
        'old',
      );
      expect(
        first.get('mac-project', 'local-card')!.revision.revisionId,
        edited.revision.revisionId,
      );
    },
  );
  test(
    'fork preserves local head and saves incoming branch conflict',
    () async {
      final original = await sample();
      await commit(
        receiver,
        receiver.prepareBytes(
          await sender.exportBytes('mac-project', ['local-card']),
          target('android-project'),
        ),
        'in',
      );
      final imported = second.list('android-project').single;
      final local = await first.save(
        projectId: 'mac-project',
        cardId: 'local-card',
        expectedHead: original.revision.revisionId,
        bodyMarkdown: 'local branch',
      );
      final remote = await second.save(
        projectId: 'android-project',
        cardId: imported.cardId,
        expectedHead: imported.revision.revisionId,
        bodyMarkdown: 'remote branch',
      );
      final receipt = await commit(
        sender,
        sender.prepareBytes(
          await receiver.exportBytes('android-project', [imported.cardId]),
          target('mac-project', create: false),
        ),
        'fork',
      );
      expect(receipt.result['conflicts'], 1);
      expect(
        first.get('mac-project', 'local-card')!.revision.revisionId,
        local.revision.revisionId,
      );
      expect(
        first.revision(remote.revision.revisionId)!.bodyMarkdown,
        'remote branch',
      );
      expect(firstDb.raw.select('SELECT * FROM rk_conflicts'), hasLength(1));
    },
  );
  test('tampered bytes missing ancestors duplicate JSON and unsafe paths reject before commit', () async {
    final original = await sample();
    await first.save(
      projectId: 'mac-project',
      cardId: 'local-card',
      expectedHead: original.revision.revisionId,
      bodyMarkdown: 'next',
    );
    final bytes = await sender.exportBytes('mac-project', ['local-card']);
    Uint8List mutate(void Function(Map<String, List<int>>) change) {
      final entries = {
        for (final entry in ZipDecoder().decodeBytes(bytes))
          entry.name: List<int>.from(entry.content),
      };
      change(entries);
      final archive = Archive();
      entries.forEach((n, b) => archive.addFile(ArchiveFile(n, b.length, b)));
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    for (final invalid in [
      mutate(
        (e) => e[e.keys.firstWhere((k) => k.startsWith('documents/'))] = [0],
      ),
      mutate((e) => e['../escape'] = [1]),
      mutate(
        (e) => e['manifest.json'] = utf8.encode(
          '{"packageType":1,"packageType":2}',
        ),
      ),
      mutate((e) {
        final m = jsonDecode(
          utf8.decode(e['manifest.json']!),
        ) as Map<String, dynamic>;
        (m['revisions'] as List).removeWhere(
          (r) => r['envelope']['revisionId'] == original.revision.revisionId,
        );
        e['manifest.json'] = utf8.encode(jsonEncode(m));
      }),
    ]) {
      expect(
        () => receiver.prepareBytes(invalid, target('android-project')),
        throwsFormatException,
      );
    }
    expect(secondDb.raw.select('SELECT * FROM projects'), isEmpty);
  });
}
