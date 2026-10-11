import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/stream_ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/assistant_subconversations.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_module_api/ui_contract.dart' show UiPlanningMode;

import 'aiui6_stream_production_test.dart' show state, validStream;
import 'support/agent_loop_fixture.dart';

Future<void> seedTask(LoopFixture f, String conversation, String id, {
  bool internal = false,
  String status = 'paused',
}) async {
  await f.repo.database.write((db) => db.execute(
    'INSERT INTO execution_records VALUES(?,?,?)',
    [id, status, jsonEncode({
      'kind': 'personal',
      'executionId': id,
      'conversationId': conversation,
      'scope': const AssistantScope.global().toJson(),
      'prompt': id,
      'state': status,
      'stage': status == 'waitingConfirmation' ? 'model' : status,
      'executionDeviceId': 'local',
      'updatedAt': '2026-10-11T00:00:00Z',
      if (internal) 'uiPlanningInternal': true,
    })],
  ));
}

void main() {
  for (final mode in UiPresentationMode.values) {
    testWidgets('internal interleaving keeps unique parent cards in ${mode.name}', (tester) async {
      final f = (await tester.runAsync(LoopFixture.open))!;
      final preference = UiPresentationPreference(f.repo);
      await tester.runAsync(() => preference.save(mode));
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        presentationPreference: preference,
      );
      final conversation = (await tester.runAsync(() => f.repo.createConversation()))!;
      final children = AssistantSubconversations(f.repo);
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          await seedTask(f, conversation.id, 'parent-$i');
          await seedTask(f, conversation.id, 'internal-$i', internal: true);
        }
        await children.openSubconversation('parent-8', 'recent saved child');
        await children.openSubconversation('parent-0', 'older saved child');
        // Even an old internal record with a saved relation is never a parent
        // card. The pending request still needs its independent controls.
        await children.openSubconversation('internal-0', 'internal relation');
        await seedTask(f, conversation.id, 'internal-pending',
          internal: true, status: 'waitingConfirmation');
      });
      try {
        await tester.pumpWidget(MaterialApp(home: AssistantPage(
          repo: f.repo,
          agent: agent,
          profiles: ProfileRepository(WorkspaceRepository(f.repo.database)),
          conversationId: conversation.id,
        )));
        await tester.pump();
        expect(tester.takeException(), isNull,
          reason: 'Filtered recent parents and older child owners cannot share keys');
        for (var i = 4; i < 12; i++) {
          expect(find.byKey(ValueKey('assistant-task-parent-$i')), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('assistant-task-parent-0')), findsOneWidget);
        for (var i = 1; i < 4; i++) {
          expect(find.byKey(ValueKey('assistant-task-parent-$i')), findsNothing);
        }
        for (var i = 0; i < 12; i++) {
          expect(find.byKey(ValueKey('assistant-task-internal-$i')), findsNothing);
        }
        final pending = find.byKey(const ValueKey('assistant-task-internal-pending'));
        expect(pending, findsOneWidget);
        expect(find.descendant(of: pending, matching: find.text('查看并确认')), findsOneWidget);
        expect(find.descendant(of: pending, matching: find.text('取消')), findsOneWidget);
        expect(find.descendant(of: pending, matching: find.text('子对话')), findsNothing);
        expect(f.bodies, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(agent.close);
      }
    });
  }

  test('few host control permits presentation without expanding the frozen model catalogue', () async {
    final f = await LoopFixture.open();
    final preference = UiPresentationPreference(f.repo);
    await preference.save(UiPresentationMode.few);
    var planningCalls = 0;
    final agent = PersonalAgent(
      repository: f.repo,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      tools: f.tools,
      presentationPreference: preference,
      uiPlanningSource: (_) async => state(f),
      uiPlanningMode: UiPlanningMode.motivation,
      uiPlanningProviders: {
        UiPlanningMode.motivation: StreamMotivationUiPlanningProvider((_, _, receive) async {
          planningCalls++;
          receive(validStream);
        }),
      },
    );
    addTearDown(agent.close);
    final task = await f.start(agent, f.profile());
    expect(task.payload['candidateIds'], isNot(contains('assistant.plan_ui')));
    await f.repo.updateTask(task.copy({'summary': 'Public fixture answer'}));
    final presentation = await agent.planUiFromUserControl(task.id);
    expect(presentation.validated, isNotNull);
    expect(planningCalls, 1);
    expect(f.repo.task(task.id)!.payload['candidateIds'], isNot(contains('assistant.plan_ui')),
      reason: 'A later host control is specific to presentation, not a model tool grant');
    expect(f.repo.task(task.id)!.payload['uiPlanningContext'], isNull);
    expect(f.bodies, isEmpty);
  });

  for (final native in [false, true]) {
    for (final scenario in ['few ordinary', 'text only', 'missing provider', 'nonstream profile', 'available stream']) {
      test('planning catalogue $scenario in ${native ? 'native' : 'JSON'} protocol', () async {
        final f = await LoopFixture.open();
        final preference = UiPresentationPreference(f.repo);
        await preference.save(scenario == 'few ordinary' ? UiPresentationMode.few
          : scenario == 'text only' ? UiPresentationMode.textOnly : UiPresentationMode.automatic);
        final agent = PersonalAgent(
          repository: f.repo,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          tools: f.tools,
          presentationPreference: preference,
          uiPlanningSource: (_) async => state(f),
          uiPlanningMode: scenario == 'missing provider'
            ? UiPlanningMode.intelligent : UiPlanningMode.motivation,
        );
        addTearDown(agent.close);
        final task = await f.start(agent, f.profile(capabilities: ModelCapabilities(
          nativeTools: native, streaming: scenario != 'nonstream profile')));
        final available = scenario == 'available stream';
        expect(task.payload['candidateIds'], available
          ? contains('assistant.plan_ui') : isNot(contains('assistant.plan_ui')));
        if (native) {
          final specs = task.payload['nativeTools'] as List;
          expect(specs.where((tool) => (tool as Map)['toolId'] == 'assistant.plan_ui'),
            available ? hasLength(1) : isEmpty);
        } else {
          final system = jsonDecode(((task.payload['messages'] as List).first as Map)['content'] as String) as Map;
          final specs = system['tools'] as List;
          expect(specs.where((tool) => (tool as Map)['toolId'] == 'assistant.plan_ui'),
            available ? hasLength(1) : isEmpty);
        }
        if (!available) {
          expect(task.payload['uiPlanningContext'], isNull,
            reason: 'Unavailable tools must not be invited through system metadata');
        }
        expect(f.bodies, isEmpty, reason: 'No request has been approved');
        expect(f.callsOf('write'), 0);
      });
    }
  }
}
