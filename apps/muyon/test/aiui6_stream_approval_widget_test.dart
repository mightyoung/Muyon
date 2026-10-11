import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';

import 'aiui6_stream_production_test.dart' show state, validStream;
import 'support/agent_loop_fixture.dart';

void main() {
  for (final mode in UiPresentationMode.values) {
    for (final approve in [true, false]) {
      testWidgets('mandatory planning approval remains reachable in ${mode.name}: $approve', (tester) async {
        final f = (await tester.runAsync(LoopFixture.open))!;
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        final preference = UiPresentationPreference(f.repo);
        await tester.runAsync(() => preference.save(mode == UiPresentationMode.textOnly
          ? UiPresentationMode.automatic : mode));
        final agent = PersonalAgent(repository: f.repo,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger), tools: f.tools,
          presentationPreference: preference, uiPlanningSource: (_) async => state(f),
          uiPlanningMode: UiPlanningMode.motivation);
        f.replies.addAll([
          LoopReply.sse(sseText('{"type":"answer","answer":"Saved answer","citationIds":[]}')),
          LoopReply.sse([sseChunk({'content': validStream}), sseChunk({}, finish: 'stop'), 'data: [DONE]\n\n']),
        ]);
        final conversation = (await tester.runAsync(() => f.repo.createConversation()))!;
        final parent = (await tester.runAsync(() => f.start(agent,
          f.profile(capabilities: const ModelCapabilities(streaming: true)),
          conversationId: conversation.id)))!;
        Future<void> tick() async {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
        try {
          await tester.pumpWidget(MaterialApp(home: AssistantPage(repo: f.repo, agent: agent,
            profiles: ProfileRepository(WorkspaceRepository(f.repo.database)), conversationId: conversation.id)));
          // Both sends are approved through the real production dialog, never
          // by direct agent.confirm on the internal child.
          await tester.ensureVisible(find.text('查看并确认'));
          await tester.tap(find.text('查看并确认')); await tester.pumpAndSettle();
          await tester.tap(find.text('确认本次操作'));
          for (var i = 0; i < 300; i++) {
            await tick();
            if (f.repo.task(parent.id)!.terminal) break;
          }
          if (mode == UiPresentationMode.few) {
            await tester.ensureVisible(find.text('规划此回答'));
            await tester.tap(find.text('规划此回答'));
          }
          for (var i = 0; i < 300; i++) {
            await tick();
            if (f.repo.tasks().any((task) => task.payload['uiPlanningInternal'] == true)) break;
          }
          final child = f.repo.tasks().singleWhere((task) => task.payload['uiPlanningInternal'] == true);
          if (mode == UiPresentationMode.textOnly) {
            await tester.runAsync(() => agent.savePresentationMode(UiPresentationMode.textOnly));
            await tester.pump();
          }
          final card = find.byKey(ValueKey('assistant-task-${child.id}'));
          expect(card, findsOneWidget);
          expect(find.descendant(of: card, matching: find.text('查看并确认')), findsOneWidget);
          expect(find.descendant(of: card, matching: find.text('取消')), findsOneWidget);
          expect(f.bodies, hasLength(1), reason: 'Internal request has not been authorized');
          final control = find.descendant(of: card, matching: find.text(approve ? '查看并确认' : '取消'));
          await tester.ensureVisible(control); await tester.tap(control);
          if (approve) {
            await tester.pumpAndSettle();
            await tester.tap(find.text('确认本次操作'));
          }
          for (var i = 0; i < 300; i++) {
            await tick();
            if (f.repo.task(child.id)!.terminal) break;
          }
          expect(f.repo.task(child.id)!.terminal, isTrue);
          expect(f.bodies, hasLength(approve && mode != UiPresentationMode.textOnly ? 2 : 1));
          for (var i = 0; i < 30; i++) { await tick(); }
          if (approve && mode != UiPresentationMode.textOnly) {
            expect(agent.uiPresentation(parent.id)?.validated, isNotNull);
          } else {
            expect(agent.uiPresentation(parent.id)?.validated, isNull);
          }
          expect(f.callsOf('write'), 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(agent.close);
          HttpOverrides.global = previousOverrides;
        }
      });
    }
  }
}
