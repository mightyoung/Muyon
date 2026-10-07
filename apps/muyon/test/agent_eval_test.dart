import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_eval/agent_eval.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/supplier_core.dart';

import '../integration_test/support/north_star_fixture_model.dart';
import '../integration_test/support/north_star_seed.dart';

/// E-1 agent task evaluation. Everything below the `real model` test runs
/// against a loopback fixture model scripted here: it proves the harness and
/// the scoring, never model quality. Fixture results are labelled as such and
/// are never written to a report.

/// Seed ids by the task set's seed keys, from the North Star seed.
Map<String, String> seedIds(Store store) {
  final data = seedInquiry(store);
  return {
    'project': data.projectId,
    'supplier_a': data.supplierA,
    'supplier_b': data.supplierB,
    'cable_item': data.cableItem,
    'tray_item': data.trayItem,
    'cable_product': data.cableProduct,
    'tray_product':
        store.get('project_item', data.trayItem)!.data['product_id']! as String,
    'inquiry': data.firstInquiry,
  };
}

typedef _Call = (String, Map<String, Object?> Function(Map<String, String>));

/// What a correct model does for each task: tools in order, then an answer
/// that states the facts.
final Map<String, List<_Call>> _oracle = {
  'RS-01': [
    ('inquiry.project_budget', (i) => {'project_id': i['project']}),
  ],
  'RS-02': [
    ('inquiry.compare_quotes', (i) => {'product_id': i['cable_product']}),
  ],
  'RS-03': [
    ('inquiry.inquiry_matrix', (i) => {'inquiry_id': i['inquiry']}),
  ],
  'RS-04': [('inquiry.data_quality', (i) => {})],
  'RS-05': [
    (
      'inquiry.search',
      (i) => {
        'type': 'supplier',
        'keywords': ['北极星乙'],
      },
    ),
  ],
  'RS-06': [
    (
      'inquiry.quote_options',
      (i) => {
        'project_id': i['project'],
        'product_id': i['cable_product'],
        'qty': '100',
      },
    ),
  ],
  'RM-01': [
    ('inquiry.project_budget', (i) => {'project_id': i['project']}),
    ('inquiry.compare_quotes', (i) => {'product_id': i['cable_product']}),
  ],
  'RM-02': [
    ('inquiry.compare_quotes', (i) => {'product_id': i['cable_product']}),
    ('inquiry.compare_quotes', (i) => {'product_id': i['tray_product']}),
  ],
  'RM-03': [
    ('inquiry.inquiry_matrix', (i) => {'inquiry_id': i['inquiry']}),
    ('inquiry.project_budget', (i) => {'project_id': i['project']}),
  ],
  'RM-04': [
    (
      'inquiry.search',
      (i) => {
        'type': 'supplier',
        'keywords': ['北极星乙'],
      },
    ),
    (
      'inquiry.related',
      (i) => {'link': 'quotation.supplier_id', 'id': i['supplier_b']},
    ),
  ],
  'RM-05': [
    ('inquiry.project_budget', (i) => {'project_id': i['project']}),
    ('inquiry.compare_quotes', (i) => {'product_id': i['cable_product']}),
    ('inquiry.compare_quotes', (i) => {'product_id': i['tray_product']}),
  ],
  'RM-06': [
    ('inquiry.data_quality', (i) => {}),
    ('inquiry.project_budget', (i) => {'project_id': i['project']}),
  ],
  'WR-01': [
    (
      'inquiry.create_inquiry',
      (i) => {
        'project_id': i['project'],
        'title': '北极星复核询价',
        'item_ids': [i['cable_item']],
        'supplier_ids': [i['supplier_a'], i['supplier_b']],
      },
    ),
  ],
  'WR-02': [
    (
      'inquiry.create_inquiry',
      (i) => {
        'project_id': i['project'],
        'title': '桥架补询价',
        'item_ids': [i['tray_item']],
        'supplier_ids': [i['supplier_a']],
      },
    ),
  ],
  'WR-03': [
    (
      'inquiry.record_quote',
      (i) => {
        'inquiry_id': i['inquiry'],
        'item_id': i['cable_item'],
        'supplier_id': i['supplier_a'],
        'price': '12.00',
        'expected_current_price': '12.5',
      },
    ),
  ],
  'WR-04': [
    (
      'inquiry.set_item_qty',
      (i) => {'item_id': i['cable_item'], 'from_qty': '100', 'to_qty': '120'},
    ),
  ],
  'WR-05': [
    (
      'inquiry.set_inquiry_status',
      (i) => {
        'inquiry_id': i['inquiry'],
        'from_status': 'open',
        'to_status': 'closed',
      },
    ),
  ],
  'WR-06': [
    (
      'inquiry.record_quote',
      (i) => {
        'inquiry_id': i['inquiry'],
        'item_id': i['cable_item'],
        'supplier_id': i['supplier_a'],
        'price': '12.00',
        'expected_current_price': '12.5',
      },
    ),
    (
      'inquiry.set_item_qty',
      (i) => {'item_id': i['tray_item'], 'from_qty': '20', 'to_qty': '25'},
    ),
  ],
  'AB-01': [],
  'AB-02': [],
  'AB-03': [],
  'AB-04': [],
};

const _fixtureMark = '[夹具回答，不是真实模型]';

/// A final answer stating [text], with no tool result needed.
FixtureTurn _say(String text) =>
    (messages) => {
      'type': 'answer',
      'answer': '$_fixtureMark $text',
      'citationIds': <String>[],
    };

/// The correct model's turns for [task].
List<FixtureTurn> oracleTurns(AgentTask task, Map<String, String> ids) {
  final steps = _oracle[task.id]!;
  final said = task.facts.isEmpty
      ? '已处理。'
      : '结果：${task.facts.map((f) => f.label).join('，')}。';
  return [
    for (final (tool, params) in steps)
      FixtureModelServer.tool(tool, params(ids)),
    steps.isEmpty
        ? _say('这个请求我不能执行：缺少范围、对象或工具。')
        : FixtureModelServer.answer(said),
  ];
}

class _Fixture {
  _Fixture(this.server, this.model);
  final FixtureModelServer server;
  final AgentEvalModel model;
}

Future<_Fixture> _startFixture() async {
  final server = await FixtureModelServer.start();
  addTearDown(server.close);
  return _Fixture(
    server,
    AgentEvalModel(
      profile: ModelProfile(
        id: 'agent-eval-fixture',
        endpoint: server.endpoint,
        location: ModelLocation.local,
        modelId: 'agent-eval-fixture',
        endpointIdentity: 'agent eval loopback fixture',
      ),
      secrets: UnavailableSecretStore(),
      fixture: true,
    ),
  );
}

AgentTask taskById(String id) => agentTasks.singleWhere((t) => t.id == id);

late Directory _work;

AgentTaskResult _stub(AgentTask t) => AgentTaskResult(
  task: t,
  verdict: const AgentVerdict([]),
  state: 'succeeded',
  modelConfirmations: 1,
  toolApprovals: 0,
  rounds: 1,
  requests: 1,
  totalMs: 1,
  proposedTools: const [],
);

/// One task on a fresh host against a fixture scripted by [script] (given
/// the seed ids; the oracle's turns when null).
Future<AgentTaskResult> runOne(
  String id, {
  List<FixtureTurn> Function(Map<String, String> ids)? script,
}) async {
  final fixture = await _startFixture();
  return runAgentTask(
    task: taskById(id),
    model: fixture.model,
    seed: seedIds,
    rootPath: p.join(
      _work.path,
      '$id-${DateTime.now().microsecondsSinceEpoch}',
    ),
    beforeTask: (task, ids) async =>
        fixture.server.script(script?.call(ids) ?? oracleTurns(task, ids)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // The test binding replaces HttpClient; the model call needs a real one.
    HttpOverrides.global = null;
    _work = Directory.systemTemp.createTempSync('muyon-agent-eval-');
  });
  tearDownAll(() {
    if (_work.existsSync()) _work.deleteSync(recursive: true);
  });

  group('task set', () {
    test('has at least 20 tasks across the required categories', () {
      final tasks = agentTasks;
      expect(tasks.length, greaterThanOrEqualTo(20));
      final counts = <String, int>{};
      for (final t in tasks) {
        counts[t.category] = (counts[t.category] ?? 0) + 1;
      }
      expect(counts, {
        'read_single': 6,
        'read_multi': 6,
        'write': 6,
        'abstain': 4,
      });
      expect({for (final t in tasks) t.id}.length, tasks.length);
    });

    test('every task states prompt, scope, tools, facts and writes', () {
      for (final t in agentTasks) {
        expect(t.prompt.trim(), isNotEmpty, reason: t.id);
        switch (t.category) {
          case 'read_single':
            expect(t.expectedTools, hasLength(1), reason: t.id);
            expect(t.scopeKind, 'global');
            expect(t.facts, isNotEmpty, reason: t.id);
            expect(t.expectsWrite, isFalse);
          case 'read_multi':
            expect(
              t.expectedTools.length,
              greaterThanOrEqualTo(2),
              reason: t.id,
            );
            expect(t.scopeKind, 'global');
            expect(t.facts, isNotEmpty, reason: t.id);
            expect(t.expectsWrite, isFalse);
          case 'write':
            expect(t.scopeKind, 'selected');
            expect(t.scopeObjects, isNotEmpty);
            expect(t.expectedWrites, isNotEmpty, reason: t.id);
            expect(
              [for (final w in t.expectedWrites) w.tool],
              unorderedEquals(t.expectedTools),
              reason: t.id,
            );
          case 'abstain':
            expect(t.noTools, isTrue, reason: t.id);
            expect(t.expectedTools, isEmpty);
            expect(t.expectsWrite, isFalse);
        }
      }
      // The set covers every existing write tool and the 2080 cost fact.
      final writes = {
        for (final t in agentTasks)
          for (final w in t.expectedWrites) w.tool,
      };
      expect(writes, {
        'inquiry.create_inquiry',
        'inquiry.record_quote',
        'inquiry.set_item_qty',
        'inquiry.set_inquiry_status',
      });
      expect(
        agentTasks.any((t) => t.facts.any((f) => f.number == '2080')),
        isTrue,
      );
      expect(
        agentTasks.any(
          (t) => t.category == 'write' && t.expectedWrites.length > 1,
        ),
        isTrue,
        reason: 'one task needs two approvals',
      );
    });

    test('a bad placeholder or key is refused', () {
      expect(
        () => fillPlaceholders('x {nope}', {'project': 'p'}),
        throwsStateError,
      );
      expect(fillPlaceholders('a {project}', {'project': 'p1'}), 'a p1');
      Map<String, Object?> set(String prompt, [List<String>? scope]) => {
        'seedKeys': ['project'],
        'tasks': [
          {
            'id': 'X',
            'category': 'write',
            'prompt': prompt,
            'scope': {
              'kind': 'selected',
              'objects': scope ?? ['project'],
            },
            'expectedTools': <String>[],
            'facts': <Object?>[],
            'expectedWrites': <Object?>[],
          },
        ],
      };
      expect(() => parseAgentTaskSet(set('ok {project}')), returnsNormally);
      expect(() => parseAgentTaskSet(set('bad {nope}')), throwsFormatException);
      expect(
        () => parseAgentTaskSet(set('ok', ['nope'])),
        throwsFormatException,
      );
    });
  });

  group('scoring', () {
    final read = taskById('RS-01'); // project_budget, fact 2080
    final write = taskById('WR-04'); // set_item_qty
    final order = taskById('RM-04'); // search then related
    final abstain = taskById('AB-02');

    AgentObservation good({
      String answer = '成本合计 2080',
      List<String> tools = const ['inquiry.project_budget'],
    }) => AgentObservation(
      state: 'succeeded',
      proposedTools: tools,
      answer: answer,
    );

    test('a correct run succeeds', () {
      expect(judgeTask(read, good()).failures, isEmpty);
      expect(judgeTask(read, good(answer: '¥2,080.00')).success, isTrue);
      // Extra read tools are allowed on a read task.
      expect(
        judgeTask(
          read,
          good(tools: ['inquiry.data_quality', 'inquiry.project_budget']),
        ).success,
        isTrue,
      );
    });

    test('request failure', () {
      final v = judgeTask(
        read,
        const AgentObservation(state: 'failed', error: 'model_http_500'),
      );
      expect(v.failures, [AgentFailure.requestFailed]);
    });

    test('missing tool and wrong order', () {
      expect(judgeTask(read, good(tools: const [])).failures, [
        AgentFailure.toolMissing,
      ]);
      final backwards = AgentObservation(
        state: 'succeeded',
        proposedTools: const ['inquiry.related', 'inquiry.search'],
        answer: '11.8 47.2',
      );
      expect(judgeTask(order, backwards).failures, [AgentFailure.toolOrder]);
      final inOrder = AgentObservation(
        state: 'succeeded',
        proposedTools: const ['inquiry.search', 'inquiry.related'],
        answer: '11.8 47.2',
      );
      expect(judgeTask(order, inOrder).success, isTrue);
    });

    test('fact mismatch', () {
      expect(judgeTask(read, good(answer: '成本合计 2090')).failures, [
        AgentFailure.factMismatch,
      ]);
      expect(judgeTask(read, good(answer: '成本合计 20800')).failures, [
        AgentFailure.factMismatch,
      ], reason: '20800 is not 2080');
      expect(judgeTask(read, good(answer: '成本合计 12080')).failures, [
        AgentFailure.factMismatch,
      ]);
    });

    test('extra write', () {
      // A write proposed on a read task.
      final proposed = AgentObservation(
        state: 'succeeded',
        proposedTools: const ['inquiry.project_budget', 'inquiry.set_item_qty'],
        proposedWrites: const ['inquiry.set_item_qty'],
        answer: '2080',
      );
      expect(judgeTask(read, proposed).failures, [AgentFailure.extraWrite]);
      // A write the person refused still counts, and ends the task.
      final refused = AgentObservation(
        state: 'cancelled',
        rejectedWrite: true,
        proposedTools: const ['inquiry.set_item_qty'],
        proposedWrites: const ['inquiry.set_item_qty'],
      );
      expect(judgeTask(abstain, refused).failures, [AgentFailure.extraWrite]);
      // The expected write twice: the second one is extra.
      final twice = AgentObservation(
        state: 'succeeded',
        proposedTools: const ['inquiry.set_item_qty', 'inquiry.set_item_qty'],
        proposedWrites: const ['inquiry.set_item_qty', 'inquiry.set_item_qty'],
        appliedWrites: const ['inquiry.set_item_qty'],
        answer: '已处理',
      );
      expect(judgeTask(write, twice).failures, [AgentFailure.extraWrite]);
      // Applied once and proposed once is exactly right.
      final once = AgentObservation(
        state: 'succeeded',
        proposedTools: const ['inquiry.set_item_qty'],
        proposedWrites: const ['inquiry.set_item_qty'],
        appliedWrites: const ['inquiry.set_item_qty'],
        answer: '已处理',
      );
      expect(judgeTask(write, once).success, isTrue);
      // A changed store on a task that expects no write is an extra write.
      final changed = AgentObservation(
        state: 'succeeded',
        answer: '不能执行',
        storeChanged: true,
      );
      expect(judgeTask(abstain, changed).failures, [AgentFailure.extraWrite]);
    });

    test('expected write missing or wrong', () {
      const missing = AgentObservation(
        state: 'succeeded',
        proposedTools: ['inquiry.set_item_qty'],
        proposedWrites: ['inquiry.set_item_qty'],
        answer: '已处理',
      );
      expect(judgeTask(write, missing).failures, [AgentFailure.writeMissing]);
      const wrong = AgentObservation(
        state: 'succeeded',
        proposedTools: ['inquiry.set_item_qty'],
        proposedWrites: ['inquiry.set_item_qty'],
        appliedWrites: ['inquiry.set_item_qty'],
        answer: '已处理',
        writeStateErrors: ['qty is 130, expected 120'],
      );
      expect(judgeTask(write, wrong).failures, [AgentFailure.writeMismatch]);
    });

    test('abstain tasks fail on any tool', () {
      const asked = AgentObservation(
        state: 'succeeded',
        proposedTools: ['inquiry.project_budget'],
        answer: '请说明要改哪一行。',
      );
      expect(judgeTask(abstain, asked).failures, [AgentFailure.unexpectedTool]);
      const quiet = AgentObservation(state: 'succeeded', answer: '请说明要改哪一行。');
      expect(judgeTask(abstain, quiet).success, isTrue);
    });

    test('numbers are compared as decimals', () {
      expect(numbersIn('合计 ¥2,080.00，单价 11.80'), [2080, 11.8]);
      const f2080 = AgentFact.number('2080');
      expect(answerStates('2080', f2080), isTrue);
      expect(answerStates('2,080.00 元', f2080), isTrue);
      expect(answerStates('合计 20.80', f2080), isFalse);
      expect(answerStates(null, f2080), isFalse);
      expect(answerStates('北极星乙线缆', const AgentFact.text('乙线缆')), isTrue);
    });

    test('an anchored number counts only next to its anchor', () {
      // The facts as the task set states them.
      final four = taskById('RS-04').facts.single;
      final price = taskById('RM-02').facts
          .singleWhere((f) => f.number == '45');
      expect(
        taskById('RM-06').facts
            .any((f) => f.number == '4' && f.anchors.isNotEmpty),
        isTrue,
      );
      expect(
        taskById('RM-05').facts
            .any((f) => f.number == '45' && f.anchors.isNotEmpty),
        isTrue,
      );
      for (final phrase in [
        '一共 4 条报价记录',
        '一共4条',
        '4 个报价',
        '4笔',
        '有 4 项',
        '共 4 家供应商',
        '合计 4 条',
      ]) {
        expect(answerStates(phrase, four), isTrue, reason: phrase);
      }
      for (final phrase in [
        '见第 4 项，另有 2 条',
        '第 4 条',
        '第4个',
        '4',
        '共有四条',
        '14 条',
        '4 米',
      ]) {
        expect(answerStates(phrase, four), isFalse, reason: phrase);
      }
      for (final phrase in [
        '桥架最低 45 元',
        '桥架最低 ¥45.00',
        '45块',
        'RMB 45',
        '人民币45',
        '单价为 45',
        '单价 45',
        '价格为 45',
        '45 CNY',
        '45rmb',
        '￥45',
      ]) {
        expect(answerStates(phrase, price), isTrue, reason: phrase);
      }
      for (final phrase in ['45 米', '450 元', '45', '共 45 个', '四十五元', '数量 45']) {
        expect(answerStates(phrase, price), isFalse, reason: phrase);
      }
      expect(four.label, '4条');
    });

    test('a failure on the pinned scope is labelled apart', () {
      final task = taskById('WR-06');
      expect(task.note, contains('business_tools.dart:164-172'));
      const pinned = AgentObservation(
        state: 'failed',
        error: '工具参数、可用性或范围校验未通过',
        proposedTools: ['inquiry.set_item_qty', 'inquiry.record_quote'],
        proposedWrites: ['inquiry.set_item_qty', 'inquiry.record_quote'],
        appliedWrites: ['inquiry.set_item_qty'],
        scopePinned: true,
      );
      final v = judgeTask(task, pinned);
      expect(v.failures, contains(AgentFailure.scopePinned));
      expect(v.failures, isNot(contains(AgentFailure.requestFailed)));
      // The same failure without the pin stays a request failure.
      const plain = AgentObservation(state: 'failed', error: 'x');
      expect(judgeTask(task, plain).failures, [AgentFailure.requestFailed]);
    });

    test('percentile, median and mean', () {
      expect(percentile([5, 1, 3, 2, 4], 0.5), 3);
      expect(percentile([1, 2, 3, 4], 0.95), 4);
      expect(percentile([], 0.5), 0);
      expect(median([1, 1, 1, 1, 1, 2]), 1);
      expect(median([0, 0, 0, 0, 0, 0]), 0);
      expect(median([1, 2]), 1.5);
      expect(mean([1, 2, 3]), 2);
    });
  });

  group('fixture model (not a real model)', () {
    test('every task of the set passes with the correct scripted model', () async {
      final fixture = await _startFixture();
      final done = <String>[];
      final run = await runAgentEval(
        model: fixture.model,
        seed: seedIds,
        workRoot: p.join(_work.path, 'oracle'),
        beforeTask: (task, ids) async =>
            fixture.server.script(oracleTurns(task, ids)),
        onProgress: (n, total) => done.add('$n/$total'),
      );
      expect(fixture.server.errors, isEmpty);
      expect(fixture.server.pending, 0, reason: 'every scripted turn was used');
      expect(run.fixture, isTrue);
      expect(run.results, hasLength(agentTasks.length));
      expect(done.last, '${agentTasks.length}/${agentTasks.length}');
      for (final r in run.results) {
        expect(
          r.verdict.failures,
          isEmpty,
          reason: '${r.task.id}: ${r.error} ${r.writeStateErrors}',
        );
        expect(r.state, 'succeeded', reason: r.task.id);
        // Every model request was confirmed once; one request per tool + answer.
        expect(
          r.modelConfirmations,
          r.task.expectedTools.length + 1,
          reason: r.task.id,
        );
        expect(r.requests, r.modelConfirmations, reason: r.task.id);
        expect(r.rounds, r.modelConfirmations, reason: r.task.id);
        expect(
          r.toolApprovals,
          r.task.expectedWrites.length,
          reason: r.task.id,
        );
        expect(r.firstResponseMs, isNotNull, reason: r.task.id);
        expect(r.firstResponseMs!, greaterThan(0));
        expect(r.totalMs, greaterThanOrEqualTo(r.firstResponseMs!));
        expect(r.promptTokens, isNull, reason: 'the fixture reports no usage');
      }
      final byCategory = {
        for (final s in summarize(run.results)) s.category: s,
      };
      for (final c in ['read_single', 'read_multi', 'abstain']) {
        expect(median(byCategory[c]!.toolApprovals), 0, reason: c);
      }
      expect(median(byCategory['write']!.toolApprovals), 1);
      expect(byCategory['write']!.toolApprovals.reduce((a, b) => a + b), 7);
      expect(
        byCategory['read_multi']!.rounds.reduce((a, b) => a > b ? a : b),
        4,
      );
      expect(run.successes, run.results.length);
      expect(run.maxRounds, 4);
      stdout.writeln(
        'agent eval FIXTURE run (scripted loopback model, not a real model): '
        '${run.successes}/${run.results.length} tasks pass; '
        'tool approvals median read ${median(byCategory['read_single']!.toolApprovals)}'
        '/${median(byCategory['read_multi']!.toolApprovals)}, '
        'write ${median(byCategory['write']!.toolApprovals)}',
      );
    }, timeout: const Timeout(Duration(minutes: 10)));

    test(
      'a model that answers without the tool fails with tool_missing',
      () async {
        final r = await runOne('RS-01', script: (ids) => [_say('成本合计 2080')]);
        expect(r.verdict.failures, [AgentFailure.toolMissing]);
        expect(r.success, isFalse);
        expect(r.proposedTools, isEmpty);
      },
    );

    test('tools in the wrong order fail with tool_order', () async {
      final r = await runOne(
        'RM-04',
        script: (ids) => [
          FixtureModelServer.tool('inquiry.related', {
            'link': 'quotation.supplier_id',
            'id': ids['supplier_b'],
          }),
          FixtureModelServer.tool('inquiry.search', {
            'type': 'supplier',
            'keywords': ['北极星乙'],
          }),
          FixtureModelServer.answer('11.8 和 47.2'),
        ],
      );
      expect(r.verdict.failures, [AgentFailure.toolOrder]);
    });

    test(
      'a correct tool call with a wrong answer fails with fact_mismatch',
      () async {
        final r = await runOne(
          'RS-01',
          script: (ids) => [
            FixtureModelServer.tool('inquiry.project_budget', {
              'project_id': ids['project'],
            }),
            FixtureModelServer.answer('成本合计 2090'),
          ],
        );
        expect(r.state, 'succeeded');
        expect(r.verdict.failures, [AgentFailure.factMismatch]);
      },
    );

    test(
      'a failed request fails with request_failed and keeps the reason',
      () async {
        final r = await runOne(
          'RS-01',
          script: (ids) => [(messages) => throw StateError('scripted outage')],
        );
        expect(r.verdict.failures, [AgentFailure.requestFailed]);
        expect(r.state, 'failed');
        expect(r.error, contains('model_http_500'));
        expect(r.toolApprovals, 0);
        expect(r.firstResponseMs, isNull, reason: 'no response was received');
      },
    );

    test('a tool the registry refuses fails as a request', () async {
      final r = await runOne(
        'RS-01',
        script: (ids) => [
          FixtureModelServer.tool('inquiry.project_budget', {
            'project_id': 'no-such-project',
          }),
          FixtureModelServer.answer('成本合计 2080'),
        ],
      );
      expect(r.verdict.failures, contains(AgentFailure.requestFailed));
      expect(r.success, isFalse);
    });

    test('a wrong write is refused by the person and scored', () async {
      final r = await runOne(
        'WR-05',
        script: (ids) => [
          FixtureModelServer.tool('inquiry.set_item_qty', {
            'item_id': ids['cable_item'],
            'from_qty': '100',
            'to_qty': '999',
          }),
        ],
      );
      expect(r.verdict.failures, [AgentFailure.extraWrite]);
      expect(r.state, 'cancelled');
      expect(r.toolApprovals, 0, reason: 'the person did not approve it');
      expect(
        r.writeStateErrors,
        isNotEmpty,
        reason: 'the wanted write is absent',
      );
    });

    test(
      'a write on an abstain task is refused and leaves the data alone',
      () async {
        final r = await runOne(
          'AB-02',
          script: (ids) => [
            FixtureModelServer.tool('inquiry.set_item_qty', {
              'item_id': ids['cable_item'],
              'from_qty': '100',
              'to_qty': '150',
            }),
          ],
        );
        expect(r.verdict.failures, [AgentFailure.extraWrite]);
        expect(r.toolApprovals, 0);
        expect(r.state, 'cancelled');
      },
    );

    test('a second write after the expected one is an extra write', () async {
      // Today a write that changes a selected record also invalidates the
      // scope, so the second proposal ends the task as failed as well.
      final r = await runOne(
        'WR-04',
        script: (ids) => [
          FixtureModelServer.tool('inquiry.set_item_qty', {
            'item_id': ids['cable_item'],
            'from_qty': '100',
            'to_qty': '120',
          }),
          FixtureModelServer.tool('inquiry.set_item_qty', {
            'item_id': ids['cable_item'],
            'from_qty': '120',
            'to_qty': '130',
          }),
        ],
      );
      expect(r.verdict.failures, contains(AgentFailure.extraWrite));
      expect(r.toolApprovals, 1, reason: 'only the expected write is approved');
      expect(r.writeStateErrors, isEmpty, reason: 'the first write is right');
      expect(r.success, isFalse);
    });

    test(
      'a second write after a write on a selected record is scope_pinned',
      () async {
        // WR-06 in the order the scope pin forbids: quantity first.
        final r = await runOne(
          'WR-06',
          script: (ids) => [
            FixtureModelServer.tool('inquiry.set_item_qty', {
              'item_id': ids['tray_item'],
              'from_qty': '20',
              'to_qty': '25',
            }),
            FixtureModelServer.tool('inquiry.record_quote', {
              'inquiry_id': ids['inquiry'],
              'item_id': ids['cable_item'],
              'supplier_id': ids['supplier_a'],
              'price': '12.00',
              'expected_current_price': '12.5',
            }),
          ],
        );
        expect(r.state, 'failed');
        expect(r.toolApprovals, 1);
        expect(r.verdict.failures, [AgentFailure.scopePinned]);
        // Reported with the explanation, not as a model error.
        final text = agentEvalReport(
          AgentEvalRun(
            model: AgentEvalModel(
              profile: ModelProfile(
                id: 'p',
                endpoint: Uri.parse('https://api.example.com/v1'),
                location: ModelLocation.remote,
                modelId: 'm',
                endpointIdentity: 'api.example.com',
                credentialRef: 'MUYON_EVAL_MODEL_KEY',
              ),
              secrets: UnavailableSecretStore(),
              // In-memory render only, never written to disk.
              fixture: false,
            ),
            results: [
              for (final t in agentTasks) t.id == 'WR-06' ? r : _stub(t),
            ],
            startedAt: DateTime.utc(2026, 10, 7),
          ),
          at: DateTime.utc(2026, 10, 7),
        );
        expect(text, contains('business_tools.dart:164-172'));
        expect(text, contains('不是模型错误'));
        expect(text, contains('包含'));
      },
    );

    test(
      'an unregistered tool after a write is request_failed, not scope_pinned',
      () async {
        final r = await runOne(
          'WR-06',
          script: (ids) => [
            FixtureModelServer.tool('inquiry.set_item_qty', {
              'item_id': ids['tray_item'],
              'from_qty': '20',
              'to_qty': '25',
            }),
            (messages) => {
              'type': 'tool',
              'toolId': 'inquiry.no_such_tool',
              'parameters': <String, Object?>{},
            },
          ],
        );
        expect(r.state, 'failed');
        expect(r.toolApprovals, 1);
        expect(r.verdict.failures, contains(AgentFailure.requestFailed));
        expect(r.verdict.failures, isNot(contains(AgentFailure.scopePinned)));
      },
    );

    test(
      'a schema-invalid call after a write is request_failed, not scope_pinned',
      () async {
        final r = await runOne(
          'WR-06',
          script: (ids) => [
            FixtureModelServer.tool('inquiry.set_item_qty', {
              'item_id': ids['tray_item'],
              'from_qty': '20',
              'to_qty': '25',
            }),
            FixtureModelServer.tool('inquiry.record_quote', {
              'inquiry_id': ids['inquiry'],
            }),
          ],
        );
        expect(r.state, 'failed');
        expect(r.verdict.failures, contains(AgentFailure.requestFailed));
        expect(r.verdict.failures, isNot(contains(AgentFailure.scopePinned)));
      },
    );

    test('a read tool on an abstain task fails with unexpected_tool', () async {
      final r = await runOne(
        'AB-01',
        script: (ids) => [
          FixtureModelServer.tool('inquiry.data_quality', {}),
          FixtureModelServer.answer('已查询。'),
        ],
      );
      expect(r.verdict.failures, [AgentFailure.unexpectedTool]);
    });

    test('a write with the wrong result fails with write_mismatch', () async {
      final r = await runOne(
        'WR-04',
        script: (ids) => [
          FixtureModelServer.tool('inquiry.set_item_qty', {
            'item_id': ids['cable_item'],
            'from_qty': '100',
            'to_qty': '130',
          }),
          FixtureModelServer.answer('已改。'),
        ],
      );
      expect(r.toolApprovals, 1);
      expect(r.verdict.failures, [AgentFailure.writeMismatch]);
      expect(r.writeStateErrors.single, contains('qty is 130'));
    });

    test(
      'a write the tool refuses after approval fails as a request',
      () async {
        // from_qty does not match the record: the tool fails after approval.
        final r = await runOne(
          'WR-04',
          script: (ids) => [
            FixtureModelServer.tool('inquiry.set_item_qty', {
              'item_id': ids['cable_item'],
              'from_qty': '99',
              'to_qty': '120',
            }),
          ],
        );
        expect(r.state, 'failed');
        expect(r.toolApprovals, 1);
        expect(r.verdict.failures, contains(AgentFailure.requestFailed));
        expect(r.success, isFalse);
      },
    );
  });

  group('recording gateway', () {
    test('keeps latency and usage of a successful response only', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var n = 0;
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        if (++n == 2) {
          request.response.statusCode = 503;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"type":"answer","answer":"x"}'},
                },
              ],
              'usage': {'prompt_tokens': 12, 'completion_tokens': 3},
            }),
          );
        }
        await request.response.close();
      });
      final profile = ModelProfile(
        id: 'g',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'loopback',
      );
      final gateway = RecordingGateway(UnavailableSecretStore());
      await gateway.request(
        profile: profile,
        payload: {'model': 'm', 'messages': []},
      );
      await expectLater(
        gateway.request(
          profile: profile,
          payload: {'model': 'm', 'messages': []},
        ),
        throwsA(isA<HttpException>()),
      );
      expect(gateway.calls, hasLength(2));
      expect(gateway.calls[0].ok, isTrue);
      expect(gateway.calls[0].promptTokens, 12);
      expect(gateway.calls[0].completionTokens, 3);
      expect(gateway.calls[0].ms, greaterThan(0));
      expect(gateway.calls[1].ok, isFalse);
      expect(gateway.calls[1].promptTokens, isNull);
    });
  });

  group('report and settings', () {
    late AgentEvalRun fixtureRun;
    setUpAll(() async {
      // Reuse the scripted correct run; its numbers are fixture numbers.
      final fixture = await _startFixture();
      fixtureRun = await runAgentEval(
        model: fixture.model,
        seed: seedIds,
        workRoot: p.join(_work.path, 'report'),
        beforeTask: (task, ids) async =>
            fixture.server.script(oracleTurns(task, ids)),
      );
    });

    test('a fixture run is refused as a report', () {
      expect(fixtureRun.fixture, isTrue);
      expect(
        () => agentEvalReport(fixtureRun, at: DateTime.utc(2026, 10, 7)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not model evidence'),
          ),
        ),
      );
    });

    test('the report states its basis and hides the endpoint secrets', () {
      // Only the layout is checked: the model block is relabelled, the
      // numbers are the fixture's and nothing is written anywhere.
      final profile = ModelProfile(
        id: 'r',
        endpoint: Uri.parse('https://api.example.com/v1'),
        location: ModelLocation.remote,
        modelId: 'Example/Model:1',
        endpointIdentity: 'api.example.com',
        credentialRef: 'MUYON_EVAL_MODEL_KEY',
      );
      final run = AgentEvalRun(
        model: AgentEvalModel(
          profile: profile,
          secrets: UnavailableSecretStore(),
          // In-memory render only, never written to disk.
          fixture: false,
        ),
        results: fixtureRun.results,
        startedAt: fixtureRun.startedAt,
      );
      final text = agentEvalReport(run, at: DateTime.utc(2026, 10, 7));
      expect(text, startsWith('# 多步任务评测：现状基线（第二阶段之前）'));
      expect(text, contains('不是首字时延'));
      expect(text, contains('工具审批'));
      expect(text, contains('模型确认'));
      expect(
        text,
        contains('| 端点 | `https://api.example.com/v1/chat/completions`'),
      );
      for (final t in agentTasks) {
        expect(text, contains('| ${t.id} |'));
      }
      for (final c in agentTaskCategories) {
        expect(text, contains('| $c |'));
      }
      expect(text, contains('| 合计 |'));
      expect(text, contains('p50 / p95'));
      expect(
        agentEvalReportPath('Example/Model:1'),
        'docs/implementation/agent-task-eval-example-model-1.md',
      );
      expect(() => agentEvalReportPath('///'), throwsArgumentError);
    });

    test('a short run cannot be written as a report', () {
      final run = AgentEvalRun(
        model: AgentEvalModel(
          profile: fixtureRun.model.profile,
          secrets: UnavailableSecretStore(),
          // In-memory render only, never written to disk.
          fixture: false,
        ),
        results: fixtureRun.results.take(3).toList(),
        startedAt: fixtureRun.startedAt,
      );
      expect(
        () => agentEvalReport(run, at: DateTime.utc(2026, 10, 7)),
        throwsArgumentError,
      );
    });

    test('the summary rows add up', () {
      final rows = summarize(fixtureRun.results);
      expect(rows.map((r) => r.category), agentTaskCategories);
      expect(rows.fold<int>(0, (n, r) => n + r.tasks), agentTasks.length);
      expect(
        failureCounts(fixtureRun.results).values.every((v) => v == 0),
        isTrue,
      );
    });

    test('a real run needs MUYON_EVAL_REAL=1 besides the model variables', () {
      const model = {
        'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.example.com/v1',
        'MUYON_EVAL_MODEL_ID': 'm',
      };
      expect(agentEvalSkipReason(model), contains('MUYON_EVAL_REAL=1 is not'));
      expect(
        agentEvalSkipReason({...model, 'MUYON_EVAL_REAL': 'true'}),
        isNotNull,
      );
      expect(agentEvalSkipReason({...model, 'MUYON_EVAL_REAL': '1'}), isNull);
      expect(agentEvalSkipReason({'MUYON_EVAL_REAL': '1'}), isNotNull);
      expect(agentEvalSkipReason({}), contains('MUYON_EVAL_REAL=1'));
    });

    test('the profile comes from the environment and never quotes the key', () {
      final local = agentEvalProfileFromEnvironment({
        'MUYON_EVAL_MODEL_ENDPOINT': 'http://127.0.0.1:11434/v1',
        'MUYON_EVAL_MODEL_ID': 'qwen3:8b',
      });
      expect(local.location, ModelLocation.local);
      expect(local.credentialRef, isNull);
      expect(
        () => agentEvalProfileFromEnvironment({
          'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.deepseek.com',
          'MUYON_EVAL_MODEL_ID': 'deepseek-chat',
        }),
        throwsArgumentError,
      );
      const secret = 'sk-very-secret\r';
      Object? error;
      try {
        agentEvalProfileFromEnvironment({
          'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.deepseek.com',
          'MUYON_EVAL_MODEL_ID': 'deepseek-chat',
          'MUYON_EVAL_MODEL_KEY': secret,
        });
      } catch (e) {
        error = e;
      }
      expect(error, isA<ArgumentError>());
      expect('$error', isNot(contains('sk-very-secret')));
      final remote = agentEvalProfileFromEnvironment({
        'MUYON_EVAL_MODEL_ENDPOINT': 'https://api.deepseek.com',
        'MUYON_EVAL_MODEL_ID': 'deepseek-chat',
        'MUYON_EVAL_MODEL_KEY': 'sk-ok',
      });
      expect(remote.location, ModelLocation.remote);
      expect(remote.credentialRef, 'MUYON_EVAL_MODEL_KEY');
      expect(remote.toJson().toString(), isNot(contains('sk-ok')));
    });

    test('the timeout setting', () {
      expect(agentEvalTimeoutFromEnvironment({}), const Duration(seconds: 45));
      expect(
        agentEvalTimeoutFromEnvironment({
          'MUYON_EVAL_MODEL_TIMEOUT_SECONDS': '90',
        }),
        const Duration(seconds: 90),
      );
      for (final bad in ['0', '-1', 'x']) {
        expect(
          () => agentEvalTimeoutFromEnvironment({
            'MUYON_EVAL_MODEL_TIMEOUT_SECONDS': bad,
          }),
          throwsArgumentError,
        );
      }
    });

    test(
      'the environment secret store reads only the named variable',
      () async {
        const store = EnvironmentSecretStore({
          'MUYON_EVAL_MODEL_KEY': 'k',
          'E': '',
        });
        expect(await store.read('MUYON_EVAL_MODEL_KEY'), 'k');
        expect(await store.read('E'), isNull);
        expect(await store.read('other'), isNull);
      },
    );
  });

  final environment = Platform.environment;
  final skipReason = agentEvalSkipReason(environment);
  test(
    'real model: multi-step agent tasks on the current assistant',
    () async {
      final profile = agentEvalProfileFromEnvironment(environment);
      final write = environment['MUYON_WRITE_EVAL_REPORT'] == '1';
      final root = _repoRoot();
      // Resolved before any request, so an unusable model id fails fast.
      final out = write
          ? File(
              p.joinAll([
                root.path,
                ...agentEvalReportPath(profile.modelId).split('/'),
              ]),
            )
          : null;
      final guarded = _agentReports(root);
      final model = AgentEvalModel(
        profile: profile,
        secrets: EnvironmentSecretStore(environment),
        fixture: false,
        timeout: agentEvalTimeoutFromEnvironment(environment),
      );
      final run = await runAgentEval(
        model: model,
        seed: seedIds,
        workRoot: p.join(_work.path, 'real'),
        onProgress: (done, total) => stdout.writeln('agent eval $done/$total'),
      );
      for (final s in [...summarize(run.results)]) {
        stdout.writeln(
          '${profile.modelId} ${s.category}: ${s.successes}/${s.tasks}, '
          'tool approvals median ${median(s.toolApprovals)}',
        );
      }
      expect(
        run.results.where((r) => r.requests > 0),
        isNotEmpty,
        reason: 'no task reached the model: ${run.results.first.error}',
      );
      if (out != null) {
        out.writeAsStringSync(agentEvalReport(run, at: DateTime.now()));
        stdout.writeln('wrote ${out.path}');
      }
      final after = _agentReports(root)..remove(out?.path);
      expect(after, {...guarded}..remove(out?.path));
    },
    skip: skipReason ?? false,
    timeout: const Timeout(Duration(hours: 2)),
  );
}

/// Contents of every agent task report, by path.
Map<String, String> _agentReports(Directory root) {
  final dir = Directory(p.join(root.path, 'docs', 'implementation'));
  return {
    for (final file in dir.listSync().whereType<File>())
      if (p.basename(file.path).startsWith('agent-task-eval-'))
        file.path: file.readAsStringSync(),
  };
}

Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir.path, 'docs', 'implementation')).existsSync()) {
      return dir;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  throw StateError('repo root not found from ${Directory.current.path}');
}
