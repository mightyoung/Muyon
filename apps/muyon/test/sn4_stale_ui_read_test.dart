import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/screens/ui_stream_task_view.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'aiui6_stream_production_test.dart' show state, validStream;
import 'support/agent_loop_fixture.dart';

UiPlanningHostState _host(LoopFixture f, int revision) {
  final base = state(f);
  final snapshot = DataSnapshot(
    ref: SnapshotRef('saved', revision),
    facts: base.snapshot.facts,
  );
  return UiPlanningHostState(
    snapshot: snapshot,
    intent: InteractionIntent(
      id: base.intent.id,
      purpose: base.intent.purpose,
      snapshotRef: snapshot.ref,
      requiredBindings: base.intent.requiredBindings,
    ),
    currentView: base.currentView,
    catalog: base.catalog,
    allowedActionRefs: const {},
  );
}

void main() {
  // Removing the renderer's pre-reconcile lifetime fence makes these fail:
  // stale reads must not mutate harness ownership even after dispose/refresh.
  for (final phase in ['fallback', 'preview']) {
    for (final boundary in ['dispose', 'refresh', 'retarget']) {
      for (final outcome in ['changed', 'null', 'throw']) {
        testWidgets('SN4 stale $phase $outcome after $boundary', (tester) async {
          final f = (await tester.runAsync(LoopFixture.open))!;
          final pending = Completer<UiPlanningHostState?>();
          final enteredRead = Completer<void>();
          final enteredStream = Completer<void>();
          final releaseStream = Completer<void>();
          String? heldTask;
          var holdNextRead = false;
          final provider = StreamMotivationUiPlanningProvider((request, _, receive) async {
            receive(validStream.replaceAll('{"op":"end"}\n', ''));
            if (phase == 'preview' && request.taskId == heldTask) {
              enteredStream.complete();
              await releaseStream.future;
            }
            // Missing end intentionally produces a zero-capability fallback.
          });
          final agent = PersonalAgent(
            repository: f.repo,
            gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
            tools: f.tools,
            uiPlanningSource: (task) {
              if (holdNextRead && task.id == heldTask) {
                holdNextRead = false;
                enteredRead.complete();
                return pending.future;
              }
              return Future.value(_host(f, task.id == heldTask ? 1 : 2));
            },
            uiPlanningMode: UiPlanningMode.motivation,
            uiPlanningProviders: {UiPlanningMode.motivation: provider},
          );
          Future<PersonalTask> start() async {
            final conversation = await f.repo.createConversation();
            final task = await agent.start(
              conversationId: conversation.id,
              prompt: 'saved facts',
              profile: f.profile(),
            );
            await f.repo.updateTask(task.copy({
              'state': 'running', 'stage': 'model', 'summary': 'Saved answer',
            }));
            await f.repo.appendMessage(conversation.id, 'assistant', 'Saved answer');
            return task;
          }
          Future<UiPlannedPresentation>? planning;
          try {
            final a = (await tester.runAsync(start))!;
            final b = (await tester.runAsync(start))!;
            heldTask = a.id;
            await tester.runAsync(() => agent.planUi(b.id));
            await tester.runAsync(() => agent.cancel(b.id));
            await tester.runAsync(() async {
              planning = agent.planUi(a.id);
              if (phase == 'preview') {
                await Future.any([
                  enteredStream.future,
                  planning!.then((_) => throw StateError('stream_not_entered')),
                ]);
              } else {
                await planning;
                await agent.cancel(a.id);
              }
            });
            final owner = boundary == 'retarget' ? b.id : a.id;
            final presentation = agent.uiPresentation(owner);
            final progress = agent.uiStreamProgress(owner)!;
            final request = progress.request;
            expect(agent.isCurrentUiRequest(request), isTrue);
            holdNextRead = true;
            Widget view(String id) => MaterialApp(home: UiStreamTaskView(agent: agent, taskId: id));
            await tester.pumpWidget(view(a.id));
            expect(enteredRead.isCompleted, isTrue, reason: 'old source read is actually blocked');
            final originalState = tester.state(find.byType(UiStreamTaskView));
            if (boundary == 'dispose') {
              await tester.pumpWidget(const SizedBox.shrink());
            } else if (boundary == 'retarget') {
              await tester.pumpWidget(view(b.id));
              expect(tester.state(find.byType(UiStreamTaskView)), same(originalState));
            } else {
              f.repo.refresh();
            }
            await tester.pump();
            if (boundary != 'dispose') {
              expect(find.text('保存事实'), findsWidgets, reason: 'new read completed before the old one');
            }
            await tester.runAsync(() async {
              if (outcome == 'throw') {
                pending.completeError(StateError('late_source_refusal'));
              } else {
                pending.complete(outcome == 'null' ? null : _host(f, 99));
              }
            });
            await tester.pump();
            expect(agent.isCurrentUiRequest(request), isTrue,
                reason: 'a stale read must not delete the current request identity');
            expect(agent.uiStreamProgress(owner), same(progress));
            expect(agent.uiPresentation(owner), same(presentation));
            if (boundary != 'dispose') expect(find.text('保存事实'), findsWidgets);
            expect(find.byType(DynamicUiSurface), findsNothing);
            expect(find.byType(ElevatedButton), findsNothing);
            expect(f.bodies, isEmpty);
            expect(f.tools.history(), isEmpty);
          } finally {
            if (!pending.isCompleted) pending.complete(null);
            if (!releaseStream.isCompleted) releaseStream.complete();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() async {
              await planning;
              await agent.close();
            });
          }
        });
      }
    }
  }
}
