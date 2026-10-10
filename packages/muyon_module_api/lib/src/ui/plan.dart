import 'collection.dart';
import 'snapshot.dart';

enum UiDisplayDecision { textOnly, supplement, replacePresentation }

enum UiActionRoute { local, business, semantic }

enum UiLocalAction {
  editField,
  expandSource,
  openDetail,
  back,
  cancelConfirmation,
  sortRows,
  openRow,
}

/// `number` and `stringList` are event payload types only (never properties).
enum UiValueType { string, integer, boolean, number, stringList }

/// `number`/`stringList` may not ride in model-writable properties. A runtime
/// throw, not an assert, so release builds cannot bypass it.
Map<String, UiValueType> _propertiesOnly(Map<String, UiValueType> properties) {
  for (final e in properties.entries) {
    if (e.value == UiValueType.number || e.value == UiValueType.stringList) {
      throw ArgumentError.value(
        e.value,
        'properties.${e.key}',
        'event_only_type',
      );
    }
  }
  return properties;
}

class UiComponentSchema {
  UiComponentSchema({
    Map<String, UiValueType> properties = const {},
    Set<String> requiredProperties = const {},
    Map<String, Set<BindingKind>> bindings = const {},
    Set<String> requiredBindings = const {},
    Map<String, UiValueType?> events = const {},
    Map<String, Set<String>> eventActions = const {},
    this.allowsChildren = false,
    Map<String, UiCollectionShape> collections = const {},
    Map<String, Set<Object>> allowedValues = const {},
    Set<String> childComponents = const {},
  }) : collections = Map.unmodifiable(collections),
       allowedValues = Map.unmodifiable({
         for (final e in allowedValues.entries)
           e.key: Set<Object>.unmodifiable(e.value),
       }),
       childComponents = Set.unmodifiable(childComponents),
       properties =Map.unmodifiable(_propertiesOnly(properties)),
       requiredProperties = Set.unmodifiable(requiredProperties),
       bindings = Map.unmodifiable({
         for (final e in bindings.entries)
           e.key: Set<BindingKind>.unmodifiable(e.value),
       }),
       requiredBindings = Set.unmodifiable(requiredBindings),
       events = Map.unmodifiable(events),
       eventActions = Map.unmodifiable({
         for (final e in eventActions.entries)
           e.key: Set<String>.unmodifiable(e.value),
       });
  final Map<String, UiValueType> properties;
  final Set<String> requiredProperties, requiredBindings;
  final Map<String, Set<BindingKind>> bindings;
  final Map<String, UiValueType?> events;

  /// Action references implemented for each component event; absent means none.
  final Map<String, Set<String>> eventActions;
  final bool allowsChildren;

  /// NOT READY (slice 1c scaffold): metadata only, not consulted by validation.
  final Map<String, UiCollectionShape> collections;
  final Map<String, Set<Object>> allowedValues;
  final Set<String> childComponents;
}

class UiActionDefinition {
  const UiActionDefinition({required this.route, this.localAction});
  final UiActionRoute route;
  final UiLocalAction? localAction;
}

class UiCatalog {
  UiCatalog({
    required this.version,
    required Map<String, UiComponentSchema> components,
    required Map<String, UiActionDefinition> actions,
  }) : components = Map.unmodifiable(components),
       actions = Map.unmodifiable(actions);
  final String version;
  final Map<String, UiComponentSchema> components;
  final Map<String, UiActionDefinition> actions;
}

class ActionBinding {
  ActionBinding({
    required this.actionRef,
    List<String> inputRefs = const [],
    this.expectedDraftRevision,
    this.operationKeyRef,
  }) : inputRefs = List.unmodifiable(inputRefs);
  final String actionRef;
  final List<String> inputRefs;
  final int? expectedDraftRevision;
  final String? operationKeyRef;
}

class UiNode {
  UiNode({
    required this.id,
    required this.component,
    Map<String, Object?> properties = const {},
    Map<String, BindingRef> bindings = const {},
    List<String> children = const [],
    Map<String, ActionBinding> events = const {},
  }) : properties = Map.unmodifiable(properties),
       bindings = Map.unmodifiable(bindings),
       children = List.unmodifiable(children),
       events = Map.unmodifiable(events);
  final String id, component;
  final Map<String, Object?> properties;
  final Map<String, BindingRef> bindings;
  final List<String> children;
  final Map<String, ActionBinding> events;
  UiNode copyWith({
    String? component,
    Map<String, Object?>? properties,
    Map<String, BindingRef>? bindings,
    List<String>? children,
    Map<String, ActionBinding>? events,
  }) => UiNode(
    id: id,
    component: component ?? this.component,
    properties: properties ?? this.properties,
    bindings: bindings ?? this.bindings,
    children: children ?? this.children,
    events: events ?? this.events,
  );
}

class UIPlan {
  UIPlan({
    required this.surfaceId,
    required this.revision,
    required this.catalogVersion,
    required this.snapshotRef,
    required this.intentRef,
    required this.root,
    required List<UiNode> nodes,
  }) : nodes = List.unmodifiable(nodes);
  final String surfaceId, catalogVersion, intentRef, root;
  final int revision;
  final SnapshotRef snapshotRef;
  final List<UiNode> nodes;
  UIPlan copyWith({
    int? revision,
    String? catalogVersion,
    SnapshotRef? snapshotRef,
    String? intentRef,
    List<UiNode>? nodes,
  }) => UIPlan(
    surfaceId: surfaceId,
    revision: revision ?? this.revision,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    snapshotRef: snapshotRef ?? this.snapshotRef,
    intentRef: intentRef ?? this.intentRef,
    root: root,
    nodes: nodes ?? this.nodes,
  );
}

class UiPlanningResult {
  const UiPlanningResult({
    required this.decision,
    required this.reasonCode,
    this.plan,
  });
  final UiDisplayDecision decision;
  final String reasonCode;
  final UIPlan? plan;
  List<String> get errors => [
    if (reasonCode.isEmpty) 'missing_reason',
    if ((decision == UiDisplayDecision.textOnly) != (plan == null))
      'decision_plan_mismatch',
  ];
}

class UiEvent {
  const UiEvent({
    required this.eventId,
    required this.surfaceId,
    required this.nodeId,
    required this.observedRevision,
    required this.kind,
    this.payload,
  });
  final String eventId, surfaceId, nodeId, kind;
  final int observedRevision;
  final Object? payload;
}
