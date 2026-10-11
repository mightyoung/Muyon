import 'dart:convert';

import 'ai_runtime.dart';
import 'assistant_actions.dart';
import 'assistant_evidence.dart';
import 'assistant_toolset.dart';
import 'assistant_web_catalog.dart';
import 'assistant_web_tools.dart';
import 'attachments.dart';
import 'pricing.dart';
import 'product_params.dart';
import 'quotation.dart';
import 'spec_constraint.dart';
import 'spec_dictionary.dart';
import 'spec_values.dart';
import 'store.dart';
import 'values.dart';

part 'assistant_procurement_compare.dart';
part 'assistant_procurement_import.dart';
part 'assistant_procurement_schema.dart';

/// The host calls this for every generic mutation, irrespective of model intent.
void guardAssistantProcurementWrite(
  String operation,
  String type,
  Map<String, Object?> values,
) {
  if (operation != 'create_record' && operation != 'update_record') return;
  if (type == 'product' ||
      type == 'quotation' ||
      (type == 'project_item' &&
          values.keys.any(
            const {
              'product_id',
              'quotation_id',
              'unit_cost',
              'unit_price',
              'requirement',
            }.contains,
          ))) {
    throw const FormatException('采购事实必须使用来源候选和审核导入工具');
  }
}

Map<String, Object?> _object(Object? value) =>
    (value as Map).cast<String, Object?>();
Object? _frozen(Object? value) => value is Map
    ? Map<String, Object?>.unmodifiable({
        for (final key in (value.keys.cast<String>().toList()..sort()))
          key: _frozen(value[key]),
      })
    : value is List
    ? List<Object?>.unmodifiable(value.map(_frozen))
    : value;
String _canonical(Object? value) => jsonEncode(_frozen(value));

class AssistantProcurementTools implements AssistantToolset {
  AssistantProcurementTools(
    this.store, {
    required this.web,
    required this.sessionId,
    required this.permission,
    this.approve,
    this.validateSession,
    this.onChanged,
    this.domesticCriterion,
    this.requestText = '',
  }) {
    if (sessionId.isEmpty || sessionId.length > 200) {
      throw ArgumentError('Invalid session ID');
    }
  }
  final Store store;
  final AssistantWebTools web;
  final String sessionId, requestText;
  final AssistantPermission permission;
  final Future<bool> Function(AssistantActionPreview)? approve;
  final void Function()? validateSession, onChanged;
  final String? Function()? domesticCriterion;
  String get _key => 'assistant_procurement:${jsonEncode(sessionId)}';
  String get _receiptPrefix =>
      'assistant_procurement_receipt:[${jsonEncode(sessionId)},';

  /// The host clears research cache only after completing the task. Imported
  /// source attachments and atomic action receipts remain business evidence.
  void clearTransient() =>
      store.db.execute('DELETE FROM meta WHERE key=?', [_key]);
  Map<String, Object?> _load() {
    final rows = store.db.select('SELECT value FROM meta WHERE key=?', [_key]);
    return rows.isEmpty
        ? {'candidates': <String, Object?>{}, 'reports': <Object?>[]}
        : _object(jsonDecode(rows.single['value'] as String));
  }

  void _save(Map<String, Object?> state) {
    final encoded = _canonical(state);
    if (utf8.encode(encoded).length > 512 * 1024) {
      throw const FormatException('任务研究证据超过512KiB限制');
    }
    store.db.execute(
      'INSERT INTO meta(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
      [_key, encoded],
    );
  }

  List<Map<String, Object?>> get appliedActions => List.unmodifiable([
    for (final row in store.db.select(
      'SELECT value FROM meta WHERE substr(key,1,length(?))=? ORDER BY key LIMIT 24',
      [_receiptPrefix, _receiptPrefix],
    ))
      _object(_frozen(_object(jsonDecode(row['value'] as String))['result'])),
  ]);
  void _check(AiCancellation cancellation, {bool write = false}) {
    cancellation.check();
    validateSession?.call();
    if (write && permission == AssistantPermission.readOnly) {
      throw const FormatException('只读模式禁止采购导入');
    }
  }

  @override
  List<Map<String, Object?>> get tools => [
    _tool(
      'procurement_stage',
      '从真实网页产品行建立采购候选；预算行研究与替代必须指定原item_id。不得提交任何事实字段。',
      {
        'source_id': {'type': 'string'},
        'row_id': {'type': 'string'},
        'item_id': {'type': 'string'},
      },
      ['source_id', 'row_id'],
    ),
    _tool(
      'procurement_check',
      '逐项检查候选与原预算要求；unknown不代表合格。',
      {
        'candidate_id': {'type': 'string'},
      },
      ['candidate_id'],
    ),
    _tool(
      'procurement_compare',
      '严格同品牌完整型号配置、币种单位税运数量日期核价；至少两个独立卖方和域名，仅参考区间。',
      {
        'candidate_ids': {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': 2,
          'maxItems': 8,
        },
        'item_id': {'type': 'string'},
      },
      ['candidate_ids'],
    ),
    if (permission != AssistantPermission.readOnly)
      _tool(
        'procurement_import',
        '人工审核后保存资料与原始来源；报价固定参考价。预算替代需重新询价并在预算界面用正式报价完成。',
        {
          'candidate_id': {'type': 'string'},
          'operation': {
            'type': 'string',
            'enum': ['catalog'],
          },
        },
        ['candidate_id', 'operation'],
      ),
  ];

  String get _today => store.clock().toIso8601String().substring(0, 10);

  @override
  Future<String> execute(
    String name,
    Map<String, Object?> arguments, {
    required String callId,
    required AiCancellation cancellation,
  }) async {
    _check(cancellation);
    if (callId.isEmpty || callId.length > 200) {
      throw const FormatException('Invalid call ID');
    }
    final args = _object(_frozen(arguments));
    switch (name) {
      case 'procurement_stage':
        _args(args, {'source_id', 'row_id'}, {'item_id'});
        final source = web.snapshot(args['source_id'] as String);
        if (source == null ||
            !source.products.any((p) => p.id == args['row_id'])) {
          throw const FormatException('没有真实来源快照或产品行');
        }
        final bindings = _bindings(args['item_id'] as String?);
        final requirement = bindings['item'] == null
            ? requestText
            : (_object(_object(bindings['item'])['data'])['requirement']
                      as String? ??
                  '');
        final id = derivedUuid(
          _canonical([source.id, args['row_id'], bindings, requirement]),
        );
        final state = _load(), candidates = _object(_load()['candidates']);
        if (!candidates.containsKey(id) && candidates.length >= 8) {
          throw const FormatException('任务最多8个候选');
        }
        final candidate = <String, Object?>{
          'id': id,
          'source': source.toJson(),
          'row_id': args['row_id'],
          'item_id': args['item_id'],
          'requirement': requirement,
          'bindings': bindings,
        };
        candidates[id] = candidate;
        state['candidates'] = candidates;
        _save(state);
        return _canonical({
          'candidate_id': id,
          'source_id': source.id,
          'row_id': args['row_id'],
          'facts': _source(candidate).$2.facts,
          'qualification': _qualification(candidate),
        });
      case 'procurement_check':
        _args(args, {'candidate_id'});
        final c = _candidate(args['candidate_id'] as String);
        _fresh(c);
        return _canonical(_qualification(c));
      case 'procurement_compare':
        _args(args, {'candidate_ids'}, {'item_id'});
        final ids = args['candidate_ids'];
        if (ids is! List ||
            ids.length < 2 ||
            ids.length > 8 ||
            ids.any((v) => v is! String) ||
            ids.toSet().length != ids.length) {
          throw const FormatException('需要2至8个不同候选ID');
        }
        final report = _compare(ids.cast<String>(), args['item_id'] as String?);
        final state = _load();
        final inputKey = _canonical([ids.toList()..sort(), args['item_id']]);
        state['reports'] = [
          ...(state['reports'] as List)
              .where((old) => _object(old)['input_key'] != inputKey)
              .toList()
              .reversed
              .take(7)
              .toList()
              .reversed,
          {
            'input_key': inputKey,
            'candidate_ids': ids,
            'item_id': args['item_id'],
            'as_of': _today,
            'bindings': _bindings(args['item_id'] as String?),
            'result': report,
          },
        ];
        _save(state);
        return _canonical(report);
      case 'procurement_import':
        _args(args, {'candidate_id', 'operation'});
        return _import(args, callId, cancellation);
      default:
        throw const FormatException('Unknown procurement tool');
    }
  }

  /// Host-generated only: never reads or interpolates the model's final prose.
  String renderReport(AssistantAnswer answer) {
    final state = _load(), candidates = _object(_load()['candidates']);
    final lines = <String>['采购研究证据报告（网页声明不等于真实认证）'];
    for (final candidate in candidates.values) {
      final c = _object(candidate);
      final (source, row) = _source(c);
      final q = _qualification(c);
      var stale = false;
      try {
        _fresh(c);
      } on FormatException {
        stale = true;
      }
      lines.add(
        assistantReadableSummary({
          'candidate_id': c['id'],
          'facts': row.facts,
          'source': source.url,
          'fetched_at': source.fetchedAt,
          'digest': source.digest,
          'truncated': source.truncated,
          'local_bindings_stale': stale,
          if (stale) 'warning': '本机原要求或关联记录已变更，必须重新研究后审核',
          'qualification': q,
        }),
      );
    }
    for (final raw in state['reports'] as List) {
      final stored = _object(raw);
      try {
        final itemId = stored['item_id'] as String?;
        if (_canonical(_bindings(itemId)) != _canonical(stored['bindings'])) {
          throw const FormatException('项目引用已改变');
        }
        final ids = (stored['candidate_ids'] as List).cast<String>();
        lines.add(assistantReadableSummary(_compare(ids, itemId)));
      } catch (_) {
        lines.add(
          assistantReadableSummary({
            'kind': 'comparison',
            'status': 'stale_comparison',
            'as_of': _today,
            'reason': '原项目、候选或报告依据已改变，请重新核价；不显示旧区间',
          }),
        );
      }
    }
    for (final receipt in appliedActions) {
      lines.add('已保存（实际回执）：\n${assistantReadableSummary(receipt)}');
    }
    if (candidates.isEmpty) lines.add('尚无可信来源候选，不能确认物料、价格或资格。');
    lines.add('支持范围：明确关联产品行、严格数字字典条件和明确国别；复杂条款、未标示单位/税运/有效期及网页真实性须人工核验。');
    return lines.join('\n\n');
  }
}
