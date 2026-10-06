import 'dart:async';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'storage_manager.dart';

/// Applies module change logs to the host `object_catalog`.
///
/// The catalog is a derived, rebuildable projection: it is used for finding
/// and listing objects only. Opening, exporting or handing an object to a
/// model still re-checks existence, scope and version through the module.
///
/// Cross-database: the module log is read, then the host catalog and cursor
/// commit together. Re-reading the cursor inside the host transaction makes
/// replays and overlapping runs idempotent and keeps deletes from being
/// undone by a stale batch.
class ProjectionService {
  ProjectionService(this.host);
  final ManagedDatabase host;
  static const _batch = 500;

  /// `project_id` value for objects that belong to no project (e.g. inquiry
  /// suppliers). The column is part of the primary key and SQLite treats NULLs
  /// as distinct, so a fixed sentinel keeps global rows unique.
  static const globalProject = '';

  /// Downstream invalidation hook (e.g. search index), called after commit.
  void Function(String moduleId, List<ModuleChange> applied)? onApplied;

  final Map<String, String> _errors = {};
  final Map<String, Future<void>> _running = {};
  final Set<String> _dirty = {};

  /// Module id → last sync failure; cleared by the next successful sync.
  Map<String, String> get errors => Map.unmodifiable(_errors);

  int cursor(String moduleId) => _cursor(host.raw, moduleId);

  static int _cursor(Database db, String moduleId) {
    final rows = db.select(
      'SELECT last_applied_seq FROM projection_cursors WHERE module_id=?',
      [moduleId],
    );
    return rows.isEmpty ? 0 : rows.first['last_applied_seq'] as int;
  }

  static bool _hasLog(Database source) => source.select(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
    [ModuleChangeLog.table],
  ).isNotEmpty;

  Future<void> sync(String moduleId, Database source) async {
    if (!_hasLog(source)) return;
    while (true) {
      final changes = ModuleChangeLog.since(
        source,
        moduleId,
        cursor(moduleId),
        limit: _batch,
      );
      if (changes.isEmpty) return;
      final applied = await host.write((h) {
        final current = _cursor(h, moduleId);
        final fresh = [
          for (final c in changes)
            if (c.sequence > current) c,
        ];
        for (final c in fresh) {
          _apply(h, moduleId, c);
        }
        if (fresh.isNotEmpty) {
          h.execute('INSERT OR REPLACE INTO projection_cursors VALUES(?,?)', [
            moduleId,
            fresh.last.sequence,
          ]);
        }
        return fresh;
      });
      if (applied.isNotEmpty) onApplied?.call(moduleId, applied);
      if (changes.length < _batch) return;
    }
  }

  static void _apply(Database h, String moduleId, ModuleChange change) {
    final ref = change.ref;
    final project = ref.nativeProjectId ?? globalProject;
    if (change.op == ChangeOp.delete) {
      h.execute(
        'DELETE FROM object_catalog WHERE module_id=? AND project_id=? AND object_type=? AND object_id=?',
        [moduleId, project, ref.objectType, ref.objectId],
      );
      return;
    }
    h.execute('INSERT OR REPLACE INTO object_catalog VALUES(?,?,?,?,?)', [
      moduleId,
      project,
      ref.objectType,
      ref.objectId,
      change.summary ?? ref.objectId,
    ]);
  }

  /// Keep [moduleId]'s projection current: catch up now and after every
  /// commit on [connection]. Bursts of commits coalesce into one more run.
  void watch(String moduleId, ManagedConnection connection) {
    connection.onCommit = () => _schedule(moduleId, connection.raw);
    _schedule(moduleId, connection.raw);
  }

  /// Completes when no sync for [moduleId] is running or pending.
  Future<void> idle(String moduleId) => _running[moduleId] ?? Future.value();

  void _schedule(String moduleId, Database source) {
    if (_running.containsKey(moduleId)) {
      _dirty.add(moduleId);
      return;
    }
    _running[moduleId] = () async {
      do {
        _dirty.remove(moduleId);
        try {
          await sync(moduleId, source);
          _errors.remove(moduleId);
        } catch (error) {
          // Projection lag is visible via [errors]; business data is intact.
          _errors[moduleId] = '$error';
        }
      } while (_dirty.contains(moduleId));
      _running.remove(moduleId);
    }();
  }
}
