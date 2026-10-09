import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/assistant_subconversation_panel.dart';
import 'package:muyon/platform/assistant_subconversations.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';

import 'support/ui_navigation_fixture.dart';

void main() {
  testWidgets('parent offers a one-level subconversation from a real task', (
    tester,
  ) async {
    final f = await NavigationFixture.open(tester);
    await tester.runAsync(
      () => f.host.foundation.database.write(
        (db) => db.execute(
          "UPDATE execution_records SET payload=json_set(payload,'\$.prompt','父任务','\$.stage','paused','\$.executionDeviceId','local','\$.state','paused') WHERE id='task'",
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantPage(
          repo: f.host.foundation,
          agent: f.host.personalAgent,
          profiles: ProfileRepository(f.host.workspaces),
          host: f.host,
          conversationId: f.conversationId,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('子对话'), findsOneWidget);
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets(
      'closing_panel_preserves_child_work; reopen input at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = await NavigationFixture.open(tester);
        final service = AssistantSubconversations(f.host.foundation);
        final ref = (await tester.runAsync(
          () => service.openSubconversation('task', '草稿问题'),
        ))!;
        final child = (await tester.runAsync(
          () => f.host.personalAgent.start(
            conversationId: ref.childConversationId,
            prompt: '子问题',
            profile: ModelProfile(
              id: 'test',
              endpoint: Uri.parse('http://127.0.0.1:1/v1'),
              location: ModelLocation.local,
              modelId: 'fixture',
              endpointIdentity: 'fixture',
            ),
          ),
        ))!;
        final before = f.host.foundation.task(child.id)!.state;
        final key = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: key,
            theme: ThemeData(
              brightness: width == 390 ? Brightness.dark : Brightness.light,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(width == 320 ? 2 : 1),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const Scaffold(body: Text('主任务')),
          ),
        );
        Future<void> open() async {
          key.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: AssistantSubconversationPanel(
                  service: service,
                  ref: ref,
                  agent: f.host.personalAgent,
                  profiles: ProfileRepository(f.host.workspaces),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await open();
        expect(find.text('子对话'), findsNothing);
        expect(find.text('回答后规划交互页面'), findsNothing);
        expect(find.byTooltip('新建对话'), findsNothing);
        await tester.enterText(find.byType(TextField), '关闭后还在的输入');
        await NavigationFixture.frames(tester);
        await tester.tap(find.byTooltip('保存并关闭子对话'));
        await NavigationFixture.frames(tester);
        await tester.pumpAndSettle();
        expect(find.text('主任务'), findsOneWidget);
        expect(service.loadWorkspace(ref).draftText, '关闭后还在的输入');
        expect(service.loadWorkspace(ref).openState, isFalse);
        expect(f.host.foundation.task(child.id)!.state, before);
        await open();
        expect(find.text('关闭后还在的输入'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('CAS conflict retains panel and pending input', (tester) async {
    final f = await NavigationFixture.open(tester);
    final s = AssistantSubconversations(f.host.foundation);
    final ref = (await tester.runAsync(
      () => s.openSubconversation('task', '初始'),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantSubconversationPanel(
            service: s,
            ref: ref,
            agent: f.host.personalAgent,
            profiles: ProfileRepository(f.host.workspaces),
          ),
        ),
      ),
    );
    await NavigationFixture.frames(tester);
    final current = s.loadWorkspace(ref).revision;
    await tester.runAsync(
      () => s.saveWorkspace(
        ref,
        SubconversationWorkspace(draftText: '另一窗口', revision: current + 1),
        expectedRevision: current,
      ),
    );
    await tester.enterText(find.byType(TextField), '不能丢失');
    await NavigationFixture.frames(tester);
    await tester.tap(find.byTooltip('保存并关闭子对话'));
    await NavigationFixture.frames(tester);
    expect(find.text('不能丢失'), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(s.loadWorkspace(ref).draftText, '另一窗口');
    await tester.pumpWidget(const SizedBox());
  });
}
