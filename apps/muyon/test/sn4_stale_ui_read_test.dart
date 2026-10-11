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

// Injected providers do not have access to the agent's private publish hook.
// Feed their real compiler progress to the renderer while planning is pending;
// terminal results and request ownership still come from the production agent.
class _PreviewAgent extends PersonalAgent {
  _PreviewAgent({
    required super.repository,
    required super.gateway,
    required super.tools,
    required super.uiPlanningSource,
    required super.uiPlanningMode,
    required super.uiPlanningProviders,
    required this.pendingProgress,
  });
  final Map<String, HostUiStreamProgress> pendingProgress;

  @override
  HostUiStreamProgress? uiStreamProgress(String taskId) {
    final stored = super.uiStreamProgress(taskId);
    if (stored != null) return stored;
    final pending = pendingProgress[taskId];
    return pending != null && isCurrentUiRequest(pending.request)
        ? pending
        : null;
  }
}

void main() {
  // Removing the renderer's pre-reconcile lifetime fence makes these fail:
  // stale reads must not mutate harness ownership even after dispose/refresh.
  for (final phase in ['fallback', 'preview']) {
    for (final boundary in [
      'dispose',
      'refresh',
      'retarget',
      if (phase == 'fallback') ...['replace', 'current'],
      if (phase == 'preview') 'cancel',
    ]) {
      for (final outcome in ['changed', 'null', 'throw']) {
        testWidgets('SN4 stale $phase $outcome after $boundary', (
          tester,
        ) async {
          final f = (await tester.runAsync(LoopFixture.open))!;
          final pending = Completer<UiPlanningHostState?>();
          final enteredRead = Completer<void>();
          final enteredStream = Completer<void>();
          final releaseStream = Completer<void>();
          String? heldTask;
          var holdNextRead = false;
          var aRevision = 1;
          final pendingProgress = <String, HostUiStreamProgress>{};
          final provider = StreamMotivationUiPlanningProvider(
            (request, _, receive) async {
              receive(validStream.replaceAll('{"op":"end"}\n', ''));
              if (phase == 'preview' && request.taskId == heldTask) {
                enteredStream.complete();
                await releaseStream.future;
              }
              // Missing end intentionally produces a zero-capability fallback.
            },
            onProgress: (progress) =>
                pendingProgress[progress.request.taskId] = progress,
          );
          final agent = _PreviewAgent(
            pendingProgress: pendingProgress,
            repository: f.repo,
            gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
            tools: f.tools,
            uiPlanningSource: (task) {
              if (holdNextRead && task.id == heldTask) {
                holdNextRead = false;
                enteredRead.complete();
                return pending.future;
              }
              return Future.value(
                _host(f, task.id == heldTask ? aRevision : 2),
              );
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
            await f.repo.updateTask(
              task.copy({
                'state': 'running',
                'stage': 'model',
                'summary': 'Saved answer',
              }),
            );
            await f.repo.appendMessage(
              conversation.id,
              'assistant',
              'Saved answer',
            );
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
                  planning!.then((_) {
                    if (!enteredStream.isCompleted) {
                      throw StateError('stream_not_entered');
                    }
                  }),
                ]);
              } else {
                await planning;
                if (boundary != 'replace') await agent.cancel(a.id);
              }
            });
            final owner = boundary == 'retarget' ? b.id : a.id;
            var presentation = agent.uiPresentation(owner);
            var progress = agent.uiStreamProgress(owner)!;
            var request = progress.request;
            expect(agent.isCurrentUiRequest(request), isTrue);
            holdNextRead = true;
            Widget view(String id) => MaterialApp(
              home: UiStreamTaskView(agent: agent, taskId: id),
            );
            await tester.pumpWidget(view(a.id));
            expect(
              enteredRead.isCompleted,
              isTrue,
              reason: 'old source read is actually blocked',
            );
            final originalState = tester.state(find.byType(UiStreamTaskView));
            if (boundary == 'dispose') {
              await tester.pumpWidget(const SizedBox.shrink());
            } else if (boundary == 'retarget') {
              await tester.pumpWidget(view(b.id));
              expect(
                tester.state(find.byType(UiStreamTaskView)),
                same(originalState),
              );
            } else if (boundary == 'cancel') {
              await tester.runAsync(() => agent.cancel(a.id));
              presentation = agent.uiPresentation(owner);
              progress = agent.uiStreamProgress(owner)!;
              expect(progress.request, same(request));
              expect(presentation?.validated, isNull);
            } else if (boundary == 'replace') {
              final oldRequest = request;
              aRevision = 3;
              await tester.runAsync(() => agent.planUiFromUserControl(a.id));
              await tester.runAsync(() => agent.cancel(a.id));
              presentation = agent.uiPresentation(owner);
              progress = agent.uiStreamProgress(owner)!;
              request = progress.request;
              expect(request, isNot(same(oldRequest)));
              expect(agent.isCurrentUiRequest(oldRequest), isFalse);
              expect(agent.isCurrentUiRequest(request), isTrue);
            } else if (boundary != 'current') {
              f.repo.refresh();
            }
            await tester.pump();
            if (boundary != 'dispose' && boundary != 'current') {
              expect(
                find.text('保存事实'),
                findsWidgets,
                reason: 'new read completed before the old one',
              );
            }
            await tester.runAsync(() async {
              if (outcome == 'throw') {
                pending.completeError(StateError('late_source_refusal'));
              } else {
                pending.complete(outcome == 'null' ? null : _host(f, 99));
              }
            });
            await tester.pump();
            if (boundary == 'current') {
              expect(agent.isCurrentUiRequest(request), isFalse);
              expect(agent.uiStreamProgress(owner), isNull);
              expect(agent.uiPresentation(owner), isNull);
              expect(find.text('保存事实'), findsNothing);
            } else {
              expect(
                agent.isCurrentUiRequest(request),
                isTrue,
                reason:
                    'a stale read must not delete the current request identity',
              );
              expect(agent.uiStreamProgress(owner), same(progress));
              expect(agent.uiPresentation(owner), same(presentation));
              if (boundary == 'dispose') {
                await tester.pumpWidget(view(owner));
                await tester.pump();
              }
              if (boundary != 'current') {
                expect(find.text('保存事实'), findsWidgets);
              }
            }
            expect(find.byType(DynamicUiSurface), findsNothing);
            expect(find.byType(ElevatedButton), findsNothing);
            expect(f.bodies, isEmpty);
            expect(f.tools.history(), isEmpty);
          } finally {
            if (!pending.isCompleted) pending.complete(null);
            await tester.runAsync(() async {
              if (!releaseStream.isCompleted) releaseStream.complete();
            });
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
