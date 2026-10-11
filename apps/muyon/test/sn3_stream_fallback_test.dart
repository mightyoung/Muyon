import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/screens/ui_stream_task_view.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'aiui6_stream_production_test.dart' show request, state, validStream, node;
import 'support/agent_loop_fixture.dart';

String failureStream(String fault) => switch (fault) {
  'malformed_stream' => 'not-json\n$validStream',
  'incomplete' => validStream.replaceAll('{"op":"end"}\n', ''),
  'limit_exceeded' => validStream.replaceAll('{"op":"end"}\n', '') +
      List.filled(UiStreamLimits.v1.lineBytes + 1, 'x').join(),
  _ => '${node('root', 'PageScaffold', props: {'title': '保存事实'})}\n'
      '${node('invalid', 'KeyValue', parent: 'root', bind: {'value': {'kind': 'fact', 'id': 'unknown'}})}\n'
      '{"op":"end"}\n',
};

void main() {
  for (final fault in ['malformed_stream', 'incomplete', 'limit_exceeded', 'invalid_plan']) {
    test('SN3 $fault keeps the original candidate and read-only last preview', () async {
      final f = await LoopFixture.open();
      final input = request(f);
      final provider = StreamMotivationUiPlanningProvider((_, _, receive) async => receive(failureStream(fault)));
      await expectLater(provider.plan(input), throwsStateError);
      final progress = provider.progressFor(input);
      expect(progress, isNotNull, reason: 'failed streams must remain visible');
      expect(progress!.view.finalPlan, isNull);
      expect(progress.view.previewPlan.nodes.first.properties['title'], '保存事实');
      expect(progress.view.previewPlan.nodes.every((n) => n.events.isEmpty), isTrue);
      if (fault == 'invalid_plan') {
        expect(progress.view.candidatePlan.nodes.any((n) => n.id == 'invalid'), isTrue);
        expect(progress.view.batchValidation!.errors, isNotEmpty);
      }
    });
  }

  test('SN3 after-end lines keep the first validated end and durable compiler diagnostic', () async {
    final f = await LoopFixture.open();
    final input = request(f);
    final provider = StreamMotivationUiPlanningProvider((_, _, receive) async =>
      receive('$validStream{"op":"end"}\nnot-json\n'));
    final result = await provider.plan(input);
    expect(result.plan!.nodes, hasLength(2));
    expect(provider.progressFor(input)!.view.complete, isTrue);
    expect(provider.progressFor(input)!.view.diagnostics.where((d) => d.reason == 'after_end'), hasLength(2));
  });

  test('SN3 transport fault after valid end revokes capability without rewriting compile result', () async {
    final f = await LoopFixture.open();
    final input = request(f);
    final provider = StreamMotivationUiPlanningProvider((_, _, receive) async {
      receive(validStream);
      throw StateError('fixture_transport_fault');
    });
    await expectLater(provider.plan(input), throwsStateError);
    final progress = provider.progressFor(input);
    expect(progress, isNotNull);
    expect(progress!.view.finalPlan, isNull);
    expect(progress.view.batchValidation!.isValid, isTrue,
      reason: 'transport failure is distinct from original candidate validation');
  });

  for (final fault in ['malformed_stream', 'incomplete', 'limit_exceeded', 'invalid_plan', 'after_end', 'transport_error']) {
    test('SN3 $fault is retained in the execution timeline', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      addTearDown(agent.close);
      final conversation = await f.repo.createConversation();
      final task = await agent.start(conversationId: conversation.id, prompt: '无配置');
      late UiPlanningHarness harness;
      final provider = StreamMotivationUiPlanningProvider((_, _, receive) async {
        receive(fault == 'after_end' ? '$validStream{"op":"end"}\n' :
          fault == 'transport_error' ? validStream : failureStream(fault));
        if (fault == 'transport_error') throw StateError('fixture_transport_fault');
      }, onProgress: (p) => harness.publishStream(p));
      harness = UiPlanningHarness(repository: f.repo, source: (_) async => state(f),
        mode: UiPlanningMode.motivation, providers: {UiPlanningMode.motivation: provider});
      final result = await harness.plan(task.id);
      expect(result.validated != null, fault == 'after_end');
      expect(jsonEncode(f.repo.taskEvents(task.id).map((e) => e.data).toList()), contains(fault));
      expect(harness.streamProgress(task.id), isNotNull);
      expect(f.bodies, isEmpty);
    });
  }

  test('SN3 timeout keeps a disabled preview and cannot revive on late end', () async {
    final f = await LoopFixture.open();
    final agent = f.agent();
    addTearDown(agent.close);
    final conversation = await f.repo.createConversation();
    final task = await agent.start(conversationId: conversation.id, prompt: '无配置');
    final release = Completer<void>();
    late UiPlanningHarness harness;
    final provider = StreamMotivationUiPlanningProvider((_, _, receive) async {
      receive(failureStream('incomplete'));
      await release.future;
      receive('{"op":"end"}\n');
    }, onProgress: (p) => harness.publishStream(p));
    harness = UiPlanningHarness(repository: f.repo, source: (_) async => state(f),
      timeout: const Duration(milliseconds: 20), mode: UiPlanningMode.motivation,
      providers: {UiPlanningMode.motivation: provider});
    final result = await harness.plan(task.id);
    expect(result.validated, isNull);
    expect(harness.streamProgress(task.id), isNotNull);
    expect(harness.streamProgress(task.id)!.view.finalPlan, isNull);
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(harness.presentation(task.id), same(result));
    expect(harness.streamProgress(task.id)!.view.finalPlan, isNull);
  });

  for (final mode in UiPresentationMode.values) {
    for (final explicit in [false, true]) {
      testWidgets('SN3 host fallback respects ${mode.name}, explicit=$explicit and has no business controls', (tester) async {
        final f = (await tester.runAsync(LoopFixture.open))!;
        final preference = UiPresentationPreference(f.repo);
        await tester.runAsync(() => preference.save(mode));
        final provider = StreamMotivationUiPlanningProvider((_, _, receive) async => receive(failureStream('incomplete')));
        final agent = PersonalAgent(repository: f.repo,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger), tools: f.tools,
          presentationPreference: preference, uiPlanningSource: (_) async => state(f),
          uiPlanningMode: UiPlanningMode.motivation,
          uiPlanningProviders: {UiPlanningMode.motivation: provider});
        try {
          final conversation = (await tester.runAsync(() => f.repo.createConversation()))!;
          final task = (await tester.runAsync(() => agent.start(conversationId: conversation.id, prompt: '无配置')))!;
          if (explicit) await tester.runAsync(() => agent.planUiFromUserControl(task.id));
          await tester.pumpWidget(MaterialApp(home: UiStreamTaskView(agent: agent, taskId: task.id)));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pumpAndSettle();
          final visible = mode == UiPresentationMode.automatic || (mode == UiPresentationMode.few && explicit);
          expect(find.textContaining('未完成'), visible ? findsWidgets : findsNothing);
          expect(find.textContaining('value: 42'), visible ? findsWidgets : findsNothing);
          expect(find.text('保存事实'), visible ? findsWidgets : findsNothing);
          expect(find.byType(ElevatedButton), findsNothing);
          expect(find.byType(TextButton), findsNothing);
          expect(f.callsOf('write'), 0);
          expect(f.bodies, isEmpty);
          if (visible) {
            expect(agent.uiPresentation(task.id)!.validated, isNull);
            expect(jsonEncode(f.repo.taskEvents(task.id).map((e) => e.data).toList()), contains('incomplete'));
          }
          await tester.runAsync(() => agent.savePresentationMode(UiPresentationMode.textOnly));
          await tester.pumpAndSettle();
          expect(find.textContaining('value: 42'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(agent.close);
        }
      });
    }
  }

  test('SN3 invalidation rejects late success and late preview publications', () async {
    final f = await LoopFixture.open();
    final agent = f.agent();
    addTearDown(agent.close);
    final conversation = await f.repo.createConversation();
    final task = await agent.start(conversationId: conversation.id, prompt: '无配置');
    final entered = Completer<void>(), release = Completer<void>();
    late UiPlanningHarness harness;
    final provider = StreamMotivationUiPlanningProvider((_, _, receive) async {
      receive(failureStream('incomplete'));
      entered.complete();
      await release.future;
      receive('{"op":"end"}\n');
    }, onProgress: (p) => harness.publishStream(p));
    harness = UiPlanningHarness(repository: f.repo, source: (_) async => state(f),
      mode: UiPlanningMode.motivation, providers: {UiPlanningMode.motivation: provider});
    final pending = harness.plan(task.id);
    await entered.future;
    harness.invalidate();
    release.complete();
    expect((await pending).validated, isNull);
    expect(harness.presentation(task.id), isNull);
    expect(harness.streamProgress(task.id), isNull);
  });
}
