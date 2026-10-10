import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart' as domain;

/// Inquiry capability coverage (ADR-0004 §8.2). Deferred means no assistant
/// authority is advertised; the existing human pages remain available.
CapabilityCoverage get inquiryCoverage => CapabilityCoverage(
  surfaces: const [
    Surface('package:supplier_core/supplier_core.dart', 'Store'),
    Surface('package:supplier_core/src/trash.dart', 'Trash'),
    Surface('package:supplier_core/src/inquiries.dart', 'Inquiries'),
    Surface('package:supplier_core/src/product_params.dart', 'ProductParams'),
    Surface('package:supplier_core/src/spec_request.dart', 'SpecRequests'),
    Surface('package:supplier_core/src/spec_response.dart', 'SpecResponses'),
    Surface('package:supplier_core/src/merge.dart', 'Merge'),
    Surface('package:supplier_core/src/budget.dart', 'Refresh'),
  ],
  operations: [
    for (final definition in domain.agentTools)
      Operation(
        id: (definition['function'] as Map)['name'] as String,
        kind: OpKind.query,
        tools: ['inquiry.${(definition['function'] as Map)['name']}'],
      ),
    Operation(id: 'object', kind: OpKind.query, tools: ['inquiry.object']),
    Operation(
      id: 'context_import',
      kind: OpKind.write,
      members: {'prepareImport', 'commitImport', 'receipt'},
      notExposed: const NotExposed(
        NotExposedKind.humanOnly,
        '文件上下文复核由人工选择功能、校验字段并确认记录集合；没有模型提交工具。',
      ),
    ),
    for (final name in [
      'create_inquiry',
      'record_quote',
      'set_item_qty',
      'set_inquiry_status',
    ])
      Operation(id: name, kind: OpKind.write, tools: ['inquiry.$name']),
    Operation(
      id: 'create_record',
      kind: OpKind.write,
      members: {'save'},
      tools: ['inquiry.create_record'],
    ),
    Operation(
      id: 'update_record',
      kind: OpKind.write,
      members: {'save'},
      tools: ['inquiry.update_record'],
    ),
    Operation(
      id: 'delete_record',
      kind: OpKind.write,
      members: {'delete', 'referencesTo'},
      tools: ['inquiry.delete_record'],
    ),
    Operation(
      id: 'restore_record',
      kind: OpKind.write,
      members: {'restore'},
      tools: ['inquiry.restore_record'],
    ),
    Operation(
      id: 'quotation_price',
      kind: OpKind.write,
      members: {'quoteForInquiry'},
      tools: ['inquiry.record_quote'],
    ),
    Operation(
      id: 'product_param',
      kind: OpKind.write,
      members: {'setParam', 'clearParam', 'confirmParams', 'applyParamFill'},
      notExposed: const NotExposed(
        NotExposedKind.deferred,
        '参数使用派生 ID 与批量确认，不能使用普通 save；待询价后续具名工具。',
        taskId: 'REG-4',
      ),
    ),
    Operation(
      id: 'spec_records',
      kind: OpKind.write,
      members: {
        'createSpecRequest',
        'deleteSpecRequest',
        'restoreSpecRequest',
        'saveClauses',
        'chooseProduct',
        'setClauseResponse',
        'clearChoice',
        'applySpecResponses',
        'addItemsToBudget',
      },
      notExposed: const NotExposed(
        NotExposedKind.deferred,
        'spec_* 条款、快照与级联预算需要专用计划/应用工具，不在通用七类写入中。',
        taskId: 'REG-4',
      ),
    ),
    Operation(
      id: 'merge_duplicates',
      kind: OpKind.write,
      members: {'mergeInto', 'redirectMerged'},
      notExposed: const NotExposed(
        NotExposedKind.deferred,
        '合并会级联改引用；保留原页，待专用工具和完整引用预览。',
        taskId: 'REG-4',
      ),
    ),
    Operation(
      id: 'award',
      kind: OpKind.write,
      members: {'award', 'withdrawAward'},
      notExposed: const NotExposed(
        NotExposedKind.deferred,
        '定标改变成交价并可写回预算；撤回不恢复旧预算快照，必须有专用预览。',
        taskId: 'REG-4',
      ),
    ),
    Operation(
      id: 'refresh_prices',
      kind: OpKind.write,
      members: {'refreshPlan', 'applyRefresh'},
      notExposed: const NotExposed(
        NotExposedKind.deferred,
        '批量刷新需冻结最优价计划和逐行版本，不能以通用单条写替代。',
        taskId: 'REG-4',
      ),
    ),
  ],
);
