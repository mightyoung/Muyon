import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';

import 'foundation_repository.dart';

/// Minimal projection in the existing host settings table. The connection owner
/// serializes CAS and commits it atomically; no schema or task history changes.
class HostUiWorkspaceStore implements UiWorkspaceStore {
  HostUiWorkspaceStore(this.repository, {required this.taskId});
  final FoundationRepository repository;
  final String taskId;
  String? get scopeKey {
    final task = repository.task(taskId);
    return task == null ? null : jsonEncode(task.scope.toJson());
  }

  String _key(String surfaceId) =>
      'ui-workspace:${jsonEncode([taskId, surfaceId])}';
  StoredUiWorkspace _decode(String value) =>
      StoredUiWorkspace.fromJson(jsonDecode(value) as Map<String, dynamic>);
  @override
  Future<StoredUiWorkspace?> load(String surfaceId) async {
    final rows = repository.database.raw.select(
      'SELECT value FROM settings WHERE key=?',
      [_key(surfaceId)],
    );
    if (rows.isEmpty) return null;
    final value = _decode(rows.single['value'] as String);
    return value.taskId == taskId &&
            value.surfaceId == surfaceId &&
            value.scopeKey == scopeKey
        ? value
        : null;
  }

  @override
  Future<bool> save(StoredUiWorkspace value, {required int expectedRevision}) =>
      repository.database.write((db) {
        if (value.taskId != taskId ||
            value.scopeKey != scopeKey ||
            value.revision != expectedRevision + 1) {
          return false;
        }
        final key = _key(value.surfaceId);
        final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
        final old = rows.isEmpty
            ? null
            : _decode(rows.single['value'] as String);
        if ((old?.revision ?? 0) != expectedRevision ||
            (old != null && old.scopeKey != value.scopeKey)) {
          return false;
        }
        db.execute(
          'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          [key, jsonEncode(value.toJson())],
        );
        return true;
      });

  /// Indexed by the existing task; no new task/conversation registry.
  List<String> surfaces() {
    const prefix = 'ui-workspace:';
    final result = <String>[];
    for (final row in repository.database.raw.select(
      'SELECT key,value FROM settings WHERE substr(key,1,?)=?',
      [prefix.length, prefix],
    )) {
      try {
        final value = _decode(row['value'] as String);
        if (value.taskId == taskId && value.scopeKey == scopeKey) {
          result.add(value.surfaceId);
        }
      } catch (_) {
        // Keep a damaged projection discoverable in its owning task. Opening
        // it reports the read failure without deleting or rewriting the bytes.
        try {
          final ids = jsonDecode(
            (row['key'] as String).substring(prefix.length),
          );
          if (ids is List &&
              ids.length == 2 &&
              ids[0] == taskId &&
              ids[1] is String) {
            result.add(ids[1] as String);
          }
        } catch (_) {
          /* Unrelated setting is not a workspace. */
        }
      }
    }
    return result;
  }
}
