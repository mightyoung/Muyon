import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_context.dart';
import 'package:muyon/assistant/agent_drafts.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_provider.dart';

import 'support/agent_loop_fixture.dart';

/// K-2b: the draft of a streamed reply is a read-only, in-memory view. It
/// never reaches the task payload, the conversation, the ledger or the
/// events (which keep its length and digest), and in compatibility mode it
/// never contains protocol JSON.
const _compat = ModelCapabilities(
  streaming: true,
  source: CapabilitySource.preset,
);
const _mark = 'DRAFT-MARK-成本合计';

/// [text] cut into [pieces] streamed content deltas, optionally ending with
/// [finish].
List<String> _pieces(String text, {int pieces = 4, String? finish = 'stop'}) {
  final runes = text.runes.toList();
  final size = (runes.length / pieces).ceil();
  return [
    for (var i = 0; i < runes.length; i += size)
      sseChunk({'content': String.fromCharCodes(runes.skip(i).take(size))}),
    if (finish != null) sseChunk({}, finish: finish),
    if (finish != null) 'data: [DONE]\n\n',
  ];
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// All events of the agent's draft stream, from now on.
List<AgentDraft> _record(PersonalAgent agent) {
  final seen = <AgentDraft>[];
  final sub = agent.drafts.listen(seen.add);
  addTearDown(sub.cancel);
  return seen;
}

String _everything(LoopFixture f, PersonalTask task) => jsonEncode({
  'payload': f.repo.task(task.id)!.payload,
  'messages': [for (final m in f.repo.messages(task.conversationId)) m.content],
  'ledger': f.ledger.recent(),
});

void main() {
  test(
    'compat: the draft is the answer text only, never protocol JSON',
    () async {
      final f = await LoopFixture.open();
      const answer =
          '{"type":"answer","answer":"$_mark 2080 元","citationIds":[]}';
      f.replies.add(LoopReply.sse(_pieces(answer, pieces: 9)));
      final agent = f.agent();
      final seen = _record(agent);
      var task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _compat)),
      );
      await _settle();
      expect(task.state, PersonalTaskState.succeeded);
      final shown = [for (final d in seen) d.text].where((t) => t.isNotEmpty);
      expect(shown, isNotEmpty);
      for (final t in shown) {
        expect('$_mark 2080 元'.startsWith(t), isTrue, reason: t);
      }
      for (final d in seen) {
        for (final bad in ['{', '"type"', 'answer', 'toolId', 'citationIds']) {
          expect(d.text, isNot(contains(bad)));
        }
      }
      expect(seen.first.stage, DraftStage.generating);
      expect(seen.last.stage, DraftStage.committed);
      expect(
        agent.draftOf(task.id),
        isNull,
        reason: 'superseded by the message',
      );
      // The answer is the saved message; the events carry size and digest.
      final events = (f.repo.task(task.id)!.payload['events'] as List)
          .cast<Map>();
      final response = events.firstWhere((e) => e['type'] == 'model_response');
      final data = response['data'] as Map;
      expect(data['draftLength'], '$_mark 2080 元'.length);
      expect(data['draftDigest'], AgentContext.digest('$_mark 2080 元'));
      expect(jsonEncode(events), isNot(contains(_mark)));
    },
  );

  test('compat: a tool step shows only that a tool is being prepared', () async {
    final f = await LoopFixture.open();
    f.replies.add(
      LoopReply.sse(
        _pieces(
          '{"type":"tool","toolId":"write","parameters":{"note":"ARG-SECRET"}}',
          pieces: 7,
        ),
      ),
    );
    final agent = f.agent();
    final seen = _record(agent);
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _compat)),
    );
    await _settle();
    expect(task.stage, 'tool', reason: 'the call waits for the person');
    expect(seen.map((d) => d.stage), contains(DraftStage.preparingTool));
    expect(seen.every((d) => d.text.isEmpty), isTrue);
    expect(seen.last.stage, DraftStage.committed);
  });

  test(
    'compat: a reply that breaks the protocol is dropped, nothing quoted',
    () async {
      final f = await LoopFixture.open();
      f.replies.add(LoopReply.sse(_pieces('$_mark，销售合计 2380 元。')));
      final agent = f.agent();
      final seen = _record(agent);
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _compat)),
        max: 1,
      );
      await _settle();
      expect(seen.map((d) => d.stage), contains(DraftStage.discarded));
      expect(
        seen.every((d) => d.text.isEmpty),
        isTrue,
        reason: 'prose is progress only',
      );
      expect(agent.draftOf(task.id), isNull);
      // The existing correction path is unchanged: one more confirmation.
      final after = f.repo.task(task.id)!;
      expect(after.state, PersonalTaskState.waitingConfirmation);
      expect(after.payload['protocolCorrections'], 1);
      expect(_everything(f, after), isNot(contains(_mark)));
    },
  );

  test('a reply cut short keeps its draft on screen and out of everything '
      'else', () async {
    final f = await LoopFixture.open();
    f.replies.add(
      LoopReply.sse(
        _pieces(
          '{"type":"answer","answer":"$_mark 还没写完',
          pieces: 6,
          finish: null,
        ),
      ),
    );
    final agent = f.agent();
    final seen = _record(agent);
    var task = await f.start(agent, f.profile(capabilities: _compat));
    task = await f.run(agent, task);
    await _settle();
    expect(task.state, PersonalTaskState.failed);
    expect(seen.last.stage, DraftStage.interrupted);
    expect(seen.last.text, startsWith('DRAFT-MARK'));
    expect(agent.draftOf(task.id), isNull);
    final all = _everything(f, task);
    expect(all, isNot(contains('DRAFT-MARK')));
    expect(all, isNot(contains('还没写完')));
    expect(f.repo.messages(task.conversationId).map((m) => m.role), ['user']);
    expect(task.error, isNot(contains('DRAFT-MARK')));
    expect(task.error, contains('stream_truncated'));
  });

  test('a length-truncated reply is interrupted, not saved', () async {
    final f = await LoopFixture.open();
    f.replies.add(
      LoopReply.sse(
        _pieces('{"type":"answer","answer":"$_mark 被截断"}', finish: 'length'),
      ),
    );
    final agent = f.agent();
    final seen = _record(agent);
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: _compat)),
    );
    await _settle();
    expect(task.state, PersonalTaskState.failed);
    expect(seen.last.stage, DraftStage.interrupted);
    expect(seen.last.text, contains('DRAFT-MARK'));
    expect(_everything(f, task), isNot(contains('DRAFT-MARK')));
  });

  test(
    'cancelling mid-stream interrupts the draft; events keep size only',
    () async {
      final f = await LoopFixture.open();
      final hold = Completer<void>();
      f.replies.add(
        LoopReply.sse([
          sseChunk({'content': '{"type":"answer","answer":"$_mark 写到一半'}),
          sseChunk({'content': '，还有'}),
          ..._pieces('', finish: 'stop'),
        ], hold: hold.future),
      );
      final agent = f.agent();
      final seen = _record(agent);
      final task = await f.start(agent, f.profile(capabilities: _compat));
      final pending = agent
          .confirm(
            task.id,
            requestDigest: task.payload['requestDigest'] as String,
          )
          .catchError((Object _) {});
      while (!seen.any((d) => d.text.contains('DRAFT-MARK'))) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(agent.draftOf(task.id)!.stage, DraftStage.generating);
      await agent.cancel(task.id);
      hold.complete();
      await pending;
      await _settle();
      final after = f.repo.task(task.id)!;
      expect(after.state, PersonalTaskState.cancelled);
      expect(seen.last.stage, DraftStage.interrupted);
      expect(seen.last.text, contains('DRAFT-MARK'));
      expect(agent.draftOf(task.id), isNull);
      expect(_everything(f, after), isNot(contains('DRAFT-MARK')));
    },
  );

  test(
    'native: text deltas show as they come; a call shows only the fact',
    () async {
      final f = await LoopFixture.open();
      f.replies.add(
        LoopReply.sse([
          ..._pieces('先查一下 $_mark', pieces: 3, finish: null),
          ...sseCalls([("c1", "write", '{"note":"ARG-SECRET"}')]),
        ]),
      );
      final agent = f.agent();
      final seen = _record(agent);
      final task = await f.run(agent, await f.start(agent, f.profile()));
      await _settle();
      expect(task.stage, 'tool');
      final texts = [for (final d in seen) d.text].where((t) => t.isNotEmpty);
      expect(texts.length, greaterThan(1), reason: 'incremental');
      expect(texts.last, '先查一下 $_mark');
      expect(seen.map((d) => d.stage), contains(DraftStage.preparingTool));
      for (final d in seen) {
        expect(d.text, isNot(contains('ARG-SECRET')));
        expect(d.text, isNot(contains('write')));
      }
      expect(seen.last.stage, DraftStage.committed);
    },
  );

  test('native answer: committed, and only the message remains', () async {
    final f = await LoopFixture.open();
    f.replies.add(LoopReply.sse(_pieces('成本合计 2080 元')));
    final agent = f.agent();
    final seen = _record(agent);
    final task = await f.run(agent, await f.start(agent, f.profile()));
    await _settle();
    expect(task.state, PersonalTaskState.succeeded);
    expect(seen.last.stage, DraftStage.committed);
    expect(f.repo.messages(task.conversationId).last.content, '成本合计 2080 元');
  });

  test('a non-streaming compat task has no draft at all', () async {
    final f = await LoopFixture.open();
    f.replies.add(
      LoopReply.sse([
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': '{"type":"answer","answer":"成本合计 2080 元"}',
              },
            },
          ],
        }),
      ]),
    );
    final agent = f.agent();
    final seen = _record(agent);
    final task = await f.run(
      agent,
      await f.start(agent, f.profile(capabilities: ModelCapabilities.compat)),
    );
    await _settle();
    expect(task.state, PersonalTaskState.succeeded);
    expect(f.bodies.single['stream'], isFalse);
    expect(seen, isEmpty);
  });
}
