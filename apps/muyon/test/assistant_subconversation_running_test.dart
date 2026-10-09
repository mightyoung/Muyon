import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/assistant_subconversations.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/screens/assistant_subconversation_panel.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';

import 'support/agent_loop_fixture.dart';
import 'support/ui_navigation_fixture.dart';

void main() {
  testWidgets(
    'closing a real streaming task keeps it running; input and scroll restore',
    (tester) async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final f = (await tester.runAsync(LoopFixture.open))!;
      final agent = f.agent();
      final conversation = (await tester.runAsync(
        () => f.repo.createConversation(),
      ))!;
      final parent = (await tester.runAsync(
        () => agent.start(conversationId: conversation.id, prompt: '父任务'),
      ))!;
      final s = AssistantSubconversations(f.repo);
      final ref = (await tester.runAsync(
        () => s.openSubconversation(parent.id, '待发问题'),
      ))!;
      await tester.runAsync(() async {
        for (var i = 0; i < 15; i++) {
          await f.repo.appendMessage(
            ref.childConversationId,
            'assistant',
            '公开已有消息 $i\n用于滚动恢复的独立子消息内容',
          );
        }
        await s.saveWorkspace(
          ref,
          const SubconversationWorkspace(
            draftText: '待发问题',
            scrollOffset: 140,
            revision: 1,
          ),
          expectedRevision: 0,
        );
      });
      final release = (await tester.runAsync(() async => Completer<void>()))!;
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      f.replies.add(LoopReply.sse(sseText('真实本机流式回复'), hold: release.future));
      final child = (await tester.runAsync(
        () => f.start(
          agent,
          f.profile(),
          conversationId: ref.childConversationId,
        ),
      ))!;
      late Future<void> request;
      await tester.runAsync(() async {
        request = agent.confirm(
          child.id,
          requestDigest: child.payload['requestDigest'] as String,
        );
        for (var i = 0; i < 100 && f.bodies.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(f.bodies, hasLength(1));
      expect(f.repo.task(child.id)!.state, PersonalTaskState.running);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('父现场')),
        ),
      );
      Future<void> open() async {
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: AssistantSubconversationPanel(
                service: s,
                ref: ref,
                agent: agent,
                profiles: ProfileRepository(
                  WorkspaceRepository(f.repo.database),
                ),
              ),
            ),
          ),
        );
        await NavigationFixture.frames(tester);
        await tester.pump(const Duration(milliseconds: 400));
      }

      await open();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect(list.controller!.offset, 140);
      await tester.enterText(find.byType(TextField), '流式执行期间的新草稿');
      await NavigationFixture.frames(tester);
      await tester.tap(find.byTooltip('保存并关闭子对话'));
      await NavigationFixture.frames(tester);
      await NavigationFixture.frames(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('父现场'), findsOneWidget);
      expect(f.repo.task(child.id)!.state, PersonalTaskState.running);
      expect(s.loadWorkspace(ref).scrollOffset, 140);
      await open();
      expect(find.text('流式执行期间的新草稿'), findsOneWidget);
      expect(
        tester.widget<ListView>(find.byType(ListView).first).controller!.offset,
        140,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        release.complete();
      });
      for (
        var i = 0;
        i < 100 && f.repo.task(child.id)!.state == PersonalTaskState.running;
        i++
      ) {
        await NavigationFixture.frames(tester, count: 1);
      }
      expect(f.repo.task(child.id)!.state, PersonalTaskState.succeeded);
      await tester.runAsync(() => request.timeout(const Duration(seconds: 5)));
    },
  );
}
