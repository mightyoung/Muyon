import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/src/cards/card_store.dart';
import 'package:research_module/src/core/citation_resolver.dart';
import 'package:research_module/src/core/store.dart';
import 'package:research_module/src/reader/source_locator.dart';
import 'package:research_module/src/source_ref.dart';

import 'citation_resolution_test.dart' show CitationDatabase;

import 'dart:io';

class FixturePages implements CitationPageProvider {
  FixturePages(this.read);
  final Future<CitationPage?> Function(CitationDocument, int) read;
  int calls = 0;
  @override
  Future<CitationPage?> loadPage(CitationDocument original, int pageIndex) {
    calls++;
    return read(original, pageIndex);
  }
}

void main() {
  late Directory temp;
  late CitationDatabase db;
  late CardStore store;
  late SourceRef ref;
  final bytes = utf8.encode('original file body');
  final box = SourceBox(left: .1, top: .2, right: .2, bottom: .3);
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('citation-resolver-');
    db = CitationDatabase('${temp.path}/test.sqlite');
    store = CardStore(db);
    final key = await store.registerDocument(
      projectId: 'p',
      localDocumentId: 'doc',
      bytes: bytes,
      fileName: 'paper.pdf',
    );
    ref = SourceRef(
      documentRef: key,
      contentDigest: sha256.convert(bytes).toString(),
      pageIndex: 1,
      quote: '研究😀',
      contextBefore: '前',
      contextAfter: '后',
      parserVersion: 'fixture-v1',
    );
  });
  tearDown(() {
    db.raw.close();
    temp.deleteSync(recursive: true);
  });
  FixturePages pages(
    String? text, {
    bool geometry = false,
    String? digest,
    int? pageIndex,
    String version = 'fixture-v1',
  }) => FixturePages((original, index) async {
    expect(original.bytes, bytes);
    expect(() => original.bytes[0] = 0, throwsUnsupportedError);
    return CitationPage(
      contentDigest: digest ?? original.contentDigest,
      pageIndex: pageIndex ?? index,
      parserVersion: version,
      text: text,
      characterBoxes: geometry && text != null
          ? List.filled(text.length, box)
          : null,
    );
  });
  CitationResolver resolver(
    CitationPageProvider provider, {
    void Function()? ensureActive,
  }) => CitationResolver(
    store,
    'p',
    provider: provider,
    ensureActive: ensureActive,
  );

  test(
    'unique Unicode raw quote has UTF16 offsets without invented geometry',
    () async {
      final result = await resolver(pages('开前研究😀后尾')).resolve(ref);
      expect(result.status, CitationStatus.uniqueText);
      expect(result.pageIndex, 1);
      expect(result.matchCount, 1);
      expect(result.startOffset, 2);
      expect(result.endOffset, 6);
      expect(result.boxes, isEmpty);
    },
  );
  test(
    'exact requires actual parser geometry and keeps physical page index',
    () async {
      final result = await resolver(pages('前研究😀后', geometry: true))
          .resolve(ref);
      expect(result.status, CitationStatus.exact);
      expect(result.pageIndex, 1);
      expect(result.boxes, hasLength(4));
      expect(result.boxes.first.toJson(), box.toJson());
    },
  );
  for (final (text, count) in [
    ('前别的后', 0),
    ('前研究😀后前研究😀后', 2),
    ('研究😀前研究😀后', 2),
  ]) {
    test('raw occurrence count $count remains ambiguous for $text', () async {
      final result = await resolver(pages(text, geometry: true)).resolve(ref);
      expect(result.status, CitationStatus.ambiguous);
      expect(result.matchCount, count);
      expect(result.pageIndex, 1);
      expect(result.startOffset, isNull);
      expect(result.boxes, isEmpty);
    });
  }
  test('overlapping raw occurrences are counted', () async {
    final source = SourceRef(
      documentRef: ref.documentRef,
      contentDigest: ref.contentDigest,
      pageIndex: 1,
      quote: 'aa',
    );
    final result = await resolver(pages('aaa')).resolve(source);
    expect(result.status, CitationStatus.ambiguous);
    expect(result.matchCount, 2);
  });
  test(
    'context mismatch preserves page and refuses unique highlight',
    () async {
      final result = await resolver(pages('错研究😀后', geometry: true))
          .resolve(ref);
      expect(result.status, CitationStatus.pageOnly);
      expect(result.reason, 'context_mismatch');
      expect(result.matchCount, 1);
      expect(result.boxes, isEmpty);
    },
  );
  test('suffix mismatch refuses unique highlight', () async {
    final result = await resolver(pages('前研究😀错', geometry: true)).resolve(ref);
    expect(result.reason, 'context_mismatch');
    expect(result.boxes, isEmpty);
  });
  test('no text layer keeps only the verified page jump', () async {
    final result = await resolver(pages(null)).resolve(ref);
    expect(result.status, CitationStatus.pageOnly);
    expect(result.reason, 'no_text_layer');
    expect(result.pageIndex, 1);
  });
  test('empty quote keeps page level only', () async {
    final source = SourceRef(
      documentRef: ref.documentRef,
      contentDigest: ref.contentDigest,
      pageIndex: 1,
      quote: '',
    );
    final result = await resolver(pages('some text', geometry: true))
        .resolve(source);
    expect(result.status, CitationStatus.pageOnly);
    expect(result.reason, 'empty_quote');
  });
  test('out of range physical page offers no jump', () async {
    final result = await resolver(FixturePages((_, _) async => null))
        .resolve(ref);
    expect(result.status, CitationStatus.pageUnavailable);
    expect(result.pageIndex, isNull);
  });
  for (final kind in ['digest', 'page', 'version']) {
    test('provider $kind evidence cannot be used for this anchor', () async {
      final result = await resolver(
        pages(
          '前研究😀后',
          geometry: true,
          digest: kind == 'digest' ? 'b' * 64 : null,
          pageIndex: kind == 'page' ? 0 : null,
          version: kind == 'version' ? 'fixture-v2' : 'fixture-v1',
        ),
      ).resolve(ref);
      expect(result.boxes, isEmpty);
      expect(result.startOffset, isNull);
      expect(
        result.status,
        kind == 'version'
            ? CitationStatus.pageOnly
            : CitationStatus.pageUnavailable,
      );
    });
  }
  test('source coordinates alone cannot create exact highlight', () async {
    final source = SourceRef.fromJson({
      ...ref.toJson(),
      'coordinates': [box.toJson()],
    });
    final result = await resolver(pages('前研究😀后')).resolve(source);
    expect(result.status, CitationStatus.uniqueText);
    expect(result.boxes, isEmpty);
  });
  test('incomplete parser geometry keeps unique offset only', () async {
    final provider = FixturePages(
      (original, index) async => CitationPage(
        contentDigest: original.contentDigest,
        pageIndex: index,
        parserVersion: 'fixture-v1',
        text: '前研究😀后',
        characterBoxes: [box],
      ),
    );
    final result = await resolver(provider).resolve(ref);
    expect(result.status, CitationStatus.uniqueText);
    expect(result.boxes, isEmpty);
  });
  test('metadata title author and filename edits preserve source and revision identity', () async {
    final saved = await store.save(
      projectId: 'p',
      cardId: 'card',
      expectedHead: null,
      bodyMarkdown: 'body',
      citations: [CardCitation(citationId: 'one', source: ref)],
    );
    final canonical = saved.revision.canonical;
    // Actual workbench paper metadata shape, independent of rk_document bytes.
    db.raw.execute(
      'CREATE TABLE entries(id TEXT PRIMARY KEY,project_id TEXT,kind TEXT,title TEXT,data TEXT)',
    );
    db.raw.execute('INSERT INTO entries VALUES(?,?,?,?,?)', [
      'paper',
      'p',
      'papers',
      'Original title',
      jsonEncode({
        'authors': ['Original author'],
      }),
    ]);
    db.raw.execute('UPDATE entries SET title=?,data=? WHERE id=?', [
      'Renamed title',
      jsonEncode({
        'authors': ['New author'],
      }),
      'paper',
    ]);
    final workbench = WorkbenchStore.attach(
      rootPath: temp.path,
      database: db.raw,
      managed: db,
    );
    expect(workbench.entries('p').single.title, 'Renamed title');
    expect(workbench.entries('p').single.data['authors'], ['New author']);
    await store.registerDocument(
      projectId: 'p',
      localDocumentId: 'doc',
      bytes: bytes,
      fileName: 'renamed.pdf',
    );
    expect(
      (await resolver(pages('前研究😀后', geometry: true)).resolve(ref)).status,
      CitationStatus.exact,
    );
    expect(store.revision(saved.revision.revisionId)!.canonical, canonical);
  });
  test(
    'replacement retains immutable citations and blocks current-version parser',
    () async {
      final saved = await store.save(
        projectId: 'p',
        cardId: 'card',
        expectedHead: null,
        bodyMarkdown: 'body',
        citations: [CardCitation(citationId: 'one', source: ref)],
      );
      await store.registerDocument(
        projectId: 'p',
        localDocumentId: 'doc',
        bytes: utf8.encode('new version with same quote'),
        fileName: 'paper.pdf',
      );
      final provider = pages('前研究😀后', geometry: true);
      final result = await resolver(provider).resolve(ref);
      expect(result.status, CitationStatus.staleVersion);
      expect(result.reason, 'stale_version');
      expect(result.pageIndex, isNull);
      expect(provider.calls, 0);
      expect(
        store.revision(saved.revision.revisionId)!.canonical,
        saved.revision.canonical,
      );
      expect(store.citationDocument('p', ref)!.bytes, bytes);
      await store.deleteDocument('p', ref.documentRef);
      expect(
        (await resolver(provider).resolve(ref)).status,
        CitationStatus.missingSource,
      );
      expect(
        store.revision(saved.revision.revisionId)!.canonical,
        saved.revision.canonical,
      );
    },
  );
  test('scope mismatch denies before provider is called', () async {
    final provider = pages('前研究😀后');
    await expectLater(
      CitationResolver(store, 'other', provider: provider).resolve(ref),
      throwsStateError,
    );
    expect(provider.calls, 0);
  });
  for (final change in ['replace', 'delete', 'scope', 'revoke']) {
    test(
      '$change during asynchronous parse cannot publish exact result',
      () async {
        final entered = Completer<void>();
        final resume = Completer<void>();
        var active = true;
        final provider = FixturePages((original, index) async {
          entered.complete();
          await resume.future;
          return CitationPage(
            contentDigest: original.contentDigest,
            pageIndex: index,
            parserVersion: 'fixture-v1',
            text: '前研究😀后',
            characterBoxes: List.filled(6, box),
          );
        });
        final pending = resolver(
          provider,
          ensureActive: () {
            if (!active) throw StateError('revoked');
          },
        ).resolve(ref);
        await entered.future;
        if (change == 'replace') {
          await store.registerDocument(
            projectId: 'p',
            localDocumentId: 'doc',
            bytes: [9],
            fileName: 'new.pdf',
          );
        }
        if (change == 'delete') {
          await store.deleteDocument('p', ref.documentRef);
        }
        if (change == 'scope') {
          db.raw.execute(
            "UPDATE canonical_object_map SET local_project_id='other' WHERE object_key=?",
            [ref.documentRef.token],
          );
        }
        if (change == 'revoke') active = false;
        if (change == 'scope' || change == 'revoke') {
          final expectation = expectLater(pending, throwsStateError);
          resume.complete();
          await expectation;
        } else {
          resume.complete();
          final result = await pending;
          expect(
            result.status,
            change == 'replace'
                ? CitationStatus.staleVersion
                : CitationStatus.missingSource,
          );
          expect(result.boxes, isEmpty);
          expect(result.pageIndex, isNull);
        }
      },
    );
  }
  test('reader adapter preserves exact geometry and rejects changed anchor arguments', () async {
    final locator = CitationQuoteLocator(
      resolver(pages('前研究😀后', geometry: true)),
      ref,
    );
    final result = await locator.locate(
      pageIndex: 1,
      quote: ref.quote,
      contextBefore: '前',
      contextAfter: '后',
    );
    expect(result, isA<ExactMatch>().having((r) => r.rects.length, 'boxes', 4));
    expect(
      await locator.locate(pageIndex: 0, quote: ref.quote),
      isA<SourceUnavailable>(),
    );
  });
  test('reader adapter maps unique text to page only and zero matches to ambiguous', () async {
    final unique = CitationQuoteLocator(resolver(pages('前研究😀后')), ref);
    expect(
      await unique.locate(
        pageIndex: 1,
        quote: ref.quote,
        contextBefore: '前',
        contextAfter: '后',
      ),
      isA<PageOnly>(),
    );
    final absent = CitationQuoteLocator(resolver(pages('nothing')), ref);
    expect(
      await absent.locate(
        pageIndex: 1,
        quote: ref.quote,
        contextBefore: '前',
        contextAfter: '后',
      ),
      isA<AmbiguousMatch>().having((r) => r.count, 'count', 0),
    );
  });
  test('reader adapter converts scope denial to source unavailable', () async {
    final provider = pages('前研究😀后', geometry: true);
    final locator = CitationQuoteLocator(
      CitationResolver(store, 'other', provider: provider),
      ref,
    );
    expect(
      await locator.locate(
        pageIndex: 1,
        quote: ref.quote,
        contextBefore: '前',
        contextAfter: '后',
      ),
      isA<SourceUnavailable>(),
    );
    expect(provider.calls, 0);
  });
  test('reader adapter converts session revocation during parse to source unavailable', () async {
    final entered = Completer<void>();
    final resume = Completer<void>();
    var active = true;
    final provider = FixturePages((original, index) async {
      entered.complete();
      await resume.future;
      return CitationPage(
        contentDigest: original.contentDigest,
        pageIndex: index,
        parserVersion: 'fixture-v1',
        text: '前研究😀后',
        characterBoxes: List.filled(6, box),
      );
    });
    final locator = CitationQuoteLocator(
      resolver(
        provider,
        ensureActive: () {
          if (!active) throw StateError('revoked');
        },
      ),
      ref,
    );
    final pending = locator.locate(
      pageIndex: 1,
      quote: ref.quote,
      contextBefore: '前',
      contextAfter: '后',
    );
    await entered.future;
    active = false;
    resume.complete();
    expect(await pending, isA<SourceUnavailable>());
  });
}
