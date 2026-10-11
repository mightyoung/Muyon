import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:muyon_module_api/ui_contract.dart' show FixtureUiPlanningProvider,
  UiDisplayDecision, UiPlanningMode, UiPlanningResult;

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
      // ListView builds only its viewport; include every seeded card so the
      // key counts test selection rather than lazy child construction.
      tester.view.physicalSize = const Size(1200, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
    for (final change in ['text only', 'missing provider', 'source null',
      'source throw', 'await text only', 'await missing provider',
      'nonstream provider switch']) {
      test('next model round removes stale planning metadata after $change in ${native ? 'native' : 'JSON'} protocol', () async {
        // Earlier widget cases initialize Flutter's fake HTTP override. These
        // rounds must reach the real loopback fixture, then restore the binding.
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() { HttpOverrides.global = previousOverrides; });
        final f = await LoopFixture.open();
        final preference = UiPresentationPreference(f.repo);
        await preference.save(UiPresentationMode.automatic);
        var sourceFaultArmed = false, faultSourceRead = false;
        final sourceEntered = Completer<void>();
        final releaseSource = Completer<void>();
        final agent = PersonalAgent(
          repository: f.repo,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
          tools: f.tools,
          presentationPreference: preference,
          uiPlanningSource: (_) async {
            if (!sourceFaultArmed) return state(f);
            faultSourceRead = true;
            if (change == 'source null') return null;
            if (change == 'source throw') throw StateError('fixture_source_unavailable');
            if (change.startsWith('await ')) {
              sourceEntered.complete();
              await releaseSource.future;
            }
            return state(f);
          },
          uiPlanningMode: change == 'nonstream provider switch'
            ? UiPlanningMode.intelligent : UiPlanningMode.motivation,
          uiPlanningProviders: change == 'nonstream provider switch' ? {
            UiPlanningMode.intelligent: FixtureUiPlanningProvider((_) async =>
              UiPlanningResult(decision: UiDisplayDecision.textOnly,
                reasonCode: 'fixture_template')),
          } : const {},
        );
        addTearDown(agent.close);
        final streaming = change != 'nonstream provider switch';
        if (streaming) {
          f.replies.add(LoopReply.sse(native
            ? sseCalls([('read-call', 'read', '{}')])
            : sseText('{"type":"tool","toolId":"read","parameters":{}}')));
        } else {
          // A frozen non-streaming profile needs one complete JSON response,
          // even when the selected protocol uses native tool calls.
          f.replies.add(LoopReply.sse([jsonEncode({
            'choices': [{
              'message': native ? {
                'content': null,
                'tool_calls': [{
                  'id': 'read-call', 'type': 'function',
                  'function': {'name': 'read', 'arguments': '{}'},
                }],
              } : {'content': '{"type":"tool","toolId":"read","parameters":{}}'},
              'finish_reason': native ? 'tool_calls' : 'stop',
            }],
          })]));
        }
        final first = await f.start(agent, f.profile(capabilities: ModelCapabilities(
          nativeTools: native, streaming: streaming)));
        final prior = first.payload['uiPlanningContext'];
        expect(prior, isA<String>(), reason: 'The first round must really load host metadata');
        final originalSystem = (first.payload['messages'] as List).first;
        final frozenCandidates = first.payload['candidateIds'];
        sourceFaultArmed = true;
        if (change == 'text only') {
          await agent.savePresentationMode(UiPresentationMode.textOnly);
        } else if (change == 'missing provider') {
          // This mode has no registered provider; registry presence alone is
          // not actual presentation support.
          agent.configureUiPlanning(mode: UiPlanningMode.intelligent);
        } else if (change == 'nonstream provider switch') {
          expect(frozenCandidates, contains('assistant.plan_ui'),
            reason: 'The initial non-streaming template provider was really advertised');
          expect(((first.payload['profile'] as Map)['capabilities'] as Map)['streaming'], isFalse);
          // Motivation is the actual production stream provider installed by
          // this preference owner; it cannot use the frozen non-streaming profile.
          agent.configureUiPlanning(mode: UiPlanningMode.motivation);
        }
        final confirming = agent.confirm(first.id,
          requestDigest: first.payload['requestDigest'] as String);
        if (change.startsWith('await ')) {
          try {
            await Future.any<void>([
              sourceEntered.future,
              confirming.then<void>((_) => throw StateError(
                'Model round completed without entering the controlled source read')),
            ]);
            if (change == 'await text only') {
              await agent.savePresentationMode(UiPresentationMode.textOnly);
            } else {
              agent.configureUiPlanning(mode: UiPlanningMode.intelligent);
            }
          } finally {
            if (!releaseSource.isCompleted) releaseSource.complete();
          }
        }
        await confirming;
        if (change == 'source null' || change == 'source throw' ||
            change.startsWith('await ')) {
          expect(faultSourceRead, isTrue,
            reason: 'Exercise a real second-round source read after the first metadata was stored');
        }
        final next = f.repo.task(first.id)!;
        expect(f.bodies, hasLength(1), reason: 'Only the first model round was approved; ${next.error ?? next.state.name}');
        if (!streaming) {
          expect(f.bodies.single['stream'], isFalse,
            reason: 'The real first request keeps its frozen non-streaming protocol');
        }
        expect(f.callsOf('read'), 1, reason: 'A real tool result advances the model round');
        expect(next.stage, 'model');
        expect(next.payload['uiPlanningContext'], isNull);
        expect((next.payload['messages'] as List).where((message) =>
          message is Map && message['role'] == 'system' && message['content'] == prior), isEmpty);
        final nextSystemMessage = (next.payload['messages'] as List).first as Map;
        expect(nextSystemMessage['role'], 'system');
        if (native) {
          expect(nextSystemMessage, originalSystem,
            reason: 'Keep ordinary native system instructions intact');
          expect(next.payload['nativeTools'],
            (first.payload['nativeTools'] as List).where((tool) =>
              (tool as Map)['toolId'] != 'assistant.plan_ui').toList());
        } else {
          final previousSystem = jsonDecode((originalSystem as Map)['content'] as String) as Map;
          final nextSystem = jsonDecode(nextSystemMessage['content'] as String) as Map;
          final priorTools = previousSystem.remove('tools') as List;
          final nextTools = nextSystem.remove('tools');
          expect(nextTools, priorTools.where((tool) =>
            (tool as Map)['toolId'] != 'assistant.plan_ui').toList());
          expect(nextSystem, previousSystem,
            reason: 'Keep every ordinary system field while narrowing only its planning tool');
        }
        expect(next.payload['candidateIds'], (frozenCandidates as List)
          .where((id) => id != 'assistant.plan_ui').toList(),
          reason: 'Revocation may shrink the host catalogue; it never adds candidates');
        expect(f.callsOf('write'), 0);
      });
    }
  }

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
