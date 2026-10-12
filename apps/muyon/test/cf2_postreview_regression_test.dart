import 'dart:async';
import 'dart:io' show HttpOverrides;

import 'package:flutter/material.dart';
import 'package:muyon/screens/ui_stream_task_view.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'aiui6_stream_production_test.dart'
    show state, request, validStream, node;
import 'support/agent_loop_fixture.dart';

void main() {
  setUp(() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
  });
  test(
    'native end-only chooses no card without validating an empty plan',
    () async {
      final f = await LoopFixture.open();
      final provider = StreamMotivationUiPlanningProvider(
        (_, _, receive) async => receive('{"op":"end"}\n'),
      );
      final input = request(f);
      final result = await provider.plan(input);
      expect(result.reasonCode, 'model_no_card');
      expect(result.decision, UiDisplayDecision.textOnly);
      expect(result.plan, isNull);
      expect(provider.progressFor(input), isNull);
    },
  );
  for (final stream in [
    '${node('bad', 'Unknown')}\n{"op":"end"}\n',
    'bad-json\n{"op":"end"}\n',
    '{"op":"patch","id":"missing","props":{}}\n{"op":"end"}\n',
    '{"op":"action","node":"missing","event":"press","action":"missing"}\n{"op":"end"}\n',
    '{"op":"end"}\nbad-json\n',
    '{"op":"end"}\n{"op":"end"}\n',
    '{"op":"end","extra":true}\n',
    '{"op":"text","md":"not a card"}\n{"op":"end"}\n',
  ]) {
    test(
      'non-end-only rejection cannot become model no-card: $stream',
      () async {
        final f = await LoopFixture.open();
        final provider = StreamMotivationUiPlanningProvider(
          (_, _, receive) async => receive(stream),
        );
        final input = request(f);
        await expectLater(provider.plan(input), throwsStateError);
        expect(
          provider.progressFor(input)!.failureCode,
          isNot('model_no_card'),
        );
        expect(provider.progressFor(input)!.view.finalPlan, isNull);
      },
    );
  }
  test('pending automatic planning revoked by saved textOnly keeps user cause and zero authority', () async {
    final f = await LoopFixture.open();
    final preference = UiPresentationPreference(f.repo);
    await preference.save(UiPresentationMode.automatic);
    final entered = Completer<void>(), release = Completer<void>();
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      presentationPreference: preference,
      uiPlanningSource: (_) async => state(f),
      uiPlanningMode: UiPlanningMode.motivation,
      uiPlanningProviders: {
        UiPlanningMode.motivation: StreamMotivationUiPlanningProvider((
          _,
          _,
          receive,
        ) async {
          entered.complete();
          await release.future;
          receive(validStream);
        }),
      },
    );
    addTearDown(agent.close);
    f.replies.add(
      LoopReply.sse(sseText('{"type":"answer","answer":"Saved answer"}')),
    );
    final task = await f.start(
      agent,
      f.profile(capabilities: const ModelCapabilities(streaming: true)),
    );
    final pending = f.run(agent, task);
    await entered.future;
    await preference.save(UiPresentationMode.textOnly);
    await preference.save(UiPresentationMode.automatic);
    release.complete();
    await pending;
    final event = f.repo
        .taskEvents(task.id)
        .singleWhere((e) => e.type == 'ui_planning');
    expect(event.data['reasonCode'], 'user_text_only');
    expect(event.data['reasonCategory'], 'user');
    expect(agent.uiPresentation(task.id), isNull);
    await preference.save(UiPresentationMode.automatic);
    expect(agent.allowsUiContent(task.id), isFalse);
    expect((await agent.planUi(task.id)).validated, isNull);
    expect(f.bodies, hasLength(1));
    expect(f.callsOf('write'), 0);
  });
  test(
    'end-only followed by transport failure never chooses no-card',
    () async {
      final f = await LoopFixture.open();
      final provider = StreamMotivationUiPlanningProvider((
        _,
        _,
        receive,
      ) async {
        receive('{"op":"end"}\n');
        throw StateError('synthetic transport failure');
      });
      final input = request(f);
      await expectLater(provider.plan(input), throwsStateError);
      expect(provider.progressFor(input)!.failureCode, 'transport_error');
      expect(provider.progressFor(input)!.view.finalPlan, isNull);
    },
  );
  test(
    'foreign request and closed preference remain host invalidation',
    () async {
      final f = await LoopFixture.open();
      final preference = UiPresentationPreference(f.repo);
      await preference.save(UiPresentationMode.automatic);
      final request = UiPresentationRequest.ordinary();
      final policy = preference.freezeFor(request);
      await preference.save(UiPresentationMode.textOnly);
      expect(
        policy.blockedReasonFor(UiPresentationRequest.ordinary()),
        'host_request_changed',
      );
      await preference.close();
      expect(policy.blockedReasonFor(request), 'host_request_changed');
      expect(policy.allowsContentFor(request), isFalse);
    },
  );
  testWidgets('ended stream awaits host without incomplete failure copy', (
    tester,
  ) async {
    final f = (await tester.runAsync(LoopFixture.open))!;
    final preference = UiPresentationPreference(f.repo);
    await tester.runAsync(() => preference.save(UiPresentationMode.automatic));
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      presentationPreference: preference,
      uiPlanningSource: (_) async => state(f),
      uiPlanningMode: UiPlanningMode.motivation,
    );
    final hold = Completer<void>();
    Future<void>? finishing;
    try {
      final taskId = (await tester.runAsync(() async {
        f.replies.addAll([
          LoopReply.sse(sseText('{"type":"answer","answer":"Saved answer"}')),
          LoopReply.sse([
            sseChunk({'content': validStream}),
            sseChunk({}, finish: 'stop'),
            'data: [DONE]\n\n',
          ], hold: hold.future),
        ]);
        final task = await f.start(
          agent,
          f.profile(capabilities: const ModelCapabilities(streaming: true)),
        );
        finishing = agent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        var confirmed = false;
        for (var turn = 0; turn < 4000; turn++) {
          final children = f.repo.tasks().where(
            (t) => t.payload['uiPlanningInternal'] == true,
          );
          if (!confirmed &&
              children.isNotEmpty &&
              children.single.state.name == 'waitingConfirmation') {
            confirmed = true;
            final child = children.single;
            unawaited(
              agent.confirm(
                child.id,
                requestDigest: child.payload['requestDigest'] as String,
              ),
            );
          }
          if (agent.uiStreamProgress(task.id)?.view.phase ==
              UiStreamPhase.complete) {
            return task.id;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        throw TestFailure('complete progress not received');
      }))!;
      expect(agent.uiStreamProgress(taskId)!.failureCode, isNull);
      expect(agent.uiPresentation(taskId), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: UiStreamTaskView(agent: agent, taskId: taskId),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byKey(ValueKey('ui-stream-preview-$taskId')), findsOneWidget);
      expect(find.text('保存事实'), findsWidgets);
      expect(find.textContaining('界面流未完成'), findsNothing);
      expect(find.textContaining('界面未完成'), findsNothing);
      expect(find.textContaining('等待宿主确认'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('界面流未完成')), findsNothing);
      semantics.dispose();
    } finally {
      if (!hold.isCompleted) hold.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await finishing;
        await agent.close();
      });
    }
  });
  testWidgets('model no-card renders explanation without host fallback card', (
    tester,
  ) async {
    final f = (await tester.runAsync(LoopFixture.open))!;
    final preference = UiPresentationPreference(f.repo);
    await tester.runAsync(() => preference.save(UiPresentationMode.automatic));
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      presentationPreference: preference,
      uiPlanningSource: (_) async => state(f),
      uiPlanningMode: UiPlanningMode.motivation,
      uiPlanningProviders: {
        UiPlanningMode.motivation: StreamMotivationUiPlanningProvider(
          (_, _, receive) async => receive('{"op":"end"}\n'),
        ),
      },
    );
    try {
      final taskId = (await tester.runAsync(() async {
        f.replies.add(
          LoopReply.sse(sseText('{"type":"answer","answer":"Saved answer"}')),
        );
        final task = await f.start(
          agent,
          f.profile(capabilities: const ModelCapabilities(streaming: true)),
        );
        await f.run(agent, task);
        expect(agent.uiPresentation(task.id)!.reason.code, 'model_no_card');
        return task.id;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: UiStreamTaskView(agent: agent, taskId: taskId),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('模型本轮未提供内容卡，保留文字回答。'), findsOneWidget);
      expect(find.textContaining('界面未完成'), findsNothing);
      expect(find.textContaining('value: 42'), findsNothing);
      expect(find.byKey(ValueKey('ui-stream-fallback-$taskId')), findsNothing);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('value: 42|界面未完成')), findsNothing);
      semantics.dispose();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(agent.close);
    }
  });
  test('failure fallback cannot claim validated stream success', () {
    expect(
      UiPlanningHarness.fallback('validated_stream_2').reason.code,
      'planner_unavailable',
    );
  });
}
