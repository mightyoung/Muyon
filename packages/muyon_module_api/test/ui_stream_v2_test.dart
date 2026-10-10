import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

// F5b slice 1 (RED): aiui-stream/2 gate. Uses only types that exist today; the
// typed/collection API (BindingKind.collection, DataSnapshot.collections,
// editSpecs) is deliberately NOT referenced, collection rows travel as raw JSON.
const v1 = 'aiui-stream/1';
const v2 = 'aiui-stream/2';

void main() {
  late ContractFixture f;
  setUp(() => f = ContractFixture());

  UiCatalog asVersion(String version) => UiCatalog(
    version: version,
    components: f.catalog.components,
    actions: f.catalog.actions,
  );

  UiStreamSession session(String protocol, UiCatalog catalog) =>
      UiStreamSession(
        surfaceId: f.plan.surfaceId,
        revision: f.plan.revision,
        snapshot: f.snapshot,
        intent: f.intent,
        catalog: catalog,
        root: f.plan.root,
        protocolVersion: protocol,
      );

  UiStreamCompiler stream(String protocol, UiCatalog catalog) =>
      UiStreamCompiler(session: session(protocol, catalog));

  void addRoot(UiStreamCompiler c) => c.addLine(
    jsonEncode({
      'op': 'node',
      'id': 'root',
      'component': 'PageScaffold',
      'props': {'title': 'Comparison'},
      'bind': <String, Object?>{},
    }),
  );
  void addCollectionField(UiStreamCompiler c) => c.addLine(
    jsonEncode({
      'op': 'node',
      'id': 'qty',
      'component': 'Field',
      'parent': 'root',
      'props': <String, Object?>{},
      'bind': {
        'value': {'kind': 'fact', 'id': 'qty'},
        'draft': {'kind': 'uiState', 'id': 'quantity'},
        'source': {'kind': 'sourceSpan', 'id': 'quote'},
        'total': {'kind': 'computed', 'id': 'total'},
        'rows': {'kind': 'collection', 'id': 'rows'},
      },
    }),
  );
  void addEnd(UiStreamCompiler c) => c.addLine('{"op":"end"}');

  // RED 1 (behavioural): today the constructor throws ArgumentError for /2.
  test('aiui-stream/2 session with host catalog library-2 constructs', () {
    expect(() => session(v2, asVersion('library-2')), returnsNormally);
    expect(session(v2, asVersion('library-2')).protocolVersion, v2);
  });

  // RED 2 (behavioural): today library-2 + v1 constructs silently.
  test('library-2 with aiui-stream/1 is rejected at construction', () {
    expect(
      () => session(v1, asVersion('library-2')),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '$e',
          'message',
          contains('catalog_requires_stream_2'),
        ),
      ),
    );
    // Explicit v1 spelling and the default behave identically.
    expect(
      () => UiStreamSession(
        surfaceId: 's',
        revision: 0,
        snapshot: f.snapshot,
        intent: f.intent,
        catalog: asVersion('library-2'),
      ),
      throwsArgumentError,
    );
  });

  // RED 3 (behavioural): real compiler on a /2 session reaches `end` and equals
  // the batch validator (same UiStreamCompiler / validateUiPlan, no fakes).
  test('library-2 + stream/2 compiles a plain plan to the batch result', () {
    final c = stream(v2, asVersion('library-2'));
    addRoot(c);
    c.addLine(
      jsonEncode({
        'op': 'node',
        'id': 'qty',
        'component': 'Field',
        'parent': 'root',
        'props': <String, Object?>{},
        'bind': {
          'value': {'kind': 'fact', 'id': 'qty'},
          'draft': {'kind': 'uiState', 'id': 'quantity'},
          'source': {'kind': 'sourceSpan', 'id': 'quote'},
          'total': {'kind': 'computed', 'id': 'total'},
        },
      }),
    );
    addEnd(c);
    final batch = validateUiPlan(
      c.current.candidatePlan,
      c.session.snapshot,
      c.session.intent,
      c.session.catalog,
    );
    expect(c.current.badLines, 0);
    expect(c.current.complete, batch.isValid);
    expect(c.current.finalPlan, isNotNull);
    expect(c.current.finalPlan!.plan.catalogVersion, 'library-2');
  });

  // RED 4 (behavioural): /2 grammar admits kind:"collection" as a syntax-level
  // bind. A catalog without collection slots then rejects it at node level
  // (placeholder), not as a bad line. Today the /2 session cannot be built.
  test('stream/2 accepts collection bind syntax; pre-collection catalog '
      'rejects it at node validation', () {
    final c = stream(v2, asVersion('minimal-1'));
    addRoot(c);
    addCollectionField(c);
    expect(c.current.badLines, 0);
    expect(c.current.streamErrors, isEmpty);
    expect(c.current.statuses['qty']!.phase, UiStreamNodePhase.placeholder);
    expect(c.current.statuses['qty']!.reasons, isNotEmpty);
    addEnd(c);
    expect(c.current.complete, isFalse);
  });

  // Controls: pass today and must keep passing (v1 rules, M2 guard).
  group('v1 and version controls', () {
    test('stream/1 keeps the four bind kinds; collection is a bad line', () {
      for (final kind in ['fact', 'computed', 'sourceSpan', 'uiState']) {
        final parsed = parseUiStreamLine(
          jsonEncode({
            'op': 'node',
            'id': 'n',
            'component': 'Text',
            'bind': {
              'x': {'kind': kind, 'id': 'a'},
            },
          }),
        );
        expect(parsed.error, isNull, reason: kind);
      }
      final c = stream(v1, f.catalog);
      addRoot(c);
      addCollectionField(c);
      expect(c.current.badLines, 1);
      expect(c.current.statuses.containsKey('qty'), isFalse);
      addEnd(c);
      expect(c.current.finalPlan, isNull);
      expect(c.current.complete, isFalse);
      expect(
        c.current.streamErrors.map((e) => e.code),
        contains(UiStreamErrorCode.malformedStream),
      );
    });

    test('old catalogs still reject collection bindings', () {
      for (final version in ['minimal-1', 'dynamic-1', 'library-1']) {
        final c = stream(v1, asVersion(version));
        addRoot(c);
        addCollectionField(c);
        expect(c.current.badLines, 1, reason: version);
        addEnd(c);
        expect(c.current.finalPlan, isNull, reason: version);
      }
    });

    test('unknown or malformed protocol versions are rejected', () {
      for (final bad in [
        'aiui-stream/0',
        'aiui-stream/3',
        'aiui-stream/2 ',
        'AIUI-STREAM/2',
        'aiui-stream/02',
        'aiui-stream',
        '',
      ]) {
        expect(
          () => session(bad, f.catalog),
          throwsArgumentError,
          reason: "'$bad'",
        );
        expect(
          () => session(bad, asVersion('library-2')),
          throwsArgumentError,
          reason: "library-2 '$bad'",
        );
      }
    });
  });
}
