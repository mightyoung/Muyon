import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

enum HostTaintState { clean, unknown, tainted }

/// Stable source authority identity. Revisions are evidence, never a new
/// pollution identity. Only host adapters construct these facts.
class HostSourceFact {
  HostSourceFact.object(ObjectRef ref)
    : moduleId = ref.moduleId,
      projectId = ref.nativeProjectId,
      objectType = ref.objectType,
      objectId = ref.objectId,
      revisionRef = ref.revisionRef;
  HostSourceFact.project(this.moduleId, this.projectId)
    : objectType = null,
      objectId = null,
      revisionRef = null;
  final String moduleId;
  final String? projectId, objectType, objectId, revisionRef;
  String get identityDigest => sha256
      .convert(
        utf8.encode(jsonEncode([moduleId, projectId, objectType, objectId])),
      )
      .toString();
}

/// Host facts live outside model messages, task snapshots and summaries.
class HostTaskFacts {
  HostTaskFacts({
    required this.taskId,
    required this.conversationId,
    required this.taintState,
    required Iterable<String> sourceDigests,
  }) : sourceDigests = Set.unmodifiable(sourceDigests);
  final String taskId;
  final String? conversationId;
  final HostTaintState taintState;
  final Set<String> sourceDigests;
  bool get requiresConfirmation => taintState != HostTaintState.clean;
}

/// Host-only state store. Never expose it through a registrar or model tool.
/// Missing facts are unknown, not a default false pollution claim.
class HostAuthorizationFacts {
  HostAuthorizationFacts(this.database);
  final ManagedDatabase database;
  static final _denials = Expando<Set<String>>();
  Set<String> get _deny => _denials[database] ??= <String>{};
  static final _sourceDenials = Expando<Map<String, HostSourceFact>>();
  Map<String, HostSourceFact> get _pendingSources =>
      _sourceDenials[database] ??= {};
  static final _historyDenials = Expando<Map<String, Set<String>>>();
  Map<String, Set<String>> get _pendingHistory =>
      _historyDenials[database] ??= {};

  Future<void> markExternal(String taskId, HostSourceFact source) {
    final current = _read(database.raw, 'auth1b:task:$taskId');
    if (current == null ||
        current['taskId'] != taskId ||
        current['conversationId'] is! String) {
      return Future.error(StateError('Missing authoritative task facts'));
    }
    final conversation = current['conversationId'] as String;
    // Set before queuing. Never undo this latch on failed persistence.
    _deny.addAll([
      'task:$taskId',
      'conversation:$conversation',
      'source:${source.identityDigest}',
    ]);
    _pendingSources[source.identityDigest] = source;
    (_pendingHistory['task:$taskId'] ??= {}).add(source.identityDigest);
    (_pendingHistory['conversation:$conversation'] ??= {}).add(
      source.identityDigest,
    );
    return database.write((db) {
      _taint(
        db,
        'auth1b:task:$taskId',
        source,
        extra: {'taskId': taskId, 'conversationId': conversation},
      );
      _taint(db, 'auth1b:conversation:$conversation', source);
      markSourceExternalInTransaction(db, source);
    });
  }

  Future<void> markSourceExternal(HostSourceFact source) {
    _deny.add('source:${source.identityDigest}');
    _pendingSources[source.identityDigest] = source;
    return database.write((db) => markSourceExternalInTransaction(db, source));
  }

  void markSourceExternalInTransaction(Database db, HostSourceFact source) {
    _owner(db);
    _deny.add('source:${source.identityDigest}');
    _pendingSources[source.identityDigest] = source;
    _taint(
      db,
      'auth1b:source:${source.identityDigest}',
      source,
      extra: {
        'moduleId': source.moduleId,
        'projectId': source.projectId,
        'objectType': source.objectType,
        'objectId': source.objectId,
        'revisionRef': source.revisionRef,
      },
    );
  }

  void _owner(Database db) {
    if (!identical(db, database.raw) || db.autocommit) {
      throw StateError('Host facts require the owner transaction');
    }
  }

  void _taint(
    Database db,
    String key,
    HostSourceFact source, {
    Map<String, Object?> extra = const {},
  }) {
    _owner(db);
    final old = _read(db, key);
    final sources = <String>{
      if (old != null) ...List<String>.from(old['sourceDigests'] as List),
      source.identityDigest,
    };
    db.execute(
      'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
      [
        key,
        jsonEncode({
          'version': 1,
          ...extra,
          'taintState': 'tainted',
          'sourceDigests': sources.toList()..sort(),
        }),
      ],
    );
  }

  HostTaskFacts readTask(String taskId) {
    final value = _read(database.raw, 'auth1b:task:$taskId');
    if (value != null &&
        value['taskId'] == taskId &&
        value['conversationId'] is String) {
      final conversation = value['conversationId'] as String;
      final history = _read(database.raw, 'auth1b:conversation:$conversation');
      return HostTaskFacts(
        taskId: taskId,
        conversationId: value['conversationId'] as String?,
        taintState:
            _deny.contains('task:$taskId') ||
                _deny.contains('conversation:$conversation') ||
                history?['taintState'] == 'tainted'
            ? HostTaintState.tainted
            : HostTaintState.values.byName(value['taintState'] as String),
        sourceDigests: {
          ...List<String>.from(value['sourceDigests'] as List),
          if (history != null)
            ...List<String>.from(history['sourceDigests'] as List),
          ...?_pendingHistory['task:$taskId'],
          ...?_pendingHistory['conversation:$conversation'],
        },
      );
    }
    return HostTaskFacts(
      taskId: taskId,
      conversationId: null,
      taintState: HostTaintState.unknown,
      sourceDigests: const [],
    );
  }

  Map<String, Object?>? _read(Database db, String key) {
    final rows = db.select('SELECT value FROM settings WHERE key=?', [key]);
    if (rows.isEmpty) return null;
    try {
      final value = Map<String, Object?>.from(
        jsonDecode(rows.single['value'] as String) as Map,
      );
      if (value['version'] != 1 ||
          !HostTaintState.values.any((s) => s.name == value['taintState']) ||
          value['sourceDigests'] is! List ||
          (value['sourceDigests'] as List).any((v) => v is! String)) {
        return null;
      }
      return value;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Called only by the host task owner, inside its create transaction.
  void initializeTaskInTransaction(
    Database db, {
    required String taskId,
    required String conversationId,
    String? previousAttemptId,
    Iterable<ObjectRef> references = const [],
    AssistantScope? scope,
  }) {
    _owner(db);
    final sources = <String>{
      ...?_pendingHistory['conversation:$conversationId'],
      if (previousAttemptId != null)
        ...?_pendingHistory['task:$previousAttemptId'],
    };
    var state =
        _deny.contains('conversation:$conversationId') ||
            (previousAttemptId != null &&
                _deny.contains('task:$previousAttemptId'))
        ? HostTaintState.tainted
        : HostTaintState.unknown;
    final history = <Map<String, Object?>?>[
      _read(db, 'auth1b:conversation:$conversationId'),
      if (previousAttemptId != null)
        _read(db, 'auth1b:task:$previousAttemptId'),
      for (final ref in references) ...[
        _read(db, 'auth1b:source:${HostSourceFact.object(ref).identityDigest}'),
        _read(
          db,
          'auth1b:source:${HostSourceFact.project(ref.moduleId, ref.nativeProjectId).identityDigest}',
        ),
      ],
    ];
    if (previousAttemptId != null) {
      final previous = readTask(previousAttemptId);
      sources.addAll(previous.sourceDigests);
      if (previous.taintState == HostTaintState.tainted) {
        state = HostTaintState.tainted;
      }
    }
    if (scope?.kind == AssistantScopeKind.global) {
      // Global may load any available source; over-taint rather than prove
      // clean from an incomplete asynchronous projection.
      for (final row in db.select(
        "SELECT key FROM settings WHERE key LIKE 'auth1b:source:%'",
      )) {
        history.add(_read(db, row['key'] as String));
      }
      if (_pendingSources.isNotEmpty) {
        state = HostTaintState.tainted;
        sources.addAll(_pendingSources.keys);
      }
    } else if (scope?.workspaceId != null) {
      for (final binding in db.select(
        'SELECT module_id,native_project_id FROM workspace_module_bindings WHERE workspace_id=?',
        [scope!.workspaceId],
      )) {
        final source = HostSourceFact.project(
          binding['module_id'] as String,
          binding['native_project_id'] as String,
        );
        history.add(_read(db, 'auth1b:source:${source.identityDigest}'));
        for (final row in db.select(
          "SELECT key FROM settings WHERE key LIKE 'auth1b:source:%' AND json_valid(value) AND json_extract(value,'\$.moduleId')=? AND json_extract(value,'\$.projectId')=?",
          [source.moduleId, source.projectId],
        )) {
          history.add(_read(db, row['key'] as String));
        }
        for (final pending in _pendingSources.values) {
          if (pending.moduleId == source.moduleId &&
              pending.projectId == source.projectId) {
            state = HostTaintState.tainted;
            sources.add(pending.identityDigest);
          }
        }
      }
    }
    for (final facts in history) {
      if (facts == null) continue;
      sources.addAll(List<String>.from(facts['sourceDigests'] as List));
      if (facts['taintState'] == 'tainted') state = HostTaintState.tainted;
    }
    for (final ref in references) {
      for (final source in [
        HostSourceFact.object(ref),
        HostSourceFact.project(ref.moduleId, ref.nativeProjectId),
      ]) {
        if (_deny.contains('source:${source.identityDigest}')) {
          state = HostTaintState.tainted;
          sources.add(source.identityDigest);
        }
      }
    }
    db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
      'auth1b:task:$taskId',
      jsonEncode({
        'version': 1,
        'taskId': taskId,
        'conversationId': conversationId,
        'taintState': state.name,
        'sourceDigests': sources.toList()..sort(),
      }),
    ]);
    if (state == HostTaintState.tainted) {
      db.execute(
        'INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [
          'auth1b:conversation:$conversationId',
          jsonEncode({
            'version': 1,
            'taintState': 'tainted',
            'sourceDigests': sources.toList()..sort(),
          }),
        ],
      );
    }
  }
}
