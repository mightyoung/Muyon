import 'package:sqlite3/sqlite3.dart';

import 'references.dart';

enum ChangeOp { upsert, delete }

class ModuleChange {
  const ModuleChange({
    required this.sequence,
    required this.ref,
    required this.op,
    required this.recordedAt,
  });
  final int sequence;
  final ObjectRef ref;
  final ChangeOp op;
  final DateTime recordedAt;
}

/// Business change records for derived projections (object directory, search).
///
/// A module calls [createTable] from one of its own declared migrations, and
/// [record] inside the same write transaction as the business row change, so
/// the record commits or rolls back with it. The host reads [since] with its
/// own cursor and updates projections idempotently; projections are never a
/// source of truth.
abstract final class ModuleChangeLog {
  static const table = 'muyon_change_log';

  static void createTable(Database db) => db.execute('''
CREATE TABLE $table(
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  native_project_id TEXT,
  revision_ref TEXT,
  content_digest TEXT,
  op TEXT NOT NULL CHECK(op IN ('upsert','delete')),
  recorded_at TEXT NOT NULL
)''');

  static void record(Database db, ObjectRef ref, ChangeOp op, {DateTime? at}) {
    if (ref.moduleId.isEmpty || ref.objectType.isEmpty || ref.objectId.isEmpty) {
      throw ArgumentError.value(ref, 'ref', 'Incomplete object reference');
    }
    db.execute(
      'INSERT INTO $table(object_type,object_id,native_project_id,revision_ref,'
      'content_digest,op,recorded_at) VALUES(?,?,?,?,?,?,?)',
      [
        ref.objectType,
        ref.objectId,
        ref.nativeProjectId,
        ref.revisionRef,
        ref.contentDigest,
        op.name,
        (at ?? DateTime.now()).toUtc().toIso8601String(),
      ],
    );
  }

  static List<ModuleChange> since(
    Database db,
    String moduleId,
    int afterSequence, {
    int limit = 500,
  }) => [
    for (final row in db.select(
      'SELECT * FROM $table WHERE sequence > ? ORDER BY sequence LIMIT ?',
      [afterSequence, limit],
    ))
      ModuleChange(
        sequence: row['sequence'] as int,
        ref: ObjectRef(
          moduleId: moduleId,
          objectType: row['object_type'] as String,
          objectId: row['object_id'] as String,
          nativeProjectId: row['native_project_id'] as String?,
          revisionRef: row['revision_ref'] as String?,
          contentDigest: row['content_digest'] as String?,
        ),
        op: ChangeOp.values.byName(row['op'] as String),
        recordedAt: DateTime.parse(row['recorded_at'] as String),
      ),
  ];
}
