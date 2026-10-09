import 'dart:async';
import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/agent_budget.dart';
import 'package:muyon/assistant/agent_event_sink.dart';
import 'package:muyon/platform/ui_planning_source.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/platform/grants/grant_store.dart';
import 'package:muyon/platform/grants/host_model_authorization.dart';
import 'package:muyon/platform/grants/outbound_content_reviewer.dart';
import 'package:muyon/assistant/ui_planning_events.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/model_request_gate.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';

import 'support/agent_loop_fixture.dart';
import 'support/ui_public_fixture.dart';

const _answerJson = '{"type":"answer","answer":"成本合计 2080 元"}';
const _prose = '成本合计 2080 元，销售合计 2380 元。';
const _streaming = ModelCapabilities(streaming: true);
const _native = ModelCapabilities(streaming: true, nativeTools: true);

UiPlanningHostState state({int viewRevision = 4}) {
  final snapshot = DataSnapshot(
    ref: const SnapshotRef('actual', 5),
    facts: {
      'qty': SnapshotFact(
        object: const ObjectRef(
          moduleId: 'test',
          objectType: 'quantity',
          objectId: 'q',
        ),
        field: 'qty',
        value: 10,
        state: FactState.verified,
      ),
    },
    initialUiState: {'quantity': '12'},
  );
  return UiPlanningHostState(
    snapshot: snapshot,
    intent: InteractionIntent(
      id: 'actual-intent',
      purpose: 'edit actual host draft',
      snapshotRef: snapshot.ref,
      allowedActionRefs: {'edit'},
    ),
    currentView: UiCurrentView(
      surfaceId: 'actual-surface',
      revision: viewRevision,
      values: {'quantity': '12'},
    ),
    catalog: dynamicUiCatalog,
    allowedActionRefs: {'edit'},
  );
}

UiPlanningResult result(UiPlanningRequest r) => UiPlanningResult(
  decision: UiDisplayDecision.supplement,
  reasonCode: 'fixture',
  plan: UIPlan(
    surfaceId: r.currentView.surfaceId,
    revision: r.currentView.revision + 1,
    catalogVersion: r.catalog.version,
    snapshotRef: r.snapshot.ref,
    intentRef: r.intent.id,
    root: 'qty',
    nodes: [
      UiNode(
        id: 'qty',
        component: 'Field',
        properties: {'label': 'Quantity'},
        bindings: {
          'value': const BindingRef.fact('qty'),
          'draft': const BindingRef.uiState('quantity'),
        },
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['quantity']),
        },
      ),
    ],
  ),
);

class _PlanningSink implements AgentEventSink {
  _PlanningSink(this.delegate);
  final AgentEventSink delegate;
  final child = Completer<String>();
  @override
  Future<void> append(String taskId, AgentEvent event) async {
    await delegate.append(taskId, event);
    if (event.type == 'ui_planning_model' && !child.isCompleted) {
      child.complete(event.data['taskId'] as String);
    }
  }
}

class _SoftGuides implements UiGuideSource {
  @override
  Future<List<UiGuideEntry>> lookup(UiGuideQuery query) async => [
    UiGuideEntry(
      guideId: 'proposed-hide',
      revision: '1',
      conditions: ['Hide delivery conflict'],
      counterexamples: ['Conflict is required'],
      evidenceIds: ['public-train-example'],
      validation: UiGuideValidation.proposed,
      split: UiGuideSplit.train,
      catalogVersion: query.catalogVersion,
    ),
  ];
}

/// Controls only the planning deadline; HTTP fixture timers remain real.
class _ManualDeadline implements Timer {
  _ManualDeadline(this.callback);
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }
}

class _PlanningStartupGate implements ModelRequestGate {
  bool holdStartup = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<GateDecision> decide(ModelRequestFacts facts) async {
    if (holdStartup) {
      entered.complete();
      await release.future;
    }
    return const GateConfirm();
  }
}

void main() {
  for (final holdStartup in [false, true]) {
    test(
      'planning deadline commits cancellation before return '
      '${holdStartup ? 'during startup' : 'while awaiting confirmation'}',
      () async {
        final f = await LoopFixture.open();
        final sink = _PlanningSink(TaskEventTableSink(f.repo));
        final gate = _PlanningStartupGate();
        final agent = PersonalAgent(
          repository: f.repo,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          tools: f.tools,
          gate: gate,
          events: sink,
          uiPlanningSource: (t) async => state(),
          uiPlanningProviders: {
            UiPlanningMode.intelligent: FixtureUiPlanningProvider(
              (r) async => result(r),
            ),
          },
        );
        addTearDown(agent.close);
        f.replies.add(LoopReply.sse(sseText(_answerJson)));
        final task = await f.run(
          agent,
          await f.start(agent, f.profile(capabilities: _streaming)),
        );
        gate.holdStartup = holdStartup;
        agent.configureUiPlanning(mode: UiPlanningMode.motivation);
        late _ManualDeadline deadline;
        final planning = runZoned(
          () => agent.planUi(task.id),
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              if (duration == const Duration(seconds: 15)) {
                deadline = _ManualDeadline(() => zone.run(callback));
                return deadline;
              }
              return parent.createTimer(zone, duration, callback);
            },
          ),
        );
        if (holdStartup) {
          await gate.entered.future;
        } else {
          await sink.child.future;
        }
        final child = f.repo.tasks().singleWhere(
          (t) => t.payload['uiPlanningInternal'] == true,
        );
        final digest = child.payload['requestDigest'] as String?;
        final sendsBefore = f.bodies.length;
        final ledgerBefore = f.ledger.recent().length;
        deadline.fire();
        final planned = await planning;
        expect(planned.result.reasonCode, 'planner_timeout');
        // The persistence assertion is immediate: no sleep or retry window.
        expect(f.repo.task(child.id)!.state, PersonalTaskState.cancelled);
        await expectLater(
          agent.confirm(child.id, requestDigest: digest ?? 'late-confirmation'),
          throwsStateError,
        );
        if (holdStartup) {
          gate.release.complete();
          await sink.child.future;
          // Finishing startup cannot resurrect the cancelled child.
          expect(f.repo.task(child.id)!.state, PersonalTaskState.cancelled);
        }
        expect(f.bodies, hasLength(sendsBefore));
        expect(f.ledger.recent(), hasLength(ledgerBefore));
      },
    );
  }
  test('internal planning cannot resume as an ordinary chat', () async {
    final f = await LoopFixture.open();
    final agent = f.agent();
    final task = await f.start(agent, f.profile(capabilities: _streaming));
    await f.repo.updateTask(
      task.copy({'state': 'paused', 'uiPlanningInternal': true}),
    );
    await expectLater(agent.resume(task.id), throwsStateError);
    expect(f.bodies, isEmpty);
  });
  test('compatibility explicit request without answer does not poison final planning', () async {
    final f = await LoopFixture.open();
    final requests = <UiPlanningRequest>[];
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      uiPlanningSource: (t) async => state(),
      uiPlanningProviders: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
          requests.add(r);
          return result(r);
        }),
      },
    );
    addTearDown(agent.close);
    f.replies.addAll([
      LoopReply.sse(
        sseText(
          jsonEncode({
            'type': 'tool',
            'toolId': 'assistant.plan_ui',
            'parameters': {
              'snapshotId': 'actual',
              'expectedSnapshotRevision': 5,
              'surfaceId': 'actual-surface',
              'expectedSurfaceRevision': 4,
            },
          }),
        ),
      ),
      LoopReply.sse(sseText(_answerJson)),
    ]);
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _streaming)),
    );
    expect(task.state, PersonalTaskState.succeeded);
    expect(requests.single.answer, '成本合计 2080 元');
    expect(agent.uiPresentation(task.id)!.validated, isNotNull);
  });
  test('guide cannot override required conflict under either mode', () async {
    final f = await LoopFixture.open();
    final agent = f.agent();
    f.replies.add(LoopReply.sse(sseText(_answerJson)));
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _streaming)),
    );
    final fixture = runtimeFixture();
    final provider = FixtureUiPlanningProvider((r) async {
      expect(r.guideEntries.single.validation, UiGuideValidation.proposed);
      final plan = fixture.plan.plan!;
      return UiPlanningResult(
        decision: UiDisplayDecision.supplement,
        reasonCode: 'bad-soft-suggestion',
        plan: plan.copyWith(
          nodes: [
            for (final node in plan.nodes)
              if (!{'delivery', 'warning', 'status'}.contains(node.id))
                node.id == plan.root
                    ? node.copyWith(
                        children: node.children
                            .where(
                              (id) => !{
                                'delivery',
                                'warning',
                                'status',
                              }.contains(id),
                            )
                            .toList(),
                      )
                    : node,
          ],
        ),
      );
    });
    for (final mode in UiPlanningMode.values) {
      final harness = UiPlanningHarness(
        repository: f.repo,
        guides: _SoftGuides(),
        mode: mode,
        providers: {mode: provider},
        source: (t) async => UiPlanningHostState(
          snapshot: fixture.snapshot,
          intent: fixture.intent,
          currentView: UiCurrentView(
            surfaceId: fixture.plan.plan!.surfaceId,
            revision: 0,
          ),
          catalog: fixture.catalog!,
          allowedActionRefs: fixture.intent.allowedActionRefs,
        ),
      );
      final result = await harness.plan(task.id);
      expect(result.result.reasonCode, 'invalid_plan');
      expect(result.validated, isNull);
      expect(f.repo.task(task.id)!.summary, '成本合计 2080 元');
    }
  });
  test('changed current view invalidates a planning model card before any bytes leave', () async {
    final f = await LoopFixture.open();
    var revision = 4;
    final sink = _PlanningSink(TaskEventTableSink(f.repo));
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      events: sink,
      uiPlanningSource: (t) async => state(viewRevision: revision),
      uiPlanningProviders: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider(
          (r) async => result(r),
        ),
      },
    );
    addTearDown(agent.close);
    f.replies.addAll([
      LoopReply.sse(sseText(_answerJson)),
      LoopReply.sse(sseText(_answerJson)),
    ]);
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _streaming)),
    );
    agent.configureUiPlanning(mode: UiPlanningMode.motivation);
    final planned = agent.planUi(task.id);
    final child = f.repo.task(await sink.child.future)!;
    revision = 5;
    await agent.confirm(
      child.id,
      requestDigest: child.payload['requestDigest'] as String,
    );
    await planned;
    expect(
      f.bodies,
      hasLength(1),
      reason: 'stale planning source must be rejected before gateway send',
    );
  });
  test(
    'mode_switch_does_not_expand_outbound under actual HostModelAuthorization',
    () async {
      final f = await LoopFixture.open();
      final sink = _PlanningSink(TaskEventTableSink(f.repo));
      final policy = HostAuthorizationPolicy(f.repo.database);
      final profile = ModelProfile(
        id: 'remote-loop-fixture',
        endpoint: f.profile().endpoint,
        location: ModelLocation.local,
        cloudProxy: true,
        modelId: 'm',
        endpointIdentity: 'fixture',
        capabilities: _streaming,
      );
      final authority = HostModelAuthorization(
        repository: f.repo,
        policy: policy,
        grants: GrantStore(f.repo.database),
        reviewer: const NoopReviewer(),
        configuredProfiles: () => [profile],
      );
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        gate: HostPolicyModelGate(policy),
        modelAuthorization: authority,
        events: sink,
        uiPlanningSource: (t) async => state(),
        uiPlanningProviders: {
          UiPlanningMode.intelligent: FixtureUiPlanningProvider(
            (r) async => result(r),
          ),
        },
      );
      addTearDown(agent.close);
      f.replies.add(LoopReply.sse(sseText(_answerJson)));
      final task = await f.run(agent, await f.start(agent, profile));
      expect(f.bodies, hasLength(1));
      agent.configureUiPlanning(mode: UiPlanningMode.motivation);
      final planning = agent.planUi(task.id);
      await sink.child.future;
      final child = f.repo.task(await sink.child.future)!;
      expect(child.state, PersonalTaskState.waitingConfirmation);
      expect(f.bodies, hasLength(1));
      expect(f.ledger.recent(), hasLength(1));
      await agent.cancel(child.id);
      // Resolve through actual cancellation rather than waiting a planning timeout.
      expect(f.repo.task(task.id)!.summary, '成本合计 2080 元');
      expect((await planning).validated, isNull);
      expect(f.bodies, hasLength(1));
    },
  );
  test(
    'planner_failure_keeps_conversation for missing invalid timeout providers',
    () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      f.replies.add(LoopReply.sse(sseText(_answerJson)));
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _streaming)),
      );
      for (final provider in <UiPlanningPort?>[
        null,
        FixtureUiPlanningProvider(
          (r) async => UiPlanningResult(
            decision: UiDisplayDecision.supplement,
            reasonCode: 'invalid',
            plan: result(r).plan!.copyWith(catalogVersion: 'invalid'),
          ),
        ),
        FixtureUiPlanningProvider((r) => Completer<UiPlanningResult>().future),
      ]) {
        final harness = UiPlanningHarness(
          repository: f.repo,
          source: (t) async => state(),
          timeout: const Duration(milliseconds: 10),
          providers: provider == null
              ? {}
              : {UiPlanningMode.intelligent: provider},
        );
        final planned = await harness.plan(task.id);
        expect(planned.validated, isNull);
        expect(planned.result.decision, UiDisplayDecision.textOnly);
        expect(f.repo.task(task.id)!.summary, '成本合计 2080 元');
      }
      f.replies.add(LoopReply.sse(sseText(_answerJson)));
      final next = await f.run(
        agent,
        await agent.start(
          conversationId: task.conversationId,
          prompt: '下一问',
          profile: f.profile(capabilities: _streaming),
        ),
      );
      expect(next.state, PersonalTaskState.succeeded);
      expect(
        f.repo
            .messages(task.conversationId)
            .where((m) => m.role == 'assistant'),
        hasLength(2),
      );
    },
  );
  test('semantic explanation runs actual harness once and validates next plan revision', () async {
    final f = await LoopFixture.open();
    var revision = 4;
    final calls = <UiPlanningRequest>[];
    UiPlanningHostState semanticState() {
      final old = state(viewRevision: revision);
      return UiPlanningHostState(
        snapshot: old.snapshot,
        intent: InteractionIntent(
          id: old.intent.id,
          purpose: 'Explain',
          snapshotRef: old.snapshot.ref,
          requiredBindings: {const BindingRef.fact('qty')},
          allowedActionRefs: {'explain'},
        ),
        currentView: old.currentView,
        catalog: old.catalog,
        allowedActionRefs: {'explain'},
      );
    }

    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      uiPlanningSource: (t) async => semanticState(),
      uiPlanningProviders: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
          calls.add(r);
          return UiPlanningResult(
            decision: UiDisplayDecision.supplement,
            reasonCode: 'fixture',
            plan: UIPlan(
              surfaceId: r.currentView.surfaceId,
              revision: r.currentView.revision + 1,
              catalogVersion: r.catalog.version,
              snapshotRef: r.snapshot.ref,
              intentRef: r.intent.id,
              root: 'warning',
              nodes: [
                UiNode(
                  id: 'warning',
                  component: 'WarnBanner',
                  bindings: {'value': const BindingRef.fact('qty')},
                  events: {'tap': ActionBinding(actionRef: 'explain')},
                ),
              ],
            ),
          );
        }),
      },
    );
    addTearDown(agent.close);
    f.replies.addAll([
      LoopReply.sse(sseText(_answerJson)),
      LoopReply.sse(sseText(_answerJson)),
    ]);
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _streaming)),
    );
    final first = agent.uiPresentation(task.id)!.validated!;
    revision = first.plan.revision;
    late UiPlanningEventRouter router;
    final surface = UiSurfaceController(
      first,
      onEvent: (e) => router.dispatch(e),
    );
    addTearDown(surface.dispose);
    router = UiPlanningEventRouter(
      agent: agent,
      taskId: task.id,
      surface: surface,
    );
    addTearDown(router.dispose);
    final event = surface.eventFor(first.plan.nodes.single, 'tap');
    await surface.dispatch(event);
    final child = f.repo.task(router.tasks[event.eventId]!)!;
    await f.run(agent, child);
    expect(calls, hasLength(2));
    expect(surface.current.plan.revision, 6);
    await surface.dispatch(event);
    expect(router.tasks, hasLength(1));
    expect(calls, hasLength(2));
  });
  test('cached result cannot retain a withdrawn actual action', () async {
    final f = await LoopFixture.open();
    var allow = true;
    final provider = FixtureUiPlanningProvider((r) async => result(r));
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      uiPlanningSource: (t) async {
        final v = state();
        return UiPlanningHostState(
          snapshot: v.snapshot,
          intent: v.intent,
          currentView: v.currentView,
          catalog: v.catalog,
          allowedActionRefs: allow ? {'edit'} : {},
        );
      },
      uiPlanningProviders: {UiPlanningMode.intelligent: provider},
    );
    addTearDown(agent.close);
    f.replies.add(LoopReply.sse(sseText(_answerJson)));
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _streaming)),
    );
    expect(agent.uiPresentation(task.id)!.validated, isNotNull);
    allow = false;
    expect(
      (await agent.planUi(task.id)).validated,
      isNull,
      reason: 'current host action withdrawal invalidates the cached result',
    );
  });
  test(
    'native explicit planning schema uses real host metadata and complete QA',
    () async {
      final f = await LoopFixture.open();
      final requests = <UiPlanningRequest>[];
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        uiPlanningSource: (t) async => state(),
        uiPlanningProviders: {
          UiPlanningMode.intelligent: FixtureUiPlanningProvider((r) async {
            requests.add(r);
            return result(r);
          }),
        },
      );
      addTearDown(agent.close);
      f.replies.addAll([
        LoopReply.sse(
          sseCalls([
            (
              'call_plan',
              'assistant__plan_ui',
              jsonEncode({
                'snapshotId': 'actual',
                'expectedSnapshotRevision': 5,
                'surfaceId': 'actual-surface',
                'expectedSurfaceRevision': 4,
              }),
            ),
          ], text: _prose),
        ),
        LoopReply.sse(sseText('最终完整回答：$_prose')),
      ]);
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _native)),
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(requests, hasLength(2));
      expect(requests.first.answer, _prose);
      expect(requests.last.answer, '最终完整回答：$_prose');
      final tools = f.bodies.first['tools'] as List;
      final schema =
          (tools.firstWhere(
                (t) => t['function']['name'] == 'assistant__plan_ui',
              )['function'])
              as Map;
      expect((schema['parameters']['properties'] as Map).keys.toSet(), {
        'snapshotId',
        'expectedSnapshotRevision',
        'surfaceId',
        'expectedSurfaceRevision',
      });
      expect(schema['description'], contains('Cannot execute business'));
      final messages = f.bodies.first['messages'] as List;
      expect(
        messages.any(
          (m) => '${m['content']}'.contains('expectedSnapshotRevision'),
        ),
        isTrue,
        reason: 'model must see actual versions; it must not guess them',
      );
    },
  );
  test(
    'default host snapshot uses actual receipts and not model-authored payload',
    () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      final task = await agent.startTool(
        conversationId: conversation.id,
        toolId: 'read',
      );
      final source = TaskReceiptUiPlanningSource(f.repo, f.tools);
      final value = await source.read(
        task.copy({
          'toolLog': [
            {'value': 999},
          ],
        }),
      );
      expect(
        value,
        isNotNull,
        reason: 'actual ToolRegistry receipt must supply the default snapshot',
      );
      expect(value!.snapshot.facts.values.single.value, 42);
      expect(
        value.snapshot.facts.values.single.object,
        f.tools
            .receiptFor(
              (task.payload['step'] as Map)['calls'][0]['invocationId'],
            )!
            .result!
            .objectRefs
            .single,
      );
      expect(value.allowedActionRefs, {'detail', 'back'});
      expect(value.currentView.revision, 0);
      final store = HostUiWorkspaceStore(f.repo, taskId: task.id);
      await store.save(
        StoredUiWorkspace(
          taskId: task.id,
          surfaceId: value.currentView.surfaceId,
          scopeKey: store.scopeKey!,
          revision: 1,
          schemaVersion: 1,
          catalogVersion: value.catalog.version,
          snapshotRef: value.snapshot.ref,
          intentRef: value.intent.id,
          planRevision: 7,
          draftRevision: 0,
          extracted: {},
          userOverrides: {},
          nodeIds: [],
        ),
        expectedRevision: 0,
      );
      expect((await source.read(task))!.currentView.revision, 7);
    },
  );
  test(
    'motivation reuses actual model confirmation and no second gateway',
    () async {
      final f = await LoopFixture.open();
      final sink = _PlanningSink(TaskEventTableSink(f.repo));
      final planned = result(
        UiPlanningRequest(
          question: 'q',
          answer: 'a',
          conversationMessages: [],
          conversationVersion: '1',
          coverage: 'full',
          taskId: 't',
          turnId: 't',
          snapshot: state().snapshot,
          intent: state().intent,
          currentView: state().currentView,
          catalog: state().catalog,
          allowedActionRefs: {'edit'},
          mode: UiPlanningMode.motivation,
        ),
      );
      final jsonPlan = jsonEncode({
        'decision': planned.decision.name,
        'reasonCode': 'fixture-online',
        'plan': encodeUiPresentation(planned.plan!),
      });
      f.replies.addAll([
        LoopReply.sse(sseText(_answerJson)),
        LoopReply.sse(
          sseText(jsonEncode({'type': 'answer', 'answer': jsonPlan})),
        ),
      ]);
      var revision = 4;
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        events: sink,
        budget: const Budget(maxSteps: 2),
        uiPlanningSource: (t) async => state(viewRevision: revision),
        uiPlanningMode: UiPlanningMode.motivation,
      );
      addTearDown(agent.close);
      final first = await f.start(agent, f.profile(capabilities: _streaming));
      final finishing = f.run(agent, first);
      await Future.any([sink.child.future, finishing]);
      expect(
        sink.child.isCompleted,
        isTrue,
        reason: 'motivation must use the live model harness',
      );
      final childId = await sink.child.future;
      final child = f.repo.task(childId)!;
      expect(child.stage, 'model');
      expect(child.state, PersonalTaskState.waitingConfirmation);
      expect(
        f.bodies,
        hasLength(1),
        reason: 'planning bytes must wait for their own actual confirmation',
      );
      expect(f.repo.task(first.id)!.summary, '成本合计 2080 元');
      await agent.confirm(
        childId,
        requestDigest: child.payload['requestDigest'] as String,
      );
      await finishing;
      expect(f.bodies, hasLength(2));
      final wire = f.bodies.last['messages'] as List;
      final prompt = jsonDecode(wire.last['content'] as String) as Map;
      expect(prompt['request']['answer'], '成本合计 2080 元');
      expect(prompt['request']['currentView']['revision'], 4);
      expect(prompt['request']['snapshot']['revision'], 5);
      expect(agent.uiPresentation(first.id)!.validated, isNotNull);
      revision = 5;
      await agent.planUi(first.id);
      expect(
        f.repo
            .tasks()
            .where((t) => t.payload['uiPlanningInternal'] == true)
            .first
            .state,
        PersonalTaskState.failed,
        reason: 'replanning shares cumulative turn budget',
      );
      expect(f.bodies, hasLength(2));
      expect(
        f.repo
            .messages(first.conversationId)
            .where((m) => m.role == 'assistant')
            .map((m) => m.content),
        ['成本合计 2080 元'],
      );
    },
  );
  test('auto_and_explicit_share_one_plan with actual current state and complete QA', () async {
    final f = await LoopFixture.open();
    final requests = <UiPlanningRequest>[];
    final entered = Completer<void>();
    final release = Completer<void>();
    final provider = FixtureUiPlanningProvider((r) async {
      requests.add(r);
      entered.complete();
      await release.future;
      return result(r);
    });
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      uiPlanningSource: (t) async => state(),
      uiPlanningProviders: {UiPlanningMode.intelligent: provider},
    );
    addTearDown(agent.close);
    f.replies.add(LoopReply.sse(sseText(_answerJson)));
    final first = await f.start(agent, f.profile(capabilities: _streaming));
    final finishing = f.run(agent, first);
    // Current baseline never enters the provider: race against a completed harness.
    await Future.any([entered.future, finishing]);
    expect(
      requests,
      hasLength(1),
      reason: 'actual automatic hook must call the selected provider',
    );
    final explicit = agent.planUi(
      first.id,
      expected: {
        'snapshotId': 'actual',
        'expectedSnapshotRevision': 5,
        'surfaceId': 'actual-surface',
        'expectedSurfaceRevision': 4,
      },
    );
    release.complete();
    await finishing;
    final planned = await explicit;
    expect(planned.validated, isNotNull);
    expect(identical(planned, agent.uiPresentation(first.id)), isTrue);
    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.question, '项目的成本预算是多少？');
    expect(request.answer, '成本合计 2080 元');
    expect(request.conversationMessages.last['content'], request.answer);
    expect(request.currentView.revision, 4);
    expect(request.currentView.values['quantity'], '12');
    expect(request.snapshot.ref.revision, 5);
    expect(request.catalog.version, dynamicUiCatalog.version);
    expect(request.allowedActionRefs, {'edit'});
    expect(planned.validated!.plan.revision, 5);
  });
  test('automatic planning retains the complete real harness answer', () async {
    final f = await LoopFixture.open();
    f.replies.add(LoopReply.sse(sseText(_answerJson)));
    final agent = f.agent();
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _streaming)),
    );
    expect(task.state, PersonalTaskState.succeeded);
    expect(task.summary, '成本合计 2080 元');
    expect(
      f.repo.taskEvents(task.id).where((e) => e.type == 'ui_planning'),
      isEmpty,
      reason: 'a completed harness answer without an attached planner keeps the original event timeline',
    );
  });
}
