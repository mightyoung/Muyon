import 'dart:convert';
import 'dart:math';

import '../references.dart';
import '../tool_status.dart';
import 'guides.dart';
import 'intent.dart';
import 'plan.dart';
import 'snapshot.dart';

/// Model-only aliases. Full pinned references stay inside this host-owned map.
/// Handles are not a query permission: callers still run their normal scope,
/// current-pin and approval checks after resolving the original reference.
class ModelReferenceMap {
  ModelReferenceMap({
    required this.taskId,
    required this.scopeKey,
    required this.snapshotKey,
    required Set<ObjectRef> objects,
    List<ArtifactRef> artifacts = const [],
    this.isCurrent,
  }) : _allowedObjects = Set.unmodifiable(objects),
       _allowedArtifacts = {
         for (final ref in artifacts) _artifactKey(ref): ref,
       };
  final String taskId, scopeKey, snapshotKey;
  final bool Function()? isCurrent;
  final Set<ObjectRef> _allowedObjects;
  final Map<String, ArtifactRef> _allowedArtifacts;
  final _random = Random.secure();
  final _objectTokens = <ObjectRef, String>{};
  final _objects = <String, ObjectRef>{};
  final _artifactTokens = <String, String>{};
  final _artifacts = <String, ArtifactRef>{};
  final _snapshotTokens = <String, String>{};
  String projectSnapshot(SnapshotRef snapshot) {
    _requireCurrent();
    return _snapshotTokens.putIfAbsent(
      jsonEncode([snapshot.id, snapshot.revision]),
      _token,
    );
  }

  bool _active = true;
  void expire() => _active = false;
  bool get _current {
    try {
      return _active && (isCurrent?.call() ?? true);
    } catch (_) {
      return false;
    }
  }

  static String _artifactKey(ArtifactRef ref) =>
      jsonEncode([ref.moduleId, ref.artifactId, ref.contentDigest]);
  String _token() =>
      'mr1_${base64Url.encode(List.generate(32, (_) => _random.nextInt(256))).replaceAll('=', '')}';
  void _requireCurrent() {
    if (!_current) throw StateError('model_reference_unavailable');
  }

  Map<String, Object?> projectObject(ObjectRef ref) {
    _requireCurrent();
    final original = _allowedObjects.lookup(ref);
    if (original == null) {
      throw StateError('model_reference_unavailable');
    }
    final token = _objectTokens.putIfAbsent(ref, () {
      final token = _token();
      _objects[token] = original;
      return token;
    });
    return {
      'modelRef': token,
      'moduleId': ref.moduleId,
      'objectType': ref.objectType,
      'objectId': ref.objectId,
      'nativeProjectId': ref.nativeProjectId,
      'revisionRef': ref.revisionRef,
    };
  }

  Map<String, Object?> projectArtifact(ArtifactRef ref) {
    _requireCurrent();
    final key = _artifactKey(ref);
    if (!_allowedArtifacts.containsKey(key)) {
      throw StateError('model_reference_unavailable');
    }
    final token = _artifactTokens.putIfAbsent(key, () {
      final token = _token();
      _artifacts[token] = _allowedArtifacts[key]!;
      return token;
    });
    return {
      'modelRef': token,
      'moduleId': ref.moduleId,
      'artifactId': ref.artifactId,
    };
  }

  bool _matches(String task, String scope, String snapshot) =>
      _current &&
      task == taskId &&
      scope == scopeKey &&
      snapshot == snapshotKey;
  ObjectRef? resolveObject(
    String token, {
    required String taskId,
    required String scopeKey,
    required String snapshotKey,
    Map<String, Object?> locators = const {},
  }) {
    if (!_matches(taskId, scopeKey, snapshotKey)) return null;
    final ref = _objects[token];
    if (ref == null) return null;
    final public = projectObject(ref);
    if (locators.entries.any(
      (e) => !public.containsKey(e.key) || public[e.key] != e.value,
    )) {
      return null;
    }
    return ref;
  }

  ArtifactRef? resolveArtifact(
    String token, {
    required String taskId,
    required String scopeKey,
    required String snapshotKey,
    Map<String, Object?> locators = const {},
  }) {
    if (!_matches(taskId, scopeKey, snapshotKey)) return null;
    final ref = _artifacts[token];
    if (ref == null) return null;
    final public = projectArtifact(ref);
    if (locators.entries.any(
      (e) => !public.containsKey(e.key) || public[e.key] != e.value,
    )) {
      return null;
    }
    return ref;
  }

  /// Structured host-owned model frames only. User prose is not reparsed.
  Object? projectJson(Object? value) {
    _requireCurrent();
    if (value is List) return [for (final item in value) projectJson(item)];
    if (value is! Map) return value;
    final map = Map<String, Object?>.from(value);
    if (map.containsKey('contentDigest')) {
      if (map['moduleId'] is String &&
          map['objectType'] is String &&
          map['objectId'] is String) {
        return projectObject(
          ObjectRef(
            moduleId: map['moduleId'] as String,
            objectType: map['objectType'] as String,
            objectId: map['objectId'] as String,
            nativeProjectId: map['nativeProjectId'] as String?,
            revisionRef: map['revisionRef'] as String?,
            contentDigest: map['contentDigest'] as String?,
          ),
        );
      }
      if (map['moduleId'] is String &&
          map['artifactId'] is String &&
          map['contentDigest'] is String) {
        return projectArtifact(
          ArtifactRef(
            moduleId: map['moduleId'] as String,
            artifactId: map['artifactId'] as String,
            contentDigest: map['contentDigest'] as String,
          ),
        );
      }
      throw StateError('model_reference_unavailable');
    }
    return {
      for (final entry in map.entries) entry.key: projectJson(entry.value),
    };
  }
}

enum UiPlanningMode { intelligent, motivation }

class UiCurrentView {
  UiCurrentView({
    required this.surfaceId,
    required this.revision,
    Map<String, Object?> values = const {},
  }) : values = Map.unmodifiable(values);
  final String surfaceId;
  final int revision;
  final Map<String, Object?> values;
}

/// Created by the host from its records/current owners, never tool arguments.
class UiPlanningRequest {
  UiPlanningRequest({
    required this.question,
    required this.answer,
    required List<Map<String, Object?>> conversationMessages,
    required this.conversationVersion,
    required this.coverage,
    required this.taskId,
    required this.turnId,
    required this.snapshot,
    required this.intent,
    required this.currentView,
    required this.catalog,
    required Set<String> allowedActionRefs,
    required this.mode,
    List<UiGuideEntry> guideEntries = const [],
    Set<String> modelDisclosedFactRefs = const {},
    Set<String> modelDisclosedComputedRefs = const {},
    Set<String> modelDisclosedUiStateRefs = const {},
    Set<int> modelDisclosedToolMessageIndices = const {},
    this.modelReferences,
    this.modelReferenceScopeKey,
    this.modelReferenceSnapshotKey,
    this.isModelReferenceCurrent,
  }) : conversationMessages = List.unmodifiable(
         conversationMessages.map(Map<String, Object?>.unmodifiable),
       ),
       allowedActionRefs = Set.unmodifiable(allowedActionRefs),
       guideEntries = List.unmodifiable(guideEntries),
       modelDisclosedFactRefs = Set.unmodifiable(modelDisclosedFactRefs),
       modelDisclosedComputedRefs = Set.unmodifiable(
         modelDisclosedComputedRefs,
       ),
       modelDisclosedUiStateRefs = Set.unmodifiable(modelDisclosedUiStateRefs),
       modelDisclosedToolMessageIndices = Set.unmodifiable(
         modelDisclosedToolMessageIndices,
       );
  final String question, answer, conversationVersion, coverage, taskId, turnId;
  final List<Map<String, Object?>> conversationMessages;
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiCurrentView currentView;
  final UiCatalog catalog;
  final Set<String> allowedActionRefs;
  final UiPlanningMode mode;
  final List<UiGuideEntry> guideEntries;

  /// Host-owned disclosure registration, intersected with current permissions
  /// before constructing this request. Fact verification is not permission.
  /// Never populate these sets from model output or UI display preferences.
  final Set<String> modelDisclosedFactRefs;
  final Set<String> modelDisclosedComputedRefs;
  final Set<String> modelDisclosedUiStateRefs;

  /// Host classification of already producer/schema/capability-projected frames.
  /// Body markers and role labels do not register disclosure.
  final Set<int> modelDisclosedToolMessageIndices;
  final ModelReferenceMap? modelReferences;
  final String? modelReferenceScopeKey;
  final String? modelReferenceSnapshotKey;
  final bool Function()? isModelReferenceCurrent;
  late final ModelReferenceMap referenceMap =
      modelReferences ??
      ModelReferenceMap(
        taskId: taskId,
        scopeKey:
            modelReferenceScopeKey ??
            jsonEncode(
              snapshot.facts.values
                  .map((fact) => fact.object.toJson())
                  .toList(),
            ),
        snapshotKey: jsonEncode([snapshot.ref.id, snapshot.ref.revision]),
        objects: snapshot.facts.values.map((fact) => fact.object).toSet(),
        artifacts: snapshot.sources.values
            .map((span) => span.artifact)
            .toList(),
        isCurrent: isModelReferenceCurrent,
      );
  List<Map<String, Object?>> _modelMessages() => [
    for (var i = 0; i < conversationMessages.length; i++)
      if (conversationMessages[i]['role'] == 'user')
        conversationMessages[i]
      else
        Map<String, Object?>.from(
          referenceMap.projectJson({
            ...conversationMessages[i],
            if (conversationMessages[i]['role'] == 'tool')
              'content': _modelToolContent(
                conversationMessages[i]['content'],
                disclosed: modelDisclosedToolMessageIndices.contains(i),
              ),
          }) as Map,
        ),
  ];
  Object? _modelToolContent(Object? content, {required bool disclosed}) {
    Object? decoded;
    try {
      decoded = content is String ? jsonDecode(content) : content;
    } catch (_) {
      throw StateError('model_reference_unavailable');
    }
    if (decoded is! Map && decoded is! List) {
      throw StateError('model_reference_unavailable');
    }
    if (!disclosed) {
      final body = decoded is Map ? decoded : const {};
      final result = body['trustedToolResult'] is Map
          ? body['trustedToolResult'] as Map
          : body;
      decoded = {
        'trustedToolResult': {
          if (ToolCallStatus.values.any(
            (status) => status.name == result['status'],
          ))
            'status': result['status'],
          if (result['executionId'] is String &&
              RegExp(
                r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
              ).hasMatch(result['executionId'] as String))
            'executionId': result['executionId'],
          'disclosure': 'notDisclosed',
          'summary': '未登记模型披露的工具内容已省略',
          'data': <String, Object?>{},
          for (final key in ['objectRefs', 'artifactRefs'])
            key: result[key] is List ? result[key] : const [],
        },
      };
    }
    final projected = referenceMap.projectJson(decoded);
    return content is String ? jsonEncode(projected) : projected;
  }

  String get modelSnapshotId {
    requireCurrentModelReferences();
    return referenceMap.projectSnapshot(snapshot.ref);
  }

  Map<String, dynamic> hostPlanJson(Map<String, dynamic> plan) {
    requireCurrentModelReferences();
    if (plan['snapshotId'] != modelSnapshotId ||
        plan['snapshotRevision'] != snapshot.ref.revision) {
      throw StateError('model_reference_unavailable');
    }
    return {...plan, 'snapshotId': snapshot.ref.id};
  }

  bool _readable(FactState state) =>
      state == FactState.verified || state == FactState.unverified;
  Map<String, Object?> _disclosedUiState(Map<String, Object?> values) => {
    for (final entry in values.entries)
      if (modelDisclosedUiStateRefs.contains(entry.key)) entry.key: entry.value,
  };
  void _checkReferenceContext() {
    if (isModelReferenceCurrent != null) {
      try {
        if (!isModelReferenceCurrent!()) {
          throw StateError('model_reference_unavailable');
        }
      } catch (_) {
        throw StateError('model_reference_unavailable');
      }
    }
    if (modelReferences != null &&
        (referenceMap.taskId != taskId ||
            referenceMap.scopeKey != modelReferenceScopeKey ||
            referenceMap.snapshotKey != modelReferenceSnapshotKey)) {
      throw StateError('model_reference_unavailable');
    }
  }

  void requireCurrentModelReferences() {
    _checkReferenceContext();
    referenceMap._requireCurrent();
  }

  Map<String, Object?> toJson() {
    requireCurrentModelReferences();
    return {
      'question': question,
      'answer': answer,
      'conversationMessages': _modelMessages(),
      'conversationVersion': conversationVersion,
      'coverage': coverage,
      'taskId': taskId,
      'turnId': turnId,
      'mode': mode.name,
      'currentView': {
        'surfaceId': currentView.surfaceId,
        'revision': currentView.revision,
        'values': _disclosedUiState(currentView.values),
      },
      'snapshot': {
        'id': modelSnapshotId,
        'revision': snapshot.ref.revision,
        'facts': {
          for (final e in snapshot.facts.entries)
            e.key: {
              'object': referenceMap.projectObject(e.value.object),
              'field': e.value.field,
              'value':
                  modelDisclosedFactRefs.contains(e.key) &&
                      _readable(e.value.state)
                  ? e.value.value
                  : null,
              'state': e.value.state.name,
              'unit': e.value.unit,
              'sourceRefs': e.value.sourceRefs,
            },
        },
        'initialUiState': _disclosedUiState(snapshot.initialUiState),
        'computations': {
          for (final e in snapshot.computations.entries)
            e.key: {
              'value':
                  modelDisclosedComputedRefs.contains(e.key) &&
                      snapshot.computedEvidence[e.key] != null &&
                      _readable(snapshot.computedEvidence[e.key]!.state) &&
                      e.value.inputVersion == snapshot.ref
                  ? e.value.value
                  : null,
              'snapshotId': e.value.inputVersion == snapshot.ref
                  ? modelSnapshotId
                  : null,
              'snapshotRevision': e.value.inputVersion.revision,
              'computationId': e.value.computationId,
            },
        },
        'sources': {
          for (final e in snapshot.sources.entries)
            e.key: {
              'artifact': referenceMap.projectArtifact(e.value.artifact),
              // Original source text has no per-field disclosure authority.
              // Retain reference/location metadata; rendering still uses the
              // untouched host snapshot, never this model projection.
              'start': e.value.start,
              'end': e.value.end,
              'page': e.value.page,
              'paragraph': e.value.paragraph,
            },
        },
        'sourceDigests': {
          for (final entry in snapshot.sources.entries)
            if (snapshot.sourceDigests[entry.value.artifact.artifactId] ==
                entry.value.artifact.contentDigest)
              entry.value.artifact.artifactId: referenceMap.projectArtifact(
                entry.value.artifact,
              )['modelRef'],
        },
        'actionContext': snapshot.actionContext == null
            ? null
            : {
                'draftRevision': snapshot.actionContext!.draftRevision,
                'draft': _disclosedUiState(snapshot.actionContext!.draft),
                'confirmedRecordRefs': snapshot
                    .actionContext!
                    .confirmedRecordRefs
                    .toList(),
                'operations': {
                  for (final e in snapshot.actionContext!.operations.entries)
                    e.key: {
                      'draftRevision': e.value.draftRevision,
                      'inputRefs': e.value.inputRefs.toList(),
                    },
                },
              },
      },
      'intent': {
        'id': intent.id,
        'purpose': intent.purpose,
        'requiredBindings': [
          for (final b in intent.requiredBindings)
            {'kind': b.kind.name, 'id': b.id},
        ],
        'mandatoryStates': intent.mandatoryStates.map((s) => s.name).toList(),
      },
      'allowedActionRefs': allowedActionRefs.toList(),
      'catalog': {
        'version': catalog.version,
        'components': {
          for (final e in catalog.components.entries)
            e.key: {
              'properties': e.value.properties.map(
                (k, v) => MapEntry(k, v.name),
              ),
              'requiredProperties': e.value.requiredProperties.toList(),
              'bindings': e.value.bindings.map(
                (k, v) => MapEntry(k, v.map((b) => b.name).toList()),
              ),
              'requiredBindings': e.value.requiredBindings.toList(),
              'events': e.value.events.map((k, v) => MapEntry(k, v?.name)),
              'eventActions': e.value.eventActions.map(
                (k, v) => MapEntry(k, v.toList()),
              ),
              'allowsChildren': e.value.allowsChildren,
            },
        },
        'actions': {
          for (final e in catalog.actions.entries)
            if (allowedActionRefs.contains(e.key))
              e.key: {
                'route': e.value.route.name,
                'localAction': e.value.localAction?.name,
              },
        },
      },
      'guideEntries': guideEntries.map((e) => e.toJson()).toList(),
    };
  }
}

abstract interface class UiPlanningPort {
  Future<UiPlanningResult> plan(UiPlanningRequest request);
}

/// Public preview/test provider. No model/network capability is implied.
class FixtureUiPlanningProvider implements UiPlanningPort {
  const FixtureUiPlanningProvider(this.build);
  final Future<UiPlanningResult> Function(UiPlanningRequest) build;
  @override
  Future<UiPlanningResult> plan(UiPlanningRequest request) => build(request);
}
