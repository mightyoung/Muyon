import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_drafts.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/draft_view.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/agent_loop_fixture.dart';

/// K-2b: how a draft looks on the assistant page, in each stage, and that the
/// page shows what the core exposes (answer text only) and drops it once the
/// reply is the saved message.
Widget _host(Widget child) => MaterialApp(
  theme: muyonTheme(Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  group('DraftView', () {
    Future<void> show(WidgetTester tester, AgentDraft draft) =>
        tester.pumpWidget(_host(DraftView(draft: draft)));

    testWidgets('no text yet: progress only', (tester) async {
      await show(tester, const AgentDraft('t', DraftStage.generating));
      expect(find.text('正在思考…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('text so far, marked as not confirmed complete', (
      tester,
    ) async {
      await show(
        tester,
        const AgentDraft('t', DraftStage.generating, text: '成本合计'),
      );
      expect(find.text('成本合计'), findsOneWidget);
      expect(find.text('生成中，尚未确认完成'), findsOneWidget);
    });

    testWidgets('a tool call: only the fact', (tester) async {
      await show(tester, const AgentDraft('t', DraftStage.preparingTool));
      expect(find.text('正在准备调用工具…'), findsOneWidget);
    });

    testWidgets('interrupted: the text stays, marked as not saved', (
      tester,
    ) async {
      await show(
        tester,
        const AgentDraft('t', DraftStage.interrupted, text: '写到一半'),
      );
      expect(find.text('写到一半'), findsOneWidget);
      expect(find.text('已中断，部分内容未保存'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('discarded: told so, nothing quoted', (tester) async {
      await show(tester, const AgentDraft('t', DraftStage.discarded));
      expect(find.text('回复格式不符，已丢弃'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('text is shown as text, not interpreted', (tester) async {
      const odd = '**x** <b>y</b> {"type":"answer"}';
      await show(
        tester,
        const AgentDraft('t', DraftStage.generating, text: odd),
      );
      expect(find.text(odd), findsOneWidget);
    });
  });

  group('AssistantPage over a real stream', () {
    testWidgets('shows the answer text as it streams, never the protocol, and '
        'drops the draft once the message is saved', (tester) async {
      final f = (await tester.runAsync(LoopFixture.open))!;
      // The test binding answers every HTTP request with 400; this endpoint
      // is a loopback fake, so the real client is used.
      HttpOverrides.global = null;
      final hold = Completer<void>();
      f.replies.add(
        LoopReply.sse([
          sseChunk({'content': '{"type":"answer","answer":"成本合计'}),
          sseChunk({'content': ' 2080 元","citationIds":[]}'}),
          sseChunk({}, finish: 'stop'),
          'data: [DONE]\n\n',
        ], hold: hold.future),
      );
      final agent = f.agent();
      final c = (await tester.runAsync(() => f.repo.createConversation()))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssistantPage(
              repo: f.repo,
              agent: agent,
              profiles: ProfileRepository(WorkspaceRepository(f.repo.database)),
              conversationId: c.id,
            ),
          ),
        ),
      );
      final task = (await tester.runAsync(
        () => f.start(
          agent,
          f.profile(
            capabilities: const ModelCapabilities(
              streaming: true,
              source: CapabilitySource.preset,
            ),
          ),
          conversationId: c.id,
        ),
      ))!;
      await tester.pump();
      late Future<void> pending;
      await tester.runAsync(() async {
        pending = agent
            .confirm(
              task.id,
              requestDigest: task.payload['requestDigest'] as String,
            )
            .catchError((Object _) {});
      });
      // The first piece has arrived; the endpoint now holds the rest back.
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find
                .byKey(const ValueKey('assistant-draft'))
                .evaluate()
                .isNotEmpty &&
            find.text('成本合计').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byKey(const ValueKey('assistant-draft')), findsOneWidget);
      expect(find.text('成本合计'), findsOneWidget);
      expect(find.text('生成中，尚未确认完成'), findsOneWidget);
      expect(find.textContaining('"type"'), findsNothing);
      expect(find.textContaining('{'), findsNothing);

      hold.complete();
      await tester.runAsync(() => pending);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('assistant-draft')), findsNothing);
      expect(find.text('成本合计 2080 元'), findsOneWidget, reason: 'the message');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cancelled stream leaves the draft, marked, on the page', (
      tester,
    ) async {
      final f = (await tester.runAsync(LoopFixture.open))!;
      // The test binding answers every HTTP request with 400; this endpoint
      // is a loopback fake, so the real client is used.
      HttpOverrides.global = null;
      final hold = Completer<void>();
      f.replies.add(
        LoopReply.sse([
          sseChunk({'content': '{"type":"answer","answer":"写到一半'}),
          sseChunk({'content': '，后面'}),
          sseChunk({}, finish: 'stop'),
          'data: [DONE]\n\n',
        ], hold: hold.future),
      );
      final agent = f.agent();
      final c = (await tester.runAsync(() => f.repo.createConversation()))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssistantPage(
              repo: f.repo,
              agent: agent,
              profiles: ProfileRepository(WorkspaceRepository(f.repo.database)),
              conversationId: c.id,
            ),
          ),
        ),
      );
      final task = (await tester.runAsync(
        () => f.start(
          agent,
          f.profile(
            capabilities: const ModelCapabilities(
              streaming: true,
              source: CapabilitySource.preset,
            ),
          ),
          conversationId: c.id,
        ),
      ))!;
      late Future<void> pending;
      await tester.runAsync(() async {
        pending = agent
            .confirm(
              task.id,
              requestDigest: task.payload['requestDigest'] as String,
            )
            .catchError((Object _) {});
      });
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text('写到一半').evaluate().isNotEmpty) break;
      }
      expect(find.text('写到一半'), findsOneWidget);
      await tester.runAsync(() => agent.cancel(task.id));
      hold.complete();
      await tester.runAsync(() => pending);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('写到一半'), findsOneWidget);
      expect(find.text('已中断，部分内容未保存'), findsOneWidget);
      // Not a message of the conversation.
      expect(f.repo.messages(c.id).map((m) => m.role), ['user']);
      // Leaving the page drops it.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssistantPage(
              repo: f.repo,
              agent: agent,
              profiles: ProfileRepository(WorkspaceRepository(f.repo.database)),
              conversationId: c.id,
            ),
          ),
        ),
      );
      expect(find.text('写到一半'), findsNothing);
    });
  });
}
