import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/app_state.dart';
import 'package:inquiry_module/src/app/theme.dart';
import 'package:inquiry_module/src/features/ai/ask_page.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

import 'host_attachment_test.dart' show HostModelSettings, HostSecrets;

const _notice = '本次任务含外部内容或宿主污染状态无法确认，写入与外发须逐次确认。';

void main() {
  for (final scenario in [
    'missing',
    'tainted',
    'throws',
    'unknown',
    'mismatch',
    'clean',
    'repeat',
  ]) {
    for (final network in [false, true]) {
      if (scenario == 'repeat' && !network) continue;
      testWidgets(
        '$scenario host facts require review of ${network ? 'outbound' : 'write'}',
        (tester) async {
          final directory = Directory.systemTemp.createTempSync('folio-taint');
          final db = sqlite3.openInMemory();
          final jobsDb = sqlite3.openInMemory();
          createSchema(db);
          AiJobStore.initializeSchema(jobsDb);
          final store = Store.attach(
            db,
            device: 'host',
            backgroundExecutor: <T>(action) async => action(),
          );
          final supplier = store.save('supplier', {
            for (final field in Supplier.fields) field: null,
            'name': '原供应商',
            'aliases': <String>[],
            'categories': <String>[],
          });
          var calls = 0;
          final identities = <List<String>>[];
          bool? probe(String taskId, String conversationId) {
            identities.add([taskId, conversationId]);
            if (scenario == 'throws') throw StateError('facts unavailable');
            if (scenario == 'unknown') return null;
            if (taskId != 'host-task' ||
                conversationId != 'host-conversation') {
              return true;
            }
            return scenario != 'clean';
          }

          final state = AppState.attach(
            store: store,
            dataDir: directory,
            aiJobs: AiJobStore.attach(jobsDb),
            secrets: HostSecrets(),
            sharedModelSettings: HostModelSettings(),
            sharedLlmFactory: ({AiCancellation? cancellation}) async =>
                LlmClient(
                  const LlmConfig(apiKey: 'fake'),
                  transport: (_) async => {
                    'choices': [
                      {
                        'message': ++calls <= (scenario == 'repeat' ? 2 : 1)
                            ? {
                                'tool_calls': [
                                  {
                                    'id': 'action-$calls',
                                    'type': 'function',
                                    'function': {
                                      'name': network
                                          ? 'web_search'
                                          : 'update_record',
                                      'arguments': jsonEncode(
                                        network
                                            ? {'query': '公开检索'}
                                            : {
                                                'type': 'supplier',
                                                'id': supplier,
                                                'values': {'name': '新供应商'},
                                              },
                                      ),
                                    },
                                  },
                                ],
                              }
                            : {'content': '完成'},
                      },
                    ],
                  },
                ),
            hostTaintProbe: scenario == 'missing' ? null : probe,
            hostTaskId: scenario == 'missing'
                ? null
                : scenario == 'mismatch'
                ? 'folio-ai-job'
                : 'host-task',
            hostConversationId: scenario == 'missing'
                ? null
                : 'host-conversation',
          );
          addTearDown(() async {
            await state.shutdown();
            state.dispose();
            db.close();
            jobsDb.close();
            directory.deleteSync(recursive: true);
          });
          state.assistantPermission = AssistantPermission.bypass;
          state.assistantWebEnabled = network;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(),
              home: Scaffold(body: AskPage(state: state)),
            ),
          );
          await tester.enterText(find.byType(TextField), '执行请求');
          await tester.pump();
          await tester.tap(find.byTooltip('发送'));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(find.text(network ? '确认联网搜索' : '确认修改供应商'), findsOneWidget);
          expect(
            find.text(_notice),
            scenario == 'clean' ? findsNothing : findsOneWidget,
          );
          expect(find.textContaining('会话内允许'), findsNothing);
          expect(state.assistantPermission, AssistantPermission.confirmWrites);
          expect(store.get('supplier', supplier)!.data['name'], '原供应商');
          if (scenario != 'missing') {
            expect(identities, isNotEmpty);
            expect(
              identities.every(
                (ids) =>
                    ids[0] ==
                        (scenario == 'mismatch'
                            ? 'folio-ai-job'
                            : 'host-task') &&
                    ids[1] == 'host-conversation',
              ),
              isTrue,
            );
          }
          if (scenario == 'repeat') {
            await tester.tap(find.text('允许此次请求'));
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 50));
            }
            expect(find.text('确认联网搜索'), findsOneWidget);
            expect(find.text(_notice), findsOneWidget);
          }
          await tester.tap(find.text('拒绝'));
          await tester.pumpAndSettle();
          expect(store.get('supplier', supplier)!.data['name'], '原供应商');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
