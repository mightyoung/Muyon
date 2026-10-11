import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/inquiry_ui_planning_source.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/screens/ui_stream_task_view.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'aiui6_stream_production_test.dart' show node, state;
import 'support/agent_loop_fixture.dart';
import 'support/aiui6_snapshot_fixture.dart';

/// Real selected-object host. The stream is a local fixture; no model is called.
Future<void> _cancelRealPlanning(
  WidgetTester tester, {
  required bool revokeDuringCancel,
}) async {
  final f = (await tester.runAsync(InquirySnapshotFixture.open))!;
  final tools = ToolRegistry(
    database: f.host.foundation.database,
    resolveScope: (scope) async =>
        ResolvedAssistantScope(requested: scope, objects: scope.objects),
  );
  final preference = UiPresentationPreference(f.host.foundation);
  await tester.runAsync(() => preference.save(UiPresentationMode.automatic));
  final entered = Completer<void>();
  final release = Completer<void>();
  final provider = StreamMotivationUiPlanningProvider((
    request,
    _,
    receive,
  ) async {
    receive('${node('root', 'PageScaffold', props: {'title': '保存事实'})}\n');
    entered.complete();
    await release.future;
    receive('{"op":"end"}\n');
  });
  final agent = PersonalAgent(
    repository: f.host.foundation,
    gateway: f.host.services.gateway,
    tools: tools,
    presentationPreference: preference,
    uiPlanningSource: InquiryUiPlanningSource(f.host).read,
    uiPlanningMode: UiPlanningMode.motivation,
    uiPlanningProviders: {UiPlanningMode.motivation: provider},
  );
  const answer = '已保存的公开回答';
  late PersonalTask task;
  late Future<UiPlannedPresentation> planning;
  try {
    final ref = f.refs['project_item']!;
    final conversation = (await tester.runAsync(
      () => f.host.foundation.createConversation(
        scope: AssistantScope.selectedObjects([ref]),
      ),
    ))!;
    final profile = ModelProfile(
      id: 'sn4-local',
      endpoint: Uri.parse('http://127.0.0.1:9/v1'),
      location: ModelLocation.local,
      modelId: 'unused',
      endpointIdentity: 'sn4-no-network',
      capabilities: const ModelCapabilities(streaming: true),
    );
    task = (await tester.runAsync(
      () => agent.start(
        conversationId: conversation.id,
        prompt: '查看已选预算行',
        profile: profile,
      ),
    ))!;
    expect(task.state, PersonalTaskState.waitingConfirmation);
    expect(
      await tester.runAsync(
        () => f.host.foundation.updateTask(
          task.copy({'state': 'running', 'stage': 'model', 'summary': answer}),
        ),
      ),
      isTrue,
    );
    await tester.runAsync(
      () =>
          f.host.foundation.appendMessage(conversation.id, 'assistant', answer),
    );
    final outboundBefore = f.host.foundation.database.raw
        .select('SELECT COUNT(*) AS n FROM outbound_requests')
        .single['n'];
    await tester.runAsync(() async {
      planning = agent.planUi(task.id);
      await Future.any<void>([
        entered.future,
        planning.then<void>((_) {
          if (!entered.isCompleted) {
            throw StateError('cancel_stream_not_reached');
          }
        }),
      ]);
    });
    await tester.runAsync(() async {
      final cancelling = agent.cancel(task.id);
      if (revokeDuringCancel) {
        // The inquiry manifest has no ocr grant row. Changing the saved
        // conversation scope is a real host refusal: facts may no longer be read.
        await f.host.foundation.database.write(
          (db) => db.execute(
            'UPDATE conversations SET scope_json=?, updated_at=? WHERE id=?',
            [
              jsonEncode(const AssistantScope.global().toJson()),
              DateTime.now().toUtc().toIso8601String(),
              conversation.id,
            ],
          ),
        );
        expect(
          jsonEncode(
            f.host.foundation.conversation(conversation.id)!.scope.toJson(),
          ),
          isNot(jsonEncode(task.scope.toJson())),
        );
      }
      await cancelling;
    });
    release.complete();
    final late = (await tester.runAsync(() => planning))!;
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: UiStreamTaskView(agent: agent, taskId: task.id, host: f.host),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    final stored = f.host.foundation.task(task.id)!;
    expect(stored.state.name, 'cancelled');
    expect(stored.summary, answer);
    expect(
      f.host.foundation
          .messages(conversation.id)
          .where((message) => message.role == 'assistant')
          .map((message) => message.content),
      [answer],
    );
    expect(late.validated, isNull);
    expect(agent.uiPresentation(task.id)?.validated, isNull);
    expect(f.host.tools.history(), isEmpty);
    expect(tools.history(), isEmpty);
    expect(
      f.host.foundation.database.raw
          .select('SELECT COUNT(*) AS n FROM outbound_requests')
          .single['n'],
      outboundBefore,
    );
    expect(find.byType(DynamicUiSurface), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    if (revokeDuringCancel) {
      expect(
        agent.uiStreamProgress(task.id),
        isNull,
        reason: 'revoking inquiry authority during cancel clears the fallback',
      );
      expect(agent.uiPresentation(task.id), isNull);
      expect(find.text('保存事实'), findsNothing);
      expect(find.textContaining('真实预算行'), findsNothing);
      expect(find.textContaining('987654.123'), findsNothing);
    } else {
      final progress = agent.uiStreamProgress(task.id);
      expect(
        progress,
        isNotNull,
        reason: 'cancelling planning keeps the read-only preview',
      );
      expect(progress!.view.finalPlan, isNull);
      expect(
        progress.view.previewPlan.nodes.every((node) => node.events.isEmpty),
        isTrue,
      );
      expect(
        progress.request.snapshot.facts.values
            .map((fact) => fact.value)
            .join('\n'),
        contains('真实预算行'),
      );
      expect(find.textContaining('界面未完成'), findsWidgets);
      expect(find.text('保存事实'), findsWidgets);
      expect(find.textContaining('真实预算行'), findsWidgets);
      expect(find.textContaining('987654.123'), findsNothing);
    }
  } finally {
    if (!release.isCompleted) release.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(agent.close);
    await tester.runAsync(tools.close);
    await tester.runAsync(f.close);
  }
}

UiPlanningHostState _actions(LoopFixture f, Set<String> actions) {
  final base = state(f);
  return UiPlanningHostState(
    snapshot: base.snapshot,
    intent: InteractionIntent(
      id: base.intent.id,
      purpose: base.intent.purpose,
      snapshotRef: base.intent.snapshotRef,
      requiredBindings: base.intent.requiredBindings,
      allowedActionRefs: actions,
    ),
    currentView: base.currentView,
    catalog: base.catalog,
    allowedActionRefs: actions,
  );
}

String get _actionStream =>
    '${node('root', 'PageScaffold', props: {'title': '保存事实'})}\n'
    '${node('chip', 'ObjectChip', parent: 'root', props: {'label': '最后预览'}, bind: {
      'value': {'kind': 'fact', 'id': 'value'},
    })}\n'
    '{"op":"action","node":"chip","event":"tap","action":"detail","inputs":[]}\n'
    '{"op":"end"}\n';

/// Only the diagnostics row is refused. The cancel event and task update stay writable.
void _refuseDiagnostics(LoopFixture f) {
  f.repo.database.raw.execute('''
CREATE TRIGGER sn4_refuse_ui_diagnostics
BEFORE INSERT ON task_events
WHEN NEW.type = 'ui_stream_diagnostics'
BEGIN
  SELECT RAISE(ABORT, 'ui_stream_diagnostics refused');
END
''');
}

void main() {
  test(
    'SN4 I1 diagnostics write failure still cancels the original task',
    () async {
      final f = await LoopFixture.open();
      final entered = Completer<void>();
      final release = Completer<void>();
      final provider = StreamMotivationUiPlanningProvider((
        request,
        _,
        receive,
      ) async {
        receive('${node('root', 'PageScaffold', props: {'title': '保存事实'})}\n');
        entered.complete();
        await release.future;
        receive('{"op":"end"}\n');
      });
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        uiPlanningSource: (_) async => state(f),
        uiPlanningMode: UiPlanningMode.motivation,
        uiPlanningProviders: {UiPlanningMode.motivation: provider},
      );
      addTearDown(agent.close);
      const answer = '已保存的公开回答';
      final conversation = await f.repo.createConversation();
      final task = await agent.start(
        conversationId: conversation.id,
        prompt: '查看预算',
        profile: f.profile(),
      );
      expect(
        await f.repo.updateTask(
          task.copy({'state': 'running', 'stage': 'model', 'summary': answer}),
        ),
        isTrue,
      );
      await f.repo.appendMessage(conversation.id, 'assistant', answer);
      final planning = agent.planUi(task.id);
      try {
        await Future.any<void>([
          entered.future,
          planning.then<void>((_) {
            if (!entered.isCompleted) {
              throw StateError('cancel_stream_not_reached');
            }
          }),
        ]);
        _refuseDiagnostics(f);
        Object? error;
        try {
          await agent.cancel(task.id);
        } catch (caught) {
          error = caught;
        }
        final stored = f.repo.task(task.id)!;
        expect(stored.state, PersonalTaskState.cancelled);
        expect(stored.summary, answer);
        expect(
          f.repo.taskEvents(task.id).map((event) => event.type),
          contains('cancel'),
        );
        expect(
          f.repo
              .taskEvents(task.id)
              .where((event) => event.type == 'ui_stream_diagnostics'),
          isEmpty,
        );
        expect('$error', contains('ui_stream_diagnostics'));
      } finally {
        if (!release.isCompleted) release.complete();
        await planning.catchError((_) => UiPlanningHarness.fallback('closed'));
      }
    },
  );

  testWidgets(
    'SN4 I2 cancelling real inquiry planning keeps the readonly fallback and zero capability',
    (tester) => _cancelRealPlanning(tester, revokeDuringCancel: false),
  );

  testWidgets(
    'SN4 I2 revocation during cancel clears the real readonly fallback',
    (tester) => _cancelRealPlanning(tester, revokeDuringCancel: true),
  );

  testWidgets(
    'SN4 I3 third source check narrowing actions keeps the readonly preview',
    (tester) async {
      final f = (await tester.runAsync(LoopFixture.open))!;
      var lookups = 0;
      final provider = StreamMotivationUiPlanningProvider(
        (_, _, receive) async => receive(_actionStream),
      );
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        uiPlanningSource: (_) async => _actions(
          f,
          ++lookups >= 3 ? const {'back'} : const {'detail', 'back'},
        ),
        uiPlanningMode: UiPlanningMode.motivation,
        uiPlanningProviders: {UiPlanningMode.motivation: provider},
      );
      const answer = 'Saved public answer';
      try {
        final conversation = (await tester.runAsync(
          f.repo.createConversation,
        ))!;
        final task = (await tester.runAsync(
          () => f.start(
            agent,
            f.profile(),
            conversationId: conversation.id,
            prompt: '显示已保存事实',
          ),
        ))!;
        expect(
          await tester.runAsync(
            () => f.repo.updateTask(
              task.copy({
                'state': 'running',
                'stage': 'model',
                'summary': answer,
              }),
            ),
          ),
          isTrue,
        );
        await tester.runAsync(
          () => f.repo.appendMessage(conversation.id, 'assistant', answer),
        );
        final result = (await tester.runAsync(() => agent.planUi(task.id)))!;
        expect(
          lookups,
          greaterThanOrEqualTo(3),
          reason: 'the barrier is the third source check',
        );
        expect(result.validated, isNull);
        final stored = agent.uiPresentation(task.id);
        expect(
          stored,
          isNotNull,
          reason: 'narrowed actions keep the readonly presentation',
        );
        expect(agent.isCurrentUiRequest(stored!.request!), isTrue);
        final progress = agent.uiStreamProgress(task.id);
        expect(progress, isNotNull, reason: 'the last preview stays attached');
        expect(progress!.view.finalPlan, isNull);
        expect(
          progress.view.previewPlan.nodes.map(
            (item) => item.properties['title'] ?? item.properties['label'],
          ),
          containsAll(['保存事实', '最后预览']),
        );
        expect(
          progress.view.previewPlan.nodes.every((item) => item.events.isEmpty),
          isTrue,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: UiStreamTaskView(agent: agent, taskId: task.id),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump();
        }
        expect(find.text('界面未完成 · 只读，动作不可用'), findsOneWidget);
        expect(find.text('保存事实'), findsWidgets);
        expect(find.text('最后预览'), findsWidgets);
        expect(find.textContaining('value: 42'), findsWidgets);
        expect(find.byType(DynamicUiSurface), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(f.bodies, isEmpty);
        expect(f.callsOf('write'), 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(agent.close);
      }
    },
  );
}
