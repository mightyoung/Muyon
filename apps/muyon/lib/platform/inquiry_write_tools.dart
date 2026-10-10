import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../app/bootstrap.dart';
import 'tool_registry.dart';
import 'inquiry_record_tools.dart';
import 'host_tool_registration.dart';
import 'grants/host_effect_intent.dart';

/// Inquiry write tools. They call the same domain functions the pages call
/// (`Store.createInquiry`, `quoteForInquiry`, `save`) through `AppState.write`,
/// so validation, amounts and change records are the module's own.
///
/// Every tool states the value it expects to replace (`from_*`). The handler
/// refuses to run when the record no longer holds that value, so the approved
/// preview — parameters that show old → new — is exactly what happens.
/// Records must be explicitly selected; nothing is written without host
/// approval (the registry enforces it for [ToolEffect.write]).
const _id = {'type': 'string', 'minLength': 1, 'maxLength': 64};
const _text = {'type': 'string', 'minLength': 1, 'maxLength': 200};
const _decimal = {'type': 'string', 'minLength': 1, 'maxLength': 40};
const _status = {
  'type': 'string',
  'enum': ['open', 'closed'],
};

Map<String, Object?> _schema(
  Map<String, Object?> properties,
  List<String> required,
) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};

/// Written objects must belong to a project the user selected.
Future<void> validateInquiryWriteResult(
  ResolvedAssistantScope scope,
  ToolCallResult result,
) async {
  final projects = {
    for (final ref in scope.objects)
      if (ref.moduleId == 'inquiry') ?ref.nativeProjectId,
  };
  if (result.artifactRefs.isNotEmpty ||
      result.objectRefs.any(
        (ref) =>
            ref.moduleId != 'inquiry' ||
            !projects.contains(ref.nativeProjectId),
      )) {
    throw const ToolPlatformException(
      'result_scope_mismatch',
      'Written records are outside the selected project',
    );
  }
}

ToolCallResult _failed(String reason) =>
    ToolCallResult(status: ToolCallStatus.failed, summary: reason);

void registerInquiryWriteTools(
  MuyonHost host, {
  HostToolRegistration? register,
}) {
  registerInquiryRecordTools(host, register: register);
  final registerTool = register ?? host.tools.register;
  void write({
    required String name,
    required String description,
    required Map<String, Object?> schema,
    required Future<ToolCallResult> Function(
      Store store,
      AppStateWriter write,
      Map<String, Object?> p,
      ToolCallContext call,
    )
    run,
  }) {
    registerTool(
      providerId: 'inquiry',
      descriptor: ToolDescriptor(
        toolId: 'inquiry.$name',
        moduleId: 'inquiry',
        effect: ToolEffect.write,
        description: description,
        parameterSchema: schema,
        supportsCancel: true,
      ),
      supportedScopes: {AssistantScopeKind.selectedObjects},
      dataModuleIds: {'inquiry'},
      validateResult: validateInquiryWriteResult,
      // Narrow verified lane: this handler only applies the requested scalar
      // change to the selected local row, never loads imported prose for AI.
      effectIntent: name != 'set_item_qty'
          ? null
          : (request, scope) => HostEffectIntent.localWrite(
              toolId: request.toolId,
              invocationId: request.invocationId,
              content: utf8.encode(jsonEncode(request.parameters)),
              sourceObjects: scope.objects,
            ),
      handler: (call) async {
        call.cancellation.throwIfCancelled();
        await host.activateInquiry();
        final state = host.inquiry?.runtime.state;
        if (state == null) {
          return _failed(host.inquiryError ?? 'Inquiry unavailable');
        }
        return run(state.store, state.write, call.request.parameters, call);
      },
    );
  }

  write(
    name: 'create_inquiry',
    description:
        '为一个项目发起询价单：选定若干预算行和供应商，创建一张进行中的询价单。'
        '会修改本机询价数据（新增一张询价单），不发送给任何供应商；需要你确认后才执行。',
    schema: _schema(
      {
        'project_id': _id,
        'title': _text,
        'item_ids': {
          'type': 'array',
          'items': _id,
          'minItems': 1,
          'maxItems': 500,
        },
        'supplier_ids': {
          'type': 'array',
          'items': _id,
          'minItems': 1,
          'maxItems': 50,
        },
      },
      ['project_id', 'title', 'item_ids', 'supplier_ids'],
    ),
    run: (store, write, p, call) async {
      final items = (p['item_ids'] as List).cast<String>();
      final suppliers = (p['supplier_ids'] as List).cast<String>();
      final missing = _unselected(call, [
        ('project', p['project_id'] as String),
        for (final id in items) ('project_item', id),
        for (final id in suppliers) ('supplier', id),
      ]);
      if (missing != null) return _failed(missing);
      // The store does not check this; the assistant's own write path and the
      // page's item picker both guarantee it, so the tool must too.
      for (final id in items) {
        final item = store.get('project_item', id);
        if (item == null ||
            item.deleted ||
            item.data['project_id'] != p['project_id']) {
          return _failed('询价的预算行必须属于这个项目');
        }
      }
      String? created;
      call.checkBeforeEffect();
      final error = write(
        (s) => created = s.createInquiry(
          p['project_id'] as String,
          p['title'] as String,
          itemIds: items,
          supplierIds: suppliers,
        ),
      );
      if (error != null || created == null) return _failed(error ?? '未创建');
      return _applied(store, '已创建询价单', 'inquiry', created!);
    },
  );

  write(
    name: 'record_quote',
    description:
        '在一张询价单上记录或修订某供应商对某预算行的报价。需写明当前已有的单价（没有则为 null），'
        '与实际不符时不会执行。会修改本机询价数据（新增或更新一条报价），不联系供应商；需要你确认后才执行。',
    schema: _schema(
      {
        'inquiry_id': _id,
        'item_id': _id,
        'supplier_id': _id,
        'price': _decimal,
        'expected_current_price': {
          'type': ['string', 'null'],
          'maxLength': 40,
        },
      },
      [
        'inquiry_id',
        'item_id',
        'supplier_id',
        'price',
        'expected_current_price',
      ],
    ),
    run: (store, write, p, call) async {
      final inquiryId = p['inquiry_id'] as String;
      final itemId = p['item_id'] as String;
      final supplierId = p['supplier_id'] as String;
      final missing = _unselected(call, [
        ('inquiry', inquiryId),
        ('project_item', itemId),
        ('supplier', supplierId),
      ]);
      if (missing != null) return _failed(missing);
      final current = _currentQuote(store, inquiryId, itemId, supplierId);
      final expected = p['expected_current_price'] as String?;
      if (current?.price != expected) {
        return _failed(
          '当前报价是 ${current?.price ?? '（还没有报价）'}，与你给出的原值 '
          '${expected ?? '（没有）'} 不符，请重新确认',
        );
      }
      String? saved;
      call.checkBeforeEffect();
      final error = write(
        (s) => saved = s.quoteForInquiry(
          inquiryId,
          itemId,
          supplierId,
          price: p['price'] as String,
          context: (inquirer: '助手（经宿主确认）', asOf: null),
        ),
      );
      if (error != null || saved == null) return _failed(error ?? '未保存');
      return _applied(store, '已记录报价', 'quotation', saved!);
    },
  );

  write(
    name: 'set_item_qty',
    description:
        '修改项目预算行的数量。需写明当前数量，与实际不符时不会执行。'
        '会修改本机询价数据（该预算行的数量，成本合计随之变化）；需要你确认后才执行。',
    schema: _schema(
      {'item_id': _id, 'from_qty': _decimal, 'to_qty': _decimal},
      ['item_id', 'from_qty', 'to_qty'],
    ),
    run: (store, write, p, call) async {
      final itemId = p['item_id'] as String;
      final missing = _unselected(call, [('project_item', itemId)]);
      if (missing != null) return _failed(missing);
      final item = store.get('project_item', itemId);
      if (item == null || item.deleted) return _failed('预算行不存在');
      if (item.data['qty'] != p['from_qty']) {
        return _failed(
          '当前数量是 ${item.data['qty']}，与你给出的原值 ${p['from_qty']} 不符，请重新确认',
        );
      }
      call.checkBeforeEffect();
      final error = write(
        (s) => s.save('project_item', {
          ...item.data,
          'qty': p['to_qty'],
        }, id: itemId),
      );
      if (error != null) return _failed(error);
      return _applied(store, '已修改数量', 'project_item', itemId);
    },
  );

  write(
    name: 'set_inquiry_status',
    description:
        '把询价单在“进行中”和“已结束”之间切换。需写明当前状态，与实际不符时不会执行。'
        '会修改本机询价数据（询价单状态）；需要你确认后才执行。',
    schema: _schema(
      {'inquiry_id': _id, 'from_status': _status, 'to_status': _status},
      ['inquiry_id', 'from_status', 'to_status'],
    ),
    run: (store, write, p, call) async {
      final inquiryId = p['inquiry_id'] as String;
      final missing = _unselected(call, [('inquiry', inquiryId)]);
      if (missing != null) return _failed(missing);
      final inquiry = store.get('inquiry', inquiryId);
      if (inquiry == null || inquiry.deleted) return _failed('询价单不存在');
      if (inquiry.data['status'] != p['from_status']) {
        return _failed(
          '当前状态是 ${inquiry.data['status']}，与你给出的原值 ${p['from_status']} 不符，请重新确认',
        );
      }
      call.checkBeforeEffect();
      final error = write(
        (s) => s.save('inquiry', {
          ...inquiry.data,
          'status': p['to_status'],
        }, id: inquiryId),
      );
      if (error != null) return _failed(error);
      return _applied(store, '已更新询价单状态', 'inquiry', inquiryId);
    },
  );
}

typedef AppStateWriter = String? Function(void Function(Store store) action);

/// Null when every (type, id) is in the user's selection.
String? _unselected(ToolCallContext call, List<(String, String)> needed) {
  for (final (type, id) in needed) {
    final found = call.resolvedScope.objects.any(
      (ref) =>
          ref.moduleId == 'inquiry' &&
          ref.objectType == type &&
          ref.objectId == id,
    );
    if (!found) return '需要先选定这条记录（$type $id），它不在本次范围内';
  }
  return null;
}

({String id, String price})? _currentQuote(
  Store store,
  String inquiryId,
  String itemId,
  String supplierId,
) {
  final product = store.get('project_item', itemId)?.data['product_id'];
  if (product == null) return null;
  final rows = store.db.select(
    "SELECT id, data FROM quotation WHERE deleted = 0 "
    "AND json_extract(data,'\$.inquiry_id') = ? "
    "AND json_extract(data,'\$.supplier_id') = ? "
    "AND json_extract(data,'\$.product_id') = ? "
    "ORDER BY json_extract(data,'\$.quoted_on') DESC, rowid DESC LIMIT 1",
    [inquiryId, supplierId, product],
  );
  if (rows.isEmpty) return null;
  final data = jsonDecode(rows.first['data'] as String) as Map;
  return (id: rows.first['id'] as String, price: data['price'] as String);
}

ToolCallResult _applied(Store store, String summary, String type, String id) {
  final row = store.db.select('SELECT version, data FROM $type WHERE id = ?', [
    id,
  ]).first;
  final data = jsonDecode(row['data'] as String) as Map;
  final project = type == 'project' ? id : data['project_id'] as String?;
  return ToolCallResult(
    status: ToolCallStatus.succeeded,
    summary: summary,
    data: {'type': type, 'id': id, 'version': row['version']},
    objectRefs: [
      ObjectRef(
        moduleId: 'inquiry',
        objectType: type,
        objectId: id,
        nativeProjectId: project ?? _projectOfQuote(store, data),
        revisionRef: '${row['version']}',
        contentDigest: sha256
            .convert(utf8.encode(row['data'] as String))
            .toString(),
      ),
    ],
  );
}

/// A quotation made for an inquiry belongs to that inquiry's project.
String? _projectOfQuote(Store store, Map data) {
  final inquiryId = data['inquiry_id'] as String?;
  return inquiryId == null
      ? null
      : store.get('inquiry', inquiryId)?.data['project_id'] as String?;
}
