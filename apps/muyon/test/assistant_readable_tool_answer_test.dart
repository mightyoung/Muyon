import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  test(
    'manual read answer shows readable facts and retains original receipts',
    () async {
      final f = await LoopFixture.open();
      const data = {
        'price': '1200',
        'currency': 'CNY',
        'source': 'https://example.com/quote',
        'status': 'unknown',
        'conflicts': ['税率待核对'],
        'actual_receipts': [
          {'id': 'saved-1', 'status': 'saved'},
        ],
      };
      f.tools.register(
        providerId: 'host.test',
        descriptor: ToolDescriptor(
          toolId: 'readable',
          moduleId: 'test',
          effect: ToolEffect.read,
          parameterSchema: const {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        handler: (_) async => ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: '实际报价查询结果',
          data: data,
        ),
      );
      final conversation = await f.repo.createConversation();
      final task = await f.agent().startTool(
        conversationId: conversation.id,
        toolId: 'readable',
      );
      expect(task.state, PersonalTaskState.succeeded);
      final answer = f.repo
          .messages(conversation.id)
          .singleWhere((m) => m.role == 'assistant')
          .content;
      expect(answer, contains('实际报价查询结果'));
      expect(answer, contains('价格：1200'));
      expect(answer, contains('来源：https://example.com/quote'));
      expect(answer, contains('未知（unknown）'));
      expect(answer, contains('税率待核对'));
      expect(answer, contains('saved-1'));
      expect(answer, isNot(contains('"price":')));
      expect(f.tools.history().single.data, data);
      final call = (task.payload['step'] as Map)['calls'] as List;
      expect(
        f.tools
            .receiptFor((call.single as Map)['invocationId'] as String)!
            .result!
            .data,
        data,
      );
      final messages = task.payload['messages'] as List;
      final toolMessage =
          jsonDecode((messages.last as Map)['content'] as String) as Map;
      expect((toolMessage['trustedToolResult'] as Map)['data'], data);
      expect(
        (((call.single as Map)['outcome'] as Map)['result'] as Map)['data'],
        data,
      );
    },
  );
}
