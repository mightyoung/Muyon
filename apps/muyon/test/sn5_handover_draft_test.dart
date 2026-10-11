import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart' show actionPlan;
import '../../../packages/muyon_ui/test/aiui5_revision2_review_test.dart'
    show reviewPlan;
import 'support/agent_loop_fixture.dart';

void main() {
  for (final operation in ['adopt', 'surface adopt', 'restore', 'discard']) {
    test(
      'new synchronous host identity fences old $operation before source and notification',
      () async {
        final f = await LoopFixture.open();
        final preference = UiPresentationPreference(f.repo);
        await preference.save(UiPresentationMode.automatic);
        final recovery = operation == 'restore' || operation == 'discard';
        final plan = recovery ? reviewPlan('NumberStepper') : actionPlan();
        final field = recovery ? 'k' : 'quantity';
        final release = Completer<void>();
        final entered = Completer<void>();
        var blockSource = false;
        final agent = PersonalAgent(
          repository: f.repo,
          tools: f.tools,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          presentationPreference: preference,
          uiPlanningSource: (_) async {
            if (blockSource) {
              if (!entered.isCompleted) entered.complete();
              await release.future;
            }
            return UiPlanningHostState(
              snapshot: plan.snapshot,
              intent: plan.intent,
              catalog: plan.catalog,
              allowedActionRefs: plan.intent.allowedActionRefs,
              currentView: UiCurrentView(
                surfaceId: plan.plan.surfaceId,
                revision: plan.plan.revision - 1,
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
        addTearDown(agent.close);
        final task = await f.start(agent, f.profile());
        await f.repo.updateTask(task.copy({'summary': 'Public answer'}));
        final presentation = await agent.planUi(task.id);
        expect(presentation.validated, isNotNull);
        final store = HostUiWorkspaceStore(f.repo, taskId: task.id);
        final seed = await UiWorkspaceController.open(
          store: store,
          taskId: task.id,
          scopeKey: store.scopeKey!,
          plan: plan,
        );
        seed.surface.session.edit(field, recovery ? 9.0 : '12');
        if (!recovery) seed.surface.session.edit(field, '20');
        await seed.flush();
        seed.dispose();
        if (recovery) {
          final old = (await store.load(plan.plan.surfaceId))!;
          final raw = old.toJson();
          raw['userOverrides'] = <String, Object?>{};
          raw['readableDraft'] = {'k': 9.0};
          raw['revision'] = old.revision + 1;
          expect(
            await store.save(
              StoredUiWorkspace.fromJson(raw),
              expectedRevision: old.revision,
            ),
            isTrue,
          );
        }
        final session = DynamicWorkspaceSession(
          DynamicWorkspace(
            repository: f.repo,
            taskId: task.id,
            surfaceId: plan.plan.surfaceId,
            plan: presentation.validated!,
            agent: agent,
          ),
        );
        addTearDown(session.dispose);
        await session.ensureLoaded();
        expect(session.error, isNull);
        final c = session.controller!;
        final before = jsonEncode(
          (await store.load(plan.plan.surfaceId))!.toJson(),
        );
        final revision = c.surface.session.draftRevision;
        final value = c.surface.session.resolve(BindingRef.uiState(field));
        final quarantined = Map.of(c.quarantinedDraft);
        Future<void> callback() => operation == 'surface adopt'
            ? Future.sync(() => c.surface.adoptExtracted(field))
            : operation == 'adopt'
            ? c.adoptExtracted(field)
            : c.resolveDraft(field, discard: operation == 'discard');
        blockSource = true;
        final fresh = agent.planUiFromUserControl(task.id);
        try {
          expect(session.allowsPresentation, isFalse);
          if (recovery) {
            await expectLater(callback(), throwsStateError);
          } else {
            expect(
              c.readOnly,
              isFalse,
              reason: 'Repository notification has not fenced the controller',
            );
            await callback();
          }
          expect(c.surface.session.resolve(BindingRef.uiState(field)), value);
          expect(c.surface.session.draftRevision, revision);
          expect(c.quarantinedDraft, quarantined);
          expect(
            jsonEncode((await store.load(plan.plan.surfaceId))!.toJson()),
            before,
          );
          await entered.future;
          expect(f.bodies, isEmpty);
        } finally {
          if (!release.isCompleted) release.complete();
          await fresh;
        }
      },
    );
  }
}
