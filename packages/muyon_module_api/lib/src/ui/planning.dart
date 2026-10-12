import 'dart:convert';
import 'dart:math';

import '../references.dart';
import 'guides.dart';
import 'intent.dart';
import 'plan.dart';
import 'snapshot.dart';

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

/// What the host registered for the model. Registration is necessary, not
/// permission: scope, revision pins, owner authority and field masking still
/// apply. Everything unregistered is withheld; the default registers nothing.
class UiModelDisclosure {
  UiModelDisclosure({
    Set<String> factIds = const {},
    Set<String> computedIds = const {},
    Set<String> stateKeys = const {},
    Set<String> viewKeys = const {},
    this.objectHandle,
    this.snapshotAlias,
  }) : factIds = Set.unmodifiable(factIds),
       computedIds = Set.unmodifiable(computedIds),
       stateKeys = Set.unmodifiable(stateKeys),
       viewKeys = Set.unmodifiable(viewKeys);
  static final none = UiModelDisclosure();

  /// Fact ids whose value may be sent (never when the fact is notDisclosed).
  final Set<String> factIds, computedIds;

  /// initialUiState / currentView keys whose values may be sent.
  final Set<String> stateKeys, viewKeys;

  /// Host-private opaque handle for an object that has a content digest. The
  /// digest itself is never sent.
  final String Function(ObjectRef)? objectHandle;

  /// Model-side alias of the host snapshot id; null keeps the declared id.
  final String? snapshotAlias;
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
    UiModelDisclosure? disclosure,
  }) : disclosure = disclosure ?? UiModelDisclosure.none,
       conversationMessages = List.unmodifiable(
         conversationMessages.map(Map<String, Object?>.unmodifiable),
       ),
       allowedActionRefs = Set.unmodifiable(allowedActionRefs),
       guideEntries = List.unmodifiable(guideEntries);
  final String question, answer, conversationVersion, coverage, taskId, turnId;
  final List<Map<String, Object?>> conversationMessages;
  final DataSnapshot snapshot;
  final InteractionIntent intent;
  final UiCurrentView currentView;
  final UiCatalog catalog;
  final Set<String> allowedActionRefs;
  final UiPlanningMode mode;
  final List<UiGuideEntry> guideEntries;
  final UiModelDisclosure disclosure;

  /// The snapshot id the model sees: the host's alias, else a random one for
  /// this request. The declared id can be derived from row digests, so it is
  /// never sent; the provider maps a returned alias back to [snapshot].
  late final String modelSnapshotId =
      disclosure.snapshotAlias ??
      'ms1_${base64Url.encode(List.generate(24, (_) => Random.secure().nextInt(256))).replaceAll('=', '')}';

  Map<String, Object?> _object(ObjectRef ref) {
    final handle = ref.contentDigest == null
        ? null
        : disclosure.objectHandle?.call(ref);
    return {
      'moduleId': ref.moduleId,
      'objectType': ref.objectType,
      'objectId': ref.objectId,
      'nativeProjectId': ref.nativeProjectId,
      'revisionRef': ref.revisionRef,
      'modelRef': ?handle,
    };
  }

  Object? _gated(Set<String> allowed, String key, Object? value) =>
      allowed.contains(key) ? value : null;

  /// The model-facing form: this is what providers serialize into prompts.
  Map<String, Object?> toJson() => {
    'question': question,
    'answer': answer,
    'conversationMessages': conversationMessages,
    'conversationVersion': conversationVersion,
    'coverage': coverage,
    'taskId': taskId,
    'turnId': turnId,
    'mode': mode.name,
    'currentView': {
      'surfaceId': currentView.surfaceId,
      'revision': currentView.revision,
      'values': {
        for (final e in currentView.values.entries)
          e.key: _gated(disclosure.viewKeys, e.key, e.value),
      },
    },
    'snapshot': {
      'id': modelSnapshotId,
      'revision': snapshot.ref.revision,
      'facts': {
        for (final e in snapshot.facts.entries)
          e.key: {
            'object': _object(e.value.object),
            'field': e.value.field,
            'value':
                e.value.state == FactState.notDisclosed ||
                    !disclosure.factIds.contains(e.key)
                ? null
                : e.value.value,
            'state': e.value.state.name,
            'unit': e.value.unit,
            'sourceRefs': e.value.sourceRefs,
          },
      },
      'initialUiState': {
        for (final e in snapshot.initialUiState.entries)
          e.key: _gated(disclosure.stateKeys, e.key, e.value),
      },
      'computations': {
        for (final e in snapshot.computations.entries)
          e.key: {
            'value': _gated(disclosure.computedIds, e.key, e.value.value),
            'snapshotId': e.value.inputVersion.id == snapshot.ref.id
                ? modelSnapshotId
                : 'ms1_other',
            'snapshotRevision': e.value.inputVersion.revision,
            'computationId': e.value.computationId,
          },
      },
      'sources': {
        for (final e in snapshot.sources.entries)
          e.key: {
            'artifact': {
              'moduleId': e.value.artifact.moduleId,
              'artifactId': e.value.artifact.artifactId,
            },
            'start': e.value.start,
            'end': e.value.end,
            'page': e.value.page,
            'paragraph': e.value.paragraph,
          },
      },
      'sourceDigests': snapshot.sourceDigests.keys.toList(),
      'actionContext': snapshot.actionContext == null
          ? null
          : {
              'draftRevision': snapshot.actionContext!.draftRevision,
              'draft': {
                for (final e in snapshot.actionContext!.draft.entries)
                  e.key: _gated(disclosure.stateKeys, e.key, e.value),
              },
              'confirmedRecordRefs': snapshot.actionContext!.confirmedRecordRefs
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
            'properties': e.value.properties.map((k, v) => MapEntry(k, v.name)),
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
