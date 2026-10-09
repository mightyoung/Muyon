import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/assistant_subconversations.dart';
import 'package:muyon/screens/assistant_page.dart';
import 'package:muyon/screens/assistant_subconversation_panel.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/ui_navigation_fixture.dart';

void main() {
  testWidgets(
    'stale child keyboard submission keeps pending text and creates no task',
    (tester) async {
      final f = await NavigationFixture.open(tester);
      final s = AssistantSubconversations(f.host.foundation);
      final ref = (await tester.runAsync(
        () => s.openSubconversation('task', '初始'),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            repo: f.host.foundation,
            agent: f.host.personalAgent,
            profiles: ProfileRepository(f.host.workspaces),
            conversationId: ref.childConversationId,
          ),
        ),
      );
      await tester.runAsync(
        () => f.host.foundation.database.write(
          (db) =>
              db.execute('UPDATE conversations SET scope_json=? WHERE id=?', [
                jsonEncode(AssistantScope.workspace('changed').toJson()),
                f.conversationId,
              ]),
        ),
      );
      f.host.foundation.refresh();
      await tester.pump();
      await tester.enterText(find.byType(TextField), '父范围失效也不能丢失');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await NavigationFixture.frames(tester);
      expect(find.text('父范围失效也不能丢失'), findsOneWidget);
      expect(
        f.host.foundation.tasks(conversationId: ref.childConversationId),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'corrupt unrelated relation is preserved and shown without breaking parent page',
    (tester) async {
      final f = await NavigationFixture.open(tester);
      await tester.runAsync(
        () => f.host.foundation.database.write((db) {
          db.execute(
            "UPDATE execution_records SET payload=json_set(payload,'\$.prompt','父任务','\$.stage','paused','\$.executionDeviceId','local','\$.state','paused') WHERE id='task'",
          );
          db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
            'subconversation:broken',
            '{',
          ]);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            repo: f.host.foundation,
            agent: f.host.personalAgent,
            profiles: ProfileRepository(f.host.workspaces),
            conversationId: f.conversationId,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('子对话'), findsOneWidget);
      expect(find.textContaining('损坏'), findsWidgets);
      expect(
        f.host.foundation.database.raw.select(
          'SELECT value FROM settings WHERE key=?',
          ['subconversation:broken'],
        ).single['value'],
        '{',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'corrupt child workspace opens a read-only error without overwriting data',
    (tester) async {
      final f = await NavigationFixture.open(tester);
      final s = AssistantSubconversations(f.host.foundation);
      final ref = (await tester.runAsync(
        () => s.openSubconversation('task', '原始问题'),
      ))!;
      final key = 'subconversation-ui:${ref.childConversationId}';
      await tester.runAsync(
        () => f.host.foundation.database.write(
          (db) =>
              db.execute('UPDATE settings SET value=? WHERE key=?', ['{', key]),
        ),
      );
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
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('现场读取失败'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        f.host.foundation.database.raw.select(
          'SELECT value FROM settings WHERE key=?',
          [key],
        ).single['value'],
        '{',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'corrupt read history preserves other versions without breaking parent',
    (tester) async {
      final f = await NavigationFixture.open(tester);
      final service = AssistantSubconversations(f.host.foundation);
      await tester.runAsync(
        () => f.host.foundation.database.write(
          (db) => db.execute(
            "UPDATE execution_records SET payload=json_set(payload,'\$.prompt','父任务','\$.stage','paused','\$.executionDeviceId','local','\$.state','paused') WHERE id='task'",
          ),
        ),
      );
      final ref = (await tester.runAsync(
        () => service.openSubconversation('task', '子问题'),
      ))!;
      await tester.runAsync(() => service.readLatestSubconversation(ref));
      await tester.runAsync(
        () => f.host.foundation.database.write(
          (db) => db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
            'subconversation-read:${ref.childConversationId}:broken',
            '{',
          ]),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantPage(
            repo: f.host.foundation,
            agent: f.host.personalAgent,
            profiles: ProfileRepository(f.host.workspaces),
            conversationId: f.conversationId,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('损坏'), findsWidgets);
      expect(service.reads(ref), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('older parent child stays reachable after eight newer tasks', (
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
    final service = AssistantSubconversations(f.host.foundation);
    final ref = (await tester.runAsync(
      () => service.openSubconversation('task', '存档子目标'),
    ))!;
    await tester.runAsync(() async {
      await service.readLatestSubconversation(ref);
      for (var i = 0; i < 8; i++) {
        await f.host.personalAgent.start(
          conversationId: f.conversationId,
          prompt: '新父任务 $i',
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AssistantPage(
          repo: f.host.foundation,
          agent: f.host.personalAgent,
          profiles: ProfileRepository(f.host.workspaces),
          conversationId: f.conversationId,
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('打开子对话 · 存档子目标'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 50,
    );
    expect(find.text('打开子对话 · 存档子目标'), findsOneWidget);
    expect(find.text('查询最新'), findsOneWidget);
    expect(find.textContaining('只读引用 ·'), findsOneWidget);
    expect(service.loadWorkspace(ref).draftText, '存档子目标');
    await tester.pumpWidget(const SizedBox());
  });
}
