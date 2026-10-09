import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/src/app/app_state.dart';
import 'package:inquiry_module/src/features/ai/ask_page.dart';
import 'package:inquiry_module/src/features/ai/ask_history.dart';
import 'package:supplier_core/supplier_core.dart';

class _State extends AppState {
  _State(super.store, super.dataDir, this.client) : super.test();
  final LlmClient client;
  @override
  Future<LlmClient?> llm({AiCancellation? cancellation}) async => client;
}

class _FailBindingState extends _State {
  _FailBindingState(super.store, super.dataDir, super.client);
  var failOnce = true;
  @override
  void saveSetting(String key, String? value) {
    if (key == 'ask_history' && value!.contains('job_id') && failOnce) {
      failOnce = false;
      throw const FileSystemException('test binding storage failure');
    }
    super.saveSetting(key, value);
  }
}

class _FailHistoryState extends _State {
  _FailHistoryState(
    super.store,
    super.dataDir,
    super.client, {
    this.failFinal = false,
  });
  final bool failFinal;
  @override
  void saveSetting(String key, String? value) {
    if (key == 'ask_history' &&
        (!failFinal || (jsonDecode(value!) as List).length > 1)) {
      throw const FileSystemException('test history storage failure');
    }
    super.saveSetting(key, value);
  }
}

String? _diskHistory(Directory dir) {
  final file = File('${dir.path}/settings.json');
  if (!file.existsSync()) return null;
  return (jsonDecode(file.readAsStringSync()) as Map)['ask_history'] as String?;
}

void main() {
  test('restored evidence retains original unverified warning packet', () {
    final answer = AssistantAnswer.fromRun(
      '[[supplier:546aff01-c05c-4e08-ac41-09ffc126235a|未核验供应商]]',
      [],
      modelCalls: 1,
      elapsed: Duration.zero,
    );
    final saved = writeAskHistory([
      AskHistoryMessage(false, answer.text, evidence: answer),
    ]);
    final restored = readAskHistory(saved);
    final packet =
        (jsonDecode(writeAskHistory(restored)) as List).single[3]['evidence'];
    expect(packet, answer.toJson());
  });
  testWidgets(
    'question and job are saved before model; leaving retains pause',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('ask_pending');
      final store = Store.open('${dir.path}/store.db', device: 'test');
      final pending = Completer<Map<String, Object?>>();
      late _State state;
      String? historyAtModel;
      state = _State(
        store,
        dir,
        LlmClient(
          const LlmConfig(apiKey: 'fake'),
          transport: (_) {
            historyAtModel = _diskHistory(dir);
            return pending.future;
          },
        ),
      );
      addTearDown(() {
        state.dispose();
        store.close();
        dir.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AskPage(state: state)),
        ),
      );
      await tester.enterText(find.byType(TextField), '保留这个问题');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      expect(historyAtModel, isNotNull);
      final saved = jsonDecode(historyAtModel!) as List;
      expect(saved.single[1], '保留这个问题');
      expect(saved.single[3]['job_id'], state.aiTasks.single.id);
      await tester.pumpWidget(const SizedBox());
      pending.complete({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': '迟到回答'},
          },
        ],
      });
      await tester.pumpAndSettle();
      final after = jsonDecode(_diskHistory(dir)!) as List;
      expect(after, hasLength(2));
      expect(after.last[2], isTrue);
      expect(state.aiTasks.single.status, 'paused');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed job binding pauses before any model call', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ask_bind_failure');
    final store = Store.open('${dir.path}/store.db', device: 'test');
    var calls = 0;
    final state = _FailBindingState(
      store,
      dir,
      LlmClient(
        const LlmConfig(apiKey: 'fake'),
        transport: (_) async {
          calls++;
          return {
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'must not run'},
              },
            ],
          };
        },
      ),
    );
    addTearDown(() {
      state.dispose();
      store.close();
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AskPage(state: state)),
      ),
    );
    await tester.enterText(find.byType(TextField), '先绑定任务');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(state.aiTasks.single.status, 'paused');
    final saved = jsonDecode(_diskHistory(dir)!) as List;
    expect(saved.first[3]['job_id'], state.aiTasks.single.id);
    expect(saved.last[2], isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final failFinal in [false, true]) {
    testWidgets('history storage failure restores composer final=$failFinal', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('ask_save_failure');
      final store = Store.open('${dir.path}/store.db', device: 'test');
      var calls = 0;
      final state = _FailHistoryState(
        store,
        dir,
        LlmClient(
          const LlmConfig(apiKey: 'fake'),
          transport: (_) async {
            calls++;
            return {
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': '完整回答'},
                },
              ],
            };
          },
        ),
        failFinal: failFinal,
      );
      addTearDown(() {
        state.dispose();
        store.close();
        dir.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AskPage(state: state)),
        ),
      );
      await tester.enterText(find.byType(TextField), '保存失败测试');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      expect(calls, failFinal ? 1 : 0);
      if (failFinal) expect(state.aiTasks.single.status, 'ready');
    });
  }

  testWidgets('resuming legacy history binds its existing question', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ask_legacy_resume');
    final store = Store.open('${dir.path}/store.db', device: 'test');
    final state = _State(
      store,
      dir,
      LlmClient(
        const LlmConfig(apiKey: 'fake'),
        transport: (_) async => {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': '恢复回答'},
            },
          ],
        },
      ),
    );
    addTearDown(() {
      state.dispose();
      store.close();
      dir.deleteSync(recursive: true);
    });
    String? jobId;
    try {
      await state.runAiTask(
        AiTask.conversation,
        {'question': '旧问题', 'history': <Object?>[]},
        (_) async => throw LlmException('暂停'),
        onCreated: (id) => jobId = id,
      );
    } on LlmException {}
    state.saveSetting(
      'ask_history',
      jsonEncode([
        [true, '旧问题', false],
        [false, '暂停', true],
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AskPage(state: state, resumeJobId: jobId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final saved = jsonDecode(_diskHistory(dir)!) as List;
    expect(saved.where((row) => row[0] == true), hasLength(1));
    expect(saved.first[3]['job_id'], jobId);
    expect(saved.last[3]['job_id'], jobId);
  });

  testWidgets('completed evidence and job survive opening history again', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ask_restore');
    final store = Store.open('${dir.path}/store.db', device: 'test');
    final supplierId = store.save('supplier', {
      for (final field in Supplier.fields) field: null,
      'name': '证据供应商',
      'aliases': <String>[],
      'categories': <String>[],
    });
    var calls = 0;
    final state = _State(
      store,
      dir,
      LlmClient(
        const LlmConfig(apiKey: 'fake'),
        transport: (_) async {
          calls++;
          if (calls == 1)
            return {
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'supplier_lookup',
                        'type': 'function',
                        'function': {
                          'name': 'get',
                          'arguments': jsonEncode({
                            'type': 'supplier',
                            'id': supplierId,
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            };
          return {
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '完整回答'},
              },
            ],
          };
        },
      ),
    );
    addTearDown(() {
      state.dispose();
      store.close();
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AskPage(state: state)),
      ),
    );
    await tester.enterText(find.byType(TextField), '问题');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();
    final saved = jsonDecode(_diskHistory(dir)!) as List;
    expect((saved.last as List).length, 4);
    expect(saved.last[3]['job_id'], saved.first[3]['job_id']);
    expect(saved.last[3]['evidence']['text'], '完整回答');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AskPage(state: state)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查询依据（1 次）'), findsOneWidget);
    final observation = saved.last[3]['evidence']['observations'].single;
    expect(observation['call_id'], 'supplier_lookup');
    expect(observation['result'], contains('证据供应商'));
    expect(find.text('历史回答，未保留查询依据'), findsNothing);
  });
}
