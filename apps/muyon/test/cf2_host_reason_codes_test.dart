import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/ui_planning_tool.dart';
import 'package:muyon/screens/ui_stream_task_view.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/muyon_module_api.dart'
    show AssistantScope, ToolCallRequest;
import 'package:muyon_module_api/ui_contract.dart';

import 'aiui6_stream_production_test.dart' show state, request, validStream;
import 'support/agent_loop_fixture.dart';

const _canary = 'RAW_MODEL_REASON_CANARY /private/export credential=secret';
const _modelNoCard = '模型本轮未提供内容卡，保留文字回答。';
const _hostClaims = [
  'planning_disabled',
  'host_request_changed',
  'host_state_unavailable',
  'stale_host_state',
  'answer_unavailable',
  'host_state_changed',
  'cancelled',
  'provider_unavailable',
  'invalid_decision',
  'stale_surface',
  'invalid_plan',
  'current_authority_changed',
  'planner_timeout',
  'planner_unavailable',
  'malformed_stream',
  'limit_exceeded',
  'incomplete',
  'model_unavailable',
  'transport_error',
  'validated_stream_2',
  'user_text_only',
  'user_explicit_request_required',
  'model_supplement',
  'model_replace_presentation',
  _canary,
];

String _raw(
  String code, {
  UiDisplayDecision decision = UiDisplayDecision.textOnly,
  UIPlan? plan,
}) => jsonEncode({
  'decision': decision.name,
  'reasonCode': code,
  'plan': plan == null ? null : encodeUiPresentation(plan),
});

PersonalAgent _agent(
  LoopFixture f,
  UiPlanningPort provider, {
  UiPresentationPreference? preference,
}) => PersonalAgent(
  repository: f.repo,
  gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
  tools: f.tools,
  uiPlanningSource: (_) async => state(f),
  presentationPreference: preference,
  uiPlanningMode: UiPlanningMode.motivation,
  uiPlanningProviders: {UiPlanningMode.motivation: provider},
);

Future<String> _localTask(LoopFixture f, PersonalAgent agent) async {
  final conversation = await f.repo.createConversation();
  return (await agent.start(conversationId: conversation.id, prompt: '无配置')).id;
}

void main() {
  for (final code in _hostClaims) {
    test('batch $code cannot claim host/user cause in tool output', () async {
      final f = await LoopFixture.open();
      final provider = MotivationUiPlanningProvider((_, _) async => _raw(code));
      final agent = f.agent();
      final taskId = await _localTask(f, agent);
      final harness = UiPlanningHarness(
        repository: f.repo,
        source: (_) async => state(f),
        mode: UiPlanningMode.motivation,
        providers: {UiPlanningMode.motivation: provider},
      );
      final tool = await runUiPlanningTool(
        harness,
        taskId,
        ToolCallRequest(
          invocationId: 'planning',
          toolId: uiPlanningToolId,
          scope: AssistantScope.global(),
          parameters: {
            'snapshotId': 'saved',
            'expectedSnapshotRevision': 1,
            'surfaceId': 'surface',
            'expectedSurfaceRevision': 0,
          },
        ),
      );
      expect(tool.data['reasonCode'], 'model_no_card');
      expect(tool.summary, _modelNoCard);
      expect(tool.data['reasonDescription'], _modelNoCard);
      expect(tool.data['reasonCategory'], 'model');
      expect(harness.presentation(taskId)!.validated, isNull);
      expect(jsonEncode(tool.toJson()), isNot(contains(_canary)));
      expect(f.bodies, isEmpty);
      expect(f.callsOf('write'), 0);
    });

    test('batch $code cannot return as persisted agent reason', () async {
      final f = await LoopFixture.open();
      f.replies.add(
        LoopReply.sse(sseText('{"type":"answer","answer":"宿主已保存回答"}')),
      );
      final provider = MotivationUiPlanningProvider((_, _) async => _raw(code));
      final agent = _agent(f, provider);
      addTearDown(agent.close);
      final task = await f.start(
        agent,
        f.profile(capabilities: const ModelCapabilities(streaming: true)),
      );
      await f.run(agent, task);
      final event = f.repo
          .taskEvents(task.id)
          .singleWhere((e) => e.type == 'ui_planning');
      expect(event.data['reasonCode'], 'model_no_card');
      expect(event.data['reasonDescription'], _modelNoCard);
      expect(event.data['reasonCategory'], 'model');
      expect(jsonEncode(event.data), isNot(contains(_canary)));
      expect(event.data.keys, isNot(contains('rawReason')));
      expect(f.bodies, hasLength(1));
      expect(f.callsOf('write'), 0);
    });
  }

  for (final decision in [
    UiDisplayDecision.supplement,
    UiDisplayDecision.replacePresentation,
  ]) {
    test(
      'valid batch ${decision.name} has a decision-consistent model code',
      () async {
        final f = await LoopFixture.open();
        final input = request(f);
        final plan = (await StreamMotivationUiPlanningProvider(
          (_, _, receive) async => receive(validStream),
        ).plan(input)).plan!;
        final provider = MotivationUiPlanningProvider(
          (_, _) async =>
              _raw('user_text_only', decision: decision, plan: plan),
        );
        final agent = f.agent();
        final taskId = await _localTask(f, agent);
        final harness = UiPlanningHarness(
          repository: f.repo,
          source: (_) async => state(f),
          mode: UiPlanningMode.motivation,
          providers: {UiPlanningMode.motivation: provider},
        );
        final value = await harness.plan(taskId);
        expect(value.validated, isNotNull);
        expect(
          value.result.reasonCode,
          decision == UiDisplayDecision.supplement
              ? 'model_supplement'
              : 'model_replace_presentation',
        );
        expect(value.result.decision, decision);
      },
    );
  }

  test(
    'illegal decision-plan pair is a host refusal, not a model no-card',
    () async {
      final f = await LoopFixture.open();
      final provider = MotivationUiPlanningProvider(
        (_, _) async => _raw(_canary, decision: UiDisplayDecision.supplement),
      );
      final agent = f.agent();
      final taskId = await _localTask(f, agent);
      final harness = UiPlanningHarness(
        repository: f.repo,
        source: (_) async => state(f),
        mode: UiPlanningMode.motivation,
        providers: {UiPlanningMode.motivation: provider},
      );
      final value = await harness.plan(taskId);
      expect(value.result.reasonCode, 'invalid_decision');
      expect(value.validated, isNull);
      expect(value.result.plan, isNull);
    },
  );

  for (final mode in [UiPresentationMode.textOnly, UiPresentationMode.few]) {
    test(
      'actual ${mode.name} policy has a user cause without requesting a model',
      () async {
        final f = await LoopFixture.open();
        final preference = UiPresentationPreference(f.repo);
        await preference.save(mode);
        var calls = 0;
        final provider = MotivationUiPlanningProvider((_, _) async {
          calls++;
          return _raw(_canary);
        });
        final agent = _agent(f, provider, preference: preference);
        addTearDown(agent.close);
        final taskId = await _localTask(f, agent);
        final value = await agent.planUi(taskId);
        expect(
          value.result.reasonCode,
          mode == UiPresentationMode.textOnly
              ? 'user_text_only'
              : 'user_explicit_request_required',
        );
        expect(calls, 0);
        expect(f.bodies, isEmpty);
        expect(value.validated, isNull);
      },
    );
  }

  test(
    'native stream success keeps the host validated_stream_2 code',
    () async {
      final f = await LoopFixture.open();
      final provider = StreamMotivationUiPlanningProvider(
        (_, _, receive) async => receive(validStream),
      );
      final agent = f.agent();
      final taskId = await _localTask(f, agent);
      final harness = UiPlanningHarness(
        repository: f.repo,
        source: (_) async => state(f),
        mode: UiPlanningMode.motivation,
        providers: {UiPlanningMode.motivation: provider},
      );
      final value = await harness.plan(taskId);
      expect(value.result.reasonCode, 'validated_stream_2');
      expect(value.validated, isNotNull);
    },
  );

  testWidgets(
    'stream fallback shows fixed host Chinese cause without exception text',
    (tester) async {
      final f = (await tester.runAsync(LoopFixture.open))!;
      final preference = UiPresentationPreference(f.repo);
      await tester.runAsync(
        () => preference.save(UiPresentationMode.automatic),
      );
      final provider = StreamMotivationUiPlanningProvider((
        _,
        _,
        receive,
      ) async {
        receive(validStream.replaceAll('{"op":"end"}\n', ''));
      });
      final agent = _agent(f, provider, preference: preference);
      try {
        final taskId = (await tester.runAsync(() => _localTask(f, agent)))!;
        await tester.runAsync(() => agent.planUi(taskId));
        await tester.pumpWidget(
          MaterialApp(
            home: UiStreamTaskView(agent: agent, taskId: taskId),
          ),
        );
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(find.text('界面流未完成，已使用只读事实展示。'), findsOneWidget);
        expect(find.textContaining('value: 42'), findsWidgets);
        expect(find.textContaining(_canary), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(agent.close);
      }
    },
  );
}
