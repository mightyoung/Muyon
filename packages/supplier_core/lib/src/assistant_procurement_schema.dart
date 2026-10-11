part of 'assistant_procurement.dart';

extension _ProcurementSchema on AssistantProcurementTools {
  Map<String, Object?> _tool(
    String name,
    String description,
    Map<String, Object?> properties,
    List<String> required,
  ) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
    },
  };
  void _args(
    Map<String, Object?> args,
    Set<String> required, [
    Set<String> optional = const {},
  ]) {
    if (!args.keys.toSet().containsAll(required) ||
        args.keys.any((k) => !required.contains(k) && !optional.contains(k))) {
      throw const FormatException('未知或缺少采购参数');
    }
    for (final key in args.keys.where((k) => k != 'candidate_ids')) {
      if (args[key] is! String ||
          (args[key] as String).isEmpty ||
          (args[key] as String).length > 200) {
        throw const FormatException('无效采购ID或操作');
      }
    }
  }

  Record _live(String type, String id) {
    final record = store.get(type, requireUuid(id, 'id'));
    if (record == null || record.deleted) {
      throw const FormatException('原业务记录不可用');
    }
    return record;
  }

  Map<String, Object?> _record(Record r) => {
    'type': r.type,
    'id': r.id,
    'version': r.version,
    'deleted': r.deleted,
    'data': r.data,
  };
}
