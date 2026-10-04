import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/services/search/search_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('retrieval eval measures lexical strategies and writes the report', () {
    final root = _repoRoot();
    final corpus = _corpus();
    final queries = _queries();
    final out = Directory.systemTemp.createTempSync('retrieval-eval-');
    try {
      final current = _measure(
        'current',
        out,
        corpus,
        queries,
        (text) => SearchService.tokens(text),
        singleCharacterScan: true,
      );
      final bigram = _measure(
        'fts-bigram-only',
        out,
        corpus,
        queries,
        (text) => SearchService.tokens(text),
      );
      final unigram = _measure('unigram', out, corpus, queries, _unigramTokens);
      final hybrid = _measureHybrid(out, corpus, queries, current, unigram);
      final metrics = {
        'current': current,
        'fts-bigram-only': bigram,
        'unigram': unigram,
        'hybrid': hybrid,
      };
      for (final metric in metrics.values) {
        expect(metric.recallAt1, inInclusiveRange(0, 1));
        expect(metric.recallAt5, inInclusiveRange(0, 1));
        expect(metric.recallAt10, inInclusiveRange(0, 1));
        expect(metric.mrr, inInclusiveRange(0, 1));
        expect(metric.indexBytes, greaterThan(0));
        expect(metric.buildMs, greaterThanOrEqualTo(0));
        expect(metric.queryMs, greaterThanOrEqualTo(0));
      }
      expect(current.perQuery['泵'], greaterThan(bigram.perQuery['泵']!));
      expect(current.recallAt10, greaterThan(bigram.recallAt10));
      final endpoint = Platform.environment['MUYON_EMBEDDING_ENDPOINT'];
      expect(endpoint, anyOf(isNull, isEmpty));
      final recommendation = _recommend(metrics);
      final report = _report(
        metrics: metrics,
        recommendation: recommendation,
        vector: 'not measured — needs real model',
      );
      final file = File(
        p.join(
          root.path,
          'docs',
          'implementation',
          'retrieval-eval-2026-10-04.md',
        ),
      );
      file.writeAsStringSync(report);
      final written = file.readAsStringSync();
      expect(written, contains(recommendation));
      expect(written, contains('not measured — needs real model'));
      expect(written, contains(current.recallAt5.toStringAsFixed(3)));
      expect(written, contains('cjk-bigram-latin-v1'));
    } finally {
      out.deleteSync(recursive: true);
    }
  });
}

Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File(
      p.join(
        dir.path,
        'docs',
        'superpowers',
        'plans',
        '2026-10-04-w1-agent-prompts.md',
      ),
    ).existsSync()) {
      return dir;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  throw StateError('repo root not found from ${Directory.current.path}');
}

class _Doc {
  const _Doc(this.id, this.text);
  final String id, text;
}

class _Query {
  const _Query(this.text, this.relevant);
  final String text;
  final Set<String> relevant;
}

class _Metric {
  const _Metric({
    required this.recallAt1,
    required this.recallAt5,
    required this.recallAt10,
    required this.mrr,
    required this.indexBytes,
    required this.buildMs,
    required this.queryMs,
    required this.perQuery,
    required this.rankings,
  });
  final double recallAt1, recallAt5, recallAt10, mrr, buildMs, queryMs;
  final int indexBytes;
  final Map<String, double> perQuery;
  final Map<String, List<String>> rankings;
}

List<_Doc> _corpus() => const [
  _Doc('pump-zh', '离心泵的材料和密封成本需要核对'),
  _Doc('pump-en', 'centrifugal pump material and seal cost'),
  _Doc('pump-mix', '离心泵 ISO9001 质量手册 Q=100m3/h'),
  _Doc('valve', '闸阀采购清单，不含泵'),
  _Doc('cost', '项目成本与报价表'),
  _Doc('quality', '质量检查记录'),
  _Doc('near-a', '数据分析显示模型 Evidence recall 稳定'),
  _Doc('near-b', '数据分析显示模型 Evidence recall 基本稳定'),
  _Doc('short-pump', '泵'),
  _Doc('alpha', 'supplier alpha 材料成本'),
  _Doc('walk', '今日天气晴朗 suitable for a walk'),
  _Doc('bm25', 'BM25 检索对中文短词 cost 不总是可靠'),
  _Doc('two-char', '成本核算单'),
  _Doc('one-long', '这台设备是泵'),
  _Doc('english', 'The retrieval benchmark uses labelled queries'),
  _Doc('acme', '供应商 ACME-泵业 联系人'),
  _Doc('secret', '研究另一份未选资料 secret token'),
  _Doc('pump-again', '离心泵的材料和密封成本需要再次核对'),
];

List<_Query> _queries() => const [
  _Query('泵', {
    'pump-zh',
    'pump-mix',
    'short-pump',
    'one-long',
    'acme',
    'pump-again',
    'valve',
  }),
  _Query('成本', {'pump-zh', 'cost', 'alpha', 'two-char', 'pump-again'}),
  _Query('质量', {'pump-mix', 'quality'}),
  _Query('ISO9001', {'pump-mix'}),
  _Query('Evidence', {'near-a', 'near-b'}),
  _Query('secret', {'secret'}),
  _Query('retrieval', {'english'}),
  _Query('BM25', {'bm25'}),
  _Query('alpha', {'alpha'}),
  _Query('闸阀', {'valve'}),
  _Query('walk', {'walk'}),
  _Query('Q=100', {'pump-mix'}),
];

List<String> _unigramTokens(String text) {
  final values = <String>[];
  final normalized = text.toLowerCase();
  for (final match in RegExp(
    r'[a-z0-9]+|[\u3400-\u9fff]',
  ).allMatches(normalized)) {
    final word = match.group(0)!;
    if (RegExp(r'^[a-z0-9]').hasMatch(word)) {
      values.add(
        'w${word.codeUnits.map((c) => c.toRadixString(16)).join('_')}',
      );
    } else {
      values.add('u${word.runes.single.toRadixString(16)}');
    }
  }
  return values;
}

_Metric _measure(
  String name,
  Directory out,
  List<_Doc> corpus,
  List<_Query> queries,
  List<String> Function(String text) tokenize, {
  bool singleCharacterScan = false,
}) {
  final path = p.join(out.path, '$name.sqlite');
  final db = sqlite3.open(path);
  try {
    db.execute('CREATE TABLE docs(id TEXT PRIMARY KEY, text TEXT)');
    db.execute(
      'CREATE VIRTUAL TABLE page_fts USING fts5(tokens, doc_id UNINDEXED)',
    );
    final build = Stopwatch()..start();
    for (final doc in corpus) {
      db.execute('INSERT INTO docs VALUES(?,?)', [doc.id, doc.text]);
      db.execute('INSERT INTO page_fts(tokens, doc_id) VALUES(?,?)', [
        tokenize(doc.text).join(' '),
        doc.id,
      ]);
    }
    build.stop();
    final rankings = <String, List<String>>{};
    final queryWatch = Stopwatch()..start();
    for (final query in queries) {
      rankings[query.text] = _search(
        db,
        query.text,
        tokenize,
        singleCharacterScan: singleCharacterScan,
      );
    }
    queryWatch.stop();
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    final metric = _score(
      queries,
      rankings,
      indexBytes: File(path).lengthSync(),
      buildMs: build.elapsedMicroseconds / 1000,
      queryMs: queryWatch.elapsedMicroseconds / 1000 / queries.length,
    );
    return metric;
  } finally {
    db.close();
  }
}

List<String> _search(
  Database db,
  String query,
  List<String> Function(String text) tokenize, {
  required bool singleCharacterScan,
}) {
  final tokens = tokenize(query).toSet();
  final single = RegExp(r'^[\u3400-\u9fff]$').hasMatch(query.trim());
  if (tokens.isEmpty && single && singleCharacterScan) {
    return [
      for (final row in db.select(
        'SELECT id FROM docs WHERE instr(text, ?) > 0 ORDER BY id',
        [query.trim()],
      ))
        row['id'] as String,
    ];
  }
  if (tokens.isEmpty) return const [];
  final expression = tokens.map((token) => '"$token"').join(' OR ');
  return [
    for (final row in db.select(
      'SELECT doc_id FROM page_fts WHERE page_fts MATCH ? ORDER BY bm25(page_fts), doc_id LIMIT 20',
      [expression],
    ))
      row['doc_id'] as String,
  ];
}

_Metric _measureHybrid(
  Directory out,
  List<_Doc> corpus,
  List<_Query> queries,
  _Metric current,
  _Metric unigram,
) {
  final build = Stopwatch()..start();
  final rankings = <String, List<String>>{};
  for (final query in queries) {
    rankings[query.text] = _rrf([
      current.rankings[query.text] ?? const [],
      unigram.rankings[query.text] ?? const [],
    ]);
  }
  build.stop();
  return _score(
    queries,
    rankings,
    indexBytes: current.indexBytes + unigram.indexBytes,
    buildMs:
        current.buildMs + unigram.buildMs + build.elapsedMicroseconds / 1000,
    queryMs: current.queryMs + unigram.queryMs,
  );
}

List<String> _rrf(List<List<String>> rankings, {int k = 60}) {
  final scores = <String, double>{};
  for (final ranking in rankings) {
    for (var i = 0; i < ranking.length && i < 20; i++) {
      final id = ranking[i];
      scores[id] = (scores[id] ?? 0) + 1 / (k + i + 1);
    }
  }
  final ordered = scores.keys.toList()
    ..sort((a, b) {
      final byScore = scores[b]!.compareTo(scores[a]!);
      return byScore != 0 ? byScore : a.compareTo(b);
    });
  return ordered;
}

_Metric _score(
  List<_Query> queries,
  Map<String, List<String>> rankings, {
  required int indexBytes,
  required double buildMs,
  required double queryMs,
}) {
  var recallAt1 = 0.0, recallAt5 = 0.0, recallAt10 = 0.0, mrr = 0.0;
  final perQuery = <String, double>{};
  for (final query in queries) {
    final ranked = rankings[query.text] ?? const <String>[];
    final at1 = _recall(ranked, query.relevant, 1);
    final at5 = _recall(ranked, query.relevant, 5);
    recallAt1 += at1;
    recallAt5 += at5;
    recallAt10 += _recall(ranked, query.relevant, 10);
    mrr += _mrr(ranked, query.relevant);
    perQuery[query.text] = at5;
  }
  final n = queries.length;
  return _Metric(
    recallAt1: recallAt1 / n,
    recallAt5: recallAt5 / n,
    recallAt10: recallAt10 / n,
    mrr: mrr / n,
    indexBytes: indexBytes,
    buildMs: buildMs,
    queryMs: queryMs,
    perQuery: perQuery,
    rankings: rankings,
  );
}

double _recall(List<String> ranked, Set<String> relevant, int k) {
  if (relevant.isEmpty) return 0;
  return ranked.take(k).where(relevant.contains).toSet().length /
      relevant.length;
}

double _mrr(List<String> ranked, Set<String> relevant) {
  for (var i = 0; i < ranked.length; i++) {
    if (relevant.contains(ranked[i])) return 1 / (i + 1);
  }
  return 0;
}

String _recommend(Map<String, _Metric> metrics) {
  final names = ['current', 'unigram', 'hybrid'];
  names.sort((a, b) {
    final byRecall = metrics[b]!.recallAt5.compareTo(metrics[a]!.recallAt5);
    if (byRecall != 0) return byRecall;
    final byRecall10 = metrics[b]!.recallAt10.compareTo(metrics[a]!.recallAt10);
    if (byRecall10 != 0) return byRecall10;
    final byMrr = metrics[b]!.mrr.compareTo(metrics[a]!.mrr);
    if (byMrr != 0) return byMrr;
    return metrics[a]!.indexBytes.compareTo(metrics[b]!.indexBytes);
  });
  final best = names.first;
  final gain = metrics[best]!.recallAt5 - metrics['current']!.recallAt5;
  final gain10 = metrics[best]!.recallAt10 - metrics['current']!.recallAt10;
  if (best != 'current' && gain < 0.02 && gain10 < 0.02) {
    return '保持当前检索（cjk-bigram-latin-v1，外加已有的单字扫描）。'
        '$best 的 recall@5 只高 ${gain.toStringAsFixed(3)}，recall@10 只高 ${gain10.toStringAsFixed(3)}，'
        '不值得为这个增益再维持一套索引。';
  }
  final winner = metrics[best]!;
  return '建议采用 $best。recall@5=${winner.recallAt5.toStringAsFixed(3)}，'
      'recall@10=${winner.recallAt10.toStringAsFixed(3)}，'
      'MRR=${winner.mrr.toStringAsFixed(3)}，索引 ${winner.indexBytes} 字节，'
      '建索引 ${winner.buildMs.toStringAsFixed(1)} ms，'
      '查询均值 ${winner.queryMs.toStringAsFixed(3)} ms。'
      '相对当前检索的 recall@5 增益为 ${gain.toStringAsFixed(3)}，'
      'recall@10 增益为 ${gain10.toStringAsFixed(3)}。';
}

String _fmt(_Metric metric) =>
    '${metric.recallAt1.toStringAsFixed(3)} | ${metric.recallAt5.toStringAsFixed(3)} | '
    '${metric.recallAt10.toStringAsFixed(3)} | ${metric.mrr.toStringAsFixed(3)} | '
    '${metric.indexBytes} | ${metric.buildMs.toStringAsFixed(1)} | '
    '${metric.queryMs.toStringAsFixed(3)}';

String _report({
  required Map<String, _Metric> metrics,
  required String recommendation,
  required String vector,
}) {
  final pump = [
    for (final name in ['current', 'fts-bigram-only', 'unigram', 'hybrid'])
      '$name ${metrics[name]!.perQuery['泵']!.toStringAsFixed(3)}',
  ].join('；');
  return '''
# 检索评测 2026-10-04

数字来自 `apps/muyon/test/retrieval_eval/retrieval_eval_test.dart` 这一次运行。语料是可再分发的合成中文、英文和中英混合短文，含 1–2 字中文、中英混排和近重复。没有使用外部模型。

重跑：

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \\
  NO_PROXY=localhost,127.0.0.1,::1 \\
  flutter test --no-pub --timeout 120s apps/muyon/test/retrieval_eval/retrieval_eval_test.dart
```

| 策略 | recall@1 | recall@5 | recall@10 | MRR | 索引字节 | 建索引 ms | 查询均值 ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| current（cjk-bigram-latin-v1 + 单字扫描） | ${_fmt(metrics['current']!)} |
| fts-bigram-only（同一分词器，没有单字扫描） | ${_fmt(metrics['fts-bigram-only']!)} |
| unigram（单字 + 拉丁词） | ${_fmt(metrics['unigram']!)} |
| hybrid（current 与 unigram 的 RRF，k=60） | ${_fmt(metrics['hybrid']!)} |
| vector | $vector | | | | | |

查询「泵」的 recall@5：$pump。

$recommendation

这 18 篇短文上的建索引时间受 SQLite 启动影响，不能外推到大库。策略取舍以 recall、MRR 和索引字节为准。

向量检索没有测量：环境变量 `MUYON_EMBEDDING_ENDPOINT` 未配置，不能用真实模型冒充数字。
''';
}
