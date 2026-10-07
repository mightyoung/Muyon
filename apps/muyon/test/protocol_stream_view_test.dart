import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/protocol_stream_view.dart';

/// K-2b: what the person may see while a compatibility-mode reply streams.
/// The scanner only ever exposes a phase and the text of `answer`.
const _answer = '{"type":"answer","answer":"成本合计 2080 元","citationIds":[]}';

/// Feeds [text] in pieces of [size] and returns what was visible after each.
List<(ProtocolPhase, String)> _watch(String text, {int size = 1}) {
  final view = ProtocolStreamView();
  final seen = <(ProtocolPhase, String)>[];
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length; i += size) {
    view.feed(String.fromCharCodes(runes.skip(i).take(size)));
    seen.add((view.phase, view.text));
  }
  return seen;
}

void main() {
  test('an answer shows only the answer text, growing', () {
    final seen = _watch(_answer);
    expect(seen.first.$1, ProtocolPhase.thinking);
    expect(seen.last, (ProtocolPhase.answering, '成本合计 2080 元'));
    var previous = '';
    for (final (_, text) in seen) {
      expect('成本合计 2080 元'.startsWith(text), isTrue, reason: text);
      expect(text.length >= previous.length, isTrue);
      expect(text, isNot(contains('{')));
      expect(text, isNot(contains('type')));
      expect(text, isNot(contains('"')));
      previous = text;
    }
    // Nothing is shown before `type` is closed.
    expect(
      seen
          .takeWhile((s) => s.$1 == ProtocolPhase.thinking)
          .every((s) => s.$2.isEmpty),
      isTrue,
    );
  });

  test('the result does not depend on where the chunks are cut', () {
    for (final size in [1, 2, 3, 5, 7, 100]) {
      expect(_watch(_answer, size: size).last, (
        ProtocolPhase.answering,
        '成本合计 2080 元',
      ), reason: 'size $size');
    }
  });

  test('escapes are undone: quotes, newlines, unicode and surrogate pairs', () {
    final seen = _watch(r'{"type":"answer","answer":"a\"b\\c\nd你😀 \/ \t"}');
    expect(seen.last.$2, 'a"b\\c\nd你😀 / \t');
    for (final (_, text) in seen) {
      // A half of a surrogate pair is never exposed.
      expect(
        text.isEmpty ||
            !(text.codeUnitAt(text.length - 1) >= 0xD800 &&
                text.codeUnitAt(text.length - 1) <= 0xDBFF),
        isTrue,
      );
    }
  });

  test('`type` after `answer`: buffered, then released at once', () {
    final seen = _watch('{"answer":"先写答案","type":"answer"}');
    final firstShown = seen.indexWhere((s) => s.$2.isNotEmpty);
    expect(seen.take(firstShown).every((s) => s.$2.isEmpty), isTrue);
    expect(seen[firstShown].$2, '先写答案', reason: 'all of it, not a prefix');
    expect(seen.last, (ProtocolPhase.answering, '先写答案'));
  });

  test('a tool call shows only that one is being prepared', () {
    const tool =
        '{"type":"tool","toolId":"read","parameters":{"note":"SECRET-ARG",'
        '"x":{"type":"answer","answer":"nested"}},"destination":"d"}';
    final seen = _watch(tool);
    expect(seen.last, (ProtocolPhase.preparingTool, ''));
    for (final (_, text) in seen) {
      expect(text, isEmpty);
    }
  });

  test('an answer key inside a tool call is not an answer', () {
    final seen = _watch('{"type":"tool","answer":"hidden","toolId":"t"}');
    expect(seen.last, (ProtocolPhase.preparingTool, ''));
  });

  test('prose, fences and native markup only ever show progress', () {
    for (final reply in [
      '成本合计 2080 元',
      '```json\n$_answer\n```',
      '<｜｜DSML｜｜function_calls>{"type":"answer","answer":"x"}',
      'Sure! $_answer',
    ]) {
      final seen = _watch(reply, size: 3);
      expect(seen.last.$1, ProtocolPhase.plain, reason: reply);
      expect(seen.every((s) => s.$2.isEmpty), isTrue, reason: reply);
    }
  });

  test('leading whitespace before the brace is fine', () {
    expect(_watch('\n  $_answer').last.$1, ProtocolPhase.answering);
  });

  test('an unknown type stays at progress', () {
    final seen = _watch('{"type":"plan","answer":"nope"}');
    expect(seen.last, (ProtocolPhase.thinking, ''));
  });

  test('a repeated answer key shows the last, like the strict parse', () {
    expect(
      _watch('{"type":"answer","answer":"one","answer":"two"}').last.$2,
      'two',
    );
  });

  test('a partial or damaged reply never throws', () {
    for (final reply in [
      '{',
      '{"type',
      '{"type":"ans',
      '{"type":"answer","answer":"abc',
      '{"type":"answer","answer":"\\u12',
      '{"type":"answer","answer":123}',
      '{"type":"answer" "answer":"x"}',
      '}}}{{{',
      '',
    ]) {
      expect(() => _watch(reply), returnsNormally, reason: reply);
    }
    expect(_watch('{"type":"ans').last, (ProtocolPhase.thinking, ''));
    expect(_watch('{"type":"answer","answer":"abc').last.$2, 'abc');
  });
}
