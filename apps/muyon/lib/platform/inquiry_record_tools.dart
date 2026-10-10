import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

import '../app/bootstrap.dart';
import 'host_tool_registration.dart';
import 'tool_registry.dart';

const _recordTypes = [
  'supplier',
  'contact',
  'product',
  'project',
  'project_item',
  'inquiry',
  'quotation',
];
const _protectedFields = {
  'merged_into',
  'attachment_ids',
  'source_attachment_ids',
  'capture_mode',
};
// A quotation's monetary basis, identity and award are owned by the named
// quotation/award workflows. Generic creation cannot invent its required price.
const _quotationFields = {
  'quoted_on',
  'lead_time_days',
  'warranty_months',
  'valid_until',
  'notes',
};

Iterable<FieldSpec> _allowedFields(String type) => ontology[type]!.fields.where(
  (field) =>
      !_protectedFields.contains(field.name) &&
      (type != 'quotation' || _quotationFields.contains(field.name)),
);

Map<String, Object?> _fieldSchema(FieldSpec field) {
  // Avoid repeating ontology prose and size limits in both create/update and
  // native/prompt catalogs. Preflight below enforces the same size limits;
  // the ontology query supplies field labels and explanations.
  final type = switch (field.kind) {
    Kind.integer => 'integer',
    Kind.boolean => 'boolean',
    Kind.textList || Kind.refList => 'array',
    Kind.object => 'object',
    _ => 'string',
  };
  return {
    'type': [type, 'null'],
    if (type == 'array') ...{
      'items': {'type': 'string'},
    },
    if (type == 'object') 'additionalProperties': true,
    if (field.values != null) 'enum': [...field.values!.keys, null],
  };
}

Map<String, Object?> _objectSchema(
  Map<String, Object?> fields,
  List<String> required,
) => {
  'type': 'object',
  'properties': fields,
  'required': required,
  'additionalProperties': false,
};
const _uuidSchema = {'type': 'string', 'minLength': 36, 'maxLength': 36};

// The registry deliberately has no oneOf/conditional-schema support. Publish
// the ontology-derived union, then enforce the selected type's exact fields in
// host preflight (and again in the transaction), never silently ignore keys.
Map<String, Object?> _recordSchema(String operation) {
  final editing = operation == 'create_record' || operation == 'update_record';
  final grouped = <String, List<FieldSpec>>{};
  for (final type in _recordTypes) {
    for (final field in _allowedFields(type)) {
      grouped.putIfAbsent(field.name, () => []).add(field);
    }
  }
  return _objectSchema(
    {
      'operation_id': {
        ..._uuidSchema,
        'description': '业务重试沿用此 UUID，不换参数或范围。',
      },
      'type': {'type': 'string', 'enum': _recordTypes},
      if (operation != 'create_record') ...{
        'id': _uuidSchema,
        'expected_version': {'type': 'integer', 'minimum': 1},
      },
      if (editing)
        'values': _objectSchema({
          for (final entry in grouped.entries)
            entry.key: {
              ..._fieldSchema(entry.value.first),
              'type': {
                for (final f in entry.value)
                  ...(_fieldSchema(f)['type'] as List),
              }.toList(),
              if (entry.value.every((f) => f.values != null))
                'enum': {
                  for (final f in entry.value) ...f.values!.keys,
                  null,
                }.toList(),
            },
        }, []),
      if (operation == 'delete_record')
        'referencing_records': {
          'type': 'array',
          'maxItems': 500,
          'description': '删除预览必须列出所有活跃引用对象的 type、id、version；执行前核对，存在引用即拒绝删除。',
          'items': _objectSchema(
            {
              'type': {'type': 'string', 'enum': entityTypes},
              'id': _uuidSchema,
              'version': {'type': 'integer', 'minimum': 1},
            },
            ['type', 'id', 'version'],
          ),
        },
    },
    [
      'operation_id',
      'type',
      if (operation != 'create_record') ...['id', 'expected_version'],
      if (editing) 'values',
      if (operation == 'delete_record') 'referencing_records',
    ],
  );
}

void _validateArguments(String operation, Map<String, Object?> p) {
  requireUuid(p['operation_id'], 'operation_id');
  final type = p['type'] as String;
  if (!_recordTypes.contains(type)) invalid('type', 'unsupported record type');
  if (operation != 'create_record') requireUuid(p['id'], 'id');
  if (p['values'] case final Map<String, Object?> values) {
    final fields = {
      for (final field in _allowedFields(type)) field.name: field,
    };
    if (values.isEmpty || values.keys.any((key) => !fields.containsKey(key))) {
      invalid('values', 'Unknown, protected or forbidden fields for $type');
    }
    for (final entry in values.entries) {
      final field = fields[entry.key]!;
      final value = entry.value;
      if (value == null) {
        continue; // Full payload validation checks required fields.
      }
      if ((value is String && value.length > 2000) ||
          (value is List &&
              (value.length > 500 ||
                  value.any((v) => v is String && v.length > 200)))) {
        invalid(entry.key, 'Field exceeds the approved size limit');
      }
      final valid = switch (field.kind) {
        Kind.integer => value is int,
        Kind.boolean => value is bool,
        Kind.textList ||
        Kind.refList => value is List && value.every((v) => v is String),
        Kind.object => value is Map<String, Object?>,
        _ => value is String,
      };
      if (!valid ||
          (field.values != null && !field.values!.containsKey(value))) {
        invalid(entry.key, 'Value does not match the ontology field');
      }
      if (field.kind == Kind.ref) requireUuid(value, entry.key);
      if (field.kind == Kind.refList) {
        for (final id in value as List) {
          requireUuid(id, entry.key);
        }
      }
    }
  }
}

Object? _canonical(Object? value) => switch (value) {
  Map value => {
    for (final key in (value.keys.cast<String>().toList()..sort()))
      key: _canonical(value[key]),
  },
  List value => value.map(_canonical).toList(),
  _ => value,
};
String _json(Object? value) => jsonEncode(_canonical(value));

ObjectRef _ref(Store store, String type, String id) {
  final row = store.db.select('SELECT data,version FROM $type WHERE id=?', [
    id,
  ]).single;
  final data = jsonDecode(row['data'] as String) as Map;
  return ObjectRef(
    moduleId: 'inquiry',
    objectType: type,
    objectId: id,
    nativeProjectId: type == 'project' ? id : data['project_id'] as String?,
    revisionRef: '${row['version']}',
    contentDigest: sha256
        .convert(utf8.encode(row['data'] as String))
        .toString(),
  );
}

void _requireSelected(ToolCallContext call, String type, String id) {
  if (!call.resolvedScope.objects.any(
    (r) => r.moduleId == 'inquiry' && r.objectType == type && r.objectId == id,
  )) {
    invalid('scope', '需要先选定这条记录（$type $id）');
  }
}

void _currentSelection(MuyonHost host, Store store, ToolCallContext call) {
  final workspace = call.request.scope.workspaceId;
  for (final selected in call.resolvedScope.objects) {
    final row = store.get(selected.objectType, selected.objectId);
    if (row == null ||
        !sameObjectIdentity(_ref(store, row.type, row.id), selected) ||
        '${row.version}' != selected.revisionRef ||
        _ref(store, row.type, row.id).contentDigest != selected.contentDigest ||
        (workspace != null &&
            host.workspaces.binding(workspace, 'inquiry')?.nativeProjectId !=
                selected.nativeProjectId)) {
      invalid('scope', '选定记录或工作区已变化，请重新确认');
    }
  }
}

List<Map<String, Object?>> _incoming(Store store, String type, String id) {
  final records = <String, Map<String, Object?>>{};
  // referencesTo supplies the domain delete preview counts. Include same-type
  // references too (its recycle-bin count intentionally omits those).
  final counts = store.referencesTo(type, id);
  for (final link in links.where(
    (l) => l.to == type && (l.from == type || counts.containsKey(l.name)),
  )) {
    final condition = link.many
        ? "EXISTS (SELECT 1 FROM json_each(data,'\$.${link.field}') WHERE value=?)"
        : "json_extract(data,'\$.${link.field}')=?";
    for (final row in store.db.select(
      'SELECT id,version FROM ${link.from} WHERE deleted=0 AND $condition',
      [id],
    )) {
      final record = {
        'type': link.from,
        'id': row['id'],
        'version': row['version'],
      };
      records['${link.from}:${row['id']}'] = record;
    }
  }
  return [for (final key in (records.keys.toList()..sort())) records[key]!];
}

void _checkDataScope(
  ToolCallContext call,
  String type,
  Map<String, Object?> data,
  Map<String, Object?> values, {
  required bool creating,
}) {
  final projects = {
    for (final r in call.resolvedScope.objects) r.nativeProjectId,
  };
  if (creating &&
      const {'supplier', 'contact', 'product', 'project'}.contains(type) &&
      !projects.contains(null)) {
    invalid('scope', '新建全局记录需要选定询价全局对象');
  }
  final project = data['project_id'];
  if (project != null && !projects.contains(project)) {
    invalid('scope', '目标项目不在选定范围内');
  }
  for (final link in links.where(
    (l) => l.from == type && values.containsKey(l.field),
  )) {
    final raw = values[link.field];
    final ids = link.many ? (raw as List? ?? []) : [?raw];
    for (final id in ids) {
      _requireSelected(call, link.to, id as String);
    }
  }
  if (type == 'inquiry') {
    for (final id in data['item_ids'] as List) {
      if (call.resolvedScope.objects.isEmpty) {
        invalid('scope', 'Empty selection');
      }
      // Membership is checked below against the real Store, as in the old tool.
      requireUuid(id, 'item_ids');
    }
  }
}

Future<void> _validateResult(
  ResolvedAssistantScope scope,
  ToolCallResult result,
) async {
  final projects = {for (final r in scope.objects) r.nativeProjectId};
  if (result.artifactRefs.isNotEmpty ||
      result.objectRefs.any(
        (r) =>
            r.moduleId != 'inquiry' ||
            !_recordTypes.contains(r.objectType) ||
            (!projects.contains(r.nativeProjectId) &&
                !(projects.contains(null) &&
                    r.objectType == 'project' &&
                    r.nativeProjectId == r.objectId)),
      )) {
    throw const ToolPlatformException(
      'result_scope_mismatch',
      'Record result outside the approved scope',
    );
  }
}

/// Registration remains host-owned. Domain writes and business receipts share
/// the existing Store transaction; invocation approvals/receipts stay in the
/// existing registry. Neither a model boolean nor an operation ID is approval.
void registerInquiryRecordTools(
  MuyonHost host, {
  HostToolRegistration? register,
}) {
  final registerTool = register ?? host.tools.register;
  for (final operation in [
    'create_record',
    'update_record',
    'delete_record',
    'restore_record',
  ]) {
    registerTool(
      providerId: 'inquiry',
      descriptor: ToolDescriptor(
        toolId: 'inquiry.$operation',
        moduleId: 'inquiry',
        effect: ToolEffect.write,
        description:
            '按询价本体${switch (operation) {
              'create_record' => '新建',
              'update_record' => '修改',
              'delete_record' => '删除',
              _ => '恢复',
            }}一条本机记录，确认后会修改台账；仅选定范围，检查版本。报价只改非价格字段；有活跃引用禁止删除。',
        parameterSchema: _recordSchema(operation),
        supportsCancel: true,
      ),
      supportedScopes: {AssistantScopeKind.selectedObjects},
      dataModuleIds: {'inquiry'},
      validateResult: _validateResult,
      preflight: (request) {
        try {
          _validateArguments(operation, request.parameters);
        } on FormatException catch (error) {
          throw ToolPlatformException('invalid_parameters', error.message);
        }
      },
      handler: (call) async {
        call.cancellation.throwIfCancelled();
        await host.activateInquiry();
        final state = host.inquiry?.runtime.state;
        if (state == null) {
          return ToolCallResult(
            status: ToolCallStatus.failed,
            summary: '询价不可用',
          );
        }
        final p = call.request.parameters;
        ToolCallResult? result;
        final error = state.write(
          (s) => s.transaction(() {
            _validateArguments(operation, p);
            _currentSelection(host, s, call);
            final type = p['type'] as String;
            final creating = operation == 'create_record';
            if (!creating) _requireSelected(call, type, p['id'] as String);
            final scopeKey = _json({
              'workspace': call.request.scope.workspaceId,
              'objects':
                  (call.resolvedScope.objects
                      .map(
                        (r) => _json([
                          r.moduleId,
                          r.objectType,
                          r.objectId,
                          r.nativeProjectId,
                        ]),
                      )
                      .toList()
                    ..sort()),
            });
            final arguments = _json({
              'operation': operation,
              'parameters': p,
              'scope': scopeKey,
            });
            final receiptKey = 'reg4c:${p['operation_id']}';
            final receipts = s.db.select('SELECT value FROM meta WHERE key=?', [
              receiptKey,
            ]);
            if (receipts.isNotEmpty) {
              final receipt =
                  jsonDecode(receipts.single['value'] as String) as Map;
              if (receipt['arguments'] != arguments) {
                invalid('operation_id', '业务操作 ID 已用于不同参数或范围');
              }
              result = ToolCallResult.fromJson(
                (receipt['result'] as Map).cast<String, Object?>(),
              );
              return;
            }
            final id = creating ? newUuid() : p['id'] as String;
            final previous = creating ? null : s.get(type, id);
            if (!creating) {
              if (previous == null ||
                  previous.deleted != (operation == 'restore_record')) {
                invalid('id', 'Record unavailable for this operation');
              }
              if (previous.version != p['expected_version']) {
                invalid('expected_version', '记录版本已变化，请重新确认');
              }
            }
            final values =
                (p['values'] as Map?)?.cast<String, Object?>() ??
                <String, Object?>{};
            final data = validatePayload(type, {
              for (final field in payloadFields(type)) field: null,
              if (type == 'supplier') ...{
                'aliases': <String>[],
                'categories': <String>[],
              },
              if (type == 'inquiry') ...{
                'item_ids': <String>[],
                'supplier_ids': <String>[],
              },
              if (type == 'quotation') 'capture_mode': 'standard',
              ...?previous?.data,
              ...values,
            });
            _checkDataScope(call, type, data, values, creating: creating);
            if (type == 'inquiry') {
              for (final item in data['item_ids'] as List) {
                if (s.get('project_item', item as String)?.data['project_id'] !=
                    data['project_id']) {
                  invalid(
                    'item_ids',
                    'Inquiry items must belong to this project',
                  );
                }
              }
            }
            if (operation == 'restore_record') {
              for (final link in links.where((l) => l.from == type)) {
                final raw = data[link.field];
                final ids = link.many
                    ? (raw as List? ?? [])
                    : [?raw];
                for (final related in ids) {
                  final target = s.get(link.to, related as String);
                  if (target == null || target.deleted) {
                    invalid(link.field, '请先恢复被引用记录');
                  }
                }
              }
            }
            if (operation == 'delete_record') {
              final incoming = _incoming(s, type, id);
              final supplied =
                  (p['referencing_records'] as List)
                      .map((r) => _json(r))
                      .toList()
                    ..sort();
              final actual = incoming.map(_json).toList()..sort();
              if (_json(supplied) != _json(actual)) {
                invalid('referencing_records', '引用预览已变化或不完整，请重新确认');
              }
              for (final r in incoming) {
                _requireSelected(call, r['type'] as String, r['id'] as String);
              }
              if (incoming.isNotEmpty) {
                invalid(
                  'references',
                  '仍被活跃记录引用，不能删除：${describeReferences(s.referencesTo(type, id))}',
                );
              }
            }
            call.checkBeforeEffect();
            switch (operation) {
              case 'create_record':
                s.save(type, data, newId: id);
              case 'update_record':
                s.save(type, data, id: id, allowClear: true);
              case 'delete_record':
                s.delete(type, id);
              case 'restore_record':
                s.restore(type, id);
            }
            final saved = s.get(type, id)!;
            final ref = _ref(s, type, id);
            result = ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: '已完成${ontology[type]!.label}记录操作',
              data: {
                'operation_id': p['operation_id'],
                'type': type,
                'id': id,
                'version': saved.version,
                'deleted': saved.deleted,
              },
              objectRefs: [ref],
              changes: [
                ObjectChange(
                  ref,
                  saved.deleted ? ChangeOp.delete : ChangeOp.upsert,
                ),
              ],
            );
            s.db.execute('INSERT INTO meta(key,value) VALUES (?,?)', [
              receiptKey,
              jsonEncode({'arguments': arguments, 'result': result!.toJson()}),
            ]);
          }),
        );
        // A committed receipt remains authoritative if a listener throws.
        if (result != null) return result!;
        return ToolCallResult(
          status: ToolCallStatus.failed,
          summary: error ?? '未执行记录操作',
        );
      },
    );
  }
}
