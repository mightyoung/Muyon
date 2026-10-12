import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart'
    show
        AssistantScope,
        ToolCallResult,
        ToolCallStatus,
        ToolDescriptor,
        ToolEffect;
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon/platform/inquiry_ui_planning_source.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/model_tool_result_projection.dart';

import 'support/agent_loop_fixture.dart';

import 'package:muyon/platform/inquiry_model_disclosure.dart';
import 'package:supplier_core/supplier_core.dart' show Quotation;

import 'support/aiui6_snapshot_fixture.dart';

const object = ObjectRef(
  moduleId: 'inquiry',
  objectType: 'project_item',
  objectId: 'item',
);
const ref = SnapshotRef('safe-ref', 1);
UiPlanningRequest request(
  DataSnapshot snapshot, {
  Set<String> facts = const {},
  Set<String> computed = const {},
  Set<String> uiState = const {},
}) => UiPlanningRequest(
  modelDisclosedFactRefs: facts,
  modelDisclosedComputedRefs: computed,
  modelDisclosedUiStateRefs: uiState,
  question: 'display',
  answer: '',
  conversationMessages: const [],
  conversationVersion: '1',
  coverage: 'selected',
  taskId: 'task',
  turnId: 'turn',
  snapshot: snapshot,
  intent: InteractionIntent(
    id: 'intent',
    purpose: 'display',
    snapshotRef: snapshot.ref,
  ),
  currentView: UiCurrentView(surfaceId: 'surface', revision: 1),
  catalog: library2UiCatalog,
  allowedActionRefs: const {},
  mode: UiPlanningMode.intelligent,
);

void main() {
  for (final path in [
    'summary',
    'step-answer',
    'filtered-view',
    'manual-tool',
  ]) {
    test(
      'planning quarantines $path legacy derived answer without changing local record',
      () async {
        final f = await InquirySnapshotFixture.open();
        try {
          final c = await f.host.foundation.createConversation(
            scope: AssistantScope.selectedObjects([f.refs['project_item']!]),
          );
          final initial = await f.host.personalAgent.start(
            conversationId: c.id,
            prompt: 'USER-ORIGINAL-KEPT',
          );
          final canary = 'OLD-TOOL-DERIVED-$path-826ac';
          final raw = ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: canary,
            data: {'notes': canary},
          );
          final messages = <Object?>[
            {'role': 'user', 'content': 'USER-ORIGINAL-KEPT'},
            if (path != 'manual-tool')
              {
                'role': 'tool',
                'content': jsonEncode({'trustedToolResult': raw.toJson()}),
              },
          ];
          final task = initial.copy({
            'messages': messages,
            'summary': path == 'step-answer' ? null : canary,
            if (path == 'step-answer') 'state': 'waitingConfirmation',
            if (path == 'step-answer')
              'step': {
                'assistant': {'content': canary},
              },
            if (path == 'manual-tool')
              'toolCall': {
                'tool': 'inquiry.read_object',
                'arguments': <String, Object?>{},
              },
          });
          // Model a completed pre-policy persisted attempt. The public update
          // API intentionally refuses terminal edits; fixtures restore bytes
          // directly, without weakening that production transition guard.
          f.host.foundation.database.raw.execute(
            'UPDATE execution_records SET payload=? WHERE id=?',
            [jsonEncode(task.payload), task.id],
          );
          UiPlanningRequest? actual;
          final harness = UiPlanningHarness(
            repository: f.host.foundation,
            source: InquiryUiPlanningSource(f.host).read,
            requestView: path == 'filtered-view'
                ? (t) =>
                      modelToolHistory(t.payload['messages'] as List).messages
                : null,
            providers: {
              UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
                actual = r;
                return const UiPlanningResult(
                  decision: UiDisplayDecision.textOnly,
                  reasonCode: 'model_no_card',
                );
              }),
            },
          );
          await harness.plan(task.id);
          expect(actual, isNotNull);
          expect(jsonEncode(actual!.toJson()), isNot(contains(canary)));
          expect(jsonEncode(actual!.toJson()), contains('USER-ORIGINAL-KEPT'));
          final preserved = f.host.foundation.task(task.id)!;
          if (path == 'step-answer') {
            expect(
              ((preserved.payload['step'] as Map)['assistant']
                  as Map)['content'],
              canary,
            );
          } else {
            expect(preserved.summary, canary);
          }
        } finally {
          await f.close();
        }
      },
    );
  }
  test(
    'producer-bound planning keeps the current registered-tool model answer',
    () async {
      final f = await LoopFixture.open();
      const selected = ObjectRef(
        moduleId: 'inquiry',
        objectType: 'project_item',
        objectId: 'item-1',
      );
      f.objects = [selected];
      const raw = 'CURRENT-TOOL-UNREGISTERED-NOTES-721bc';
      f.tools.register(
        providerId: 'inquiry',
        descriptor: ToolDescriptor(
          toolId: 'inquiry.object',
          moduleId: 'inquiry',
          effect: ToolEffect.read,
          parameterSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        handler: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: raw,
          data: {
            'record': {'name': '合法品名', 'qty': 4, 'notes': raw},
          },
          objectRefs: [selected],
        ),
      );
      const ordinary = 'CURRENT-AFTER-REGISTERED-TOOL-ANSWER-9a26';
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'inquiry__object', '{}')])))
        ..add(LoopReply.sse(sseText(ordinary)));
      final agent = f.agent();
      final done = await f.run(agent, await f.start(agent, f.profile()));
      expect(done.summary, ordinary);
      final provenance = modelTaskToolHistory(done, f.tools);
      expect(
        provenance.hadLegacyResult,
        isFalse,
        reason: 'actual host registry invocation, receipt, frozen identity and producer agree',
      );
      expect(jsonEncode(provenance.messages), contains('合法品名'));
      UiPlanningRequest? actual;
      final harness = UiPlanningHarness(
        repository: f.repo,
        modelHistory: (t) => modelTaskToolHistory(t, f.tools),
        requestView: (t) => modelTaskToolHistory(t, f.tools).messages,
        source: (t) async => UiPlanningHostState(
          snapshot: DataSnapshot(ref: ref, facts: {}),
          intent: InteractionIntent(
            id: 'i',
            purpose: 'display',
            snapshotRef: ref,
          ),
          currentView: UiCurrentView(surfaceId: 's', revision: 1),
          catalog: library2UiCatalog,
          allowedActionRefs: {},
        ),
        providers: {
          UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
            actual = r;
            return const UiPlanningResult(
              decision: UiDisplayDecision.textOnly,
              reasonCode: 'model_no_card',
            );
          }),
        },
      );
      await harness.plan(done.id);
      expect(actual, isNotNull);
      expect(actual!.answer, ordinary);
      expect(jsonEncode(actual!.toJson()), contains('合法品名'));
      expect(jsonEncode(actual!.toJson()), isNot(contains(raw)));
      expect(
        jsonEncode(done.payload['step']),
        contains(raw),
        reason: 'model projection does not erase the local receipt',
      );
    },
  );
  test('real startChat current ordinary model answer remains available to planning', () async {
    final f = await LoopFixture.open();
    final agent = f.agent();
    const ordinary = 'CURRENT-ORDINARY-ANSWER-928c';
    f.replies.add(LoopReply.sse(sseText(ordinary)));
    final first = await f.start(agent, f.profile());
    final done = await f.run(agent, first);
    expect(done.summary, ordinary);
    UiPlanningRequest? actual;
    final harness = UiPlanningHarness(
      repository: f.repo,
      source: (t) async => UiPlanningHostState(
        snapshot: DataSnapshot(ref: ref, facts: {}),
        intent: InteractionIntent(
          id: 'i',
          purpose: 'display',
          snapshotRef: ref,
        ),
        currentView: UiCurrentView(surfaceId: 's', revision: 1),
        catalog: library2UiCatalog,
        allowedActionRefs: {},
      ),
      providers: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
          actual = r;
          return const UiPlanningResult(
            decision: UiDisplayDecision.textOnly,
            reasonCode: 'model_no_card',
          );
        }),
      },
    );
    await harness.plan(done.id);
    expect(actual, isNotNull);
    expect(actual!.answer, ordinary);
    expect(jsonEncode(actual!.toJson()), contains(ordinary));
  });
  test('only explicitly registered ordinary fields are eligible and masking still wins', () {
    for (final type in ['project_item', 'quotation', 'inquiry']) {
      for (final field in [
        'unknown_future_field',
        'notes',
        'award_note',
        'requirement',
      ]) {
        expect(
          inquiryFieldDisclosedToModel(type, field, masked: false),
          isFalse,
        );
      }
      for (final field in inquiryModelDisclosedFields[type]!) {
        expect(
          inquiryFieldDisclosedToModel(type, field, masked: false),
          isTrue,
        );
        expect(
          inquiryFieldDisclosedToModel(type, field, masked: true),
          isFalse,
        );
      }
    }
    expect(
      inquiryFieldDisclosedToModel('new-type', 'name', masked: false),
      isFalse,
    );
  });
  for (final type in ['project_item', 'quotation', 'inquiry']) {
    test(
      'real $type source denies free text while local record retains it',
      () async {
        final f = await InquirySnapshotFixture.open();
        try {
          final store = f.host.inquiry!.runtime.state.store;
          final old = f.refs[type]!;
          final row = store.db.select('SELECT data FROM $type WHERE id=?', [
            old.objectId,
          ]).single;
          final data = Map<String, Object?>.from(
            jsonDecode(row['data'] as String) as Map,
          );
          for (final field in [
            'notes',
            if (type == 'quotation') 'award_note',
            if (type == 'project_item') 'requirement',
          ]) {
            data[field] = 'FREE-TEXT-SECRET-$field-18ac';
          }
          if (type == 'quotation') {
            for (final field in Quotation.fields) {
              data.putIfAbsent(field, () => null);
            }
          }
          store.save(type, data, id: old.objectId);
          final source = f.host.scopeResolver.sources.singleWhere(
            (s) => s.moduleId == 'inquiry',
          );
          final live = (await source.resolve(
            ObjectRef(
              moduleId: 'inquiry',
              objectType: type,
              objectId: old.objectId,
              nativeProjectId: old.nativeProjectId,
            ),
          ))!;
          final c = await f.host.foundation.createConversation(
            scope: AssistantScope.selectedObjects([live]),
          );
          final task = await f.host.personalAgent.start(
            conversationId: c.id,
            prompt: 'local',
          );
          final state = (await InquiryUiPlanningSource(f.host).read(task))!;

          UiPlanningRequest? actual;
          final harness = UiPlanningHarness(
            repository: f.host.foundation,
            source: InquiryUiPlanningSource(f.host).read,
            providers: {
              UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
                actual = r;
                return const UiPlanningResult(
                  decision: UiDisplayDecision.textOnly,
                  reasonCode: 'model_no_card',
                );
              }),
            },
          );
          await harness.plan(task.id);
          expect(
            actual,
            isNotNull,
            reason: 'actual source-to-harness request carries host disclosure registration',
          );
          expect(
            jsonEncode(actual!.toJson()),
            isNot(contains('FREE-TEXT-SECRET')),
          );
          if (type == 'project_item') {
            expect(jsonEncode(actual!.toJson()), contains('真实预算行'));
          }
          expect(
            jsonEncode(
              request(
                state.snapshot,
                facts: state.modelDisclosedFactRefs,
              ).toJson(),
            ),
            isNot(contains('FREE-TEXT-SECRET')),
          );
          for (final field in [
            'notes',
            if (type == 'quotation') 'award_note',
            if (type == 'project_item') 'requirement',
          ]) {
            expect(
              state.snapshot.facts['saved-$field']!.state,
              FactState.notDisclosed,
            );
          }
          expect(
            store.db.select('SELECT data FROM $type WHERE id=?', [
              old.objectId,
            ]).single['data'],
            contains('FREE-TEXT-SECRET'),
          );
          if (type == 'project_item') {
            expect(state.snapshot.facts['saved-name']!.value, '真实预算行');
            expect(
              state.snapshot.facts['saved-unit_cost']!.state,
              FactState.notDisclosed,
            );
          }
        } finally {
          await f.close();
        }
      },
    );
  }
}
