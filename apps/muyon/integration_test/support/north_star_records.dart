// Read-only queries over what a North Star run recorded in the host database.
import 'dart:convert';

import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:supplier_core/supplier_core.dart';

List<String> proposedTools(PersonalTask task) => [
  for (final m in task.payload['messages'] as List)
    if ((m as Map)['role'] == 'assistant')
      if (_tryJson(m['content'] as String) case {
        'type': 'tool',
        'toolId': final String id,
      })
        id,
];

Object? _tryJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

String? previewText(String? text) => text == null
    ? null
    : text.length > 200
    ? '${text.substring(0, 200)}…'
    : text;

Map<String, int> histogram(Iterable<String> values) {
  final out = <String, int>{};
  for (final v in values) {
    out[v] = (out[v] ?? 0) + 1;
  }
  return out;
}

int countRows(Store store, String type) =>
    store.db.select('SELECT COUNT(*) c FROM $type WHERE deleted=0').first['c']
        as int;

List<Map<String, Object?>> _rows(MuyonHost host, String sql) => [
  for (final row in host.foundation.database.raw.select(sql))
    Map<String, Object?>.from(row),
];

List<Map<String, Object?>> receiptRows(MuyonHost host) =>
    _rows(host, 'SELECT * FROM tool_invocation_receipts ORDER BY rowid');
List<Map<String, Object?>> approvalRows(MuyonHost host) =>
    _rows(host, 'SELECT * FROM tool_approvals ORDER BY rowid');
List<Map<String, Object?>> ledgerRows(MuyonHost host) =>
    _rows(host, 'SELECT * FROM outbound_requests ORDER BY rowid');

/// Everything that must be identical after close and reopen.
Map<String, Object?> recordSnapshot(MuyonHost host) => {
  'conversations': [
    for (final c in host.foundation.conversations())
      {
        'id': c.id,
        'title': c.title,
        'scope': c.scope.toJson(),
        'messages': [
          for (final m in host.foundation.messages(c.id))
            {
              'id': m.id,
              'role': m.role,
              'content': m.content,
              'references': m.references.map((r) => r.toJson()).toList(),
            },
        ],
      },
  ],
  'tasks': [for (final t in host.foundation.tasks()) t.payload],
  'receipts': receiptRows(host),
  'approvals': approvalRows(host),
  'outboundRequests': ledgerRows(host),
};

Map<String, Object?> snapshotCounts(Map<String, Object?> snapshot) => {
  'conversations': (snapshot['conversations'] as List).length,
  'messages': (snapshot['conversations'] as List).fold<int>(
    0,
    (n, c) => n + ((c as Map)['messages'] as List).length,
  ),
  'tasks': (snapshot['tasks'] as List).length,
  'receipts': (snapshot['receipts'] as List).length,
  'approvals': (snapshot['approvals'] as List).length,
  'outboundRequests': (snapshot['outboundRequests'] as List).length,
};
