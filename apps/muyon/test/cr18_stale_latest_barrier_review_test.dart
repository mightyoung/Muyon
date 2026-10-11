import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/conversation_workspace_pane.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart' show actionPlan;
import 'support/agent_loop_fixture.dart';
import 'support/conversation_workspace_fixture.dart';

class _HeldReplacement {
  final entered = Completer<void>();
  final release = Completer<UiPlanningHostState?>();
  bool hold = false;
  late LoopFixture f;
  late PersonalAgent agent;
  late PersonalTask task;
  late UiPlannedPresentation first;
  late Future<UiPlannedPresentation> pending;
  final plan = actionPlan();

  UiPlanningHostState get hostState => UiPlanningHostState(
    snapshot: plan.snapshot,
    intent: plan.intent,
    catalog: plan.catalog,
    allowedActionRefs: plan.intent.allowedActionRefs,
    currentView: UiCurrentView(
      surfaceId: plan.plan.surfaceId,
      revision: plan.plan.revision - 1,
    ),
  );

  Future<void> open() async {
    f = await LoopFixture.open();
    final preference = UiPresentationPreference(f.repo);
    await preference.save(UiPresentationMode.automatic);
    agent = PersonalAgent(
      repository: f.repo,
      tools: f.tools,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      presentationPreference: preference,
      uiPlanningSource: (_) {
        if (hold) {
          if (!entered.isCompleted) entered.complete();
          return release.future;
        }
        return Future.value(
          UiPlanningHostState(
            snapshot: plan.snapshot,
            intent: plan.intent,
            catalog: plan.catalog,
            allowedActionRefs: plan.intent.allowedActionRefs,
            currentView: UiCurrentView(
              surfaceId: plan.plan.surfaceId,
              revision: plan.plan.revision - 1,
            ),
          ),
        );
      },
      uiPlanningProviders: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider(
          (_) async => UiPlanningResult(
            decision: UiDisplayDecision.supplement,
            reasonCode: 'fixture',
            plan: plan.plan,
          ),
        ),
      },
    );
    task = await f.start(agent, f.profile());
    await f.repo.updateTask(task.copy({'summary': 'Public answer'}));
    first = await agent.planUiFromUserControl(task.id);
    expect(first.validated, isNotNull);
    expect(agent.isCurrentUiRequest(first.request!), isTrue);
  }

  Future<void> replace() async {
    final oldIdentity = agent.uiContentIdentity(task.id);
    hold = true;
    pending = agent.planUiFromUserControl(task.id);
    await entered.future;
    expect(agent.uiContentIdentity(task.id), isNot(same(oldIdentity)));
    expect(agent.isCurrentUiRequest(first.request!), isFalse);
  }

  DynamicWorkspace workspace({DynamicWorkspaceSession? session}) =>
      DynamicWorkspace(
        repository: f.repo,
        taskId: task.id,
        surfaceId: plan.plan.surfaceId,
        plan: first.validated!,
        agent: agent,
        session: session,
      );

  Future<void> close([WidgetTester? tester]) async {
    if (!release.isCompleted) release.complete(null);
    if (tester != null) {
      await workspaceOperation(tester, () async {
        await pending;
      });
      await workspaceOperation(tester, agent.close);
    } else {
      await pending;
      await agent.close();
    }
  }
}

void main() {
  testWidgets(
    'pane close barrier must not reauthorize queued B1 after B2 completes',
    (tester) async {
      final h = _HeldReplacement();
      await workspaceOperation(tester, h.open);
      final enteredClose = Completer<void>();
      final releaseClose = Completer<void>();
      WorkspaceOpener? opener;
      DynamicWorkspaceSession? next;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        final a = (await workspaceOperation(
          tester,
          () => h.f.start(h.agent, h.f.profile()),
        ));
        await tester.pumpWidget(
          MaterialApp(
            home: ConversationWorkspaceHost(
              builder: (context, open) {
                opener = open;
                return const Scaffold(body: Text('parent'));
              },
            ),
          ),
        );
        await opener!(
          DynamicWorkspace(
            repository: h.f.repo,
            taskId: a.id,
            surfaceId: h.plan.plan.surfaceId,
            plan: h.plan,
          ),
        );
        await tester.pump();
        final previous = tester
            .widget<DynamicWorkspace>(find.byType(DynamicWorkspace))
            .session!;
        await workspaceOperation(tester, previous.ensureLoaded);
        await tester.pump();
        final queuedB = h.workspace();
        final closeStore = _CloseBarrierStore(
          HostUiWorkspaceStore(h.f.repo, taskId: a.id),
          enteredClose,
          releaseClose,
        );
        previous.controller!.dispose();
        previous.controller = await workspaceOperation(
          tester,
          () => UiWorkspaceController.open(
            store: closeStore,
            taskId: a.id,
            scopeKey: closeStore.host.scopeKey!,
            plan: h.plan,
          ),
        );
        closeStore.hold = true;
        var openFinished = false;
        final opening = opener!(queuedB).then((_) => openFinished = true);
        await workspaceOperation(tester, () async {
          await enteredClose.future;
        });
        expect(openFinished, isFalse);
        expect(
          tester.widget<DynamicWorkspace>(find.byType(DynamicWorkspace)).taskId,
          a.id,
        );
        await workspaceOperation(tester, h.replace);
        await workspaceOperation(tester, () async {
          h.release.complete(h.hostState);
          final second = await h.pending;
          expect(second.validated, isNotNull);
          expect(second.request, isNot(same(h.first.request)));
          expect(h.agent.isCurrentUiRequest(second.request!), isTrue);
          releaseClose.complete();
        });
        await workspaceOperation(tester, () async {
          await opening;
        });
        await tester.pump();
        final views = find.byType(DynamicWorkspace).evaluate();
        next = views.isEmpty
            ? null
            : (views.single.widget as DynamicWorkspace).session;
        if (next != null) await workspaceOperation(tester, next.ensureLoaded);
        await tester.pump();
        final c = next?.controller;
        if (c != null) {
          await workspaceOperation(tester, () async {
            c.step = 'CR18_QUEUED_B1_SAVED';
            await next!.checkpoint();
          });
        }
        final stored = await tester.runAsync(
          () => HostUiWorkspaceStore(
            h.f.repo,
            taskId: h.task.id,
          ).load(h.plan.plan.surfaceId),
        );
        final displayed = find.text('Public comparison').evaluate().isNotEmpty;
        debugPrintSynchronously(
          'CR18_CLOSE_BARRIER ${jsonEncode({'closeBarrierEntered': enteredClose.isCompleted, 'B2CompletedBeforeCloseReleased': h.release.isCompleted, 'oldRequestCurrent': h.agent.isCurrentUiRequest(h.first.request!), 'queuedPlanInstalled': identical(c?.surface.current, h.first.validated), 'sessionAllowsPresentation': next?.allowsPresentation, 'oldTitleDisplayed': displayed, 'storedOldStep': stored?.step, 'storedRevision': stored?.revision, 'modelRequests': h.f.bodies.length, 'toolHistory': h.f.tools.history().length})}',
        );
        expect(
          {'oldTitleDisplayed': displayed, 'storedOldStep': stored?.step},
          {'oldTitleDisplayed': false, 'storedOldStep': null},
          reason: 'queued B1 same-surface plan must not acquire B2 ownership',
        );
      } finally {
        if (!releaseClose.isCompleted) releaseClose.complete();
        next?.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await workspaceReady(tester);
        await h.close(tester);
      }
    },
  );
  test('B2 source barrier must synchronously hide B1 validated presentation', () async {
    final h = _HeldReplacement();
    await h.open();
    addTearDown(h.close);
    await h.replace();
    final observed = h.agent.uiPresentation(h.task.id);
    debugPrintSynchronously(
      'CR18_SOURCE_BARRIER ${jsonEncode({'barrierEntered': h.entered.isCompleted, 'barrierReleased': h.release.isCompleted, 'oldRequestCurrent': h.agent.isCurrentUiRequest(h.first.request!), 'oldPresentationReturned': identical(observed, h.first), 'oldValidatedReturned': observed?.validated != null, 'modelRequests': h.f.bodies.length, 'toolHistory': h.f.tools.history().length})}',
    );
    expect(
      observed?.validated,
      isNull,
      reason: 'B1 is stale before B2 source resolves',
    );
  });

  testWidgets('new B2-identity session must not display or save captured B1', (
    tester,
  ) async {
    final h = _HeldReplacement();
    await workspaceOperation(tester, h.open);
    DynamicWorkspaceSession? session;
    try {
      await workspaceOperation(tester, h.replace);
      final store = HostUiWorkspaceStore(h.f.repo, taskId: h.task.id);
      expect(
        await tester.runAsync(() => store.load(h.plan.plan.surfaceId)),
        isNull,
      );
      session = DynamicWorkspaceSession(h.workspace());
      await workspaceOperation(tester, session.ensureLoaded);
      final controller = session.controller;
      await tester.pumpWidget(MaterialApp(home: h.workspace(session: session)));
      await tester.pump();
      final displayed = find.text('Public comparison').evaluate().isNotEmpty;
      if (controller != null) {
        await workspaceOperation(tester, () async {
          controller.step = 'CR18_STALE_B1_SAVED';
          await controller.adoptExtracted('quantity');
          await controller.flush();
        });
      }
      final saved = await tester.runAsync(
        () => store.load(h.plan.plan.surfaceId),
      );
      final observed = {
        'barrierEntered': h.entered.isCompleted,
        'barrierReleased': h.release.isCompleted,
        'oldRequestCurrent': h.agent.isCurrentUiRequest(h.first.request!),
        'sessionAllowsPresentation': session.allowsPresentation,
        'controllerReadOnly': controller?.readOnly,
        'oldTitleDisplayed': displayed,
        'storedOldStep': saved?.step,
        'storedRevision': saved?.revision,
        'modelRequests': h.f.bodies.length,
        'toolHistory': h.f.tools.history().length,
      };
      debugPrintSynchronously(
        'CR18_NEW_SESSION_BARRIER ${jsonEncode(observed)}',
      );
      expect(
        {
          'oldTitleDisplayed': displayed,
          'storedOldStep': saved?.step,
          'sessionAllowsPresentation': session.allowsPresentation,
        },
        {
          'oldTitleDisplayed': false,
          'storedOldStep': null,
          'sessionAllowsPresentation': false,
        },
        reason:
            'B2 identity must not reauthorize captured B1 content/checkpoint',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session?.dispose();
      await h.close(tester);
    }
  });
}

class _CloseBarrierStore implements UiWorkspaceStore {
  _CloseBarrierStore(this.host, this.entered, this.release);
  final HostUiWorkspaceStore host;
  final Completer<void> entered, release;
  bool hold = false;
  @override
  Future<StoredUiWorkspace?> load(String surfaceId) => host.load(surfaceId);
  @override
  Future<bool> save(
    StoredUiWorkspace value, {
    required int expectedRevision,
  }) async {
    if (hold) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return host.save(value, expectedRevision: expectedRevision);
  }
}
