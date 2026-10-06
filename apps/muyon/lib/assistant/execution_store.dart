import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';

class ExecutionStore {
  ExecutionStore(this.database);
  final ManagedDatabase database;
  Future<void> create(AgentExecutionRecord record) => database.write((db) {
    if (record.state != ExecutionState.queued) {
      throw StateError('Must queue first');
    }
    db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
      record.executionId,
      record.state.name,
      jsonEncode(_encode(record)),
    ]);
  });
  AgentExecutionRecord? get(String id) {
    final rows = database.raw.select(
      "SELECT payload FROM execution_records WHERE id=? AND COALESCE(json_extract(payload,'\$.kind'),'')!='personal'",
      [id],
    );
    return rows.isEmpty
        ? null
        : _decode(
            jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
          );
  }

  List<AgentExecutionRecord> all() => [
    for (final row in database.raw.select(
      "SELECT payload FROM execution_records WHERE COALESCE(json_extract(payload,'\$.kind'),'')!='personal' ORDER BY rowid DESC",
    ))
      _decode(jsonDecode(row['payload'] as String) as Map<String, dynamic>),
  ];
  Future<bool> transition(
    String id,
    ExecutionState state, {
    String? error,
    String? answer,
    bool Function()? canCommit,
  }) => database.write((db) {
    if (canCommit != null && !canCommit()) return false;
    final old = get(id);
    if (old == null) throw StateError('Unknown execution');
    if (![ExecutionState.queued, ExecutionState.running].contains(old.state)) {
      return false;
    }
    if (state == ExecutionState.queued ||
        (state == ExecutionState.running &&
            old.state != ExecutionState.queued)) {
      throw StateError('Invalid transition');
    }
    final payload = _encode(old);
    final now = DateTime.now().toUtc().toIso8601String();
    payload.addAll({
      'state': state.name,
      'stage': state.name,
      'updatedAt': now,
      'error': error,
      'finishedAt': state == ExecutionState.running ? null : now,
      if (state == ExecutionState.succeeded && answer != null) 'answer': answer,
    });
    db.execute('UPDATE execution_records SET state=?,payload=? WHERE id=?', [
      state.name,
      jsonEncode(payload),
      id,
    ]);
    return true;
  });
  String? answer(String id) {
    final rows = database.raw.select(
      'SELECT payload FROM execution_records WHERE id=? AND state=?',
      [id, ExecutionState.succeeded.name],
    );
    return rows.isEmpty
        ? null
        : (jsonDecode(rows.first['payload'] as String) as Map)['answer']
              as String?;
  }

  Future<void> recoverInterrupted() async {
    for (final record in all()) {
      if ([
        ExecutionState.queued,
        ExecutionState.running,
      ].contains(record.state)) {
        await transition(
          record.executionId,
          ExecutionState.interrupted,
          error: 'process_interrupted',
        );
      }
    }
  }

  Map<String, Object?> _encode(AgentExecutionRecord r) => {
    'executionId': r.executionId,
    'parentConversationId': r.parentConversationId,
    'toolId': r.toolId,
    'contextSnapshot': r.contextSnapshot.toJson(),
    'profileId': r.profileId,
    'executionDeviceId': r.executionDeviceId,
    'state': r.state.name,
    'stage': r.stage,
    'waitReason': r.waitReason,
    'error': r.error,
    'createdAt': r.createdAt.toIso8601String(),
    'updatedAt': r.updatedAt.toIso8601String(),
    'finishedAt': r.finishedAt?.toIso8601String(),
    'previousAttemptId': r.previousAttemptId,
    'artifactRefs': [
      for (final a in r.artifactRefs)
        {
          'moduleId': a.moduleId,
          'artifactId': a.artifactId,
          'contentDigest': a.contentDigest,
        },
    ],
    'resultRefs': r.resultRefs.map((r) => r.toJson()).toList(),
  };
  ObjectRef _object(Map<String, dynamic> j) => ObjectRef(
    moduleId: j['moduleId'] as String,
    objectType: j['objectType'] as String,
    objectId: j['objectId'] as String,
    nativeProjectId: j['nativeProjectId'] as String?,
    revisionRef: j['revisionRef'] as String?,
    contentDigest: j['contentDigest'] as String?,
  );
  AgentExecutionRecord _decode(Map<String, dynamic> j) {
    final c = j['contextSnapshot'] as Map<String, dynamic>;
    return AgentExecutionRecord(
      executionId: j['executionId'] as String,
      toolId: j['toolId'] as String,
      contextSnapshot: ContextRef(
        workspaceId: c['workspaceId'] as String,
        moduleId: c['moduleId'] as String,
        nativeProjectId: c['nativeProjectId'] as String,
        currentObjectRef: c['currentObjectRef'] == null
            ? null
            : _object(c['currentObjectRef'] as Map<String, dynamic>),
        selectedObjectRefs: [
          for (final r in c['selectedObjectRefs'] as List)
            _object(r as Map<String, dynamic>),
        ],
      ),
      parentConversationId: j['parentConversationId'] as String?,
      profileId: j['profileId'] as String?,
      executionDeviceId: j['executionDeviceId'] as String,
      state: ExecutionState.values.byName(j['state'] as String),
      stage: j['stage'] as String,
      waitReason: j['waitReason'] as String?,
      error: j['error'] as String?,
      previousAttemptId: j['previousAttemptId'] as String?,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      finishedAt: j['finishedAt'] == null
          ? null
          : DateTime.parse(j['finishedAt'] as String),
      resultRefs: [
        for (final r in j['resultRefs'] as List)
          _object(r as Map<String, dynamic>),
      ],
      artifactRefs: [
        for (final r in j['artifactRefs'] as List)
          ArtifactRef(
            moduleId: r['moduleId'] as String,
            artifactId: r['artifactId'] as String,
            contentDigest: r['contentDigest'] as String,
          ),
      ],
    );
  }
}
