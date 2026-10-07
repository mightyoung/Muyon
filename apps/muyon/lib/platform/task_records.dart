/// Task rows, the append-only event table and the object links behind them
/// (K-4; ADR-0005 §6.5, §8.3; deep review §6.4.4).
///
/// `execution_records` stays the authority for what a personal task *is*
/// (its payload). `tasks` is a flat copy kept in the same transaction so a
/// task can be listed and joined without parsing JSON; `task_events` is the
/// timeline; `task_objects` answers "which tasks touched this object".
/// Everything here runs inside the caller's `database.write` transaction.
library;

import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// An event before it has a `seq`. Like every event it carries digests,
/// sizes, ids and fixed codes only, never a body or a key.
class TaskEventDraft {
  const TaskEventDraft(this.type, {this.step, this.data = const {}});
  final String type;
  final int? step;
  final Map<String, Object?> data;
}

/// One stored event. [toJson] has the shape the payload list always had
/// (`seq`, `at`, `type`, and `step` / `data` when present).
class TaskEvent {
  const TaskEvent({
    required this.taskId,
    required this.seq,
    required this.at,
    required this.type,
    this.step,
    this.data = const {},
  });
  final String taskId;
  final int seq;
  final String at;
  final String type;
  final int? step;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'seq': seq,
    'at': at,
    'type': type,
    'step': ?step,
    if (data.isNotEmpty) 'data': data,
  };
}

/// Why an object is linked to a task.
abstract final class TaskObjectRole {
  /// Returned by a tool call that has a receipt.
  static const toolResult = 'tool_result';

  /// Cited by the answer.
  static const answer = 'answer';
}

class TaskObjectLink {
  const TaskObjectLink({
    required this.taskId,
    required this.ref,
    required this.role,
  });
  final String taskId;
  final ObjectRef ref;
  final String role;
}

abstract final class TaskRecords {
  /// Migration 8 body: the tables, and the tasks and events that already
  /// exist in payloads copied over (the payload keeps its own `events`, which
  /// stay readable).
  static void migrate(Database db) {
    db.execute('''
CREATE TABLE tasks(
  id TEXT PRIMARY KEY,
  conversation_id TEXT,
  kind TEXT,
  state TEXT,
  goal TEXT,
  workspace_id TEXT,
  profile_id TEXT,
  device_id TEXT,
  created_at TEXT,
  updated_at TEXT,
  finished_at TEXT,
  previous_attempt_id TEXT
);
CREATE INDEX tasks_conversation ON tasks(conversation_id);
CREATE TABLE task_events(
  task_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  at TEXT NOT NULL,
  type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY(task_id, seq)
);
CREATE TABLE task_objects(
  task_id TEXT NOT NULL,
  module_id TEXT NOT NULL,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  role TEXT NOT NULL,
  PRIMARY KEY(task_id, module_id, object_type, object_id, role)
);
CREATE INDEX task_objects_object ON task_objects(module_id, object_type, object_id);
INSERT INTO tasks
SELECT id,
  json_extract(payload,'\$.conversationId'),
  'personal',
  state,
  json_extract(payload,'\$.prompt'),
  json_extract(payload,'\$.scope.workspaceId'),
  json_extract(payload,'\$.profile.id'),
  json_extract(payload,'\$.executionDeviceId'),
  json_extract(payload,'\$.createdAt'),
  json_extract(payload,'\$.updatedAt'),
  CASE WHEN state IN ('succeeded','failed','cancelled')
    THEN json_extract(payload,'\$.updatedAt') END,
  json_extract(payload,'\$.previousAttemptId')
FROM execution_records
WHERE json_extract(payload,'\$.kind')='personal';
INSERT OR IGNORE INTO task_events
SELECT r.id,
  json_extract(e.value,'\$.seq'),
  COALESCE(json_extract(e.value,'\$.at'),''),
  json_extract(e.value,'\$.type'),
  json_remove(e.value,'\$.seq','\$.at','\$.type')
FROM execution_records r, json_each(r.payload,'\$.events') e
WHERE json_extract(r.payload,'\$.kind')='personal'
  AND json_extract(e.value,'\$.seq') IS NOT NULL
  AND json_extract(e.value,'\$.type') IS NOT NULL;
''');
  }

  static const _finished = {'succeeded', 'failed', 'cancelled'};

  /// Keeps the flat row of a personal task equal to its payload.
  static void syncTask(
    Database db,
    Map<String, Object?> payload,
    String state,
  ) {
    final scope = payload['scope'];
    final updated = payload['updatedAt'] as String?;
    db.execute(
      '''
INSERT INTO tasks(id,conversation_id,kind,state,goal,workspace_id,profile_id,
  device_id,created_at,updated_at,finished_at,previous_attempt_id)
VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(id) DO UPDATE SET
  conversation_id=excluded.conversation_id, kind=excluded.kind,
  state=excluded.state, goal=excluded.goal, workspace_id=excluded.workspace_id,
  profile_id=excluded.profile_id, device_id=excluded.device_id,
  updated_at=excluded.updated_at, finished_at=excluded.finished_at,
  previous_attempt_id=excluded.previous_attempt_id
''',
      [
        payload['executionId'],
        payload['conversationId'],
        payload['kind'],
        state,
        payload['prompt'],
        scope is Map ? scope['workspaceId'] : null,
        (payload['profile'] as Map?)?['id'],
        payload['executionDeviceId'],
        payload['createdAt'],
        updated,
        _finished.contains(state) ? updated : null,
        payload['previousAttemptId'],
      ],
    );
  }

  /// Events from before the table: a task payload's own `events` list.
  static List<TaskEvent> _legacy(String taskId, Object? list) => [
    for (final e in list as List? ?? const [])
      if (e is Map && e['seq'] is int && e['type'] is String)
        TaskEvent(
          taskId: taskId,
          seq: e['seq'] as int,
          at: '${e['at'] ?? ''}',
          type: e['type'] as String,
          step: e['step'] as int?,
          data: e['data'] is Map
              ? Map<String, Object?>.from(e['data'] as Map)
              : const {},
        ),
  ];

  /// The timeline of [taskId] in `seq` order: the table's events plus any
  /// from the payload's old `events` list that the table does not hold.
  static List<TaskEvent> events(Database db, String taskId) {
    final stored = [
      for (final r in db.select(
        'SELECT seq,at,type,payload_json FROM task_events WHERE task_id=? ORDER BY seq',
        [taskId],
      ))
        _row(taskId, r),
    ];
    final payload = db.select(
      'SELECT payload FROM execution_records WHERE id=?',
      [taskId],
    );
    if (payload.isEmpty) return stored;
    final legacy = _legacy(
      taskId,
      (jsonDecode(payload.first['payload'] as String) as Map)['events'],
    );
    if (legacy.isEmpty) return stored;
    final seen = {for (final e in stored) e.seq};
    return [
      ...stored,
      for (final e in legacy)
        if (!seen.contains(e.seq)) e,
    ]..sort((a, b) => a.seq.compareTo(b.seq));
  }

  static TaskEvent _row(String taskId, Row r) {
    final body = jsonDecode(r['payload_json'] as String) as Map;
    return TaskEvent(
      taskId: taskId,
      seq: r['seq'] as int,
      at: r['at'] as String,
      type: r['type'] as String,
      step: body['step'] as int?,
      data: body['data'] is Map
          ? Map<String, Object?>.from(body['data'] as Map)
          : const {},
    );
  }

  /// Appends [drafts] after the last event of [taskId]. `seq` is computed
  /// here, in the writer's transaction, from what is stored (and from any old
  /// payload `events`), so it only ever goes up.
  static void append(
    Database db,
    String taskId,
    List<TaskEventDraft> drafts,
    String at,
  ) {
    if (drafts.isEmpty) return;
    var seq =
        db.select(
              'SELECT COALESCE(MAX(seq),0) AS m FROM task_events WHERE task_id=?',
              [taskId],
            ).first['m']
            as int;
    final payload = db.select(
      'SELECT payload FROM execution_records WHERE id=?',
      [taskId],
    );
    if (payload.isNotEmpty) {
      for (final e in _legacy(
        taskId,
        (jsonDecode(payload.first['payload'] as String) as Map)['events'],
      )) {
        if (e.seq > seq) seq = e.seq;
      }
    }
    for (final d in drafts) {
      seq++;
      db.execute(
        'INSERT INTO task_events(task_id,seq,at,type,payload_json) VALUES(?,?,?,?,?)',
        [
          taskId,
          seq,
          at,
          d.type,
          jsonEncode({'step': ?d.step, if (d.data.isNotEmpty) 'data': d.data}),
        ],
      );
    }
  }

  static void link(
    Database db,
    String taskId,
    Iterable<ObjectRef> refs,
    String role,
  ) {
    for (final ref in refs) {
      db.execute('INSERT OR IGNORE INTO task_objects VALUES(?,?,?,?,?)', [
        taskId,
        ref.moduleId,
        ref.objectType,
        ref.objectId,
        role,
      ]);
    }
  }

  /// Objects of the tool results the task has recorded (the receipts it took
  /// results from).
  static List<ObjectRef> toolResultObjects(Map<String, Object?> payload) => [
    for (final c in (payload['step'] as Map?)?['calls'] as List? ?? const [])
      for (final r
          in ((c as Map)['outcome'] as Map?)?['result'] == null
              ? const []
              : (((c['outcome'] as Map)['result'] as Map)['objectRefs']
                        as List? ??
                    const []))
        objectRefFromJson(Map<String, Object?>.from(r as Map)),
  ];

  static List<TaskObjectLink> linksOfTask(Database db, String taskId) => [
    for (final r in db.select(
      'SELECT * FROM task_objects WHERE task_id=? ORDER BY rowid',
      [taskId],
    ))
      _link(r),
  ];

  static List<TaskObjectLink> linksOfObject(Database db, ObjectRef ref) => [
    for (final r in db.select(
      'SELECT * FROM task_objects WHERE module_id=? AND object_type=? AND object_id=? ORDER BY rowid',
      [ref.moduleId, ref.objectType, ref.objectId],
    ))
      _link(r),
  ];

  static TaskObjectLink _link(Row r) => TaskObjectLink(
    taskId: r['task_id'] as String,
    ref: ObjectRef(
      moduleId: r['module_id'] as String,
      objectType: r['object_type'] as String,
      objectId: r['object_id'] as String,
    ),
    role: r['role'] as String,
  );
}
