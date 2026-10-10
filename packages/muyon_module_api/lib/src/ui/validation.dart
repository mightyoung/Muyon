import 'dart:convert';

import 'collection.dart';
import 'edit_spec.dart';
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
  if (plan.snapshotRef != snapshot.ref || intent.snapshotRef != snapshot.ref) {
    reject('snapshot_revision');
  }
  if (plan.catalogVersion != catalog.version) reject('catalog_version');
  if (plan.intentRef != intent.id) reject('intent_reference');
  if (plan.nodes.isEmpty || plan.nodes.length > 200) reject('node_limit');
  final nodes = <String, UiNode>{};
  for (final node in plan.nodes) {
    if (node.id.isEmpty || nodes.containsKey(node.id)) {
      reject('duplicate_node:${node.id}');
    }
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
  for (final node in plan.nodes) {
    final allowed = catalog.components[node.component]?.childComponents;
    if (allowed == null || allowed.isEmpty) continue;
    for (final child in node.children) {
      final component = nodes[child]?.component;
      if (component != null && !allowed.contains(component)) {
        reject('child_component:${node.id}:$child');
      }
    }
  }
  final shown = <BindingRef>{};
  for (final node in plan.nodes) {
    final nodeErrors = validateUiNode(node, snapshot, intent, catalog);
    errors.addAll(nodeErrors);
    if (catalog.components.containsKey(node.component)) {
      shown.addAll(node.bindings.values);
      for (final ref in node.bindings.values) {
        // Only a fully valid collection may vouch for its cells as shown.
        if (nodeErrors.isEmpty &&
            ref.kind == BindingKind.collection &&
            _collectionErrors(snapshot, catalog, ref).isEmpty) {
          shown.addAll(
            snapshot.collections[ref.id]!.rows.expand((r) => r.cells.values),
          );
        }
      }
    }
  }

  for (final required in intent.requiredBindings) {
    if (!shown.contains(required)) reject('required_binding:${required.id}');
  }
  for (final fact in snapshot.facts.entries) {
    if (intent.mandatoryStates.contains(fact.value.state) &&
        !shown.contains(BindingRef.fact(fact.key))) {
      reject('mandatory_state:${fact.key}');
    }
  }
  return UiValidationResult._(
    errors,
    errors.isEmpty ? ValidatedUiPlan._(plan, snapshot, intent, catalog) : null,
  );
}

/// library-2 editField rules: spec metadata, event type, initial value (payload
/// and context) and the view/business-draft separation.
List<String> _typedEditErrors(
  DataSnapshot snapshot,
  String key,
  UiValueType? eventType,
) {
  final spec = snapshot.editSpecs[key] ?? const UiStringEdit();
  final errors = <String>[];
  if (spec.validateSpec() != null) errors.add('edit_spec:$key');
  final isIds = spec is UiItemIdsEdit;
  final present = snapshot.initialUiState.containsKey(key);
  final Object? initial = spec is UiItemIdsEdit
      ? spec.initial
      : snapshot.initialUiState[key];
  if (spec.payloadType != eventType ||
      (isIds ? present : !present) ||
      spec.reject(initial, UiEditContext(collections: snapshot.collections)) !=
          null) {
    errors.add('edit_input');
  }
  if (spec.view && (snapshot.actionContext?.draft.containsKey(key) ?? false)) {
    errors.add('view_business_input');
  }
  return errors;
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
  if (!schema.allowsChildren && node.children.isNotEmpty) {
    reject('children:${node.id}');
  }
  for (final required in schema.requiredProperties) {
    if (!node.properties.containsKey(required)) {
      reject('missing_property:${node.id}:$required');
    }
  }
  for (final entry in node.properties.entries) {
    final type = schema.properties[entry.key];
    if (type == null || !matchesUiValue(type, entry.value)) {
      reject('property_type:${node.id}:${entry.key}');
    } else if (!(schema.allowedValues[entry.key]?.contains(entry.value) ??
        true)) {
      reject('property_value:${node.id}:${entry.key}');
    }
  }
  for (final required in schema.requiredBindings) {
    if (!node.bindings.containsKey(required)) {
      reject('missing_binding:${node.id}:$required');
    }
  }
  for (final entry in node.bindings.entries) {
    final ref = entry.value;
    if (!(schema.bindings[entry.key]?.contains(ref.kind) ?? false)) {
      reject('binding_kind:${node.id}:${entry.key}');
    }
    if (ref.kind != BindingKind.collection) {
      errors.addAll(_bindingErrors(ref, snapshot, catalog));
      continue;
    }
    final collectionErrors = _collectionErrors(snapshot, catalog, ref);
    errors.addAll(collectionErrors);
    final collection = snapshot.collections[ref.id];
    final shape = schema.collections[entry.key];
    if (shape == null) reject('collection:${ref.id}:shape_declaration');
    if (collectionErrors.isEmpty && collection != null && shape != null) {
      if (!shape.accepts(collection)) {
        reject('collection:${collection.id}:shape');
      } else if (shape == UiCollectionShape.series) {
        errors.addAll(
          _seriesErrors(collection, snapshot, node.properties['kind'] == 'pie'),
        );
      }
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
    // All event routes share the view/draft boundary, including a business
    // button whose state key is not displayed or locally editable.
    if (usesTypedEdits(catalog) &&
        binding.inputRefs.any(
          (ref) =>
              (snapshot.editSpecs[ref]?.view ?? false) &&
              (snapshot.actionContext?.draft.containsKey(ref) ?? false),
        )) {
      reject('view_business_input');
    }
    if (action.route == UiActionRoute.local) {
      if (action.localAction == null) reject('local_action_missing');
      if (binding.operationKeyRef != null ||
          binding.expectedDraftRevision != null) {
        reject('local_business_reference');
      }
      final isEdit = action.localAction == UiLocalAction.editField;
      if (isEdit || action.localAction == UiLocalAction.sortRows) {
        if (binding.inputRefs.length != 1 ||
            !node.bindings.values.contains(
              BindingRef.uiState(binding.inputRefs.first),
            )) {
          reject('edit_input');
        } else if (isEdit && usesTypedEdits(catalog)) {
          errors.addAll(
            _typedEditErrors(
              snapshot,
              binding.inputRefs.first,
              schema.events[entry.key],
            ),
          );
        } else if (schema.events[entry.key] != UiValueType.string ||
            snapshot.initialUiState[binding.inputRefs.first] is! String) {
          reject('edit_input');
        } else if (!isEdit &&
            usesTypedEdits(catalog) &&
            snapshot.editSpecs[binding.inputRefs.first] != null) {
          // library-2 sort writes view state: a registered spec must be a
          // view string spec (no draft bypass); unregistered keys keep the
          // legacy sort mapping.
          final spec = snapshot.editSpecs[binding.inputRefs.first]!;
          if (spec is! UiStringEdit || !spec.view) {
            reject('edit_input');
          } else {
            errors.addAll(
              _typedEditErrors(
                snapshot,
                binding.inputRefs.first,
                schema.events[entry.key],
              ),
            );
          }
        }
      }
      if (action.localAction == UiLocalAction.sortRows &&
          binding.inputRefs.any(
            (ref) => snapshot.actionContext?.draft.containsKey(ref) ?? false,
          )) {
        reject('view_business_input');
      }
      if (action.localAction == UiLocalAction.expandSource &&
          !node.bindings.values.any(
            (ref) => ref.kind == BindingKind.sourceSpan,
          )) {
        reject('source_input');
      }
      if (action.localAction == UiLocalAction.openRow &&
          (!usesTypedEdits(catalog) ||
              binding.inputRefs.isNotEmpty ||
              schema.events[entry.key] != UiValueType.string ||
              !node.bindings.values.any(
                (ref) => ref.kind == BindingKind.collection,
              ))) {
        reject('row_input');
      }
      if (action.localAction == UiLocalAction.openDetail &&
          !node.bindings.containsKey('value')) {
        reject('detail_input');
      }
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
          )) {
        reject('host_operation_reference');
      }
    }
  }
  return List.unmodifiable(errors);
}

bool _sourceInvalid(SourceSpanRef? source, DataSnapshot snapshot) =>
    source == null ||
    source.artifact.moduleId.isEmpty ||
    source.artifact.artifactId.isEmpty ||
    source.artifact.contentDigest.isEmpty ||
    snapshot.sourceDigests[source.artifact.artifactId] !=
        source.artifact.contentDigest ||
    source.start < 0 ||
    source.end <= source.start ||
    source.end > source.originalText.length ||
    (source.page != null && source.page! < 1) ||
    (source.paragraph != null && source.paragraph! < 1);

/// Fact / uiState / computed / sourceSpan resolution rules, shared by node
/// bindings and collection cells. Collection refs are handled by the caller.
List<String> _bindingErrors(
  BindingRef ref,
  DataSnapshot snapshot,
  UiCatalog catalog,
) {
  final errors = <String>[];
  final typed = usesTypedEdits(catalog);
  switch (ref.kind) {
    case BindingKind.fact:
      final fact = snapshot.facts[ref.id];
      if (fact == null || !isUiScalar(fact.value)) {
        errors.add('unknown_fact:${ref.id}');
      }
      if (fact != null &&
          (fact.object.moduleId.isEmpty ||
              fact.object.objectType.isEmpty ||
              fact.object.objectId.isEmpty ||
              fact.field.isEmpty)) {
        errors.add('fact_identity:${ref.id}');
      }
      for (final source in fact?.sourceRefs ?? <String>[]) {
        if (!snapshot.sources.containsKey(source)) {
          errors.add('fact_source:${ref.id}:$source');
        } else if (typed &&
            _sourceInvalid(snapshot.sources[source], snapshot)) {
          errors.add('unknown_or_stale_source:$source');
        }
      }
    case BindingKind.uiState:
      final spec = typed
          ? (snapshot.editSpecs[ref.id] ?? const UiStringEdit())
          : null;
      // itemIds selections live outside initialUiState (never scalar).
      final isIds = spec is UiItemIdsEdit;
      if (!isIds &&
          (!snapshot.initialUiState.containsKey(ref.id) ||
              !isUiScalar(snapshot.initialUiState[ref.id]))) {
        errors.add('unknown_state:${ref.id}');
      }
      // Readonly typed bindings are checked too, not only editField ones.
      if (spec != null) {
        if (isIds && snapshot.initialUiState.containsKey(ref.id)) {
          errors.add('edit_input:${ref.id}');
        }
        if (spec.view &&
            (snapshot.actionContext?.draft.containsKey(ref.id) ?? false)) {
          errors.add('view_business_input');
        }
        final context = UiEditContext(collections: snapshot.collections);
        if (spec.validateSpec() != null) {
          errors.add('edit_spec:${ref.id}');
        } else if (isIds
            ? spec.reject(spec.initial, context) != null
            : snapshot.initialUiState.containsKey(ref.id) &&
                  spec.reject(snapshot.initialUiState[ref.id], context) !=
                      null) {
          errors.add('edit_input:${ref.id}');
        }
      }
    case BindingKind.computed:
      final value = snapshot.computations[ref.id];
      if (value == null ||
          value.computationId.isEmpty ||
          value.inputVersion != snapshot.ref ||
          !isUiScalar(value.value)) {
        errors.add('unknown_or_stale_computation:${ref.id}');
      }
      if (typed) {
        final evidence = snapshot.computedEvidence[ref.id];
        if (evidence == null) {
          errors.add('computed_evidence_missing:${ref.id}');
        } else {
          for (final source in evidence.sourceRefs) {
            if (_sourceInvalid(snapshot.sources[source], snapshot)) {
              errors.add('unknown_or_stale_source:$source');
            }
          }
        }
      }
    case BindingKind.collection:
      break;
    case BindingKind.sourceSpan:
      if (_sourceInvalid(snapshot.sources[ref.id], snapshot)) {
        errors.add('unknown_or_stale_source:${ref.id}');
      }
  }
  return errors;
}

const _idMaxBytes = UiCollectionLimits.idBytes,
    _labelMaxBytes = UiCollectionLimits.labelBytes,
    _collectionMetaMaxBytes = UiCollectionLimits.metadataBytes;
int _bytes(String s) => utf8.encode(s).length;

/// UTF-8 size of the structural reference metadata (ids, labels, cell refs,
/// row objects); never fact/computed values. Execution clarification pending
/// parent review.
int _metaBytes(UiCollection c) => _bytes(
  jsonEncode({
    'id': c.id,
    'columns': [
      for (final col in c.columns) {'id': col.id, 'label': col.label},
    ],
    'rows': [
      for (final row in c.rows)
        {
          'itemId': row.itemId,
          'cells': [
            for (final col in c.columns)
              {
                'kind': row.cells[col.id]!.kind.name,
                'id': row.cells[col.id]!.id,
              },
          ],
          if (row.object != null) 'object': row.object!.toJson(),
        },
    ],
  }),
);

/// Whole-collection check: any failure rejects the entire collection.
List<String> _collectionErrors(
  DataSnapshot snapshot,
  UiCatalog catalog,
  BindingRef ref,
) {
  final c = snapshot.collections[ref.id];
  if (c == null || c.id != ref.id) return ['unknown_collection:${ref.id}'];
  // Older catalogs never admit collections, whatever their schemas declare.
  if (!usesTypedEdits(catalog)) return ['collection_catalog:${ref.id}'];
  final errors = <String>[];
  void bad(String code) => errors.add('collection:${c.id}:$code');
  if (c.id.isEmpty || _bytes(c.id) > _idMaxBytes) bad('id');
  if (c.columns.length > UiCollectionLimits.columns) bad('columns');
  if (c.rows.length > UiCollectionLimits.rows) bad('rows');
  final columnIds = <String>{};
  for (final col in c.columns) {
    if (col.id.isEmpty || _bytes(col.id) > _idMaxBytes) bad('column_id');
    if (!columnIds.add(col.id)) bad('duplicate_column');
    if (_bytes(col.label) > _labelMaxBytes) bad('column_label');
  }
  final itemIds = <String>{};
  var wellFormed = true;
  for (final row in c.rows) {
    if (row.itemId.isEmpty || _bytes(row.itemId) > _idMaxBytes) bad('item_id');
    if (!itemIds.add(row.itemId)) bad('duplicate_row');
    if (row.cells.length != columnIds.length ||
        !row.cells.keys.every(columnIds.contains)) {
      bad('cells');
      wellFormed = false;
      continue;
    }
    for (final cell in row.cells.values) {
      if (cell.kind != BindingKind.fact && cell.kind != BindingKind.computed) {
        bad('cell_kind');
        continue;
      }
      for (final e in _bindingErrors(cell, snapshot, catalog)) {
        bad('cell:$e');
      }
    }
    final object = row.object;
    if (object != null &&
        !row.cells.values.any(
          (cell) =>
              cell.kind == BindingKind.fact &&
              snapshot.facts[cell.id]?.object == object,
        )) {
      bad('row_object');
    }
  }
  if (wellFormed && _metaBytes(c) > _collectionMetaMaxBytes) bad('size');
  return errors;
}

final _decimal = RegExp(r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?$');

/// Series `value` column: finite number, canonical decimal string, or a legal
/// gap (null keeps its FactState). Pie additionally rejects negatives.
List<String> _seriesErrors(UiCollection c, DataSnapshot snapshot, bool pie) {
  for (final row in c.rows) {
    final ref = row.cells['value'];
    if (ref == null) continue;
    final Object? v = switch (ref.kind) {
      BindingKind.fact => snapshot.facts[ref.id]?.value,
      BindingKind.computed => snapshot.computations[ref.id]?.value,
      _ => null,
    };
    final valid = switch (v) {
      null => true,
      final num n => n.isFinite && !(pie && n < 0),
      final String s =>
        _decimal.hasMatch(s) &&
            (double.tryParse(s)?.isFinite ?? false) &&
            !(pie && double.parse(s) < 0),
      _ => false,
    };
    if (!valid) return ['collection:${c.id}:series_value:${row.itemId}'];
  }
  return const [];
}
