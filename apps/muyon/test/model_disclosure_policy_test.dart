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
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
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
  test('source reference preparation is awaited and refusal creates no model frame', () async {
    final f = await LoopFixture.open();
    final agent = f.agent();
    f.replies.add(LoopReply.sse(sseText('普通已登记答复')));
    final task = await f.run(agent, await f.start(agent, f.profile()));
    var projected = 0;
    var sent = 0;
    final harness = UiPlanningHarness(
      repository: f.repo,
      source: (t) async => UiPlanningHostState(
        snapshot: DataSnapshot(ref: ref, facts: {}),
        intent: InteractionIntent(
          id: 'intent',
          purpose: 'display',
          snapshotRef: ref,
        ),
        currentView: UiCurrentView(surfaceId: 'surface', revision: 1),
        catalog: library2UiCatalog,
        allowedActionRefs: {},
      ),
      prepareModelReferences: (t, state) async {
        await Future<void>.value();
        throw StateError('unknown_source_pin');
      },
      modelReferences: (t) {
        projected++;
        return ModelReferenceMap(
          taskId: t.id,
          scopeKey: PersonalAgent.digest(t.scope.toJson()),
          snapshotKey: 'host-pin',
          objects: {},
        );
      },
      providers: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
          sent++;
          return const UiPlanningResult(
            decision: UiDisplayDecision.textOnly,
            reasonCode: 'model_no_card',
          );
        }),
      },
    );
    final planned = await harness.plan(task.id);
    expect(planned.result.reasonCode, 'host_state_changed');
    expect(planned.result.decision, UiDisplayDecision.textOnly);
    expect(planned.request, isNull);
    expect(planned.validated, isNull);
    expect(projected, 0);
    expect(sent, 0);
  });

  test(
    'actual startTool origin text never becomes model planning question',
    () async {
      final f = await LoopFixture.open();
      const raw = 'ACTUAL-MANUAL-QUESTION-NOTES-329ca';
      const privatePin = ObjectRef(
        moduleId: 'test',
        objectType: 'budget',
        objectId: 'b1',
        contentDigest: 'ACTUAL-MANUAL-PRIVATE-ROW-DIGEST-672da',
      );
      f.objects = [privatePin];
      f.tools.register(
        providerId: 'test',
        descriptor: ToolDescriptor(
          toolId: 'localinput',
          moduleId: 'test',
          effect: ToolEffect.read,
          parameterSchema: {
            'type': 'object',
            'properties': {
              'notes': {'type': 'string'},
            },
            'additionalProperties': false,
          },
        ),
        handler: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: '本机完成',
          objectRefs: [privatePin],
        ),
      );
      final agent = f.agent();
      final c = await f.repo.createConversation();
      final manual = await agent.startTool(
        conversationId: c.id,
        toolId: 'localinput',
        parameters: {'notes': raw},
      );
      expect(manual.state.name, 'succeeded');
      expect(manual.payload['modelHostToolRequestText'], contains(raw));
      String? prompt;
      final harness = UiPlanningHarness(
        repository: f.repo,
        source: (t) async => UiPlanningHostState(
          snapshot: DataSnapshot(ref: ref, facts: {}),
          intent: InteractionIntent(
            id: 'intent',
            purpose: 'display',
            snapshotRef: ref,
          ),
          currentView: UiCurrentView(surfaceId: 'surface', revision: 1),
          catalog: library2UiCatalog,
          allowedActionRefs: {},
        ),
        providers: {
          UiPlanningMode.intelligent: MotivationUiPlanningProvider((
            r,
            modelPrompt,
          ) async {
            prompt = modelPrompt;
            return '{"decision":"textOnly","reasonCode":"fixture","plan":null}';
          }),
        },
      );
      await harness.plan(manual.id);
      expect(prompt, isNotNull);
      expect(prompt, isNot(contains(raw)));
      expect(prompt, isNot(contains(privatePin.contentDigest!)));
      expect(
        f.repo.task(manual.id)!.payload['modelHostToolRequestText'],
        contains(raw),
      );
      expect(
        f.repo.messages(c.id).where((m) => m.role == 'user').single.content,
        contains(raw),
      );
    },
  );

  test(
    'C6 providers refuse a snapshot expired during actual model callback',
    () async {
      final snapshot = DataSnapshot(ref: ref, facts: {});
      final batchRequest = request(snapshot);
      final batch = MotivationUiPlanningProvider((r, _) async {
        r.referenceMap.expire();
        return '{"decision":"textOnly","reasonCode":"fixture","plan":null}';
      });
      await expectLater(batch.plan(batchRequest), throwsStateError);
      final streamRequest = request(snapshot);
      final stream = StreamMotivationUiPlanningProvider((r, _, emit) async {
        emit('{"op":"end"}\n');
        r.referenceMap.expire();
      });
      await expectLater(stream.plan(streamRequest), throwsStateError);
    },
  );

  test('C6 batch callback sees opaque snapshot and restores exact current host pin', () async {
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('PRIVATE-SAVED-ROW-HASH', 3),
      facts: {},
    );
    final r = request(snapshot);
    final provider = MotivationUiPlanningProvider((received, prompt) async {
      final wire = jsonDecode(prompt) as Map;
      expect(prompt, isNot(contains(snapshot.ref.id)));
      final alias = wire['request']['snapshot']['id'];
      return jsonEncode({
        'decision': 'supplement',
        'reasonCode': 'fixture',
        'plan': {
          'surfaceId': 'surface',
          'revision': 2,
          'catalogVersion': library2UiCatalog.version,
          'snapshotId': alias,
          'snapshotRevision': 3,
          'intentRef': 'intent',
          'root': 'root',
          'nodes': [],
        },
      });
    });
    expect((await provider.plan(r)).plan!.snapshotRef, snapshot.ref);
    final forged = MotivationUiPlanningProvider(
      (_, _) async => jsonEncode({
        'decision': 'supplement',
        'reasonCode': 'fixture',
        'plan': {'snapshotId': snapshot.ref.id, 'snapshotRevision': 3},
      }),
    );
    await expectLater(forged.plan(r), throwsStateError);
  });
  test('C6 stream uses opaque prompt and keeps host frozen pin and malformed guards', () async {
    final snapshot = DataSnapshot(
      ref: const SnapshotRef('PRIVATE-SAVED-ROW-HASH', 3),
      facts: {},
    );
    final r = request(snapshot);
    final provider = StreamMotivationUiPlanningProvider((
      received,
      prompt,
      emit,
    ) async {
      expect(prompt, isNot(contains(snapshot.ref.id)));
      expect(
        jsonDecode(prompt)['request']['snapshot']['id'],
        r.modelSnapshotId,
      );
      emit('{"op":"end"}\n');
    });
    expect((await provider.plan(r)).decision, UiDisplayDecision.textOnly);
    final bad = StreamMotivationUiPlanningProvider((_, _, emit) async {
      emit('{"op":"end","snapshotId":"forged"}\n');
    });
    await expectLater(bad.plan(r), throwsA(anything));
    r.referenceMap.expire();
    var sent = false;
    final expired = StreamMotivationUiPlanningProvider((_, _, _) async {
      sent = true;
    });
    await expectLater(expired.plan(r), throwsStateError);
    expect(sent, isFalse);
  });
  test(
    'C6 source snapshot aliases bind task scope pin lifecycle and authority',
    () {
      final owner = Object();
      String id({
        String task = 'task',
        String scope = 'scope',
        ObjectRef pin = object,
        String authority = 'owner',
        String policy = '1',
        int revoked = 0,
      }) => inquiryModelSnapshotId(
        owner: owner,
        taskId: task,
        scopeKey: scope,
        object: pin,
        lifecycle: 'active',
        authority: authority,
        policyRevision: policy,
        revocationRevision: revoked,
      );
      final initial = id();
      expect(initial, startsWith('ms1_'));
      expect(id(), initial);
      expect(id(task: 'other'), isNot(initial));
      expect(id(scope: 'other'), isNot(initial));
      expect(id(), isNot(initial)); // scope ABA invalidates old alias.
      final next = id();
      expect(id(authority: 'other'), isNot(next));
      expect(id(policy: '2'), isNot(next));
      expect(id(revoked: 1), isNot(next));
      expect(
        id(
          pin: const ObjectRef(
            moduleId: 'inquiry',
            objectType: 'project_item',
            objectId: 'item',
            contentDigest: 'changed-private-pin',
          ),
        ),
        isNot(next),
      );
    },
  );

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
            objectRefs: [
              ObjectRef(
                moduleId: 'inquiry',
                objectType: 'project_item',
                objectId: 'unknown-host-result',
                contentDigest: 'FALLBACK-PRIVATE-ROW-HASH-$path-123',
              ),
            ],
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
            if (path == 'manual-tool') 'prompt': canary,
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
          expect(
            jsonEncode(actual!.toJson()),
            isNot(contains('FALLBACK-PRIVATE-ROW-HASH')),
          );
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
        modelReferences: (t) => ModelReferenceMap(
          taskId: t.id,
          scopeKey: PersonalAgent.digest(t.scope.toJson()),
          snapshotKey: jsonEncode([ref.id, ref.revision]),
          objects: {selected},
        ),
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
