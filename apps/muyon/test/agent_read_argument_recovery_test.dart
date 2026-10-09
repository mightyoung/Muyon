import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  for (final mixed in [false, true]) {
    test(
      'read argument correction continues with receipt; mixed=$mixed',
      () async {
        final f = await LoopFixture.open();
        f.addTool(
          'invalid',
          ToolEffect.read,
          onCall: (_) async => ToolCallResult(
            status: ToolCallStatus.invalidArguments,
            summary: 'field: unknown field bad',
            data: {'error': 'field: unknown field bad'},
          ),
        );
        f.replies
          ..add(
            LoopReply.sse(
              sseCalls([
                ('bad', 'invalid', '{}'),
                if (mixed) ('oldwrite', 'write', '{}'),
              ]),
            ),
          )
          ..add(LoopReply.sse(sseCalls([('fixed', 'read', '{}')])))
          ..add(LoopReply.sse(sseText('已修正 [r1]')));
        final agent = f.agent();
        final task = await f.run(agent, await f.start(agent, f.profile()));
        expect(task.state, PersonalTaskState.succeeded);
        expect(f.callsOf('read'), 1);
        expect(f.callsOf('write'), 0);
        expect(f.receipts(), hasLength(2));
        final messages = f.bodies[1]['messages'] as List;
        final bad = messages.singleWhere((m) => m['tool_call_id'] == 'bad');
        expect(
          jsonDecode(bad['content'])['trustedToolResult']['status'],
          'invalidArguments',
        );
        if (mixed) {
          final oldwrite = messages.singleWhere(
            (m) => m['tool_call_id'] == 'oldwrite',
          );
          expect(
            jsonDecode(oldwrite['content'])['notExecuted'],
            contains('参数'),
          );
        }
        expect(
          (task.payload['toolLog'] as List).first['status'],
          'invalidArguments',
        );
      },
    );
  }
  test(
    'corrected read and manual detail share readable facts and raw receipts',
    () async {
      final f = await LoopFixture.open();
      const facts = {
        'price': '1200',
        'currency': 'CNY',
        'source': 'https://example.com/verified-quote',
        'status': 'unknown',
        'conflicts': ['税率待核对'],
        'actual_receipts': [
          {'id': 'saved-combined', 'status': 'saved'},
        ],
      };
      f.addTool(
        'invalid',
        ToolEffect.read,
        onCall: (_) async => ToolCallResult(
          status: ToolCallStatus.invalidArguments,
          summary: 'unknown field',
        ),
      );
      f.addTool(
        'corrected',
        ToolEffect.read,
        onCall: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: '实际报价查询结果',
          data: facts,
        ),
      );
      f.replies
        ..add(
          LoopReply.sse(
            sseCalls([('bad', 'invalid', '{}'), ('oldwrite', 'write', '{}')]),
          ),
        )
        ..add(LoopReply.sse(sseCalls([('fixed', 'corrected', '{}')])))
        ..add(LoopReply.sse(sseText('查询完成 [r1]')));
      final agent = f.agent();
      final corrected = await f.run(agent, await f.start(agent, f.profile()));
      expect(corrected.state, PersonalTaskState.succeeded);
      expect(f.callsOf('write'), 0);
      final toolMessage = (f.bodies[2]['messages'] as List).singleWhere(
        (m) => m['tool_call_id'] == 'fixed',
      );
      expect(
        jsonDecode(toolMessage['content'])['trustedToolResult']['data'],
        facts,
      );
      final detail = await agent.startTool(
        conversationId: corrected.conversationId,
        toolId: 'corrected',
      );
      expect(detail.state, PersonalTaskState.succeeded);
      final answer = f.repo.messages(corrected.conversationId).last.content;
      for (final text in [
        '价格：1200',
        '来源：https://example.com/verified-quote',
        '未知（unknown）',
        '税率待核对',
        'saved-combined',
      ]) {
        expect(answer, contains(text));
      }
      expect(answer, isNot(contains('"price":')));
      expect(
        f.tools
            .history()
            .where((r) => r.status == ToolCallStatus.succeeded)
            .map((r) => r.data),
        [facts, facts],
      );
      expect(f.receipts(), hasLength(3));
    },
  );
  test(
    'manual read with invalid arguments ends failed without a model',
    () async {
      final f = await LoopFixture.open();
      f.addTool(
        'manual',
        ToolEffect.read,
        onCall: (_) async => ToolCallResult(
          status: ToolCallStatus.invalidArguments,
          summary: 'invalid input',
        ),
      );
      final agent = f.agent();
      final conversation = await f.repo.createConversation();
      final task = await agent.startTool(
        conversationId: conversation.id,
        toolId: 'manual',
      );
      expect(f.repo.task(task.id)!.state, PersonalTaskState.failed);
      expect(f.bodies, isEmpty);
    },
  );
  test('unknown FormatException from a handler never continues', () async {
    final f = await LoopFixture.open();
    f.addTool(
      'exception',
      ToolEffect.read,
      onCall: (_) async =>
          throw const FormatException('unexpected storage format'),
    );
    f.replies.add(LoopReply.sse(sseCalls([('error', 'exception', '{}')])));
    final agent = f.agent();
    final task = await f.run(agent, await f.start(agent, f.profile()));
    expect(task.state, PersonalTaskState.failed);
    expect(f.bodies, hasLength(1));
    expect(
      jsonDecode(f.receipts().single['result_json'] as String)['status'],
      'failed',
    );
  });
  test('an effectful invalidArguments receipt never continues', () async {
    final f = await LoopFixture.open();
    f.addTool(
      'effect',
      ToolEffect.write,
      onCall: (_) async => ToolCallResult(
        status: ToolCallStatus.invalidArguments,
        summary: 'write invalid',
      ),
    );
    f.replies.add(LoopReply.sse(sseCalls([('error', 'effect', '{}')])));
    final agent = f.agent();
    final task = await f.run(
      agent,
      await f.start(agent, f.profile()),
      confirmTools: true,
    );
    expect(task.state, PersonalTaskState.failed);
    expect(f.bodies, hasLength(1));
  });
  for (final status in [
    ToolCallStatus.failed,
    ToolCallStatus.blocked,
    ToolCallStatus.cancelled,
    ToolCallStatus.interrupted,
  ]) {
    test('$status never continues to model', () async {
      final f = await LoopFixture.open();
      f.addTool(
        'stop',
        ToolEffect.read,
        onCall: (_) async => ToolCallResult(
          status: status,
          summary: 'stop',
          data: {'error': 'bad arguments'},
        ),
      );
      f.replies.add(LoopReply.sse(sseCalls([('stop', 'stop', '{}')])));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.terminal, isTrue);
      expect(f.bodies, hasLength(1));
    });
  }
}
