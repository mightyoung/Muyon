import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../primitives.dart' show StatusTone;
import '../tokens.dart';
import 'state.dart';

Color _tone(MuyonTokens t, StatusTone tone) => switch (tone) {
  StatusTone.success => t.green,
  StatusTone.danger => t.red,
  StatusTone.warn => t.warn,
  StatusTone.neutral => t.ink2,
};

/// Label and value pairs, one per line, label above value when narrow.
class KeyValue extends StatelessWidget {
  const KeyValue({
    super.key,
    required this.items,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final List<(String, String)> items;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent => items.map((e) => '${e.$1}：${e.$2}').join('；');

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: MuyonTokens.space1 + 2,
              ),
              child: Wrap(
                spacing: MuyonTokens.space3,
                runSpacing: MuyonTokens.space1,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 96,
                      maxWidth: 220,
                    ),
                    child: Text(item.$1, style: TextStyle(color: t.ink3)),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SelectableText(
                      item.$2,
                      style: TextStyle(color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One headline number with its label, unit and an optional change note.
class Metric extends StatelessWidget {
  const Metric({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.delta,
    this.tone = StatusTone.neutral,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final String label, value;
  final String? unit, delta;
  final StatusTone tone;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent =>
      '$label：$value${unit ?? ''}${delta == null ? '' : '，$delta'}';

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      placeholderHeight: 88,
      excludeChildSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(MuyonTokens.space4),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.rule),
          borderRadius: BorderRadius.circular(MuyonTokens.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: t.ink3)),
            const SizedBox(height: MuyonTokens.space1),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: MuyonTokens.space1,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(color: t.ink, fontWeight: FontWeight.w600),
                ),
                if (unit != null) Text(unit!, style: TextStyle(color: t.ink2)),
              ],
            ),
            if (delta != null)
              Padding(
                padding: const EdgeInsets.only(top: MuyonTokens.space1),
                child: Text(delta!, style: TextStyle(color: _tone(t, tone))),
              ),
          ],
        ),
      ),
    );
  }
}

/// How a [CompareTable] cell stands among the candidates (design §5.2).
enum CompareMark {
  none(''),
  best('最优'),
  unmet('不满足'),
  unverified('未核验');

  const CompareMark(this.label);
  final String label;
}

/// A grid with a header row. Scrolls sideways instead of squeezing columns.
///
/// [marks] flags cells by (row, column): the best candidate, a requirement a
/// candidate does not meet, and a value nobody has verified. Each mark has an
/// icon and a word as well as a colour, and is part of the text equivalent.
class CompareTable extends StatelessWidget {
  const CompareTable({
    super.key,
    required this.columns,
    required this.rows,
    this.marks = const {},
    this.caption = '对比表',
    this.minColumnWidth = 120,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final List<String> columns;
  final List<List<String>> rows;
  final Map<(int, int), CompareMark> marks;
  final String caption;
  final double minColumnWidth;
  final UiComponentState state;
  final String? errorMessage;

  String _cellText(int r, int c) {
    final text = c < rows[r].length ? rows[r][c] : '—';
    final mark = marks[(r, c)] ?? CompareMark.none;
    return mark == CompareMark.none ? text : '$text（${mark.label}）';
  }

  String get textEquivalent {
    final lines = <String>[
      '$caption，${rows.length} 行 ${columns.length} 列：${columns.join('、')}',
      for (var r = 0; r < rows.length; r++)
        '第 ${r + 1} 行：${[for (var c = 0; c < columns.length; c++) '${columns[c]} ${_cellText(r, c)}'].join('，')}',
    ];
    return lines.join('。');
  }

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      excludeChildSemantics: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minColumnWidth * columns.length,
          ),
          child: Table(
            defaultColumnWidth: IntrinsicColumnWidth(),
            border: TableBorder(horizontalInside: BorderSide(color: t.rule)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: t.groupRow),
                children: [
                  for (final c in columns)
                    _Cell(c, header: true, minWidth: minColumnWidth),
                ],
              ),
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  children: [
                    for (var c = 0; c < columns.length; c++)
                      _Cell(
                        c < rows[r].length ? rows[r][c] : '—',
                        first: c == 0,
                        mark: marks[(r, c)] ?? CompareMark.none,
                        minWidth: minColumnWidth,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain table (rows and a header) in the library's four states; the
/// dynamic surface keeps its own `Table` node rendering until AIUI-5.
class MuyonTable extends StatelessWidget {
  const MuyonTable({
    super.key,
    required this.columns,
    required this.rows,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final List<String> columns;
  final List<List<String>> rows;
  final UiComponentState state;
  final String? errorMessage;

  String get textEquivalent =>
      CompareTable(columns: columns, rows: rows, caption: '表格').textEquivalent;

  @override
  Widget build(BuildContext context) => CompareTable(
    columns: columns,
    rows: rows,
    caption: '表格',
    state: state,
    errorMessage: errorMessage,
  );
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.text, {
    this.header = false,
    this.first = false,
    this.mark = CompareMark.none,
    this.minWidth = 0,
  });
  final String text;
  final bool header, first;
  final CompareMark mark;
  final double minWidth;
  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    final (fg, bg, icon) = switch (mark) {
      CompareMark.none => (t.ink, null, null),
      CompareMark.best => (t.green, t.greenBg, Icons.check_circle_outline),
      CompareMark.unmet => (t.red, t.redBg, Icons.cancel_outlined),
      CompareMark.unverified => (t.warn, t.warnBg, Icons.help_outline),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: Container(
        color: bg,
        padding: const EdgeInsets.all(MuyonTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: header ? t.ink2 : t.ink,
                fontWeight: header || first ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (icon != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: MuyonTokens.space1),
                  Text(mark.label, style: TextStyle(color: fg)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum ChartKind { bar, line, pie }

class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;
  final double value;
}

/// Bar, line or pie drawn with a [CustomPainter]; no chart package.
///
/// The numbers are always repeated in a table under the drawing, which is also
/// what a screen reader gets.
class Chart extends StatelessWidget {
  const Chart({
    super.key,
    required this.kind,
    required this.points,
    this.title,
    this.unit,
    this.state = UiComponentState.ready,
    this.errorMessage,
  });
  final ChartKind kind;
  final List<ChartPoint> points;
  final String? title, unit;
  final UiComponentState state;
  final String? errorMessage;

  String get _kindLabel => switch (kind) {
    ChartKind.bar => '柱状图',
    ChartKind.line => '折线图',
    ChartKind.pie => '饼图',
  };

  String get textEquivalent =>
      '$_kindLabel${title == null ? '' : '「$title」'}：'
      '${points.map((p) => '${p.label} ${uiFormatNumber(p.value)}${unit ?? ''}').join('；')}';

  static List<Color> palette(MuyonTokens t) => [
    t.accent,
    t.green,
    t.warn,
    t.red,
    t.ink2,
    t.ink3,
  ];

  @override
  Widget build(BuildContext context) {
    final t = MuyonTokens.of(context);
    return UiComponentFrame(
      state: state,
      textEquivalent: textEquivalent,
      errorMessage: errorMessage,
      placeholderHeight: 200,
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MuyonTokens.space2),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              key: const ValueKey('chart-canvas'),
              painter: _ChartPainter(kind, points, palette(t), t.rule, t.ink3),
            ),
          ),
          const SizedBox(height: MuyonTokens.space3),
          for (var i = 0; i < points.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: palette(t)[i % palette(t).length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: MuyonTokens.space2),
                  Expanded(
                    child: Text(
                      points[i].label,
                      style: TextStyle(color: t.ink2),
                    ),
                  ),
                  Text(
                    '${uiFormatNumber(points[i].value)}${unit ?? ''}',
                    style: TextStyle(color: t.ink, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.kind, this.points, this.colors, this.rule, this.label);
  final ChartKind kind;
  final List<ChartPoint> points;
  final List<Color> colors;
  final Color rule, label;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    switch (kind) {
      case ChartKind.pie:
        _pie(canvas, size);
      case ChartKind.bar:
        _bars(canvas, size);
      case ChartKind.line:
        _line(canvas, size);
    }
  }

  (double, double) _range() {
    final values = points.map((p) => p.value);
    final lo = math.min(0.0, values.reduce(math.min));
    var hi = math.max(0.0, values.reduce(math.max));
    if (hi == lo) hi = lo + 1;
    return (lo, hi);
  }

  void _axis(Canvas canvas, Size size, double y0) {
    canvas.drawLine(
      Offset(0, y0),
      Offset(size.width, y0),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );
  }

  void _bars(Canvas canvas, Size size) {
    final (lo, hi) = _range();
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    final slot = size.width / points.length;
    final bar = math.min(slot * 0.6, 56.0);
    _axis(canvas, size, y(0));
    for (var i = 0; i < points.length; i++) {
      final x = slot * i + (slot - bar) / 2;
      final top = y(math.max(points[i].value, 0));
      final bottom = y(math.min(points[i].value, 0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, top, x + bar, math.max(bottom, top + 1)),
          const Radius.circular(4),
        ),
        Paint()..color = colors[i % colors.length],
      );
    }
  }

  void _line(Canvas canvas, Size size) {
    final (lo, hi) = _range();
    double y(double v) =>
        size.height - 6 - (v - lo) / (hi - lo) * (size.height - 12);
    final step = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    _axis(canvas, size, y(0));
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(
        points.length == 1 ? size.width / 2 : step * i,
        y(points[i].value),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colors[0]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < points.length; i++) {
      final p = Offset(
        points.length == 1 ? size.width / 2 : step * i,
        y(points[i].value),
      );
      canvas.drawCircle(p, 4.5, Paint()..color = colors[0]);
    }
  }

  void _pie(Canvas canvas, Size size) {
    final total = points.fold<double>(0, (a, p) => a + math.max(p.value, 0));
    final radius = math.min(size.width, size.height) / 2 - 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    if (total <= 0) {
      canvas.drawCircle(
        rect.center,
        radius,
        Paint()
          ..color = rule
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    var start = -math.pi / 2;
    for (var i = 0; i < points.length; i++) {
      final sweep = math.max(points[i].value, 0) / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.kind != kind || old.points != points || old.colors != colors;
}
