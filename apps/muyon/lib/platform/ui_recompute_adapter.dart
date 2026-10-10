// Pinned PR21 has no public export yet; H2 belongs to F5b. Remove this narrow
// import suppression when that owner's export is available.
// ignore: implementation_imports
import 'package:muyon_module_api/src/ui/recomputation.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'ui_formula_registry.dart';

/// Host-only candidate and its diagnostic evidence; neither grants authority.
/// The complete token must still pass the owner's synchronous publisher.
final class UiPreparedFormulaRecompute {
  UiPreparedFormulaRecompute._({
    required this.result,
    this.batch,
    Map<String, UiFormulaEvaluation> evaluations = const {},
  }) : evaluations = Map.unmodifiable(evaluations);

  final UiRecomputeResult result;
  final UiVersionBatch? batch;

  /// F3a diagnostics keyed by displayed computed binding, never a result cache.
  /// Retains fingerprints, unavailable reasons and unverified dependencies.
  final Map<String, UiFormulaEvaluation> evaluations;
}

/// Thin scalar F3b adapter over the fixed F5c port and real F3a evaluator.
///
/// Construct per accepted base plan, using trusted host formula declarations
/// and non-view parameter keys. This initial slice supports the existing
/// minimal/dynamic catalogs. Library-2 specs/collections and live publication
/// remain owner dependencies; unsupported catalogs fail closed.
/// No IO, listener/runtime, authority probe, business mapping or publication.
final class UiFormulaRecomputeAdapter implements UiRecomputePort {
  UiFormulaRecomputeAdapter({
    required this.basePlan,
    required this.registry,
    required Map<String, UiFormulaDefinition> computations,
    required Set<String> parameterStateKeys,
  }) : computations = Map.unmodifiable(computations),
       parameterStateKeys = Set.unmodifiable(parameterStateKeys);

  final ValidatedUiPlan basePlan;
  final UiFormulaRegistry registry;
  final Map<String, UiFormulaDefinition> computations;
  final Set<String> parameterStateKeys;

  @override
  Future<UiRecomputeResult> rebuild(UiRecomputeInput input) async =>
      prepare(input).result;

  UiPreparedFormulaRecompute prepare(UiRecomputeInput input) {
    final evidence = <String, UiFormulaEvaluation>{};
    UiPreparedFormulaRecompute reject(List<String> errors) =>
        UiPreparedFormulaRecompute._(
          result: UiRecomputeResult(token: input.token, errors: errors),
          evaluations: evidence,
        );
    final previous = input.previousSnapshot;
    if (!identical(previous, basePlan.snapshot)) {
      return reject(['recompute_snapshot_mismatch']);
    }
    if (input.token.baseSnapshotRef != previous.ref) {
      return reject(['recompute_token_snapshot_mismatch']);
    }
    if (basePlan.catalog.version != 'minimal-1' &&
        basePlan.catalog.version != 'dynamic-1') {
      return reject(['recompute_catalog_unavailable']);
    }

    final nextRef = SnapshotRef(previous.ref.id, previous.ref.revision + 1);
    // Extracted values remain in the snapshot; accepted manual values are
    // passed separately as the complete frozen projection to evaluate.
    final inputs = DataSnapshot(
      ref: nextRef,
      facts: previous.facts,
      initialUiState: previous.initialUiState,
      sources: previous.sources,
      sourceDigests: previous.sourceDigests,
    );
    final displayed = <String>{
      for (final node in basePlan.plan.nodes)
        for (final binding in node.bindings.values)
          if (binding.kind == BindingKind.computed) binding.id,
    };
    final computed = <String, ComputedValue>{};
    for (final id in displayed.toList()..sort()) {
      final definition = computations[id];
      final prior = previous.computations[id];
      if (definition == null ||
          prior == null ||
          definition.computationId != prior.computationId) {
        return reject(['recompute_computation_unregistered:$id']);
      }
      for (final slot in definition.slots.values) {
        final binding = slot.binding;
        if (binding.kind != BindingKind.uiState) continue;
        if (!parameterStateKeys.contains(binding.id)) {
          return reject(['formula_view_or_undeclared_parameter:${binding.id}']);
        }
        if (input.currentUiState[binding.id] is! String) {
          return reject(['formula_state_not_string:${binding.id}']);
        }
      }
      final evaluation = registry.evaluate(
        UiFormulaInvocation.forDefinition(definition, nextRef),
        inputs,
        input.currentUiState,
      );
      evidence[id] = evaluation;
      if (evaluation.status != UiFormulaStatus.ready &&
          evaluation.status != UiFormulaStatus.unavailable) {
        return reject([
          for (final error in evaluation.errors) '$id:$error',
          if (evaluation.errors.isEmpty) '$id:formula_${evaluation.status.name}',
        ]);
      }
      computed[id] = ComputedValue(
        value: evaluation.value,
        inputVersion: evaluation.inputVersion,
        computationId: evaluation.computationId,
      );
    }

    final next = inputs.copyWith(computations: computed);
    // No production quantity business mapping exists in this slice. Do not
    // carry old draft/operation capabilities into a recomputed candidate.
    final allowed = basePlan.intent.allowedActionRefs.where(
      (ref) => basePlan.catalog.actions[ref]?.route != UiActionRoute.business,
    );
    final intent = InteractionIntent(
      id: basePlan.intent.id,
      purpose: basePlan.intent.purpose,
      snapshotRef: nextRef,
      requiredBindings: basePlan.intent.requiredBindings,
      mandatoryStates: basePlan.intent.mandatoryStates,
      allowedActionRefs: allowed.toSet(),
    );
    final plan = basePlan.plan.copyWith(
      revision: basePlan.plan.revision + 1,
      snapshotRef: nextRef,
      intentRef: intent.id,
      nodes: [
        for (final node in basePlan.plan.nodes)
          node.copyWith(
            events: {
              for (final event in node.events.entries)
                if (basePlan.catalog.actions[event.value.actionRef]?.route !=
                    UiActionRoute.business)
                  event.key: event.value,
            },
          ),
      ],
    );
    final validation = validateUiPlan(plan, next, intent, basePlan.catalog);
    if (!validation.isValid) return reject(validation.errors);
    final result = UiRecomputeResult(
      token: input.token,
      nextSnapshot: next,
      nextIntent: intent,
    );
    return UiPreparedFormulaRecompute._(
      result: result,
      batch: UiVersionBatch(
        token: input.token,
        snapshot: next,
        intent: intent,
        plan: plan,
      ),
      evaluations: evidence,
    );
  }
}
