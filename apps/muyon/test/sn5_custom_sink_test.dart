import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart' show actionPlan;
import 'support/agent_loop_fixture.dart';

void main() {
  for (final terminal in ['cancelled', 'interrupted', 'active']) {
    test(
      'custom sink rejects $terminal task after real host transition',
      () async {
        final f = await LoopFixture.open();
        final plan = actionPlan();
        final agent = PersonalAgent(
          repository: f.repo,
          tools: f.tools,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          uiPlanningEnabled: true,
          uiPlanningSource: (_) async => UiPlanningHostState(
            snapshot: plan.snapshot,
            intent: plan.intent,
            catalog: plan.catalog,
            allowedActionRefs: plan.intent.allowedActionRefs,
            currentView: UiCurrentView(
              surfaceId: plan.plan.surfaceId,
              revision: plan.plan.revision,
            ),
          ),
        );
        addTearDown(agent.close);
        final task = await f.start(agent, f.profile());
        final events = <UiEvent>[];
        final session = DynamicWorkspaceSession(
          DynamicWorkspace(
            repository: f.repo,
            agent: agent,
            taskId: task.id,
            surfaceId: plan.plan.surfaceId,
            plan: plan,
            onEvent: (e) async => events.add(e),
          ),
        );
        addTearDown(session.dispose);
        await session.ensureLoaded();
        expect(session.error, isNull);
        final sink = session.controller!.surface.onEvent!;
        final node = plan.plan.nodes.firstWhere(
          (n) => n.events.containsKey('tap'),
        );
        final event = session.controller!.surface.eventFor(node, 'tap');
        if (terminal == 'cancelled') {
          await agent.cancel(task.id);
          expect(f.repo.task(task.id)!.state, PersonalTaskState.cancelled);
        } else if (terminal == 'interrupted') {
          await f.repo.updateTask(
            f.repo.task(task.id)!.copy({'state': 'interrupted'}),
          );
          expect(f.repo.task(task.id)!.state, PersonalTaskState.interrupted);
        }
        expect(
          session.allowsPresentation,
          isTrue,
          reason: 'Terminal refusal must be exercised independently of preference revocation',
        );
        if (terminal == 'active') {
          await sink(event);
          expect(events, hasLength(1));
        } else {
          await expectLater(sink(event), throwsStateError);
          expect(events, isEmpty);
        }
        expect(f.bodies, isEmpty);
        expect(f.callsOf('write'), 0);
      },
    );
  }
}
