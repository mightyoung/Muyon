part of 'spec_parse.dart';

/// One requirement row before it is saved: "温湿度传感器 ×25 个" and its
/// clauses.
class SpecItemDraft {
  SpecItemDraft(
    this.name,
    this.text, {
    this.qty,
    this.unit,
    this.specClass,
    this.clauses = const [],
    this.projectItemId,
  });
  final String name, text;
  final String? qty, unit, specClass;

  /// The budget line the item came from, if any.
  final String? projectItemId;
  final List<SpecClause> clauses;
}

/// Reads [name] and [text] into a draft: class from the name (then the
/// text), clauses split and parsed.
SpecItemDraft draftItem(
  String name,
  String text, {
  String? qty,
  String? unit,
  String? specClass,
  String? projectItemId,
}) {
  final cls = specClass ?? guessSpecClass([name]) ?? guessSpecClass([text]);
  return SpecItemDraft(
    name,
    text,
    qty: qty,
    unit: unit,
    specClass: cls,
    projectItemId: projectItemId,
    clauses: [
      for (final (i, c) in splitClauses(text).indexed)
        parseClause(cls, i + 1, c),
    ],
  );
}

/// Requirement rows of a workbook (name + requirement columns), or null.
List<SpecItemDraft>? specItemsFromWorkbook(XWorkbook book) => [
  for (final r in requirementRows(book) ?? const <Map<String, String?>>[])
    draftItem(
      r['name']!,
      r['specification'] ?? '',
      qty: r['qty'],
      unit: r['unit'],
    ),
].nullIfEmpty;

/// Pasted text: a table copied from Excel, or paragraphs separated by blank
/// lines whose short first line names the equipment.
List<SpecItemDraft> specItemsFromText(String text) {
  if (tableFromText(text) case final book?) {
    if (specItemsFromWorkbook(book) case final items?) return items;
  }
  return [
    for (final para in text.split(RegExp(r'\n\s*\n')))
      if (para.trim().isNotEmpty) _paragraph(para.trim()),
  ];
}

SpecItemDraft _paragraph(String para) {
  final lines = para.split(RegExp(r'\r?\n'));
  final first = lines.first.trim().replaceFirst(RegExp(r'[:：]$'), '');
  final named =
      lines.length > 1 &&
      first.length <= 30 &&
      !_numbering.hasMatch(first) &&
      !RegExp(r'\d').hasMatch(first);
  return named
      ? draftItem(first, lines.skip(1).join('\n'))
      : draftItem('', para);
}

extension on List<SpecItemDraft> {
  List<SpecItemDraft>? get nullIfEmpty => isEmpty ? null : this;
}

// ------------------------------------------------------------ splitting --

final _numbering = RegExp(
  r'^\s*(?:[(（]\s*\d{1,2}\s*[)）]|\d{1,2}\s*[)）、．](?!\d)|\d{1,2}\.(?!\d)'
  r'|[①-⑳]|[一二三四五六七八九十]{1,3}\s*[、．.])\s*',
);
final _inlineNumber = RegExp(
  r'(?=[(（]\d{1,2}[)）])|(?<![\dA-Za-z.(（])(?=\d{1,2}[)）])|(?=[①-⑳])',
);
const _markChars = {
  '★': ClauseMark.star,
  '☆': ClauseMark.star,
  '※': ClauseMark.star,
  '▲': ClauseMark.triangle,
  '△': ClauseMark.triangle,
  '#': ClauseMark.triangle,
  '＃': ClauseMark.triangle,
};

bool _heading(String l) =>
    RegExp(r'[:：]$').hasMatch(l) &&
    !RegExp(r'\d').hasMatch(l) &&
    l.length <= 30;

/// Clauses of a requirement text: one per numbered item; unnumbered lines
/// split at "；" and "。". Headings such as "主要技术指标：" are dropped.
List<String> splitClauses(String text) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || _heading(line)) continue;
    final bare = line.replaceFirst(RegExp(r'^[★☆※▲△#＃]\s*'), '');
    final parts = _numbering.hasMatch(bare)
        ? line.split(_inlineNumber)
        : line.split(RegExp(r'[；;]|。(?=\S)'));
    // A mark written before a number ("；★（2）") belongs to the next part.
    var carry = '';
    for (final p in parts) {
      final m = RegExp(r'[★☆※▲△#＃]\s*$').firstMatch(p.trimRight());
      final body = m == null ? p : p.trimRight().substring(0, m.start);
      final c = '$carry$body'.trim().replaceFirst(RegExp(r'[；;。，,、\s]+$'), '');
      carry = m == null ? '' : m[0]!.trim();
      if (c.isEmpty || _heading(c)) continue;
      if (_markOnly(c)) {
        carry = '$c$carry';
      } else {
        out.add(c);
      }
    }
  }
  return out;
}

bool _markOnly(String s) => RegExp(r'^[★☆※▲△#＃\s]+$').hasMatch(s);

(ClauseMark, String) _head(String raw) {
  var t = raw.trim();
  var mark = ClauseMark.none;
  while (t.isNotEmpty) {
    if (_markChars[t[0]] case final m?) {
      mark = m;
      t = t.substring(1).trimLeft();
    } else if (_numbering.firstMatch(t) case final m? when m.end > 0) {
      t = t.substring(m.end);
    } else {
      break;
    }
  }
  if (mark == ClauseMark.none) {
    if (RegExp(r'[(（]\s*实质性').hasMatch(t)) mark = ClauseMark.star;
    if (RegExp(r'[(（]\s*重要').hasMatch(t)) mark = ClauseMark.triangle;
  }
  return (mark, t);
}

// -------------------------------------------------------------- parsing --

/// Comparison words, longer spellings first (附录 A). "better" means "no
/// worse than": ≥ or ≤ by the parameter's direction.
const _before = [
  ('大于或等于', 'ge'), ('大于等于', 'ge'), ('不小于', 'ge'), ('不少于', 'ge'), //
  ('至少', 'ge'), ('≥', 'ge'), ('>=', 'ge'),
  ('小于或等于', 'le'), ('小于等于', 'le'), ('不大于', 'le'), ('不超过', 'le'),
  ('不高于', 'le'), ('不多于', 'le'), ('最多', 'le'), ('≤', 'le'), ('<=', 'le'),
  ('不低于', 'better'), ('不劣于', 'better'), ('不差于', 'better'),
  ('优于', 'better'), ('好于', 'better'), ('达到', 'better'),
  ('大于', 'gt'), ('高于', 'gt'), ('超过', 'gt'), ('>', 'gt'),
  ('小于', 'lt'), ('低于', 'lt'), ('<', 'lt'),
];
const _after = [
  ('及以上', 'ge'),
  ('以上', 'ge'),
  ('起', 'ge'),
  ('及以下', 'le'),
  ('以下', 'le'),
  ('以内', 'le'),
];
const _cmpLabels = {'ge': '不小于', 'le': '不大于', 'gt': '大于', 'lt': '小于'};

/// Model codes, class names and words that are not requirement values.
const _plainWords = {
  'cpu', 'gpu', 'plc', 'io', 'ai', 'ao', 'di', 'do', 'pc', 'ipc', 'os', //
  'led', 'usb', 'lan', 'wifi',
};
const _envCue = '工作|环境|使用|运行|储存|存储';

class _Hit {
  _Hit(this.start, this.end, this.kind, this.options, [this.value]);
  final int start, end;

  /// 'mention' (a parameter's name), 'choice' (an enum value) or 'fixed'
  /// (IP, Ex, catalog: the value is complete).
  final String kind;

  /// Parameters (and the value code for a choice) this spelling can mean.
  final List<(SpecProperty, String?)> options;
  final Map<String, Object?>? value;
  int get length => end - start;
  bool overlaps(_Hit o) => start < o.end && o.start < end;
}

class _Number {
  _Number(
    this.start,
    this.end,
    this.shape,
    this.v,
    this.units, {
    this.max,
    this.basis,
  });
  final int start, end;
  final String shape; // num, range, tol
  final String v;
  final String? max, basis;

  /// (quantity kind, unit code) readings; (null, "核") for counted words,
  /// (null, null) when no unit is written.
  final List<(String?, String?)> units;
}

/// Parses one clause of an item of [classCode]. Never guesses: when a value
/// has no single fitting parameter, or text is left over that looks like a
/// requirement, the clause carries a [SpecClause.hint].
SpecClause parseClause(String? classCode, int n, String raw) {
  final (mark, body) = _head(raw);
  final cls = classCode == null ? null : specClass(classCode);
  if (cls == null) return SpecClause(n, raw, mark: mark);
  return _ClauseReader(classCode!, body, mark).read(n, raw);
}
