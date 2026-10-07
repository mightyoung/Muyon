/// Read-only incremental scanner for what a compatibility-mode model streams
/// (ADR-0005 §5.3). The stream carries the JSON protocol, which the person
/// must never see: this class turns it into progress, or into the text of the
/// `answer` value only. It affects display and nothing else; the strict parse
/// after `Done` is the only authority, and a reply that fails it is dropped.
library;

enum ProtocolPhase {
  /// `type` is not known yet (or is not a type the scanner shows).
  thinking,

  /// `type` is `answer`: [ProtocolStreamView.text] is its value so far.
  answering,

  /// `type` is `tool`: only the fact is shown, never the id or parameters.
  preparingTool,

  /// The reply does not start with `{` (prose, a fence, native markup): only
  /// progress is shown, whatever follows.
  plain,
}

enum _S { start, key, inKey, colon, value, string, other, between, end }

class ProtocolStreamView {
  _S _state = _S.start;
  final _key = StringBuffer();
  String _currentKey = '';
  final _type = StringBuffer();
  final _answer = StringBuffer();
  var _escape = false;
  // Pending `\uXXXX`; null when not inside one.
  StringBuffer? _unicode;
  // Depth and string tracking of a value that is skipped (object, array,
  // number, literal). `toolId` and `parameters` are skipped, never kept.
  var _depth = 0;
  var _skipString = false;
  var _skipEscape = false;
  var _plain = false;
  var _typeDone = false;

  /// Takes the next piece of the reply text.
  void feed(String chunk) {
    for (final unit in chunk.runes) {
      _step(String.fromCharCode(unit));
    }
  }

  static bool _space(String c) =>
      c == ' ' || c == '\n' || c == '\r' || c == '\t';

  void _step(String c) {
    switch (_state) {
      case _S.start:
        if (_space(c)) return;
        if (c == '{') {
          _state = _S.key;
        } else {
          _plain = true;
          _state = _S.end;
        }
      case _S.key:
        if (_space(c) || c == ',') return;
        if (c == '"') {
          _key.clear();
          _state = _S.inKey;
        } else {
          // `}` or garbage: nothing more to show.
          _state = _S.end;
        }
      case _S.inKey:
        if (_stringChar(c, _key, cap: 32)) {
          _currentKey = _key.toString();
          _state = _S.colon;
        }
      case _S.colon:
        if (_space(c)) return;
        _state = c == ':' ? _S.value : _S.end;
      case _S.value:
        if (_space(c)) return;
        if (c == '"') {
          _escape = false;
          _unicode = null;
          if (_currentKey == 'type') {
            _type.clear();
            _typeDone = false;
          } else if (_currentKey == 'answer') {
            // A repeated key: the last one is what the strict parse keeps.
            _answer.clear();
          }
          _state = _S.string;
        } else {
          _depth = 0;
          _skipString = false;
          _skipEscape = false;
          _state = _S.other;
          _step(c);
        }
      case _S.string:
        final sink = switch (_currentKey) {
          'type' => _type,
          'answer' => _answer,
          _ => null,
        };
        if (_stringChar(c, sink, cap: _currentKey == 'type' ? 32 : null)) {
          if (_currentKey == 'type') _typeDone = true;
          _state = _S.between;
        }
      case _S.other:
        if (_skipString) {
          if (_skipEscape) {
            _skipEscape = false;
          } else if (c == '\\') {
            _skipEscape = true;
          } else if (c == '"') {
            _skipString = false;
          }
          return;
        }
        if (c == '"') {
          _skipString = true;
        } else if (c == '{' || c == '[') {
          _depth++;
        } else if (c == '}' || c == ']') {
          if (_depth == 0) {
            _state = _S.end;
          } else {
            _depth--;
          }
        } else if (c == ',' && _depth == 0) {
          _state = _S.key;
        }
      case _S.between:
        if (_space(c)) return;
        if (c == ',') {
          _state = _S.key;
        } else {
          _state = _S.end;
        }
      case _S.end:
        break;
    }
  }

  /// Consumes one character of a JSON string; true when its closing quote
  /// arrives. Escapes are undone into [sink] (null: the value is not kept).
  /// [cap] limits short values; the answer is unbounded (the response size is
  /// capped upstream).
  bool _stringChar(String c, StringBuffer? sink, {int? cap}) {
    void put(String text) {
      if (sink != null && (cap == null || sink.length < cap)) sink.write(text);
    }

    final unicode = _unicode;
    if (unicode != null) {
      unicode.write(c);
      if (unicode.length == 4) {
        _unicode = null;
        final code = int.tryParse(unicode.toString(), radix: 16);
        put(String.fromCharCode(code ?? 0xFFFD));
      }
      return false;
    }
    if (_escape) {
      _escape = false;
      if (c == 'u') {
        _unicode = StringBuffer();
      } else {
        put(switch (c) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          'b' => '\b',
          'f' => '\f',
          '"' || '\\' || '/' => c,
          _ => '\uFFFD',
        });
      }
      return false;
    }
    if (c == '\\') {
      _escape = true;
      return false;
    }
    if (c == '"') return true;
    put(c);
    return false;
  }

  /// What the reply is, as far as it has been read.
  ProtocolPhase get phase {
    if (_plain) return ProtocolPhase.plain;
    return switch (_typeValue) {
      'answer' => ProtocolPhase.answering,
      'tool' => ProtocolPhase.preparingTool,
      _ => ProtocolPhase.thinking,
    };
  }

  // `type` counts once its value is closed; `answer` may come before it and
  // is held back until then.
  String? get _typeValue => _typeDone ? _type.toString() : null;

  /// The answer text to show: only when `type` is `answer`, never a lone high
  /// surrogate at the end (it waits for its pair).
  String get text {
    if (phase != ProtocolPhase.answering) return '';
    final all = _answer.toString();
    if (all.isEmpty) return all;
    final last = all.codeUnitAt(all.length - 1);
    return last >= 0xD800 && last <= 0xDBFF
        ? all.substring(0, all.length - 1)
        : all;
  }
}
