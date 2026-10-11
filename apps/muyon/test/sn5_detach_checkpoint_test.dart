import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart' show actionPlan;
import 'support/agent_loop_fixture.dart';

void main() {
  for (final change in [
    'normal',
    'cancel before detach',
    'identity after detach',
    'identity after save queued',
  ]) {
    test('real native detach checkpoints only live host authority: $change', () async {
      final f = await LoopFixture.open();
      final preference = UiPresentationPreference(f.repo);
      await preference.save(UiPresentationMode.automatic);
      final plan = actionPlan();
      final agent = PersonalAgent(
        repository: f.repo,
        tools: f.tools,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        presentationPreference: preference,
        uiPlanningSource: (_) async => UiPlanningHostState(
          snapshot: plan.snapshot,
          intent: plan.intent,
          catalog: plan.catalog,
          allowedActionRefs: plan.intent.allowedActionRefs,
          currentView: UiCurrentView(
            surfaceId: plan.plan.surfaceId,
            revision: plan.plan.revision - 1,
          ),
        ),
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
      final session = DynamicWorkspaceSession(
        DynamicWorkspace(
          repository: f.repo,
          taskId: task.id,
          surfaceId: plan.plan.surfaceId,
          plan: plan,
          agent: agent,
        ),
      );
      addTearDown(session.dispose);
      await session.ensureLoaded();
      expect(session.error, isNull);
      final c = session.controller!;
      final store = HostUiWorkspaceStore(f.repo, taskId: task.id);
      await c.flush();
      if (change == 'cancel before detach') {
        await agent.cancel(task.id);
        await Future<void>(() {});
        await f.repo.database.write((_) {});
      }
      final before = (await store.load(plan.plan.surfaceId))!;
      // Native pane disposal captures presentation immediately, without an
      // awaited close or a controller change notification to save it first.
      c.step = 'last native view';
      c.scrollOffset = 321;
      c.selectedRecords = ['native-selected'];
      final entered = Completer<void>();
      final release = Completer<void>();
      Future<void>? blocked;
      if (change == 'identity after save queued') {
        blocked = (f.repo.database as ManagedConnection).exclusiveAsync((
          _,
        ) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
      }
      session.detachWithBestEffortCheckpoint();
      expect(session.allowsPresentation, isFalse);
      Future<Object?>? replacement;
      if (change == 'identity after detach') {
        replacement = agent.planUiFromUserControl(task.id);
      }
      // One event-loop turn admits the queued flush before this SQLite barrier;
      // the barrier then waits for every submitted write. No timing sleep.
      await Future<void>(() {});
      if (change == 'identity after save queued') {
        // The controller's queued guard has run, but SQLite cannot yet execute
        // its submitted save. Identity revocation is synchronous.
        replacement = agent.planUiFromUserControl(task.id);
        release.complete();
        await blocked;
      }
      await f.repo.database.write((_) {});
      if (replacement != null) {
        await replacement;
      }
      final saved = (await store.load(plan.plan.surfaceId))!;
      if (change == 'normal') {
        expect(saved.step, 'last native view');
        expect(saved.scrollOffset, 321);
        expect(saved.selectedRecords, ['native-selected']);
        expect(saved.revision, before.revision + 1);
        // Disposal must not authorize new captures through a retained flush.
        c.scrollOffset = 777;
        await c.flush();
        await f.repo.database.write((_) {});
        expect(
          jsonEncode((await store.load(plan.plan.surfaceId))!.toJson()),
          jsonEncode(saved.toJson()),
        );
      } else {
        expect(jsonEncode(saved.toJson()), jsonEncode(before.toJson()));
      }
      expect(f.bodies, isEmpty);
      expect(f.callsOf('write'), 0);
    });
  }
}
