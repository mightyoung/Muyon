import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_planning_events.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show ToolEffect;
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart' show actionPlan;
import 'support/agent_loop_fixture.dart';
import 'support/ui_public_fixture.dart' show comparisonFixture;

// Real router/tool admission tests. No model or tool confirmation is granted.
void main() {
  test('unchanged business route prepares a real waiting tool child', () async {
    final live = await _RouterFixture.open();
    var mapped = false;
    live.parameters = (pending) {
      mapped = true;
      expect(pending.inputs, {'quantity': '12'});
      return {'note': 'Public quantity ${pending.inputs['quantity']}'};
    };
    await live.confirm();
    expect(mapped, isTrue);
    expect(live.router.tasks, hasLength(1));
    final child = live.f.repo.task(live.router.tasks.values.single)!;
    expect(child.previousAttemptId, live.task.id);
    expect(child.conversationId, live.task.conversationId);
    expect(child.state, PersonalTaskState.waitingConfirmation);
    expect(child.stage, 'tool');
    expect(live.f.repo.tasks(), hasLength(live.initialTaskCount + 1));
    expect(live.f.callsOf('write'), 0);
    expect(live.f.approvals(), isEmpty);
    expect(live.f.receipts(), isEmpty);
    expect(live.f.bodies, isEmpty);
  });

  test('mapper accepted plan advancement rejects the old business request', () async {
    final live = await _RouterFixture.open();
    var mapped = false;
    live.parameters = (_) {
      mapped = true;
      expect(live.surface.acceptPlan(live.replacement(advance: true)), isTrue);
      return {'note': 'old request'};
    };
    await live.confirm();
    expect(mapped, isTrue);
    expect(live.surface.current.plan.revision, live.plan.plan.revision + 1);
    live.expectNoAdmission();
  });

  test('hostile same-revision current substitution rejects the old plan identity', () async {
    final live = await _RouterFixture.open(hostileSubstitution: true);
    var mapped = false;
    live.parameters = (_) {
      mapped = true;
      final replacement = live.replacement(advance: false);
      expect(replacement.plan.revision, live.plan.plan.revision);
      (live.surface as _HostSubstitutionSurface).substitution = replacement;
      return {'note': 'same revision, different host plan'};
    };
    await live.confirm();
    expect(mapped, isTrue);
    expect(identical(live.surface.current, live.plan), isFalse);
    live.expectNoAdmission();
  });

  test('synchronous pending notification advances plan before router admission', () async {
    final live = await _RouterFixture.open();
    var changed = false;
    late void Function() listener;
    listener = () {
      if (changed) return;
      changed = true;
      live.surface.removeListener(listener);
      expect(live.surface.acceptPlan(live.replacement(advance: true)), isTrue);
    };
    live.surface.addListener(listener);
    await live.confirm();
    expect(changed, isTrue);
    live.expectNoAdmission();
  });

  test('synchronous pending notification taints the clean request before admission', () async {
    final live = await _RouterFixture.open();
    Future<void>? taintWrite;
    late void Function() listener;
    listener = () {
      if (taintWrite != null) return;
      live.surface.removeListener(listener);
      // markExternal latches host provenance synchronously before its write.
      taintWrite = live.f.repo.authorizationFacts.markExternal(
        live.task.id, HostSourceFact.object(live.f.ref));
    };
    live.surface.addListener(listener);
    await live.confirm();
    expect(taintWrite, isNotNull);
    await taintWrite;
    expect(live.f.repo.authorizationFacts.readTask(live.task.id).taintState,
        HostTaintState.tainted);
    live.expectNoAdmission();
  });

  test('mapper changes source identity while taint stays tainted', () async {
    final live = await _RouterFixture.open();
    await live.f.repo.authorizationFacts.markExternal(
      live.task.id, HostSourceFact.object(live.f.ref));
    final before = live.f.repo.authorizationFacts.readTask(live.task.id);
    expect(before.taintState, HostTaintState.tainted);
    Future<void>? taintWrite;
    live.parameters = (_) {
      taintWrite = live.f.repo.authorizationFacts.markExternal(live.task.id,
        HostSourceFact.object(const ObjectRef(
          moduleId: 'test', objectType: 'budget', objectId: 'second-source')));
      return {'note': 'old provenance'};
    };
    await live.confirm();
    expect(taintWrite, isNotNull);
    await taintWrite;
    final after = live.f.repo.authorizationFacts.readTask(live.task.id);
    expect(after.taintState, HostTaintState.tainted);
    expect(after.sourceDigests, containsAll(before.sourceDigests));
    expect(after.sourceDigests.length, greaterThan(before.sourceDigests.length));
    live.expectNoAdmission();
  });

  test('mapper fresh explicit request cannot authorize an old router', () async {
    final live = await _RouterFixture.open();
    Future<UiPlannedPresentation>? freshPlanning;
    live.parameters = (_) {
      // This host entry point freezes a new identity synchronously, even
      // though the planning Future completes later. The mode remains auto.
      freshPlanning = live.agent.planUiFromUserControl(live.task.id);
      return {'note': 'old presentation identity'};
    };
    await live.confirm();
    expect(freshPlanning, isNotNull);
    await freshPlanning;
    expect(live.agent.presentationMode, UiPresentationMode.automatic);
    live.expectNoAdmission();
  });

  test('mapper preference closing revokes the frozen presentation policy', () async {
    final live = await _RouterFixture.open();
    Future<void>? closing;
    live.parameters = (_) {
      // close invalidates all frozen policies synchronously. A synchronous
      // mapper cannot await savePresentationMode's persisted transition.
      closing = live.preference.close();
      return {'note': 'revoked presentation owner'};
    };
    await live.confirm();
    expect(closing, isNotNull);
    await closing;
    live.expectNoAdmission();
  });
}

class _RouterFixture {
  _RouterFixture(this.f, this.preference, this.agent, this.task, this.plan,
      this.surface, this.router, this.initialTaskCount);
  final LoopFixture f;
  final UiPresentationPreference preference;
  final PersonalAgent agent;
  final PersonalTask task;
  final ValidatedUiPlan plan;
  final UiSurfaceController surface;
  final UiPlanningEventRouter router;
  final int initialTaskCount;
  Map<String, Object?> Function(UiPendingAction) parameters =
      (_) => {'note': 'Public fixture write'};

  static Future<_RouterFixture> open({bool hostileSubstitution = false}) async {
    final f = await LoopFixture.open();
    expect(f.tools.inspect('write')!.available, isTrue);
    expect(f.tools.inspect('write')!.descriptor.effect, ToolEffect.write);
    expect(f.tools.inspect('read')!.descriptor.effect, ToolEffect.read);
    final preference = UiPresentationPreference(f.repo);
    await preference.save(UiPresentationMode.automatic);
    final base = actionPlan();
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      presentationPreference: preference,
      uiPlanningSource: (_) async => UiPlanningHostState(
        snapshot: base.snapshot,
        intent: base.intent,
        currentView: UiCurrentView(surfaceId: base.plan.surfaceId,
          revision: base.plan.revision - 1,
          values: base.snapshot.initialUiState),
        catalog: base.catalog,
        allowedActionRefs: base.intent.allowedActionRefs,
      ),
      uiPlanningProviders: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider((_) async =>
          UiPlanningResult(decision: UiDisplayDecision.supplement,
            reasonCode: 'public-router-admission', plan: base.plan)),
      },
    );
    addTearDown(() async {
      await agent.close();
      await preference.close();
    });
    final task = await f.start(agent, f.profile());
    expect(await f.repo.updateTask(task.copy({'summary': comparisonFixture().answer})), isTrue);
    final presentation = await agent.planUi(task.id);
    expect(presentation.validated, isNotNull,
        reason: presentation.result.reasonCode);
    final plan = presentation.validated!;
    late UiPlanningEventRouter router;
    final surface = hostileSubstitution
        ? _HostSubstitutionSurface(plan, onEvent: (event) => router.dispatch(event))
        : UiSurfaceController(plan, onEvent: (event) => router.dispatch(event));
    addTearDown(surface.dispose);
    late _RouterFixture live;
    router = UiPlanningEventRouter(agent: agent, taskId: task.id,
      surface: surface, businessActions: {
        'confirm': UiBusinessAction('write', (pending) => live.parameters(pending)),
      });
    addTearDown(router.dispose);
    live = _RouterFixture(f, preference, agent, task, plan, surface, router,
        f.repo.tasks().length);
    expect(f.bodies, isEmpty);
    return live;
  }

  Future<UiDispatchOutcome> confirm() {
    final node = plan.plan.nodes.singleWhere((node) => node.id == 'confirm');
    expect(surface.canConfirm(node), isTrue);
    return surface.dispatchCaptured(surface.captureRender(), node, 'confirm');
  }

  ValidatedUiPlan replacement({required bool advance}) {
    final checked = validateUiPlan(plan.plan.copyWith(
      revision: plan.plan.revision + (advance ? 1 : 0),
      nodes: [for (final node in plan.plan.nodes)
        if (node.id == 'confirm')
          node.copyWith(properties: {...node.properties, 'label': 'New host presentation'})
        else node],
    ), plan.snapshot, plan.intent, plan.catalog);
    expect(checked.isValid, isTrue, reason: '${checked.errors}');
    return checked.validatedPlan!;
  }

  void expectNoAdmission() {
    expect(router.tasks, isEmpty);
    expect(f.repo.tasks(), hasLength(initialTaskCount));
    expect(f.repo.taskEvents(task.id).where((event) => event.type == 'ui_business_task'), isEmpty);
    expect(f.callsOf('write'), 0);
    expect(f.callsOf('read'), 0);
    expect(f.approvals(), isEmpty);
    expect(f.receipts(), isEmpty);
    expect(f.bodies, isEmpty);
  }
}

// Additional hostile boundary case only: the public acceptPlan API already
// rejects different same-revision objects. Override its existing getter to
// model a host substitution while preserving real pending actions/dispatch.
class _HostSubstitutionSurface extends UiSurfaceController {
  _HostSubstitutionSurface(super.plan, {super.onEvent});
  ValidatedUiPlan? substitution;
  @override
  ValidatedUiPlan get current => substitution ?? super.current;
}
