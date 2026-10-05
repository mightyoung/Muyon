import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:research_module/src/cards/card_store.dart';
import 'package:research_module/src/core/store.dart';
import 'package:research_module/src/research_services.dart';
import 'package:research_module/src/reader/source_locator.dart';

import 'citation_resolution_test.dart' show CitationDatabase;
import 'citation_resolver_test.dart' show FixturePages;

/// A real two-page PDF with valid xref offsets. No mocked pdfrx backend.
Uint8List twoPagePdf({
  int rotation = 0,
  bool blank = false,
  bool unicode = false,
}) {
  final first = unicode ? '' : 'BT /F1 12 Tf 20 150 Td (Front page) Tj ET';
  final second = blank
      ? ''
      : unicode
      ? 'BT /F1 12 Tf 20 150 Td <000100020001> Tj ET'
      : 'BT /F1 12 Tf 20 150 Td (Alpha quote omega) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Rotate $rotation /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${first.length} >>\nstream\n$first\nendstream',
    '<< /Length ${second.length} >>\nstream\n$second\nendstream',
  ];
  if (unicode) {
    final cmap =
        '/CIDInit /ProcSet findresource begin 12 dict begin begincmap '
        '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def '
        '/CMapName /Adobe-Identity-UCS def /CMapType 2 def '
        '1 begincodespacerange <0000> <FFFF> endcodespacerange '
        '2 beginbfchar <0001> <0058> <0002> <D83DDE00> endbfchar '
        'endcmap CMapName currentdict /CMap defineresource pop end end';
    objects[4] = '<< /Type /Font /Subtype /Type0 /BaseFont /Arial /Encoding /Identity-H /DescendantFonts [8 0 R] /ToUnicode 9 0 R >>';
    objects.addAll([
      '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Arial /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 10 0 R /DW 600 /CIDToGIDMap /Identity >>',
      '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream',
      '<< /Type /FontDescriptor /FontName /Arial /Flags 32 /FontBBox [0 -200 1000 900] /ItalicAngle 0 /Ascent 800 /Descent -200 /CapHeight 700 /StemV 80 >>',
    ]);
  }
  final output = StringBuffer('%PDF-1.7\n');
  final offsets = [0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = output.length;
  output.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(output.toString()));
}

void main() {
  late Directory temp;
  late CitationDatabase db;
  late CardStore store;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('citation-provider-');
    db = CitationDatabase('${temp.path}/test.sqlite');
    store = CardStore(db);
  });
  tearDown(() {
    db.raw.close();
    temp.deleteSync(recursive: true);
  });
  setUpAll(() {
    // Flutter tester does not expose PDFium's native-asset mapping on this
    // installed toolchain. An explicit existing library permits a real test;
    // no mock, download, conditional skip, or production path override.
    final library = switch (Platform.operatingSystem) {
      'macos' => 'libpdfium.dylib',
      'linux' => 'libpdfium.so',
      'windows' => 'pdfium.dll',
      _ => null,
    };
    final modulePath =
        Platform.environment['C3_PDFIUM_MODULE_PATH'] ??
        (library == null
            ? null
            : File('build/native_assets/${Platform.operatingSystem}/$library')
                  .absolute
                  .path);
    if (modulePath != null) {
      expect(File(modulePath).existsSync(), isTrue);
      Pdfrx.pdfiumModulePath = modulePath;
    }
  });
  tearDownAll(() async => PdfrxEntryFunctions.instance.stopBackgroundWorker());
  Future<SourceRef> register(
    Uint8List bytes, {
    int page = 1,
    String quote = 'quote',
  }) async {
    final key = await store.registerDocument(
      projectId: 'p',
      localDocumentId: 'doc',
      bytes: bytes,
      fileName: 'paper.pdf',
    );
    return SourceRef(
      documentRef: key,
      contentDigest: sha256.convert(bytes).toString(),
      pageIndex: page,
      quote: quote,
      parserVersion: PdfrxCitationPageProvider.version,
    );
  }

  test('real pdfrx original bytes find quote on second physical page with actual glyph boxes', () async {
    final ref = await register(twoPagePdf());
    final result = await CitationResolver(store, 'p').resolve(ref);
    expect(result.status, CitationStatus.exact, reason: result.reason);
    expect(result.pageIndex, 1);
    expect(result.startOffset, 6);
    expect(result.endOffset, 11);
    expect(result.boxes, hasLength(5));
    for (final box in result.boxes) {
      expect(box.left, inInclusiveRange(.17, .29));
      expect(box.top, inInclusiveRange(.19, .27));
      expect(box.right, greaterThan(box.left));
      expect(box.bottom, greaterThan(box.top));
    }
  });
  test(
    'real pdfrx nonBMP quote offsets use UTF16 with real glyph geometry',
    () async {
      final ref = await register(twoPagePdf(unicode: true), quote: '😀');
      final page = await const PdfrxCitationPageProvider().loadPage(
        store.citationDocument('p', ref)!,
        1,
      );
      expect(page!.text, 'X😀X');
      expect(page.characterBoxes, hasLength(4));
      final result = await CitationResolver(store, 'p').resolve(ref);
      expect(result.status, CitationStatus.exact, reason: result.reason);
      expect(result.startOffset, 1);
      expect(result.endOffset, 3);
      expect(result.boxes, hasLength(2));
      expect(result.boxes[0].toJson(), result.boxes[1].toJson());
    },
  );
  test('real pdfrx never searches other physical pages', () async {
    final ref = await register(twoPagePdf(), page: 0);
    final result = await CitationResolver(store, 'p').resolve(ref);
    expect(result.status, CitationStatus.ambiguous);
    expect(result.matchCount, 0);
    expect(result.pageIndex, 0);
  });
  test('real pdfrx missing physical page does not offer a jump', () async {
    final ref = await register(twoPagePdf(), page: 2);
    expect(
      (await CitationResolver(store, 'p').resolve(ref)).status,
      CitationStatus.pageUnavailable,
    );
  });
  test('real pdfrx blank page gives page only', () async {
    final ref = await register(twoPagePdf(blank: true));
    final result = await CitationResolver(store, 'p').resolve(ref);
    expect(result.status, CitationStatus.pageOnly);
    expect(result.reason, 'no_text_layer');
    expect(result.pageIndex, 1);
  });
  test(
    'real pdfrx 90 degree rotation transforms original glyph geometry',
    () async {
      final normal = await register(twoPagePdf());
      final a = await CitationResolver(store, 'p').resolve(normal);
      final rotated = await register(twoPagePdf(rotation: 90));
      final b = await CitationResolver(store, 'p').resolve(rotated);
      expect(b.status, CitationStatus.exact, reason: b.reason);
      expect(b.boxes, hasLength(a.boxes.length));
      for (var i = 0; i < a.boxes.length; i++) {
        expect(b.boxes[i].left, closeTo(1 - a.boxes[i].bottom, 1e-6));
        expect(b.boxes[i].top, closeTo(a.boxes[i].left, 1e-6));
        expect(b.boxes[i].right, closeTo(1 - a.boxes[i].top, 1e-6));
        expect(b.boxes[i].bottom, closeTo(a.boxes[i].right, 1e-6));
      }
    },
  );
  test(
    'invalid PDF with out of range anchor cannot promise a page jump',
    () async {
      final ref = await register(
        Uint8List.fromList(ascii.encode('not a PDF')),
        page: 999,
      );
      final result = await CitationResolver(store, 'p').resolve(ref);
      expect(result.status, CitationStatus.pageUnavailable);
      expect(result.reason, 'parser_unavailable');
      expect(result.pageIndex, isNull);
      expect(result.boxes, isEmpty);
    },
  );
  test('throwing page provider leaves physical page unknown', () async {
    final ref = await register(twoPagePdf(), page: 999);
    final provider = FixturePages(
      (_, _) async => throw StateError('parser failed'),
    );
    final result = await CitationResolver(
      store,
      'p',
      provider: provider,
    ).resolve(ref);
    expect(result.status, CitationStatus.pageUnavailable);
    expect(result.pageIndex, isNull);
    final locator = CitationQuoteLocator(
      CitationResolver(store, 'p', provider: provider),
      ref,
    );
    expect(
      await locator.locate(pageIndex: 999, quote: 'quote'),
      isA<SourceUnavailable>(),
    );
  });
  test('ResearchServices scoped facade resolves citations through injected provider', () async {
    final ref = await register(twoPagePdf());
    final services = ResearchServices(
      WorkbenchStore.attach(rootPath: temp.path, database: db.raw, managed: db),
      'p',
    );
    final provider = FixturePages(
      (original, index) async => CitationPage(
        contentDigest: original.contentDigest,
        pageIndex: index,
        parserVersion: PdfrxCitationPageProvider.version,
        text: 'quote',
      ),
    );
    final result = await services.resolveCitation(ref, provider: provider);
    expect(result.status, CitationStatus.uniqueText);
    final locator = services.quoteLocator(ref, provider: provider);
    expect(await locator.locate(pageIndex: 1, quote: 'quote'), isA<PageOnly>());
    expect((await services.resolveCitation(ref)).status, CitationStatus.exact);
  });
  test(
    'ResearchServices refuses standalone unmanaged canonical resolution',
    () async {
      final services = ResearchServices(
        WorkbenchStore.attach(rootPath: temp.path, database: db.raw),
        'p',
      );
      expect(() => services.citationResolver(), throwsStateError);
    },
  );
}
