import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_eval/agent_eval.dart';
import 'package:muyon/screens/assistant_page.dart';

/// A summary request is a model request, not a tool operation.
void main() {
  test('the confirmation is titled by what it confirms', () {
    expect(confirmTitle('model'), '确认发送给模型');
    expect(confirmTitle('compaction'), '确认发送较早内容做摘要');
    expect(confirmTitle('tool'), '确认工具操作');
  });

  test('the evaluation confirms a summary request like a model request', () {
    expect(confirmsAsModelRequest('model'), isTrue);
    expect(confirmsAsModelRequest('compaction'), isTrue);
    expect(confirmsAsModelRequest('tool'), isFalse);
  });
}
