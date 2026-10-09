import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

// F5a fixtures exercise the existing contract. No proposed schema, codec,
// formula registry, business tool, model provider or second runtime is used.
const object = ObjectRef(
  moduleId: 'fixture',
  objectType: 'quote',
  objectId: 'a',
);

DataSnapshot projection(int revision, String qty, {Object? total}) {
  final ref = SnapshotRef('quote-view', revision);
  return DataSnapshot(
    ref: ref,
    facts: {
      'price': SnapshotFact(
        object: object,
        field: 'price',
        value: '10',
        state: FactState.verified,
      ),
    },
    initialUiState: {'qty': qty, 'enabled': false},
    computations: {
      'total': ComputedValue(
        // Public deterministic host fixture, not the future F3a evaluator.
        value: total ?? '${10 * int.parse(qty)}',
        inputVersion: ref,
        computationId: 'host-total-instance',
      ),
    },
  );
}

InteractionIntent intent(DataSnapshot snapshot) => InteractionIntent(
  id: 'quote-intent-${snapshot.ref.revision}',
  purpose: 'public offline fixture',
  snapshotRef: snapshot.ref,
  requiredBindings: {const BindingRef.computed('total')},
  allowedActionRefs: {'edit', 'detail'},
);

UIPlan plan(DataSnapshot snapshot, InteractionIntent intent, int revision) =>
    UIPlan(
      surfaceId: 'quote-surface',
      revision: revision,
      catalogVersion: libraryUiCatalog.version,
      snapshotRef: snapshot.ref,
      intentRef: intent.id,
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'PageScaffold',
          properties: {'title': 'Public quote'},
          children: ['qty', 'total'],
        ),
        UiNode(
          id: 'qty',
          component: 'Field',
          properties: {'label': 'Quantity'},
          bindings: {
            'value': const BindingRef.fact('price'),
            'draft': const BindingRef.uiState('qty'),
          },
          events: {
            'change': ActionBinding(actionRef: 'edit', inputRefs: ['qty']),
          },
        ),
        UiNode(
          id: 'total',
          component: 'Metric',
          properties: {'label': 'Total'},
          bindings: {'value': const BindingRef.computed('total')},
        ),
      ],
    );

StoredUiWorkspace stored(UIPlan plan, Map<String, Object?> overrides) =>
    StoredUiWorkspace(
      taskId: 'fixture-task',
      surfaceId: plan.surfaceId,
      scopeKey: 'fixture-scope',
      revision: 1,
      schemaVersion: 1,
      catalogVersion: plan.catalogVersion,
      snapshotRef: plan.snapshotRef,
      intentRef: plan.intentRef,
      planRevision: plan.revision,
      draftRevision: 1,
      extracted: {'qty': '2'},
      userOverrides: overrides,
      nodeIds: plan.nodes.map((n) => n.id).toList(),
      presentation: plan,
    );

void main() {
  test('host_constructs_matching_snapshot_computed_intent_plan_fixture', () {
    final s7 = projection(7, '2');
    final i7 = intent(s7);
    final p11 = plan(s7, i7, 11);
    final s8 = projection(8, '3');
    final i8 = intent(s8);
    final p12 = plan(s8, i8, 12);
    expect(validateUiPlan(p11, s7, i7, libraryUiCatalog).errors, isEmpty);
    final checked = validateUiPlan(p12, s8, i8, libraryUiCatalog);
    expect(checked.errors, isEmpty);
    expect(checked.validatedPlan, isNotNull);
    expect(s7.computations['total']!.value, '20');
    expect(s8.computations['total']!.value, '30');
    expect(s7.computations['total']!.computationId, 'host-total-instance');
    expect(s8.computations['total']!.computationId, s7.computations['total']!.computationId);
    expect(s8.computations['total']!.inputVersion, s8.ref);
    expect(i8.snapshotRef, s8.ref);
    expect(p12.snapshotRef, s8.ref);
    expect(p12.intentRef, i8.id);
    expect(p12.revision, greaterThan(p11.revision));
    expect(s8.facts['price']!.object, s7.facts['price']!.object);
    expect(s8.facts['price']!.value, s7.facts['price']!.value);
  });

  test('mixed_intent_or_old_computation_cannot_grant_validated_plan', () {
    final s7 = projection(7, '2');
    final s8 = projection(8, '3');
    final i8 = intent(s8);
    final p12 = plan(s8, i8, 12);
    final mixed = validateUiPlan(p12, s8, intent(s7), libraryUiCatalog);
    expect(mixed.errors, contains('snapshot_revision'));
    expect(mixed.validatedPlan, isNull);
    final stale = s8.copyWith(computations: s7.computations);
    final checked = validateUiPlan(p12, stale, i8, libraryUiCatalog);
    expect(checked.errors, contains('unknown_or_stale_computation:total'));
    expect(checked.validatedPlan, isNull);
  });

  test('relabelled_old_result_is_a_current_validator_diagnostic_gap', () {
    final s8 = projection(8, '3', total: '20');
    final i8 = intent(s8);
    // This demonstrates why a host fingerprint/evaluation check is required.
    // Passing here is not proposed recomputation acceptance.
    expect(
      validateUiPlan(plan(s8, i8, 12), s8, i8, libraryUiCatalog).errors,
      isEmpty,
    );
    expect(s8.computations['total']!.value, isNot('30'));
  });

  test('string_edit_preserves_fact_and_does_not_automatically_recompute', () {
    final s7 = projection(7, '2');
    final i7 = intent(s7);
    final checked = validateUiPlan(
      plan(s7, i7, 11), s7, i7, libraryUiCatalog,
    ).validatedPlan!;
    final state = UiSessionState(s7);
    expect(state.accept(checked), isTrue);
    UiEvent event(Object payload) => UiEvent(
      eventId: 'fixture-edit', surfaceId: 'quote-surface', nodeId: 'qty',
      observedRevision: 11, kind: 'change', payload: payload,
    );
    expect(state.dispatch(event(3), checked, libraryUiCatalog), UiEventOutcome.invalid);
    expect(state.draftRevision, 0);
    expect(state.resolve(const BindingRef.uiState('qty')), '2');
    expect(state.dispatch(event('3'), checked, libraryUiCatalog), UiEventOutcome.applied);
    expect(state.draftRevision, 1);
    expect(state.userOverrides['qty'], '3');
    expect(state.resolve(const BindingRef.fact('price')), '10');
    expect(state.resolve(const BindingRef.computed('total')), '20');
  });

  test('existing_session_cannot_adopt_cross_snapshot_capability', () {
    final s7 = projection(7, '2');
    final s8 = projection(8, '3');
    final i8 = intent(s8);
    final checked = validateUiPlan(
      plan(s8, i8, 12), s8, i8, libraryUiCatalog,
    ).validatedPlan!;
    expect(UiSessionState(s7).accept(checked), isFalse);
  });

  test('typed_toggle_and_compare_detail_keep_current_rejection', () {
    final snapshot = projection(7, '2');
    final currentIntent = InteractionIntent(
      id: 'blocker-intent', purpose: 'boundary fixture',
      snapshotRef: snapshot.ref, allowedActionRefs: {'edit', 'detail'},
    );
    for (final (node, error) in [
      (
        UiNode(
          id: 'root', component: 'Toggle', properties: {'label': 'Enabled'},
          bindings: {'value': const BindingRef.uiState('enabled')},
          events: {'change': ActionBinding(actionRef: 'edit', inputRefs: ['enabled'])},
        ),
        'edit_input',
      ),
      (
        UiNode(
          id: 'root', component: 'CompareTable', properties: {'label': 'Quotes'},
          bindings: {'rows': const BindingRef.computed('total')},
          events: {'tap': ActionBinding(actionRef: 'detail')},
        ),
        'detail_input',
      ),
    ]) {
      final candidate = UIPlan(
        surfaceId: 'blocker', revision: 1, catalogVersion: libraryUiCatalog.version,
        snapshotRef: snapshot.ref, intentRef: currentIntent.id, root: 'root', nodes: [node],
      );
      final checked = validateUiPlan(candidate, snapshot, currentIntent, libraryUiCatalog);
      expect(checked.errors, [error]);
      expect(checked.validatedPlan, isNull);
    }
  });

  test('raw_collection_and_nonfinite_computation_remain_rejected', () {
    final snapshot = projection(7, '2');
    final currentIntent = intent(snapshot);
    for (final value in <Object>[
      [{'itemId': 'quote-a', 'price': 10}], double.nan, double.infinity,
    ]) {
      final bad = snapshot.copyWith(computations: {
        'total': ComputedValue(value: value, inputVersion: snapshot.ref, computationId: 'host-total'),
      });
      final checked = validateUiPlan(plan(bad, currentIntent, 11), bad, currentIntent, libraryUiCatalog);
      expect(checked.errors, contains('unknown_or_stale_computation:total'));
      expect(checked.validatedPlan, isNull);
    }
  });

  test('presentation_roundtrip_keeps_ids_versions_and_scalar_override', () {
    final snapshot = projection(7, '2');
    final currentIntent = intent(snapshot);
    final original = plan(snapshot, currentIntent, 11);
    final restored = decodeUiPresentation(jsonDecode(jsonEncode(encodeUiPresentation(original))) as Map<String, dynamic>);
    expect(restored.nodes.map((n) => n.id), original.nodes.map((n) => n.id));
    expect(restored.snapshotRef, snapshot.ref);
    expect(restored.intentRef, currentIntent.id);
    expect(validateUiPlan(restored, snapshot, currentIntent, libraryUiCatalog).errors, isEmpty);
    final state = UiSessionState(snapshot);
    state.restoreWorkspace(stored(restored, {'qty': '3'}));
    expect(state.userOverrides['qty'], '3');
    expect(state.resolve(const BindingRef.uiState('qty')), '3');
  });

  test('workspace_rejects_collection_override_without_touching_checkpoint', () {
    final snapshot = projection(7, '2');
    final candidate = plan(snapshot, intent(snapshot), 11);
    final prior = stored(candidate, {'qty': '3'});
    expect(() => stored(candidate, {'qty': ['item-a']}), throwsArgumentError);
    expect(prior.userOverrides, {'qty': '3'});
    expect(prior.revision, 1);
    // Constructor rejection only; not a claim of real CAS/SQLite recovery.
  });

  testWidgets('library_catalog_uses_whole_surface_host_snapshot_fallback', (tester) async {
    final snapshot = projection(7, '2');
    final currentIntent = InteractionIntent(
      id: 'fallback-intent', purpose: 'public fallback fixture',
      snapshotRef: snapshot.ref,
      requiredBindings: {const BindingRef.fact('price')},
      allowedActionRefs: {'edit'},
    );
    final checked = validateUiPlan(
      plan(snapshot, currentIntent, 11), snapshot, currentIntent, libraryUiCatalog,
    ).validatedPlan!;
    var routed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DynamicUiSurface(
        plan: checked, onEvent: (_) async { routed++; },
      )),
    ));
    expect(find.text('price: 10 · verified'), findsOneWidget);
    expect(find.text('Public quote'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(routed, 0);
    expect(tester.takeException(), isNull);
  });

  test('draft_collection_binding_is_rejected_by_unchanged_stream1', () {
    final fixture = jsonDecode(File(
      '../../docs/fixtures/aiui5/collection-binding.draft.json',
    ).readAsStringSync()) as Map<String, dynamic>;
    final rowLine = jsonEncode((fixture['modelLines'] as List)[1]);
    final parsed = parseUiStreamLine(rowLine);
    expect(parsed.operation, isNull);
    expect(parsed.error!.code, UiStreamErrorCode.invalidFields);
    final snapshot = projection(7, '2');
    final compiler = UiStreamCompiler(session: UiStreamSession(
      surfaceId: 'quote-surface', revision: 11, snapshot: snapshot,
      intent: intent(snapshot), catalog: libraryUiCatalog,
    ));
    compiler.addLine(jsonEncode((fixture['modelLines'] as List).first));
    compiler.addLine(rowLine);
    compiler.addLine('{"op":"end"}');
    expect(compiler.current.finalPlan, isNull);
    expect(compiler.current.badLines, 1);
    expect(compiler.current.streamErrors, isNotEmpty);
  });

  test('public_library1_stream_golden_compiles_through_existing_final_gate', () {
    final snapshot = projection(7, '2');
    final currentIntent = intent(snapshot);
    final compiler = UiStreamCompiler(session: UiStreamSession(
      surfaceId: 'quote-surface', revision: 11, snapshot: snapshot,
      intent: currentIntent, catalog: libraryUiCatalog,
    ));
    final lines = File(
      '../../docs/fixtures/aiui5/string-projection.library-1.jsonl',
    ).readAsLinesSync();
    for (final line in lines.take(lines.length - 1)) {
      compiler.addLine(line);
    }
    expect(compiler.current.finalPlan, isNull);
    compiler.addLine(lines.last);
    expect(compiler.current.streamErrors, isEmpty);
    expect(compiler.current.finalPlan, isNotNull);
    expect(compiler.current.finalPlan!.snapshot, same(snapshot));
    expect(compiler.current.finalPlan!.plan.intentRef, currentIntent.id);
    expect(compiler.current.text, ['Public host fixture; total is bound.']);
  });
}
