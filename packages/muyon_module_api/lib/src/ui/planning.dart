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
  }) : conversationMessages = List.unmodifiable(
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
      'values': currentView.values,
    },
    'snapshot': {
      'id': snapshot.ref.id,
      'revision': snapshot.ref.revision,
      'facts': {
        for (final e in snapshot.facts.entries)
          e.key: {
            'object': e.value.object.toJson(),
            'field': e.value.field,
            'value': e.value.value,
            'state': e.value.state.name,
            'unit': e.value.unit,
            'sourceRefs': e.value.sourceRefs,
          },
      },
      'initialUiState': snapshot.initialUiState,
      'computations': {
        for (final e in snapshot.computations.entries)
          e.key: {
            'value': e.value.value,
            'snapshotId': e.value.inputVersion.id,
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
              'contentDigest': e.value.artifact.contentDigest,
            },
            'originalText': e.value.originalText,
            'start': e.value.start,
            'end': e.value.end,
            'page': e.value.page,
            'paragraph': e.value.paragraph,
          },
      },
      'sourceDigests': snapshot.sourceDigests,
      'actionContext': snapshot.actionContext == null
          ? null
          : {
              'draftRevision': snapshot.actionContext!.draftRevision,
              'draft': snapshot.actionContext!.draft,
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
