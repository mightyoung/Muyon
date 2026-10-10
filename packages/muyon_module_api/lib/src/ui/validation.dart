import 'snapshot.dart';
import 'intent.dart';
import 'plan.dart';

/// Only this validator can construct the renderer's capability.
class ValidatedUiPlan {
  ValidatedUiPlan._(
    this.plan,
    this.snapshot,
    this.intent,
    this.catalog, [
    Map<String, String> patches = const {},
  ]) : appliedPatches = Map.unmodifiable(patches);
  final UIPlan plan;
  final DataSnapshot snapshot;
  final UiCatalog catalog;
  final InteractionIntent intent;
  final Map<String, String> appliedPatches;
}

class UiValidationResult {
  UiValidationResult._(List<String> errors, this.validatedPlan)
    : errors = List.unmodifiable(errors);
  factory UiValidationResult.rejected(List<String> errors) =>
      UiValidationResult._(errors, null);
  factory UiValidationResult.unchanged(ValidatedUiPlan current) =>
      UiValidationResult._([], current);
  UiValidationResult recordPatch(String id, String fingerprint) {
    final checked = validatedPlan;
    if (checked == null) return this;
    return UiValidationResult._(
      [],
      ValidatedUiPlan._(
        checked.plan,
        checked.snapshot,
        checked.intent,
        checked.catalog,
        {...checked.appliedPatches, id: fingerprint},
      ),
    );
  }

  final List<String> errors;
  final ValidatedUiPlan? validatedPlan;
  bool get isValid => errors.isEmpty;
}

bool matchesUiValue(UiValueType type, Object? value) => switch (type) {
  UiValueType.string => value is String,
  UiValueType.integer => value is int,
  UiValueType.boolean => value is bool,
  UiValueType.number => value is num && value.isFinite,
  UiValueType.stringList => value is List && value.every((e) => e is String),
};
bool isUiScalar(Object? value) =>
    value == null ||
    value is String ||
    value is bool ||
    (value is num && value.isFinite);

UiValidationResult validateUiPlan(
  UIPlan plan,
  DataSnapshot snapshot,
  InteractionIntent intent,
  UiCatalog catalog,
) {
  final errors = <String>[];
  void reject(String reason) => errors.add(reason);
  if (plan.surfaceId.isEmpty || plan.revision < 0) reject('invalid_surface');
  if (plan.snapshotRef != snapshot.ref || intent.snapshotRef != snapshot.ref)
    reject('snapshot_revision');
  if (plan.catalogVersion != catalog.version) reject('catalog_version');
  if (plan.intentRef != intent.id) reject('intent_reference');
  if (plan.nodes.isEmpty || plan.nodes.length > 200) reject('node_limit');
  final nodes = <String, UiNode>{};
  for (final node in plan.nodes) {
    if (node.id.isEmpty || nodes.containsKey(node.id))
      reject('duplicate_node:${node.id}');
    nodes[node.id] = node;
  }
  final visited = <String>{}, active = <String>{};
  void visit(String id) {
    final node = nodes[id];
    if (node == null) {
      reject('missing_child:$id');
      return;
    }
    if (active.contains(id)) {
      reject('cycle:$id');
      return;
    }
    if (!visited.add(id)) {
      reject('multiple_parents:$id');
      return;
    }
    active.add(id);
    for (final child in node.children) {
      visit(child);
    }
    active.remove(id);
  }

  if (plan.nodes.length <= 200) visit(plan.root);
  if (visited.length != nodes.length) reject('unreachable_nodes');
  final shown = <BindingRef>{};
  for (final node in plan.nodes) {
    if (catalog.components.containsKey(node.component)) {
      shown.addAll(node.bindings.values);
    }
    errors.addAll(validateUiNode(node, snapshot, intent, catalog));
  }

  for (final required in intent.requiredBindings) {
    if (!shown.contains(required)) reject('required_binding:${required.id}');
  }
  for (final fact in snapshot.facts.entries) {
    if (intent.mandatoryStates.contains(fact.value.state) &&
        !shown.contains(BindingRef.fact(fact.key)))
      reject('mandatory_state:${fact.key}');
  }
  return UiValidationResult._(
    errors,
    errors.isEmpty ? ValidatedUiPlan._(plan, snapshot, intent, catalog) : null,
  );
}

/// Shared component, binding and event rules; tree/intent coverage is plan-level.
List<String> validateUiNode(
  UiNode node,
  DataSnapshot snapshot,
  InteractionIntent intent,
  UiCatalog catalog,
) {
  final errors = <String>[];
  void reject(String reason) => errors.add(reason);
  final schema = catalog.components[node.component];
  if (schema == null) {
    reject('unknown_component:${node.component}');
    return errors;
  }
  if (!schema.allowsChildren && node.children.isNotEmpty)
    reject('children:${node.id}');
  for (final required in schema.requiredProperties) {
    if (!node.properties.containsKey(required))
      reject('missing_property:${node.id}:$required');
  }
  for (final entry in node.properties.entries) {
    final type = schema.properties[entry.key];
    if (type == null || !matchesUiValue(type, entry.value))
      reject('property_type:${node.id}:${entry.key}');
  }
  for (final required in schema.requiredBindings) {
    if (!node.bindings.containsKey(required))
      reject('missing_binding:${node.id}:$required');
  }
  for (final entry in node.bindings.entries) {
    final ref = entry.value;
    if (!(schema.bindings[entry.key]?.contains(ref.kind) ?? false))
      reject('binding_kind:${node.id}:${entry.key}');
    switch (ref.kind) {
      case BindingKind.fact:
        final fact = snapshot.facts[ref.id];
        if (fact == null || !isUiScalar(fact.value))
          reject('unknown_fact:${ref.id}');
        if (fact != null &&
            (fact.object.moduleId.isEmpty ||
                fact.object.objectType.isEmpty ||
                fact.object.objectId.isEmpty ||
                fact.field.isEmpty))
          reject('fact_identity:${ref.id}');
        for (final source in fact?.sourceRefs ?? <String>[]) {
          if (!snapshot.sources.containsKey(source))
            reject('fact_source:${ref.id}:$source');
        }
      case BindingKind.uiState:
        if (!snapshot.initialUiState.containsKey(ref.id) ||
            !isUiScalar(snapshot.initialUiState[ref.id]))
          reject('unknown_state:${ref.id}');
      case BindingKind.computed:
        final value = snapshot.computations[ref.id];
        if (value == null ||
            value.computationId.isEmpty ||
            value.inputVersion != snapshot.ref ||
            !isUiScalar(value.value))
          reject('unknown_or_stale_computation:${ref.id}');
      case BindingKind.collection:
        // No host collection registry yet (slice 1b): never valid.
        reject('unknown_collection:${ref.id}');
      case BindingKind.sourceSpan:
        final source = snapshot.sources[ref.id];
        if (source == null ||
            source.artifact.moduleId.isEmpty ||
            source.artifact.artifactId.isEmpty ||
            source.artifact.contentDigest.isEmpty ||
            snapshot.sourceDigests[source.artifact.artifactId] !=
                source.artifact.contentDigest ||
            source.start < 0 ||
            source.end <= source.start ||
            source.end > source.originalText.length ||
            (source.page != null && source.page! < 1) ||
            (source.paragraph != null && source.paragraph! < 1))
          reject('unknown_or_stale_source:${ref.id}');
    }
  }
  for (final entry in node.events.entries) {
    final binding = entry.value;
    final action = catalog.actions[binding.actionRef];
    if (!schema.events.containsKey(entry.key) ||
        action == null ||
        !intent.allowedActionRefs.contains(binding.actionRef)) {
      reject('unknown_event_or_action:${node.id}:${entry.key}');
      continue;
    }
    if (!(schema.eventActions[entry.key]?.contains(binding.actionRef) ??
        false)) {
      reject('incompatible_event_action:${node.id}:${entry.key}');
      continue;
    }
    if (action.route == UiActionRoute.local) {
      if (action.localAction == null) reject('local_action_missing');
      if (binding.operationKeyRef != null ||
          binding.expectedDraftRevision != null)
        reject('local_business_reference');
      if ((action.localAction == UiLocalAction.editField ||
              action.localAction == UiLocalAction.sortRows) &&
          (binding.inputRefs.length != 1 ||
              !node.bindings.values.contains(
                BindingRef.uiState(binding.inputRefs.first),
              ) ||
              schema.events[entry.key] != UiValueType.string ||
              snapshot.initialUiState[binding.inputRefs.first] is! String))
        reject('edit_input');
      if (action.localAction == UiLocalAction.sortRows &&
          binding.inputRefs.any(
            (ref) => snapshot.actionContext?.draft.containsKey(ref) ?? false,
          ))
        reject('view_business_input');
      if (action.localAction == UiLocalAction.expandSource &&
          !node.bindings.values.any(
            (ref) => ref.kind == BindingKind.sourceSpan,
          ))
        reject('source_input');
      if (action.localAction == UiLocalAction.openDetail &&
          !node.bindings.containsKey('value'))
        reject('detail_input');
    } else if (action.route == UiActionRoute.business) {
      final context = snapshot.actionContext;
      final operation = context?.operations[binding.operationKeyRef];
      final inputs = binding.inputRefs.toSet();
      if (context == null ||
          operation == null ||
          binding.expectedDraftRevision != context.draftRevision ||
          operation.draftRevision != context.draftRevision ||
          inputs.length != binding.inputRefs.length ||
          inputs.isEmpty ||
          inputs.length != operation.inputRefs.length ||
          !inputs.containsAll(operation.inputRefs) ||
          !inputs.every(
            (ref) =>
                context.draft.containsKey(ref) ||
                context.confirmedRecordRefs.contains(ref),
          ))
        reject('host_operation_reference');
    }
  }
  return List.unmodifiable(errors);
}
