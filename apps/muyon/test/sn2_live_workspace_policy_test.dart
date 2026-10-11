import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart' show actionPlan;
import 'support/agent_loop_fixture.dart';
import 'support/ui_public_fixture.dart' show comparisonFixture;

// SN-2 exercises the already-open production workspace, including callbacks
// saved by an old rendered tree. The SQLite, preferences, agent and session are
// real; the planning provider is public fixture data and no model is approved.
void main() {
  LiveTestWidgetsFlutterBinding();

  Future<_LiveWorkspace> open(
    WidgetTester tester, {
    UiPresentationMode mode = UiPresentationMode.automatic,
    bool explicit = false,
    bool batch = false,
  }) async {
    final f = (await tester.runAsync(LoopFixture.open))!;
    final preference = UiPresentationPreference(f.repo);
    await tester.runAsync(() => preference.save(mode));
    final base = actionPlan();
    final candidate = base.plan.copyWith(nodes: [
      for (final node in base.plan.nodes)
        if (batch && node.id == 'confirm')
          node.copyWith(component: 'BatchConfirmCard')
        else
          node,
    ]);
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      presentationPreference: preference,
      uiPlanningSource: (_) async => UiPlanningHostState(
        snapshot: base.snapshot,
        intent: base.intent,
        currentView: UiCurrentView(
          surfaceId: candidate.surfaceId,
          revision: candidate.revision - 1,
          values: base.snapshot.initialUiState,
        ),
        catalog: base.catalog,
        allowedActionRefs: base.intent.allowedActionRefs,
      ),
      uiPlanningProviders: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider(
          (_) async => UiPlanningResult(
            decision: UiDisplayDecision.supplement,
            reasonCode: 'public-live-policy-regression',
            plan: candidate,
          ),
        ),
      },
    );
    addTearDown(() async {
      await agent.close();
      await preference.close();
    });
    final task = (await tester.runAsync(() => f.start(agent, f.profile())))!;
    final presentation = (await tester.runAsync(() => explicit
        ? agent.planUiFromUserControl(task.id)
        : agent.planUi(task.id)))!;
    expect(presentation.validated, isNotNull,
        reason: presentation.result.reasonCode);
    final events = <UiEvent>[];
    final answer = comparisonFixture().answer;
    final workspace = DynamicWorkspace(
      repository: f.repo,
      taskId: task.id,
      surfaceId: candidate.surfaceId,
      plan: presentation.validated!,
      agent: agent,
      tools: f.tools,
      originalAnswer: answer,
      onEvent: (event) async => events.add(event),
      embedded: true,
    );
    final session = DynamicWorkspaceSession(workspace);
    addTearDown(session.dispose);
    await tester.runAsync(session.ensureLoaded);
    expect(session.error, isNull);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DynamicWorkspace(
      repository: f.repo,
      taskId: task.id,
      surfaceId: candidate.surfaceId,
      plan: presentation.validated!,
      agent: agent,
      tools: f.tools,
      originalAnswer: answer,
      onEvent: workspace.onEvent,
      session: session,
      embedded: true,
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(DynamicUiSurface), findsOneWidget);
    expect(f.bodies, isEmpty);
    return _LiveWorkspace(f, agent, session, task.id, answer, events);
  }

  for (final next in [UiPresentationMode.few, UiPresentationMode.textOnly]) {
    testWidgets('open automatic workspace loses content after ${next.name}',
        (tester) async {
      final live = await open(tester);
      await tester.runAsync(() => live.agent.savePresentationMode(next));
      await tester.pumpAndSettle();
      expect(find.byType(DynamicUiSurface), findsNothing);
      expect(find.byType(ConfirmCard), findsNothing);
      expect(find.text(live.answer), findsOneWidget);
      expect(live.f.bodies, isEmpty);
    });

    testWidgets('captured automatic callbacks cannot dispatch after ${next.name}',
        (tester) async {
      final live = await open(tester);
      final confirm = tester.widget<ConfirmCard>(find.byType(ConfirmCard)).onDecision!;
      final explain = tester.widget<WarnBanner>(find.byType(WarnBanner)).onAction!;
      final edit = tester.widget<TextFormField>(find.byType(TextFormField)).onChanged!;
      final surface = live.session.controller!.surface;
      final before = surface.session.resolve(const BindingRef.uiState('quantity'));
      await tester.runAsync(() => live.agent.savePresentationMode(next));
      // Invoke before rebuilding too: presentation revocation must fence the
      // saved callback even while the old tree is still mounted.
      edit('999');
      explain();
      confirm(ConfirmationChoice.once);
      await tester.pumpAndSettle();
      expect(surface.session.resolve(const BindingRef.uiState('quantity')), before);
      expect(live.events, isEmpty);
      expect(live.f.callsOf('write'), 0);
      expect(live.f.bodies, isEmpty);
    });
  }

  testWidgets('few explicit workspace stays revoked through textOnly then few',
      (tester) async {
    final live = await open(tester, mode: UiPresentationMode.few, explicit: true);
    final confirm = tester.widget<ConfirmCard>(find.byType(ConfirmCard)).onDecision!;
    final explain = tester.widget<WarnBanner>(find.byType(WarnBanner)).onAction!;
    await tester.runAsync(() => live.agent.savePresentationMode(UiPresentationMode.textOnly));
    await tester.pumpAndSettle();
    expect(find.byType(DynamicUiSurface), findsNothing);
    await tester.runAsync(() => live.agent.savePresentationMode(UiPresentationMode.few));
    await tester.pumpAndSettle();
    expect(find.byType(DynamicUiSurface), findsNothing,
        reason: 'Returning to few cannot renew an old explicit user request');
    explain();
    confirm(ConfirmationChoice.once);
    await tester.pumpAndSettle();
    expect(live.events, isEmpty);
    expect(find.text(live.answer), findsOneWidget);
    expect(live.f.bodies, isEmpty);
  });

  testWidgets('batch individual control is disabled without an individual route',
      (tester) async {
    final live = await open(tester, batch: true);
    await tester.runAsync(() => live.f.repo.authorizationFacts.markExternal(
      live.taskId, HostSourceFact.object(live.f.ref)));
    live.f.repo.refresh();
    await tester.pumpAndSettle();
    expect(find.text('全部允许'), findsNothing);
    final individual = find.widgetWithText(TextButton, '逐项决定');
    expect(individual, findsOneWidget);
    expect(tester.widget<TextButton>(individual).onPressed, isNull);
    expect(tester.widget<BatchConfirmCard>(find.byType(BatchConfirmCard)).onIndividual, isNull);
    await tester.ensureVisible(individual);
    await tester.tap(individual);
    await tester.pumpAndSettle();
    expect(live.events, isEmpty);
    expect(live.f.callsOf('write'), 0);
    expect(live.f.bodies, isEmpty);
  });

  testWidgets('taint updates live confirmation and rejects old clean callback',
      (tester) async {
    final live = await open(tester);
    final oldCard = tester.widget<ConfirmCard>(find.byType(ConfirmCard));
    expect(oldCard.externalContent, isFalse);
    final cleanConfirm = oldCard.onDecision!;
    await tester.runAsync(() => live.f.repo.authorizationFacts.markExternal(
      live.taskId, HostSourceFact.object(live.f.ref)));
    live.f.repo.refresh();
    await tester.pumpAndSettle();
    final card = tester.widget<ConfirmCard>(find.byType(ConfirmCard));
    expect(card.externalContent, isTrue);
    expect(find.descendant(of: find.byType(ConfirmCard), matching: find.byType(WarnBanner)), findsOneWidget);
    cleanConfirm(ConfirmationChoice.once);
    await tester.pumpAndSettle();
    expect(live.events, isEmpty);
    expect(live.f.callsOf('write'), 0);
    expect(live.f.bodies, isEmpty);
    // A newly rendered per-action confirmation remains available; provenance
    // changes invalidate the old capture rather than disabling every action.
    expect(card.onDecision, isNotNull);
    card.onDecision!(ConfirmationChoice.once);
    await tester.pumpAndSettle();
    expect(live.events, hasLength(1));
    expect(live.events.single.kind, 'confirm');
  });
}

class _LiveWorkspace {
  const _LiveWorkspace(this.f, this.agent, this.session, this.taskId,
      this.answer, this.events);
  final LoopFixture f;
  final PersonalAgent agent;
  final DynamicWorkspaceSession session;
  final String taskId, answer;
  final List<UiEvent> events;
}
