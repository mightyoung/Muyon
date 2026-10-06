import 'dart:convert';

/// RFC 8785 JCS. The strict reader additionally forbids integer literals outside
/// the project's safe integer range before any floating-point conversion.
String canonicalJson(Object? value) {
  if (value == null || value is bool) return '$value';
  if (value is String) {
    validateUnicode(value);
    return jsonEncode(value);
  }
  if (value is int) {
    if (value.abs() > 9007199254740991) {
      throw const FormatException('Unsafe integer; use a string');
    }
    return '$value';
  }
  if (value is double) {
    if (!value.isFinite) throw const FormatException('Non-finite number');
    if (value == 0) return '0';
    final negative = value < 0;
    final raw = value.abs().toString().toLowerCase();
    final parts = raw.split('e');
    final mantissa = parts.first;
    final dot = mantissa.indexOf('.');
    var digits = mantissa.replaceAll('.', '');
    var point =
        (dot < 0 ? mantissa.length : dot) +
        (parts.length == 2 ? int.parse(parts[1]) : 0);
    while (digits.length > 1 && digits.startsWith('0')) {
      digits = digits.substring(1);
      point--;
    }
    while (digits.length > 1 && digits.endsWith('0')) {
      digits = digits.substring(0, digits.length - 1);
    }
    String result;
    if (point > 0 && point <= 21) {
      result = point >= digits.length
          ? digits + '0' * (point - digits.length)
          : '${digits.substring(0, point)}.${digits.substring(point)}';
    } else if (point <= 0 && point > -6) {
      result = '0.${'0' * -point}$digits';
    } else {
      final exponent = point - 1;
      final suffix = digits.length > 1 ? '.${digits.substring(1)}' : '';
      result = '${digits[0]}${suffix}e${exponent >= 0 ? '+' : ''}$exponent';
    }
    return '${negative ? '-' : ''}$result';
  }
  if (value is List) return '[${value.map(canonicalJson).join(',')}]';
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort((a, b) => a.compareTo(b));
    return '{${keys.map((key) => '${canonicalJson(key)}:${canonicalJson(value[key])}').join(',')}}';
  }
  throw const FormatException('Unsupported JSON value');
}

void validateUnicode(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Unpaired Unicode surrogate');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Unpaired Unicode surrogate');
    }
  }
}

Object? strictJsonDecode(String text) => _Reader(text).read();

class _Reader {
  _Reader(this.text);
  final String text;
  int offset = 0;
  void space() {
    while (offset < text.length && ' \t\r\n'.contains(text[offset])) {
      offset++;
    }
  }

  Never fail() =>
      throw FormatException('Invalid or duplicate JSON', text, offset);
  Object? read() {
    final result = value(0);
    space();
    if (offset != text.length) fail();
    return result;
  }

  Object? value(int depth) {
    if (depth > 64) fail();
    space();
    if (offset >= text.length) fail();
    final c = text[offset];
    if (c == '"') return string();
    if (c == '{' || c == '[') {
      offset++;
      space();
      final map = <String, Object?>{};
      final list = <Object?>[];
      final end = c == '{' ? '}' : ']';
      if (offset < text.length && text[offset] == end) {
        offset++;
        return c == '{' ? map : list;
      }
      while (true) {
        if (c == '{') {
          space();
          final key = string();
          if (map.containsKey(key)) fail();
          space();
          if (offset >= text.length || text[offset++] != ':') fail();
          map[key] = value(depth + 1);
        } else {
          list.add(value(depth + 1));
        }
        space();
        if (offset >= text.length) fail();
        final separator = text[offset++];
        if (separator == end) break;
        if (separator != ',') fail();
      }
      return c == '{' ? map : list;
    }
    for (final literal in ['true', 'false', 'null']) {
      if (text.startsWith(literal, offset)) {
        offset += literal.length;
        return literal == 'null' ? null : literal == 'true';
      }
    }
    final match = RegExp(
      r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
    ).matchAsPrefix(text, offset);
    if (match == null) fail();
    final token = match.group(0)!;
    offset += token.length;
    if (!token.contains(RegExp('[.eE]'))) {
      final integer = BigInt.parse(token);
      if (integer.abs() > BigInt.from(9007199254740991)) fail();
      return integer.toInt();
    }
    final number = double.parse(token);
    if (!number.isFinite) fail();
    return number;
  }

  String string() {
    if (offset >= text.length || text[offset] != '"') fail();
    final start = offset++;
    while (offset < text.length) {
      final c = text[offset++];
      if (c == '\\') {
        offset++;
        continue;
      }
      if (c == '"') {
        final result = jsonDecode(text.substring(start, offset)) as String;
        validateUnicode(result);
        return result;
      }
    }
    fail();
  }
}
