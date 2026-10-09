import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui/fixtures.dart';

void main() {
  late ContractFixture f;
  late UiStreamCompiler c;
  setUp(() {
    f = ContractFixture();
    c = compiler(f);
  });
  void differential(UiStreamCompiler stream) {
    final v = stream.current;
    final batch = validateUiPlan(
      v.candidatePlan,
      stream.session.snapshot,
      stream.session.intent,
      stream.session.catalog,
    );
    expect(v.batchValidation!.isValid, batch.isValid);
    expect(v.batchValidation!.errors, batch.errors);
    if (v.badLines == 0) expect(v.complete, batch.isValid);
  }

  test('session metadata and protocol version are host owned', () {
    expect(c.session.protocolVersion, 'aiui-stream/1');
    expect(
      () => UiStreamSession(
        surfaceId: 's',
        revision: 0,
        snapshot: f.snapshot,
        intent: f.intent,
        catalog: f.catalog,
        protocolVersion: 'aiui-stream/2',
      ),
      throwsArgumentError,
    );
    root(c);
    field(c);
    end(c);
    expect(c.current.finalPlan!.plan.surfaceId, f.plan.surfaceId);
    expect(c.current.finalPlan!.plan.snapshotRef, f.snapshot.ref);
    differential(c);
  });
  test('node validation isolates placeholders and blocked descendants', () {
    root(c);
    node(c, 'bad', 'Unknown', parent: 'root');
    node(c, 'child', 'Text', parent: 'bad');
    node(c, 'good', 'Text', parent: 'root');
    expect(c.current.statuses['bad']!.phase, UiStreamNodePhase.placeholder);
    expect(c.current.statuses['child']!.reasons, ['blocked_by_parent']);
    expect(c.current.statuses['good']!.phase, UiStreamNodePhase.rendered);
    expect(c.current.previewPlan.nodes.map((n) => n.id), ['root', 'good']);
    end(c);
    differential(c);
    expect(c.current.previewPlan.nodes, isEmpty);
    expect(c.current.candidatePlan.nodes.length, 4);
  });
  test('binding range rejects missing facts without rendering', () {
    root(c);
    field(c, fact: 'missing');
    expect(c.current.statuses['qty']!.phase, UiStreamNodePhase.placeholder);
    expect(
      c.current.statuses['qty']!.reasons,
      contains('unknown_fact:missing'),
    );
    expect(c.current.previewPlan.nodes.map((n) => n.id), ['root']);
    end(c);
    differential(c);
  });
  test('interrupted action remains disabled after complete action line', () {
    root(c);
    field(c);
    action(c);
    expect(c.current.previewPlan.nodes.last.events, isEmpty);
    final v = c.interrupt();
    expect(v.phase, UiStreamPhase.incomplete);
    expect(v.previewPlan.nodes.last.events, isEmpty);
    expect(v.candidatePlan.nodes.last.events, isNotEmpty);
    expect(v.finalPlan, isNull);
    end(c);
    expect(c.current.batchValidation, isNull);
  });
  test('every truncated action line is inert and malformed', () {
    final line = jsonEncode(actionMap());
    for (var i = 1; i < line.length; i++) {
      c = compiler(f);
      root(c);
      field(c);
      c.addLine(line.substring(0, i));
      expect(c.current.badLines, 1, reason: 'cut $i');
      expect(c.interrupt().previewPlan.nodes.last.events, isEmpty);
      expect(c.current.finalPlan, isNull);
    }
  });
  test('invalid patch retains raw candidate and last valid preview', () {
    root(c);
    field(c);
    patch(c, 'root', {'title': 3});
    expect(c.current.candidatePlan.nodes.first.properties['title'], 3);
    expect(c.current.streamErrors, isEmpty);
    expect(c.current.previewPlan.nodes.first.properties['title'], 'Comparison');
    expect(
      c.current.statuses['root']!.reasons,
      contains('property_type:root:title'),
    );
    expect(c.current.previewPlan.nodes.last.id, 'qty');
    end(c);
    differential(c);
    expect(c.current.complete, isFalse);
    expect(c.current.previewPlan.nodes, isEmpty);
  });
  test('patch null deletes and key merge preserves other properties', () {
    root(c);
    field(c);
    patch(c, 'root', {'title': null});
    expect(c.current.candidatePlan.nodes.first.properties, isEmpty);
    expect(c.current.previewPlan.nodes.first.properties['title'], 'Comparison');
    expect(
      c.current.statuses['root']!.reasons,
      contains('missing_property:root:title'),
    );
    patch(c, 'root', {'title': 'Fixed'});
    expect(c.current.previewPlan.nodes.first.properties['title'], 'Fixed');
    end(c);
    expect(c.current.complete, isTrue);
    differential(c);
  });
  test('invalid first version remains placeholder until valid patch', () {
    node(c, 'root', 'PageScaffold', props: {'title': false});
    expect(c.current.statuses['root']!.phase, UiStreamNodePhase.placeholder);
    expect(c.current.previewPlan.nodes, isEmpty);
    patch(c, 'root', {'title': 'fixed'});
    expect(c.current.statuses['root']!.phase, UiStreamNodePhase.rendered);
  });
  test(
    'root ordering missing parent duplicates and missing patch are bad lines',
    () {
      for (final line in [
        {'op': 'node', 'id': 'not-root', 'component': 'Text'},
        {'op': 'node', 'id': 'root', 'parent': 'root', 'component': 'Text'},
        {'op': 'node', 'id': 'child', 'component': 'Text'},
      ]) {
        c = compiler(f);
        c.addLine(jsonEncode(line));
        expect(c.current.badLines, 1);
        expect(c.current.candidatePlan.nodes, isEmpty);
      }
      c = compiler(f);
      root(c);
      node(c, 'orphan', 'Text', parent: 'absent');
      node(c, 'self', 'Text', parent: 'self');
      node(c, 'root', 'Text');
      node(c, 'child', 'Text');
      patch(c, 'absent', {});
      expect(c.current.badLines, 5);
      expect(c.current.candidatePlan.nodes.length, 1);
      expect(c.current.candidatePlan.nodes.first.component, 'PageScaffold');
      end(c);
      expect(c.current.phase, UiStreamPhase.rejected);
      expect(
        c.current.diagnostics.any((d) => d.reason == 'malformed_stream'),
        isTrue,
      );
      differential(c);
    },
  );
  test(
    'parent without children support invalidates parent and blocks child',
    () {
      node(c, 'root', 'Text');
      node(c, 'child', 'Text', parent: 'root');
      expect(c.current.statuses['root']!.phase, UiStreamNodePhase.placeholder);
      expect(c.current.statuses['child']!.reasons, ['blocked_by_parent']);
      end(c);
      expect(c.current.batchValidation!.errors, contains('children:root'));
      differential(c);
    },
  );
  test('business revision host filled; local refs remain null', () {
    root(c);
    field(c);
    action(c);
    final b = c.current.candidatePlan.nodes.last.events['tap']!;
    expect(b.expectedDraftRevision, 15);
    expect(c.current.previewPlan.nodes.last.events, isEmpty);
    end(c);
    expect(c.current.complete, isTrue);
    expect(
      c.current.finalPlan!.plan.nodes.last.events['tap']!.actionRef,
      'commit',
    );
    c = compiler(f);
    root(c);
    field(c);
    c.addLine(
      jsonEncode({
        'op': 'action',
        'node': 'qty',
        'event': 'change',
        'action': 'edit',
        'inputs': ['quantity'],
      }),
    );
    final local = c.current.candidatePlan.nodes.last.events['change']!;
    expect(local.expectedDraftRevision, isNull);
    expect(local.operationKeyRef, isNull);
    end(c);
    expect(c.current.complete, isTrue);
    differential(c);
  });
  test('duplicate events and missing business operation cannot finalize', () {
    root(c);
    field(c);
    action(c);
    action(c);
    expect(c.current.badLines, 1);
    expect(c.current.candidatePlan.nodes.last.events.length, 1);
    end(c);
    expect(c.current.batchValidation!.isValid, isTrue);
    expect(c.current.complete, isFalse);
    expect(c.current.finalPlan, isNull);
    c = compiler(f);
    root(c);
    field(c);
    final missing = actionMap()..remove('operation');
    c.addLine(jsonEncode(missing));
    expect(c.current.badLines, 1);
    expect(c.current.candidatePlan.nodes.last.events, isEmpty);
    final inputs = actionMap()..remove('inputs');
    c.addLine(jsonEncode(inputs));
    expect(c.current.badLines, 2);
  });
  test('action binding and allowlist rejection matrix matches batch', () {
    for (final overrides in [
      {'action': 'missing'},
      {
        'inputs': ['missing'],
      },
      {'operation': 'missing'},
      {
        'inputs': ['quantity', 'quantity'],
      },
      {'action': 'edit'},
      {'event': 'unknown'},
    ]) {
      c = compiler(f);
      root(c);
      field(c);
      action(c, overrides);
      expect(c.current.statuses['qty']!.phase, UiStreamNodePhase.placeholder);
      end(c);
      differential(c);
      expect(c.current.complete, isFalse);
    }
    final denied = InteractionIntent(
      id: f.intent.id,
      purpose: 'denied',
      snapshotRef: f.snapshot.ref,
    );
    c = compiler(f, intent: denied);
    root(c);
    field(c);
    action(c);
    end(c);
    differential(c);
    expect(
      c.current.batchValidation!.errors,
      contains('unknown_event_or_action:qty:tap'),
    );
  });
  test('missing stale and mismatched binding kinds match batch', () {
    for (final bind in [
      {'value': ref('fact', 'qty@rev4')},
      {'draft': ref('uiState', 'new')},
      {'source': ref('sourceSpan', 'missing')},
      {'total': ref('computed', 'missing')},
      {'value': ref('computed', 'total')},
    ]) {
      c = compiler(f);
      root(c);
      field(c, overrides: bind);
      expect(c.current.statuses['qty']!.phase, UiStreamNodePhase.placeholder);
      end(c);
      differential(c);
      expect(c.current.complete, isFalse);
    }
    final stale = f.snapshot.copyWith(
      computations: {
        'total': const ComputedValue(
          value: 120,
          inputVersion: SnapshotRef('comparison', 3),
          computationId: 'total',
        ),
      },
    );
    c = compiler(f, snapshot: stale);
    root(c);
    field(c);
    end(c);
    differential(c);
    expect(
      c.current.batchValidation!.errors,
      contains('unknown_or_stale_computation:total'),
    );
    final staleSource = f.snapshot.copyWith(
      sourceDigests: {'document': 'changed'},
    );
    c = compiler(f, snapshot: staleSource);
    root(c);
    field(c);
    end(c);
    differential(c);
    expect(
      c.current.batchValidation!.errors,
      contains('unknown_or_stale_source:quote'),
    );
  });
  test('batch coverage only applies at end and unknown component never satisfies it', () {
    root(c);
    expect(c.current.statuses['root']!.phase, UiStreamNodePhase.rendered);
    end(c);
    differential(c);
    expect(c.current.batchValidation!.errors, contains('required_binding:qty'));
    expect(c.current.batchValidation!.errors, contains('mandatory_state:qty'));
    c = compiler(f);
    root(c);
    field(c, component: 'unknown');
    end(c);
    differential(c);
    expect(
      c.current.batchValidation!.errors,
      contains('unknown_component:unknown'),
    );
    expect(c.current.batchValidation!.errors, contains('mandatory_state:qty'));
  });
  test('bad line veto is independent of exact candidate batch equivalence', () {
    c = compiler(f, intent: emptyIntent(f));
    root(c);
    c.addLine('{"op":"unknown"}');
    end(c);
    differential(c);
    expect(c.current.batchValidation!.isValid, isTrue);
    expect(c.current.phase, UiStreamPhase.rejected);
    expect(c.current.streamErrors, isNotEmpty);
    expect(c.current.finalPlan, isNull);
    expect(
      c.current.diagnostics.any(
        (d) => d.code == UiStreamErrorCode.malformedStream,
      ),
      isTrue,
    );
    expect(c.current.previewPlan.nodes, isEmpty);
  });
  test(
    'forbidden metadata formula binding and v2 fields are typed bad lines',
    () {
      for (final m in [
        {'op': 'node', 'id': 'root', 'component': 'Text', 'surfaceId': 'evil'},
        {'op': 'node', 'id': 'root', 'component': 'Text', 'revision': 7},
        {
          'op': 'node',
          'id': 'root',
          'component': 'Text',
          'catalogVersion': 'evil',
        },
        {
          'op': 'node',
          'id': 'root',
          'component': 'Text',
          'snapshotRef': 'evil',
        },
        {'op': 'node', 'id': 'root', 'component': 'Text', 'intentRef': 'evil'},
        {'op': 'node', 'id': 'root', 'type': 'Text'},
        {
          'op': 'node',
          'id': 'root',
          'component': 'Text',
          'bind': {'x': 'fact:a'},
        },
        for (final key in ['formula', 'expr', 'value'])
          {
            'op': 'node',
            'id': 'root',
            'component': 'Text',
            'bind': {
              'x': {'kind': 'computed', 'id': 'total', key: 'evil'},
            },
          },
        {'op': 'patch', 'id': 'root', 'bind': {}},
        {'op': 'patch', 'id': 'root', 'component': 'Text'},
        {'op': 'patch', 'id': 'root', 'parent': 'other'},
        {'op': 'patch', 'id': 'root', 'children': []},
        {'op': 'delete', 'id': 'root'},
        {'op': 'reorder', 'id': 'root'},
        {...actionMap(), 'route': 'business'},
        {...actionMap(), 'expectedDraftRevision': 15},
        {'op': 'end', 'extra': true},
      ]) {
        final parsed = parseUiStreamLine(jsonEncode(m));
        expect(parsed.error, isNotNull, reason: '$m');
        expect(parsed.operation, isNull);
      }
      for (final line in ['null', '[1]', '{', ''])
        expect(parseUiStreamLine(line).error, isNotNull);
    },
  );
  test('node limit permits N minus one and N, rejects N plus one', () {
    final n = UiStreamLimits.v1.nodes;
    c = compiler(f, intent: emptyIntent(f));
    root(c);
    for (var i = 1; i < n - 1; i++) node(c, 'n$i', 'Text', parent: 'root');
    expect(c.current.candidatePlan.nodes.length, n - 1);
    node(c, 'last', 'Text', parent: 'root');
    expect(c.current.candidatePlan.nodes.length, n);
    end(c);
    expect(c.current.complete, isTrue);
    differential(c);
    c = compiler(f, intent: emptyIntent(f));
    root(c);
    for (var i = 1; i < n; i++) node(c, 'n$i', 'Text', parent: 'root');
    node(c, 'overflow', 'Text', parent: 'root');
    expect(c.current.phase, UiStreamPhase.limitExceeded);
    expect(c.current.diagnostics.last.code, UiStreamErrorCode.nodeLimit);
    expect(c.current.candidatePlan.nodes.length, n);
    final before = c.current.receivedLines;
    end(c);
    expect(c.current.receivedLines, before + 1);
    expect(c.current.batchValidation, isNull);
  });
  test('depth boundary stops before accepting excess child', () {
    c = compiler(f, intent: emptyIntent(f));
    root(c);
    for (var i = 2; i <= UiStreamLimits.v1.depth; i++) {
      node(
        c,
        'd$i',
        'PageScaffold',
        parent: i == 2 ? 'root' : 'd${i - 1}',
        props: {'title': 'x'},
      );
    }
    expect(c.current.phase, UiStreamPhase.streaming);
    node(c, 'too-deep', 'Text', parent: 'd${UiStreamLimits.v1.depth}');
    expect(c.current.phase, UiStreamPhase.limitExceeded);
    expect(c.current.diagnostics.last.code, UiStreamErrorCode.depthLimit);
    expect(c.current.candidatePlan.nodes.length, UiStreamLimits.v1.depth);
    end(c);
    expect(c.current.batchValidation, isNull);
  });
  test('line byte boundary uses UTF8 and preserves prior preview', () {
    final line = jsonEncode({'op': 'text', 'md': '界'});
    final size = utf8.encode(line).length;
    expect(
      parseUiStreamLine(line, limits: UiStreamLimits(lineBytes: size)).error,
      isNull,
    );
    expect(
      parseUiStreamLine(
        line,
        limits: UiStreamLimits(lineBytes: size - 1),
      ).error!.code,
      UiStreamErrorCode.lineLimit,
    );
    expect(
      parseUiStreamLine(
        line,
        limits: UiStreamLimits(lineBytes: size + 1),
      ).error,
      isNull,
    );
    root(c);
    final old = c.current.previewPlan.nodes.length;
    c.addLine('界' * (UiStreamLimits.v1.lineBytes ~/ 3 + 1));
    expect(c.current.phase, UiStreamPhase.limitExceeded);
    expect(c.current.previewPlan.nodes.length, old);
  });
  test('total text bytes includes text and all string properties', () {
    c = compiler(f, limits: const UiStreamLimits(textBytes: 13));
    root(c); // Comparison=10
    c.addLine('{"op":"text","md":"界"}');
    expect(c.current.phase, UiStreamPhase.streaming);
    c.addLine('{"op":"text","md":"x"}');
    expect(c.current.phase, UiStreamPhase.limitExceeded);
    expect(c.current.text, ['界']);
    expect(c.current.diagnostics.last.code, UiStreamErrorCode.textLimit);
    c = compiler(f, limits: const UiStreamLimits(textBytes: 11));
    root(c);
    patch(c, 'root', {'title': 'xx'});
    expect(c.current.phase, UiStreamPhase.limitExceeded);
    expect(
      c.current.candidatePlan.nodes.first.properties['title'],
      'Comparison',
    );
  });
  test('line bad line and per node patch quotas are inclusive', () {
    c = compiler(f, limits: const UiStreamLimits(lines: 2));
    c.addLine('{"op":"text","md":"one"}');
    c.addLine('{"op":"text","md":"two"}');
    expect(c.current.phase, UiStreamPhase.streaming);
    end(c);
    expect(c.current.diagnostics.last.code, UiStreamErrorCode.lineCountLimit);
    c = compiler(f, limits: const UiStreamLimits(badLines: 2));
    c.addLine('{');
    c.addLine('{');
    expect(c.current.phase, UiStreamPhase.streaming);
    c.addLine('{');
    expect(c.current.phase, UiStreamPhase.limitExceeded);
    expect(c.current.diagnostics.last.code, UiStreamErrorCode.badLineLimit);
    c = compiler(f);
    root(c);
    for (var i = 0; i < UiStreamLimits.v1.patchesPerNode; i++)
      patch(c, 'root', {'title': 'v$i'});
    expect(c.current.phase, UiStreamPhase.streaming);
    patch(c, 'root', {'title': 'overflow'});
    expect(c.current.phase, UiStreamPhase.limitExceeded);
    expect(c.current.diagnostics.last.code, UiStreamErrorCode.patchLimit);
    expect(c.current.candidatePlan.nodes.first.properties['title'], 'v19');
  });
  test(
    'after end preserves first result; diagnostics truncate and keep counting',
    () {
      root(c);
      field(c);
      end(c);
      expect(c.current.complete, isTrue);
      final candidate = c.current.candidatePlan.nodes.length;
      for (var i = 0; i < UiStreamLimits.v1.diagnostics + 1; i++) end(c);
      expect(c.current.complete, isTrue);
      expect(c.current.candidatePlan.nodes.length, candidate);
      expect(c.current.diagnostics.length, UiStreamLimits.v1.diagnostics);
      expect(c.current.diagnosticCount, UiStreamLimits.v1.diagnostics + 1);
      expect(
        c.current.diagnostics.every(
          (d) => d.code == UiStreamErrorCode.afterEnd,
        ),
        isTrue,
      );
      node(c, 'ignored', 'Text', parent: 'root');
      expect(c.current.diagnosticCount, 102);
      expect(c.current.candidatePlan.nodes.length, candidate);
    },
  );
  test('patch fallback survives new valid child but cannot hide forbidden children', () {
    root(c);
    patch(c, 'root', {'title': 3});
    node(c, 'child', 'Text', parent: 'root');
    expect(c.current.previewPlan.nodes.map((n) => n.id), ['root', 'child']);
    expect(c.current.previewPlan.nodes.first.properties['title'], 'Comparison');
    expect(c.current.candidatePlan.nodes.first.properties['title'], 3);
    c = compiler(f);
    node(c, 'root', 'Text');
    node(c, 'child', 'Text', parent: 'root');
    expect(c.current.previewPlan.nodes, isEmpty);
  });
  test('missing action targets and local business refs are rejected', () {
    root(c);
    c.addLine(jsonEncode(actionMap()));
    expect(c.current.badLines, 1);
    expect(c.current.candidatePlan.nodes.first.events, isEmpty);
    c = compiler(f);
    root(c);
    field(c);
    c.addLine(
      jsonEncode({
        'op': 'action',
        'node': 'qty',
        'event': 'change',
        'action': 'edit',
        'inputs': ['quantity'],
        'operation': 'host-operation-1',
      }),
    );
    expect(
      c.current.statuses['qty']!.reasons,
      contains('local_business_reference'),
    );
    end(c);
    differential(c);
    expect(c.current.complete, isFalse);
  });
  test('every JSON property stays raw and shared schema validation controls recovery', () {
    for (final value in [
      1.5,
      null,
      ['nested'],
      {'nested': 'x'},
    ]) {
      c = compiler(f);
      node(c, 'root', 'PageScaffold', props: {'title': value});
      expect(c.current.badLines, 0);
      expect(c.current.candidatePlan.nodes.first.properties['title'], value);
      expect(c.current.statuses['root']!.phase, UiStreamNodePhase.placeholder);
      patch(c, 'root', {'title': 'fixed'});
      field(c);
      end(c);
      differential(c);
      expect(c.current.complete, isTrue);
    }
  });
  test(
    'valid action retains patch fallback but invalid action cannot use it',
    () {
      root(c);
      field(c);
      patch(c, 'qty', {'unknown': 1});
      c.addLine(
        jsonEncode({
          'op': 'action',
          'node': 'qty',
          'event': 'change',
          'action': 'edit',
          'inputs': ['quantity'],
        }),
      );
      expect(c.current.statuses['qty']!.phase, UiStreamNodePhase.rendered);
      expect(c.current.previewPlan.nodes.last.properties, isEmpty);
      expect(c.current.previewPlan.nodes.last.events, isEmpty);
      expect(c.current.candidatePlan.nodes.last.properties['unknown'], 1);
      end(c);
      differential(c);
      expect(c.current.complete, isFalse);
      c = compiler(f);
      root(c);
      field(c);
      patch(c, 'qty', {'unknown': 1});
      action(c, {'action': 'missing'});
      expect(c.current.statuses['qty']!.phase, UiStreamNodePhase.placeholder);
    },
  );
  test('host limit configuration can only tighten v1 bounds', () {
    for (final limits in [
      const UiStreamLimits(nodes: 201),
      const UiStreamLimits(depth: 13),
      const UiStreamLimits(lineBytes: 16385),
      const UiStreamLimits(textBytes: 65537),
      const UiStreamLimits(lines: 2001),
      const UiStreamLimits(badLines: 21),
      const UiStreamLimits(patchesPerNode: 21),
      const UiStreamLimits(diagnostics: 101),
      const UiStreamLimits(nodes: 0),
    ]) {
      expect(() => compiler(f, limits: limits), throwsArgumentError);
    }
  });
  test('pure text and empty end follow batch empty plan rejection', () {
    c.addLine('{"op":"text","md":"Model prose"}');
    end(c);
    differential(c);
    expect(c.current.text, ['Model prose']);
    expect(c.current.finalPlan, isNull);
    expect(c.current.batchValidation!.errors, contains('node_limit'));
    c = compiler(f);
    end(c);
    differential(c);
    expect(c.current.complete, isFalse);
  });
}

UiStreamCompiler compiler(
  ContractFixture f, {
  DataSnapshot? snapshot,
  InteractionIntent? intent,
  UiStreamLimits limits = UiStreamLimits.v1,
}) => UiStreamCompiler(
  session: UiStreamSession(
    surfaceId: f.plan.surfaceId,
    revision: f.plan.revision,
    snapshot: snapshot ?? f.snapshot,
    intent: intent ?? f.intent,
    catalog: f.catalog,
    root: f.plan.root,
  ),
  limits: limits,
);
InteractionIntent emptyIntent(ContractFixture f) => InteractionIntent(
  id: f.intent.id,
  purpose: 'limits',
  snapshotRef: f.snapshot.ref,
);
Map<String, String> ref(String kind, String id) => {'kind': kind, 'id': id};
void node(
  UiStreamCompiler c,
  String id,
  String component, {
  String? parent,
  Map<String, Object?> props = const {},
  Map<String, Object?> bind = const {},
}) => c.addLine(
  jsonEncode({
    'op': 'node',
    'id': id,
    'component': component,
    if (parent != null) 'parent': parent,
    'props': props,
    'bind': bind,
  }),
);
void root(UiStreamCompiler c) =>
    node(c, 'root', 'PageScaffold', props: {'title': 'Comparison'});
void field(
  UiStreamCompiler c, {
  String fact = 'qty',
  String component = 'Field',
  Map<String, Object?> overrides = const {},
}) => node(
  c,
  'qty',
  component,
  parent: 'root',
  bind: {
    'value': ref('fact', fact),
    'draft': ref('uiState', 'quantity'),
    'source': ref('sourceSpan', 'quote'),
    'total': ref('computed', 'total'),
    ...overrides,
  },
);
void patch(UiStreamCompiler c, String id, Map<String, Object?> props) =>
    c.addLine(jsonEncode({'op': 'patch', 'id': id, 'props': props}));
Map<String, Object?> actionMap([Map<String, Object?> overrides = const {}]) => {
  'op': 'action',
  'node': 'qty',
  'event': 'tap',
  'action': 'commit',
  'inputs': ['quantity', 'record-a'],
  'operation': 'host-operation-1',
  ...overrides,
};
void action(UiStreamCompiler c, [Map<String, Object?> overrides = const {}]) =>
    c.addLine(jsonEncode(actionMap(overrides)));
void end(UiStreamCompiler c) => c.addLine('{"op":"end"}');
