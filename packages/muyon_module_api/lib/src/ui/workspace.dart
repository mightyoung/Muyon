import 'plan.dart';
import 'edit_spec.dart';
import 'collection.dart';
import 'snapshot.dart';
import 'validation.dart';

/// Projection storage only. Saving is a compare-and-swap against the last
/// durable revision (0 means absent). It never grants or executes an action.
abstract interface class UiWorkspaceStore {
  Future<StoredUiWorkspace?> load(String surfaceId);
  Future<bool> save(StoredUiWorkspace value, {required int expectedRevision});
}

/// Decode failure retains the original checkpoint instead of treating it as absent.
class UiWorkspaceUnreadable implements Exception {
  const UiWorkspaceUnreadable(this.reason, this.rawJson);
  final String reason, rawJson;
  @override
  String toString() => 'UiWorkspaceUnreadable: $reason';
}

abstract final class UiWorkspaceLimits {
  static const bytes = 256 * 1024;
}

/// No object bodies, credentials, approvals or receipt results live here.
/// Old fields stay readable even if their current node no longer exists.
class StoredUiWorkspace {
  StoredUiWorkspace({
    required this.taskId,
    required this.surfaceId,
    required this.scopeKey,
    required this.revision,
    required this.schemaVersion,
    required this.catalogVersion,
    required this.snapshotRef,
    required this.intentRef,
    required this.planRevision,
    required this.draftRevision,
    required Map<String, Object?> extracted,
    required Map<String, Object?> userOverrides,
    required List<String> nodeIds,
    this.step = '',
    List<String> selectedRecords = const [],
    this.returnAnchor,
    this.scrollOffset = 0,
    List<String> expandedSources = const [],
    this.detailNode,
    List<String> cancelledNodes = const [],
    List<String> operationRefs = const [],
    this.presentation,
    Map<String, String> patchHistory = const {},
    Map<String, Object?> viewValues = const {},
    Map<String, List<String>> selections = const {},
    List<String> selectionOverrides = const [],
    Map<String, List<String>> viewSelections = const {},
    Map<String, Object?> readableDraft = const {},
  }) : selections = _ids(selections),
       selectionOverrides = List.unmodifiable(selectionOverrides),
       viewSelections = _ids(viewSelections),
       readableDraft = _draftValues(readableDraft),
       viewValues = _scalars(viewValues),
       extracted = _scalars(extracted),
       userOverrides = _scalars(userOverrides),
       nodeIds = List.unmodifiable(nodeIds),
       selectedRecords = List.unmodifiable(selectedRecords),
       expandedSources = List.unmodifiable(expandedSources),
       cancelledNodes = List.unmodifiable(cancelledNodes),
       operationRefs = List.unmodifiable(operationRefs),
       patchHistory = Map.unmodifiable(patchHistory) {
    if ((catalogVersion == 'library-2' && schemaVersion != 2) ||
        (schemaVersion != 2 &&
            (selections.isNotEmpty ||
                selectionOverrides.isNotEmpty ||
                viewSelections.isNotEmpty)) ||
        selectionOverrides.toSet().length != selectionOverrides.length ||
        selectionOverrides.any((key) => !selections.containsKey(key)) ||
        viewSelections.keys.any((key) => !selections.containsKey(key))) {
      throw ArgumentError('workspace_selection_schema');
    }
    if ([
          taskId,
          surfaceId,
          scopeKey,
          catalogVersion,
          intentRef,
          snapshotRef.id,
        ].any((v) => v.isEmpty) ||
        revision < 1 ||
        schemaVersion < 1 ||
        planRevision < 0 ||
        draftRevision < 0 ||
        snapshotRef.revision < 0 ||
        !scrollOffset.isFinite ||
        scrollOffset < 0 ||
        nodeIds.toSet().length != nodeIds.length) {
      throw ArgumentError('Invalid workspace projection');
    }
  }
  static Map<String, Object?> _scalars(Map<String, Object?> input) {
    if (input.entries.any((e) => e.key.isEmpty || !isUiScalar(e.value))) {
      throw ArgumentError('Workspace fields must be named UI scalars');
    }
    return Map.unmodifiable(input);
  }

  static Map<String, List<String>> _ids(Map<String, List<String>> input) {
    if (input.entries.any(
      (e) =>
          e.key.isEmpty ||
          e.value.length > UiCollectionLimits.rows ||
          e.value.any((id) => id.isEmpty) ||
          e.value.toSet().length != e.value.length,
    )) {
      throw ArgumentError('workspace_selection_shape');
    }
    return Map.unmodifiable({
      for (final e in input.entries) e.key: UiItemIdsEdit.normalize(e.value),
    });
  }

  static Map<String, Object?> _draftValues(Map<String, Object?> input) {
    if (input.entries.any(
      (e) =>
          e.key.isEmpty ||
          !(isUiScalar(e.value) ||
              (e.value is List &&
                  (e.value as List).every((id) => id is String))),
    )) {
      throw ArgumentError('workspace_readable_shape');
    }
    return Map.unmodifiable({
      for (final e in input.entries)
        e.key: e.value is List
            ? List<String>.unmodifiable((e.value as List).cast<String>())
            : e.value,
    });
  }

  final Map<String, List<String>> selections, viewSelections;
  final List<String> selectionOverrides;
  final Map<String, Object?> readableDraft;
  final String taskId, surfaceId, scopeKey, catalogVersion, intentRef, step;
  final int revision, schemaVersion, planRevision, draftRevision;
  final SnapshotRef snapshotRef;
  final Map<String, Object?> extracted, userOverrides, viewValues;
  final List<String> nodeIds,
      selectedRecords,
      expandedSources,
      cancelledNodes,
      operationRefs;
  final String? returnAnchor, detailNode;
  final double scrollOffset;
  final UIPlan? presentation;
  final Map<String, String> patchHistory;
  Map<String, Object?> get displayValues => Map.unmodifiable({
    ...extracted,
    ...userOverrides,
    for (final key in selectionOverrides) key: selections[key],
    ...readableDraft,
  });

  StoredUiWorkspace copyWith({
    int? revision,
    Map<String, Object?>? extracted,
    Map<String, Object?>? userOverrides,
    SnapshotRef? snapshotRef,
    int? draftRevision,
  }) => StoredUiWorkspace(
    taskId: taskId,
    surfaceId: surfaceId,
    scopeKey: scopeKey,
    revision: revision ?? this.revision,
    schemaVersion: schemaVersion,
    catalogVersion: catalogVersion,
    snapshotRef: snapshotRef ?? this.snapshotRef,
    intentRef: intentRef,
    planRevision: planRevision,
    draftRevision: draftRevision ?? this.draftRevision,
    extracted: extracted ?? this.extracted,
    userOverrides: userOverrides ?? this.userOverrides,
    nodeIds: nodeIds,
    selectedRecords: selectedRecords,
    returnAnchor: returnAnchor,
    scrollOffset: scrollOffset,
    step: step,
    expandedSources: expandedSources,
    detailNode: detailNode,
    cancelledNodes: cancelledNodes,
    operationRefs: operationRefs,
    presentation: presentation,
    patchHistory: patchHistory,
    viewValues: viewValues,
    selections: selections,
    selectionOverrides: selectionOverrides,
    viewSelections: viewSelections,
    readableDraft: readableDraft,
  );
  StoredUiWorkspace refreshExtraction(
    Map<String, Object?> values,
    SnapshotRef ref,
  ) => copyWith(extracted: values, snapshotRef: ref);
  StoredUiWorkspace adoptExtracted(String key) => copyWith(
    userOverrides: {...userOverrides}..remove(key),
    draftRevision: draftRevision + (userOverrides.containsKey(key) ? 1 : 0),
  );

  Map<String, Object?> toJson() => {
    'taskId': taskId,
    'surfaceId': surfaceId,
    'scopeKey': scopeKey,
    'revision': revision,
    'schemaVersion': schemaVersion,
    'catalogVersion': catalogVersion,
    'snapshotId': snapshotRef.id,
    'snapshotRevision': snapshotRef.revision,
    'intentRef': intentRef,
    'planRevision': planRevision,
    'draftRevision': draftRevision,
    'extracted': extracted,
    'userOverrides': userOverrides,
    'nodeIds': nodeIds,
    'step': step,
    'selectedRecords': selectedRecords,
    'returnAnchor': returnAnchor,
    'scrollOffset': scrollOffset,
    'expandedSources': expandedSources,
    'detailNode': detailNode,
    'cancelledNodes': cancelledNodes,
    'operationRefs': operationRefs,
    'presentation': presentation == null
        ? null
        : encodeUiPresentation(presentation!),
    'patchHistory': patchHistory,
    'viewValues': viewValues,
    if (schemaVersion == 2) ...{
      'selections': selections,
      'selectionOverrides': selectionOverrides,
      'viewSelections': viewSelections,
      'readableDraft': readableDraft,
    },
  };
  factory StoredUiWorkspace.fromJson(Map<String, dynamic> j) =>
      StoredUiWorkspace(
        taskId: j['taskId'] as String,
        surfaceId: j['surfaceId'] as String,
        scopeKey: j['scopeKey'] as String,
        revision: j['revision'] as int,
        schemaVersion: j['schemaVersion'] as int,
        catalogVersion: j['catalogVersion'] as String,
        snapshotRef: SnapshotRef(
          j['snapshotId'] as String,
          j['snapshotRevision'] as int,
        ),
        intentRef: j['intentRef'] as String,
        planRevision: j['planRevision'] as int,
        draftRevision: j['draftRevision'] as int,
        extracted: Map<String, Object?>.from(j['extracted'] as Map),
        userOverrides: Map<String, Object?>.from(j['userOverrides'] as Map),
        nodeIds: List<String>.from(j['nodeIds'] as List),
        step: j['step'] as String,
        selectedRecords: List<String>.from(j['selectedRecords'] as List),
        returnAnchor: j['returnAnchor'] as String?,
        scrollOffset: (j['scrollOffset'] as num).toDouble(),
        expandedSources: List<String>.from(j['expandedSources'] as List? ?? []),
        detailNode: j['detailNode'] as String?,
        cancelledNodes: List<String>.from(j['cancelledNodes'] as List? ?? []),
        operationRefs: List<String>.from(j['operationRefs'] as List? ?? []),
        presentation: j['presentation'] == null
            ? null
            : decodeUiPresentation(
                Map<String, dynamic>.from(j['presentation'] as Map),
                schemaVersion: j['schemaVersion'] as int,
              ),
        patchHistory: Map<String, String>.from(j['patchHistory'] as Map? ?? {}),
        viewValues: Map<String, Object?>.from(j['viewValues'] as Map? ?? {}),
        selections: {
          for (final e in (j['selections'] as Map? ?? {}).entries)
            e.key as String: List<String>.from(e.value as List),
        },
        selectionOverrides: List<String>.from(
          j['selectionOverrides'] as List? ?? [],
        ),
        viewSelections: {
          for (final e in (j['viewSelections'] as Map? ?? {}).entries)
            e.key as String: List<String>.from(e.value as List),
        },
        readableDraft: Map<String, Object?>.from(
          j['readableDraft'] as Map? ?? {},
        ),
      );
}

/// A stored plan is data, never a ValidatedUiPlan. It must pass the current
/// validator against host-supplied snapshot, intent and catalog before use.
Map<String, Object?> encodeUiPresentation(UIPlan p) => {
  'surfaceId': p.surfaceId,
  'revision': p.revision,
  'catalogVersion': p.catalogVersion,
  'snapshotId': p.snapshotRef.id,
  'snapshotRevision': p.snapshotRef.revision,
  'intentRef': p.intentRef,
  'root': p.root,
  'nodes': [
    for (final n in p.nodes)
      {
        'id': n.id,
        'component': n.component,
        'properties': n.properties,
        'children': n.children,
        'bindings': {
          for (final e in n.bindings.entries)
            e.key: {'kind': e.value.kind.name, 'id': e.value.id},
        },
        'events': {
          for (final e in n.events.entries)
            e.key: {
              'actionRef': e.value.actionRef,
              'inputRefs': e.value.inputRefs,
              'expectedDraftRevision': e.value.expectedDraftRevision,
              'operationKeyRef': e.value.operationKeyRef,
            },
        },
      },
  ],
};
UIPlan decodeUiPresentation(Map<String, dynamic> j, {int schemaVersion = 1}) =>
    UIPlan(
      surfaceId: j['surfaceId'] as String,
      revision: j['revision'] as int,
      catalogVersion: j['catalogVersion'] as String,
      snapshotRef: SnapshotRef(
        j['snapshotId'] as String,
        j['snapshotRevision'] as int,
      ),
      intentRef: j['intentRef'] as String,
      root: j['root'] as String,
      nodes: [
        for (final raw in j['nodes'] as List)
          (() {
            final n = Map<String, dynamic>.from(raw as Map);
            return UiNode(
              id: n['id'] as String,
              component: n['component'] as String,
              properties: Map<String, Object?>.from(n['properties'] as Map),
              children: List<String>.from(n['children'] as List),
              bindings: {
                for (final e in (n['bindings'] as Map).entries)
                  e.key as String: BindingRef(
                    // Only explicit library-2/schema2 checkpoints carry collection refs.
                    e.value['kind'] == 'collection' &&
                            (schemaVersion != 2 ||
                                j['catalogVersion'] != 'library-2')
                        ? throw ArgumentError.value(e.value['kind'], 'kind')
                        : BindingKind.values.byName(e.value['kind'] as String),
                    e.value['id'] as String,
                  ),
              },
              events: {
                for (final e in (n['events'] as Map).entries)
                  e.key as String: ActionBinding(
                    actionRef: e.value['actionRef'] as String,
                    inputRefs: List<String>.from(e.value['inputRefs'] as List),
                    expectedDraftRevision:
                        e.value['expectedDraftRevision'] as int?,
                    operationKeyRef: e.value['operationKeyRef'] as String?,
                  ),
              },
            );
          })(),
      ],
    );
