import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  testWidgets('confirmation expands exact preview without altering approval', (
    tester,
  ) async {
    final f = (await tester.runAsync(LoopFixture.open))!;
    final agent = f.agent();
    final conversation = (await tester.runAsync(
      () => f.repo.createConversation(),
    ))!;
    final task = (await tester.runAsync(
      () => f.start(agent, f.profile(), conversationId: conversation.id),
    ))!;
    final preview = task.payload['preview'];
    final digest = task.payload['requestDigest'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantPage(
            repo: f.repo,
            agent: agent,
            profiles: ProfileRepository(WorkspaceRepository(f.repo.database)),
            conversationId: conversation.id,
          ),
        ),
      ),
    );
    await tester.tap(find.text('查看并确认'));
    await tester.pumpAndSettle();
    expect(find.text('原始请求详情'), findsOneWidget);
    final raw = const JsonEncoder.withIndent('  ').convert(preview);
    expect(find.text(raw), findsNothing);
    await tester.ensureVisible(find.text('原始请求详情'));
    await tester.tap(find.text('原始请求详情'));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
    expect(f.repo.task(task.id)!.payload['requestDigest'], digest);
    expect(f.repo.task(task.id)!.payload['preview'], preview);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
