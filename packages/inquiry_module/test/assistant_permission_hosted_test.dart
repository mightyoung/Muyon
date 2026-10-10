import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/app_state.dart';
import 'package:inquiry_module/src/app/theme.dart';
import 'package:inquiry_module/src/features/ai/ask_page.dart';
import 'package:inquiry_module/src/features/settings/ai_settings.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

import 'host_attachment_test.dart' show HostModelSettings, HostSecrets;

Map<String, Object?> _reply(Map<String, Object?> message) => {
  'choices': [
    {'message': message},
  ],
};

Map<String, Object?> _tool(String name, Map<String, Object?> args) => _reply({
  'tool_calls': [
    {
      'id': 'hosted-action',
      'type': 'function',
      'function': {'name': name, 'arguments': jsonEncode(args)},
    },
  ],
});

Future<void> _start(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: AskPage(state: state)),
    ),
  );
  await tester.enterText(find.byType(TextField), '执行请求');
  await tester.pump();
  await tester.tap(find.byTooltip('发送'));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('hosted', () {
    late Directory directory;
    late Database db, jobsDb;
    late Store store;
    late AppState state;
    late String supplierId;
    late Transport transport;

    setUp(() {
      directory = Directory.systemTemp.createTempSync(
        'assistant-permission-hosted',
      );
      db = sqlite3.openInMemory();
      jobsDb = sqlite3.openInMemory();
      createSchema(db);
      AiJobStore.initializeSchema(jobsDb);
      store = Store.attach(
        db,
        device: 'host',
        backgroundExecutor: <T>(action) async => await action(),
      );
      supplierId = store.save('supplier', {
        for (final field in Supplier.fields) field: null,
        'name': '原供应商',
        'aliases': <String>[],
        'categories': <String>[],
      });
      transport = (_) async => _reply({'content': '未使用'});
      state = AppState.attach(
        store: store,
        dataDir: directory,
        aiJobs: AiJobStore.attach(jobsDb),
        secrets: HostSecrets(),
        sharedLlmFactory: ({cancellation}) async =>
            LlmClient(const LlmConfig(apiKey: 'fake'), transport: transport),
        sharedModelSettings: HostModelSettings(),
      );
    });
    tearDown(() async {
      await state.shutdown();
      state.dispose();
      db.close();
      jobsDb.close();
      directory.deleteSync(recursive: true);
    });

    test(
      'a stored bypass reads as confirmWrites and the stored value is kept',
      () {
        state.assistantPermission = AssistantPermission.bypass;
        expect(state.assistantPermission, AssistantPermission.confirmWrites);
        expect(state.setting('assistant_permission'), 'bypass');
        state.assistantPermission = AssistantPermission.readOnly;
        expect(state.assistantPermission, AssistantPermission.readOnly);
        state.assistantPermission = AssistantPermission.confirmWrites;
        expect(state.assistantPermission, AssistantPermission.confirmWrites);
      },
    );

    test(
      'a stored bypass without an approval interface is refused, not applied',
      () async {
        state.assistantPermission = AssistantPermission.bypass;
        final tools = AssistantAppTools(
          store,
          permission: state.assistantPermission,
          sessionId: 'hosted-bypass',
        );
        await expectLater(
          tools.execute(
            'update_record',
            {
              'type': 'supplier',
              'id': supplierId,
              'values': {'name': '不应自动写入'},
            },
            callId: 'hosted-bypass-1',
            cancellation: AiCancellation(),
          ),
          throwsFormatException,
        );
        expect(store.get('supplier', supplierId)!.data['name'], '原供应商');
      },
    );

    testWidgets('a stored bypass still asks before a write', (tester) async {
      var requests = 0;
      transport = (_) async => ++requests == 1
          ? _tool('update_record', {
              'type': 'supplier',
              'id': supplierId,
              'values': {'name': '新供应商'},
            })
          : _reply({'content': '操作处理完毕。'});
      state.assistantPermission = AssistantPermission.bypass;
      await _start(tester, state);
      expect(state.assistantPermission, AssistantPermission.confirmWrites);
      expect(find.text('确认修改供应商'), findsOneWidget);
      expect(store.get('supplier', supplierId)!.data['name'], '原供应商');
      expect(
        store.db.select(
          "SELECT value FROM meta WHERE key LIKE 'assistant_action:%'",
        ),
        isEmpty,
      );
      await tester.tap(find.text('确认修改'));
      await tester.pumpAndSettle();
      expect(store.get('supplier', supplierId)!.data['name'], '新供应商');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'hosted settings are hidden and compatibility AskPage hides bypass',
      (tester) async {
        state.assistantPermission = AssistantPermission.bypass;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: SingleChildScrollView(child: AiSettings(state: state)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // REG-4c removes the entire hosted permission surface, a stronger
        // boundary than merely omitting bypass from an accessible dropdown.
        expect(find.byType(DropdownButton<AssistantPermission>), findsNothing);
        expect(find.text('助手操作权限'), findsNothing);
        expect(find.text('助手联网查询'), findsNothing);
        expect(find.textContaining('助手会直接保存修改和联网请求'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(body: AskPage(state: state)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('助手权限'));
        await tester.pumpAndSettle();
        expect(find.textContaining('自动执行（免确认）'), findsNothing);
        expect(find.text('✓ 修改前逐次确认'), findsOneWidget);
      },
    );
  });

  group('standalone', () {
    late Directory directory;
    late Store store;
    late AppState state;

    setUp(() {
      directory = Directory.systemTemp.createTempSync(
        'assistant-permission-standalone',
      );
      store = Store.open('${directory.path}/data.db', device: 'test');
      state = AppState.test(store, directory);
    });
    tearDown(() async {
      await state.shutdown();
      state.dispose();
      store.close();
      directory.deleteSync(recursive: true);
    });

    testWidgets('a stored bypass reads as bypass and both selectors list it', (
      tester,
    ) async {
      state.assistantPermission = AssistantPermission.bypass;
      expect(state.assistantPermission, AssistantPermission.bypass);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(child: AiSettings(state: state)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButton<AssistantPermission>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(DropdownMenuItem<AssistantPermission>, '自动执行（免确认）'),
        findsWidgets,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: AskPage(state: state)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('助手权限'));
      await tester.pumpAndSettle();
      expect(find.text('✓ 自动执行（免确认）'), findsOneWidget);
    });
  });
}
