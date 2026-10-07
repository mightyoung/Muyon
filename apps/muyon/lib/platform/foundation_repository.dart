import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'task_records.dart';
import 'tool_registry.dart';

class AssistantConversation {
  AssistantConversation(this.id, this.title, this.scope, this.createdAt);
  final String id, title;
  final AssistantScope scope;
  final DateTime createdAt;
}

class AssistantMessage {
  AssistantMessage(
    this.id,
    this.conversationId,
    this.role,
    this.content,
    this.createdAt,
    this.references,
  );
  final String id, conversationId, role, content;
  final DateTime createdAt;
  final List<ObjectRef> references;
}

class PersonalMemory {
  PersonalMemory(
    this.id,
    this.content,
    this.source,
    this.updatedAt,
    this.expiresAt,
    this.scope,
    this.sourceRef,
    this.verified,
    this.revision, {
    DateTime? createdAt,
    this.disabled = false,
    this.kind = 'fact',
    this.inference = false,
    List<Map<String, Object?>> lineage = const [],
  }) : createdAt = createdAt ?? updatedAt,
       lineage = List.unmodifiable(lineage);
  final String id, content, source;
  final DateTime createdAt, updatedAt;
  final DateTime? expiresAt;
  final AssistantScope scope;
  final ObjectRef? sourceRef;
  final bool verified;
  final int revision;
  final bool disabled, inference;
  final String kind;
  final List<Map<String, Object?>> lineage;
  bool get isExpired =>
      expiresAt != null && !DateTime.now().toUtc().isBefore(expiresAt!);

  Map<String, Object?> toJson() => {
    'id': id,
    'content': content,
    'source': source,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
    'scope': scope.toJson(),
    'sourceRef': sourceRef?.toJson(),
    'verified': verified,
    'revision': revision,
    'disabled': disabled,
    'kind': kind,
    'inference': inference,
    'lineage': lineage,
  };
}

class ExperienceEntry {
  ExperienceEntry({
    required this.id,
    required this.content,
    required this.source,
    required this.scope,
    required this.status,
    required this.evidence,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, content, source, status;
  final AssistantScope scope;
  final List<Map<String, Object?>> evidence;
  final int revision;
  final DateTime createdAt, updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'content': content,
    'source': source,
    'scope': scope.toJson(),
    'status': status,
    'evidence': evidence,
    'revision': revision,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class FoundationNotification {
  FoundationNotification(
    this.id,
    this.title,
    this.body,
    this.taskId,
    this.read,
    this.createdAt,
  );
  final String id, title, body;
  final String? taskId;
  final bool read;
  final DateTime createdAt;
}

enum PersonalTaskState {
  queued,
  waitingConfirmation,
  running,
  succeeded,
  failed,
  cancelled,
  paused,
  interrupted,
}

class PersonalTask {
  PersonalTask(
    Map<String, Object?> payload, {
    this.pendingEvents = const [],
    this.keepStage = false,
  }) : payload = freezeJsonMap(payload);
  final Map<String, Object?> payload;

  /// Events that go into the same transaction as the write of this task
  /// (`createTask` / `updateTask`). They are not part of the payload and are
  /// not copied by [copy]: only [withEvents] sets them.
  final List<TaskEventDraft> pendingEvents;

  /// For `updateTask`: keep the stage that is stored (a cancel may have
  /// changed it while the writer was working) instead of this task's.
  final bool keepStage;

  PersonalTask withEvents(
    List<TaskEventDraft> events, {
    bool keepStage = false,
  }) => PersonalTask(
    payload,
    pendingEvents: List.unmodifiable(events),
    keepStage: keepStage,
  );
  String get id => payload['executionId'] as String;
  String get conversationId => payload['conversationId'] as String;
  String get prompt => payload['prompt'] as String;
  PersonalTaskState get state =>
      PersonalTaskState.values.byName(payload['state'] as String);
  String get stage => payload['stage'] as String;
  String? get error => payload['error'] as String?;
  String? get waitingFor => payload['waitingFor'] as String?;
  String? get waitReason => waitingFor;
  String get deviceId => executionDeviceId;
  String? get summary => payload['summary'] as String?;
  List<ObjectRef> get objectRefs => [
    for (final r in payload['references'] as List? ?? const [])
      objectRefFromJson(Map<String, Object?>.from(r as Map)),
  ];
  String get executionDeviceId => payload['executionDeviceId'] as String;
  String? get profileId => (payload['profile'] as Map?)?['id'] as String?;
  String? get previousAttemptId => payload['previousAttemptId'] as String?;
  AssistantScope get scope => AssistantScope.fromJson(
    Map<String, Object?>.from(payload['scope'] as Map),
  );
  DateTime get updatedAt => DateTime.parse(payload['updatedAt'] as String);
  bool get terminal => [
    PersonalTaskState.succeeded,
    PersonalTaskState.failed,
    PersonalTaskState.cancelled,
    PersonalTaskState.paused,
    PersonalTaskState.interrupted,
  ].contains(state);
  PersonalTask copy(Map<String, Object?> changes) => PersonalTask({
    ...payload,
    ...changes,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  });
}

/// One host database: conversations add context, execution_records remain the
/// sole execution authority. No parallel workspace/settings/device tables.
class FoundationRepository extends ChangeNotifier {
  FoundationRepository(this.database);
  final ManagedDatabase database;
  void refresh() => notifyListeners();
  static final migration = ModuleMigration(
    version: 2,
    id: 'foundation-v2',
    definitionDigest: 'foundation-v2',
    migrate: (db) {
      db.execute('''
CREATE TABLE conversations(id TEXT PRIMARY KEY,title TEXT NOT NULL,scope_json TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
CREATE TABLE messages(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL REFERENCES conversations(id),role TEXT NOT NULL,content TEXT NOT NULL,references_json TEXT NOT NULL,created_at TEXT NOT NULL);
CREATE INDEX messages_conversation ON messages(conversation_id,created_at);
CREATE TABLE memories(id TEXT PRIMARY KEY,content TEXT NOT NULL,source TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,expires_at TEXT,scope_json TEXT NOT NULL,source_ref TEXT,verified INTEGER NOT NULL,revision INTEGER NOT NULL);
CREATE TABLE notifications(id TEXT PRIMARY KEY,title TEXT NOT NULL,body TEXT NOT NULL,task_id TEXT,read INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL);
''');
      installToolRegistrySchema(db);
    },
  );
  String _id() => const Uuid().v4();
  String _now() => DateTime.now().toUtc().toIso8601String();
  List<AssistantConversation> conversations() => [
    for (final r in database.raw.select(
      'SELECT * FROM conversations ORDER BY updated_at DESC,rowid DESC',
    ))
      AssistantConversation(
        r['id'] as String,
        r['title'] as String,
        AssistantScope.fromJson(
          Map<String, Object?>.from(
            jsonDecode(r['scope_json'] as String) as Map,
          ),
        ),
        DateTime.parse(r['created_at'] as String),
      ),
  ];
  AssistantConversation? conversation(String id) {
    for (final c in conversations()) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<AssistantConversation> createConversation({
    String title = '主对话',
    AssistantScope scope = const AssistantScope.global(),
  }) async {
    if (title.trim().isEmpty) {
      throw ArgumentError('Conversation title required');
    }
    final id = _id(), now = _now();
    await database.write(
      (db) => db.execute('INSERT INTO conversations VALUES(?,?,?,?,?)', [
        id,
        title.trim(),
        jsonEncode(scope.toJson()),
        now,
        now,
      ]),
    );
    notifyListeners();
    return conversation(id)!;
  }

  List<AssistantMessage> messages(String conversationId) => [
    for (final r in database.raw.select(
      'SELECT * FROM messages WHERE conversation_id=? ORDER BY created_at,rowid',
      [conversationId],
    ))
      AssistantMessage(
        r['id'] as String,
        conversationId,
        r['role'] as String,
        r['content'] as String,
        DateTime.parse(r['created_at'] as String),
        List.unmodifiable([
          for (final ref in jsonDecode(r['references_json'] as String) as List)
            objectRefFromJson(Map<String, Object?>.from(ref as Map)),
        ]),
      ),
  ];
  Future<void> appendMessage(
    String conversationId,
    String role,
    String content, {
    List<ObjectRef> references = const [],
  }) async {
    if (!['user', 'assistant', 'tool', 'system'].contains(role) ||
        content.trim().isEmpty) {
      throw ArgumentError('Invalid message');
    }
    await database.write((db) {
      db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?)', [
        _id(),
        conversationId,
        role,
        content,
        jsonEncode(references.map((e) => e.toJson()).toList()),
        _now(),
      ]);
      db.execute('UPDATE conversations SET updated_at=? WHERE id=?', [
        _now(),
        conversationId,
      ]);
    });
    notifyListeners();
  }

  static const memoryKinds = {'source', 'fact', 'topic', 'summary'};

  List<PersonalMemory> memories({
    bool includeExpired = false,
    bool includeDisabled = false,
  }) => [
    for (final memory in _allMemories())
      if ((includeExpired || !memory.isExpired) &&
          (includeDisabled || !memory.disabled))
        memory,
  ];

  /// Enabled, unexpired, verified memories visible to [scope].
  List<PersonalMemory> memoriesFor(AssistantScope scope) => [
    for (final memory in memories())
      if (memory.verified && _visible(memory.scope, scope)) memory,
  ];

  List<PersonalMemory> _allMemories() => [
    for (final row in database.raw.select(
      'SELECT * FROM memories ORDER BY updated_at DESC',
    ))
      _memory(row),
  ];

  PersonalMemory _memory(Row row) => PersonalMemory(
    row['id'] as String,
    row['content'] as String,
    row['source'] as String,
    DateTime.parse(row['updated_at'] as String),
    row['expires_at'] == null
        ? null
        : DateTime.parse(row['expires_at'] as String),
    AssistantScope.fromJson(
      Map<String, Object?>.from(jsonDecode(row['scope_json'] as String) as Map),
    ),
    row['source_ref'] == null
        ? null
        : objectRefFromJson(
            Map<String, Object?>.from(
              jsonDecode(row['source_ref'] as String) as Map,
            ),
          ),
    row['verified'] == 1,
    row['revision'] as int,
    createdAt: DateTime.parse(row['created_at'] as String),
    disabled: (row['disabled'] as int? ?? 0) == 1,
    kind: (row['kind'] as String?) ?? 'fact',
    inference: (row['inference'] as int? ?? 0) == 1,
    lineage: [
      for (final item
          in jsonDecode(row['lineage_json'] as String? ?? '[]') as List)
        Map<String, Object?>.from(item as Map),
    ],
  );

  bool _visible(AssistantScope item, AssistantScope request) =>
      item.kind == AssistantScopeKind.global ||
      jsonEncode(item.toJson()) == jsonEncode(request.toJson());

  static String contentHash(String content) => sha256
      .convert(utf8.encode(content.trim().replaceAll(RegExp(r'\s+'), ' ')))
      .toString();

  Future<String> saveMemory({
    String? id,
    required String content,
    required String source,
    DateTime? expiresAt,
    AssistantScope scope = const AssistantScope.global(),
    ObjectRef? sourceRef,
    bool verified = true,
    bool disabled = false,
    String kind = 'fact',
    bool inference = false,
    List<Map<String, Object?>> lineage = const [],
  }) async {
    if (content.trim().isEmpty || source.trim().isEmpty) {
      throw ArgumentError('Memory requires content and source');
    }
    if (!memoryKinds.contains(kind)) throw ArgumentError('Unknown memory kind');
    final key = id ?? _id(), now = _now();
    await database.write((db) {
      final blocked = db.select(
        "SELECT reason FROM memory_tombstones WHERE id=? AND kind='memory' ORDER BY rowid DESC LIMIT 1",
        [key],
      );
      if (blocked.isNotEmpty && blocked.first['reason'] == 'deleted') {
        throw StateError('已删除的记忆不会被重新写入');
      }
      db.execute(
        'INSERT INTO memories(id,content,source,created_at,updated_at,expires_at,scope_json,source_ref,verified,revision,disabled,kind,inference,lineage_json) VALUES(?,?,?,?,?,?,?,?,?,1,?,?,?,?) '
        'ON CONFLICT(id) DO UPDATE SET content=excluded.content,source=excluded.source,updated_at=excluded.updated_at,expires_at=excluded.expires_at,scope_json=excluded.scope_json,source_ref=excluded.source_ref,verified=excluded.verified,revision=memories.revision+1,disabled=excluded.disabled,kind=excluded.kind,inference=excluded.inference,lineage_json=excluded.lineage_json',
        [
          key,
          content.trim(),
          source.trim(),
          now,
          now,
          expiresAt?.toUtc().toIso8601String(),
          jsonEncode(scope.toJson()),
          sourceRef == null ? null : jsonEncode(sourceRef.toJson()),
          verified ? 1 : 0,
          disabled ? 1 : 0,
          kind,
          inference ? 1 : 0,
          jsonEncode(lineage),
        ],
      );
    });
    notifyListeners();
    return key;
  }

  Future<void> setMemoryDisabled(String id, bool disabled) async {
    await database.write((db) {
      final rows = db.select('SELECT * FROM memories WHERE id=?', [id]);
      if (rows.isEmpty) throw StateError('记忆不存在');
      final memory = _memory(rows.single);
      db.execute(
        'UPDATE memories SET disabled=?, revision=revision+1, updated_at=? WHERE id=?',
        [disabled ? 1 : 0, _now(), id],
      );
      _tombstone(
        db,
        id: id,
        kind: 'memory',
        revision: memory.revision + 1,
        reason: disabled ? 'disabled' : 'enabled',
        scopeJson: jsonEncode(memory.scope.toJson()),
        contentHash: contentHash(memory.content),
      );
    });
    notifyListeners();
  }

  Future<void> narrowMemoryScope(String id, AssistantScope scope) async {
    await database.write((db) {
      final rows = db.select('SELECT * FROM memories WHERE id=?', [id]);
      if (rows.isEmpty) throw StateError('记忆不存在');
      final memory = _memory(rows.single);
      if (!_narrows(memory.scope, scope)) {
        throw ArgumentError('新范围没有变窄');
      }
      final now = _now();
      final encoded = jsonEncode(scope.toJson());
      db.execute(
        'UPDATE memories SET scope_json=?, revision=revision+1, updated_at=? WHERE id=?',
        [encoded, now, id],
      );
      for (final row in db.select('SELECT id, lineage_json FROM memories')) {
        if (row['id'] == id || !_cites(row['lineage_json'] as String, id)) {
          continue;
        }
        db.execute(
          'UPDATE memories SET scope_json=?, revision=revision+1, updated_at=? WHERE id=?',
          [encoded, now, row['id']],
        );
      }
      for (final row in db.select(
        'SELECT id, evidence_json FROM experiences',
      )) {
        if (!_cites(row['evidence_json'] as String, id)) continue;
        db.execute(
          'UPDATE experiences SET scope_json=?, revision=revision+1, updated_at=? WHERE id=?',
          [encoded, now, row['id']],
        );
      }
    });
    notifyListeners();
  }

  Future<void> deleteMemory(String id) async {
    await database.write((db) => _deleteMemoryTree(db, id));
    notifyListeners();
  }

  void _deleteMemoryTree(Database db, String id) {
    final pending = <String>[id];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!seen.add(current)) continue;
      final rows = db.select('SELECT * FROM memories WHERE id=?', [current]);
      if (rows.isNotEmpty) {
        final memory = _memory(rows.single);
        _tombstone(
          db,
          id: current,
          kind: 'memory',
          revision: memory.revision,
          reason: 'deleted',
          scopeJson: jsonEncode(memory.scope.toJson()),
          contentHash: contentHash(memory.content),
        );
        db.execute('DELETE FROM memories WHERE id=?', [current]);
      }
      for (final row in db.select('SELECT id, lineage_json FROM memories')) {
        if (_cites(row['lineage_json'] as String, current)) {
          pending.add(row['id'] as String);
        }
      }
      for (final row in db.select('SELECT * FROM experiences')) {
        if (!_cites(row['evidence_json'] as String, current)) continue;
        _tombstone(
          db,
          id: row['id'] as String,
          kind: 'experience',
          revision: row['revision'] as int,
          reason: 'deleted',
          scopeJson: row['scope_json'] as String,
          contentHash: contentHash(row['content'] as String),
        );
        db.execute(
          "UPDATE experiences SET status='retired', revision=revision+1, updated_at=? WHERE id=?",
          [_now(), row['id']],
        );
      }
    }
  }

  bool deletedContent(String content) {
    final hash = contentHash(content);
    return database.raw.select(
      "SELECT 1 FROM memory_tombstones WHERE reason='deleted' AND content_hash=? LIMIT 1",
      [hash],
    ).isNotEmpty;
  }

  List<ExperienceEntry> experiences({
    bool includeUnverified = false,
    bool includeRetired = false,
  }) => [
    for (final entry in _allExperiences())
      if ((includeRetired || entry.status != 'retired') &&
          (includeUnverified || entry.status == 'verified'))
        entry,
  ];

  List<ExperienceEntry> experiencesFor(AssistantScope scope) => [
    for (final entry in experiences())
      if (_visible(entry.scope, scope)) entry,
  ];

  ExperienceEntry? experience(String id) {
    for (final entry in _allExperiences()) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  List<ExperienceEntry> _allExperiences() => [
    for (final row in database.raw.select(
      'SELECT * FROM experiences ORDER BY updated_at DESC',
    ))
      _experience(row),
  ];

  ExperienceEntry _experience(Row row) => ExperienceEntry(
    id: row['id'] as String,
    content: row['content'] as String,
    source: row['source'] as String,
    scope: AssistantScope.fromJson(
      Map<String, Object?>.from(jsonDecode(row['scope_json'] as String) as Map),
    ),
    status: row['status'] as String,
    evidence: [
      for (final item in jsonDecode(row['evidence_json'] as String) as List)
        Map<String, Object?>.from(item as Map),
    ],
    revision: row['revision'] as int,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );

  Future<String> saveExperience({
    String? id,
    required String content,
    required String source,
    AssistantScope scope = const AssistantScope.global(),
    required List<Map<String, Object?>> evidence,
  }) async {
    if (content.trim().isEmpty || source.trim().isEmpty) {
      throw ArgumentError('Experience requires content and source');
    }
    if (deletedContent(content)) {
      throw StateError('已删除的内容不会被重新写入');
    }
    final key = id ?? _id(), now = _now();
    await database.write((db) {
      final existing = db.select('SELECT status FROM experiences WHERE id=?', [
        key,
      ]);
      if (existing.isNotEmpty) throw StateError('经验已存在');
      db.execute(
        'INSERT INTO experiences(id,content,source,scope_json,status,evidence_json,revision,created_at,updated_at) VALUES(?,?,?,?,?,?,1,?,?)',
        [
          key,
          content.trim(),
          source.trim(),
          jsonEncode(scope.toJson()),
          'candidate',
          jsonEncode(evidence),
          now,
          now,
        ],
      );
    });
    notifyListeners();
    return key;
  }

  Future<void> verifyExperience(String id) async {
    await database.write((db) {
      final rows = db.select('SELECT status FROM experiences WHERE id=?', [id]);
      if (rows.isEmpty || rows.single['status'] != 'candidate') {
        throw StateError('只有候选经验可以确认');
      }
      db.execute(
        "UPDATE experiences SET status='verified', revision=revision+1, updated_at=? WHERE id=?",
        [_now(), id],
      );
    });
    notifyListeners();
  }

  Future<void> retireExperience(String id) async {
    await database.write((db) {
      final rows = db.select('SELECT * FROM experiences WHERE id=?', [id]);
      if (rows.isEmpty) throw StateError('经验不存在');
      final row = rows.single;
      if (row['status'] == 'retired') return;
      _tombstone(
        db,
        id: id,
        kind: 'experience',
        revision: (row['revision'] as int) + 1,
        reason: 'retired',
        scopeJson: row['scope_json'] as String,
        contentHash: contentHash(row['content'] as String),
      );
      db.execute(
        "UPDATE experiences SET status='retired', revision=revision+1, updated_at=? WHERE id=?",
        [_now(), id],
      );
    });
    notifyListeners();
  }

  /// Replaces memories, experiences and tombstones. Used to revert one Dream run.
  Future<void> restoreOrganizationSnapshot(
    Map<String, Object?> snapshot,
  ) async {
    final memories = (snapshot['memories'] as List).cast<Map>();
    final experienceRows = (snapshot['experiences'] as List).cast<Map>();
    final tombstones = (snapshot['tombstones'] as List).cast<Map>();
    await database.write((db) {
      db.execute('DELETE FROM memories');
      db.execute('DELETE FROM experiences');
      db.execute('DELETE FROM memory_tombstones');
      for (final raw in memories) {
        final memory = Map<String, Object?>.from(raw);
        db.execute(
          'INSERT INTO memories(id,content,source,created_at,updated_at,expires_at,scope_json,source_ref,verified,revision,disabled,kind,inference,lineage_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            memory['id'],
            memory['content'],
            memory['source'],
            memory['createdAt'],
            memory['updatedAt'],
            memory['expiresAt'],
            jsonEncode(memory['scope']),
            memory['sourceRef'] == null
                ? null
                : jsonEncode(memory['sourceRef']),
            memory['verified'] == true ? 1 : 0,
            memory['revision'],
            memory['disabled'] == true ? 1 : 0,
            memory['kind'],
            memory['inference'] == true ? 1 : 0,
            jsonEncode(memory['lineage']),
          ],
        );
      }
      for (final raw in experienceRows) {
        final entry = Map<String, Object?>.from(raw);
        db.execute(
          'INSERT INTO experiences(id,content,source,scope_json,status,evidence_json,revision,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',
          [
            entry['id'],
            entry['content'],
            entry['source'],
            jsonEncode(entry['scope']),
            entry['status'],
            jsonEncode(entry['evidence']),
            entry['revision'],
            entry['createdAt'],
            entry['updatedAt'],
          ],
        );
      }
      for (final raw in tombstones) {
        final tombstone = Map<String, Object?>.from(raw);
        db.execute(
          'INSERT INTO memory_tombstones(id,kind,revision,reason,scope_json,content_hash,created_at) VALUES(?,?,?,?,?,?,?)',
          [
            tombstone['id'],
            tombstone['kind'],
            tombstone['revision'],
            tombstone['reason'],
            tombstone['scopeJson'],
            tombstone['contentHash'],
            tombstone['createdAt'],
          ],
        );
      }
    });
    notifyListeners();
  }

  Map<String, Object?> organizationSnapshot() => {
    'memories': [for (final memory in _allMemories()) memory.toJson()],
    'experiences': [for (final entry in _allExperiences()) entry.toJson()],
    'tombstones': [
      for (final row in database.raw.select(
        'SELECT * FROM memory_tombstones ORDER BY rowid',
      ))
        {
          'id': row['id'],
          'kind': row['kind'],
          'revision': row['revision'],
          'reason': row['reason'],
          'scopeJson': row['scope_json'],
          'contentHash': row['content_hash'],
          'createdAt': row['created_at'],
        },
    ],
  };

  void _tombstone(
    Database db, {
    required String id,
    required String kind,
    required int revision,
    required String reason,
    required String? scopeJson,
    required String contentHash,
  }) {
    db.execute(
      'INSERT INTO memory_tombstones(id,kind,revision,reason,scope_json,content_hash,created_at) VALUES(?,?,?,?,?,?,?)',
      [id, kind, revision, reason, scopeJson, contentHash, _now()],
    );
  }

  bool _cites(String encoded, String id) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List) return false;
    for (final item in decoded) {
      if (item is Map && item['id'] == id) return true;
    }
    return false;
  }

  bool _narrows(AssistantScope from, AssistantScope to) {
    if (jsonEncode(from.toJson()) == jsonEncode(to.toJson())) return false;
    const rank = {
      AssistantScopeKind.global: 2,
      AssistantScopeKind.workspace: 1,
      AssistantScopeKind.selectedObjects: 0,
    };
    if (rank[to.kind]! > rank[from.kind]!) return false;
    if (from.kind == AssistantScopeKind.global) return to.kind != from.kind;
    if (from.kind == AssistantScopeKind.workspace &&
        to.kind == AssistantScopeKind.selectedObjects) {
      return to.workspaceId == from.workspaceId;
    }
    if (from.kind == AssistantScopeKind.selectedObjects &&
        to.kind == AssistantScopeKind.selectedObjects) {
      final next = to.objects.map(_identity).toSet();
      final previous = from.objects.map(_identity).toSet();
      return next.isNotEmpty &&
          next.length < previous.length &&
          previous.containsAll(next) &&
          to.workspaceId == from.workspaceId;
    }
    return false;
  }

  String _identity(ObjectRef ref) =>
      '${ref.moduleId}\u0000${ref.objectType}\u0000${ref.nativeProjectId}\u0000${ref.objectId}';

  List<FoundationNotification> notifications({bool unreadOnly = false}) => [
    for (final r in database.raw.select(
      'SELECT * FROM notifications ${unreadOnly ? 'WHERE read=0' : ''} ORDER BY created_at DESC,rowid DESC',
    ))
      FoundationNotification(
        r['id'] as String,
        r['title'] as String,
        r['body'] as String,
        r['task_id'] as String?,
        r['read'] == 1,
        DateTime.parse(r['created_at'] as String),
      ),
  ];
  Future<void> notify({
    required String title,
    required String body,
    String? taskId,
  }) async {
    await database.write(
      (db) => db.execute('INSERT INTO notifications VALUES(?,?,?,?,0,?)', [
        _id(),
        title,
        body,
        taskId,
        _now(),
      ]),
    );
    notifyListeners();
  }

  Future<void> markNotificationRead(String id) async {
    await database.write(
      (db) => db.execute('UPDATE notifications SET read=1 WHERE id=?', [id]),
    );
    notifyListeners();
  }

  List<PersonalTask> tasks({String? conversationId}) => [
    for (final r in database.raw.select(
      "SELECT payload FROM execution_records WHERE json_extract(payload,'\$.kind')='personal' ORDER BY rowid DESC",
    ))
      if (conversationId == null ||
          (jsonDecode(r['payload'] as String) as Map)['conversationId'] ==
              conversationId)
        PersonalTask(
          Map<String, Object?>.from(jsonDecode(r['payload'] as String) as Map),
        ),
  ];
  PersonalTask? task(String id) {
    final r = database.raw.select(
      "SELECT payload FROM execution_records WHERE id=? AND json_extract(payload,'\$.kind')='personal'",
      [id],
    );
    return r.isEmpty
        ? null
        : PersonalTask(
            Map<String, Object?>.from(
              jsonDecode(r.first['payload'] as String) as Map,
            ),
          );
  }

  /// Stores a new task; its [PersonalTask.pendingEvents] go into the same
  /// transaction.
  Future<void> createTask(PersonalTask task) async {
    if (task.payload['kind'] != 'personal' ||
        task.state != PersonalTaskState.queued) {
      throw ArgumentError('Invalid new task');
    }
    await database.write((db) {
      db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
        task.id,
        task.state.name,
        jsonEncode(task.payload),
      ]);
      TaskRecords.syncTask(db, task.payload, task.state.name);
      TaskRecords.append(db, task.id, task.pendingEvents, _now());
    });
    notifyListeners();
  }

  /// Writes the task's new state. The state, the flat `tasks` row, the object
  /// links and every one of `next.pendingEvents` are one transaction: they all
  /// land or none does, so the timeline never disagrees with the state.
  Future<bool> updateTask(
    PersonalTask next, {
    Set<PersonalTaskState>? expected,
    bool Function()? canCommit,
    String? assistantAnswer,
    List<ObjectRef> references = const [],
  }) async {
    final result = await database.write((db) {
      final current = task(next.id);
      if (current == null ||
          current.terminal ||
          (expected != null && !expected.contains(current.state)) ||
          (canCommit != null && !canCommit())) {
        return false;
      }
      if (current.conversationId != next.conversationId ||
          jsonEncode(current.scope.toJson()) !=
              jsonEncode(next.scope.toJson())) {
        throw StateError('Task scope changed');
      }
      // Events of the old payload list are history: a snapshot taken before
      // this write cannot drop them. New events never go there.
      final legacy = current.payload['events'];
      final payload = {
        ...next.payload,
        if (next.keepStage) 'stage': current.stage,
        'events': ?legacy,
      };
      db.execute('UPDATE execution_records SET state=?,payload=? WHERE id=?', [
        next.state.name,
        jsonEncode(payload),
        next.id,
      ]);
      TaskRecords.syncTask(db, payload, next.state.name);
      TaskRecords.link(
        db,
        next.id,
        TaskRecords.toolResultObjects(payload),
        TaskObjectRole.toolResult,
      );
      TaskRecords.append(db, next.id, next.pendingEvents, _now());
      if (assistantAnswer != null) {
        if (next.state != PersonalTaskState.succeeded) {
          throw StateError('Answer requires success');
        }
        db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?)', [
          _id(),
          next.conversationId,
          'assistant',
          assistantAnswer,
          jsonEncode(references.map((e) => e.toJson()).toList()),
          _now(),
        ]);
        db.execute('UPDATE conversations SET updated_at=? WHERE id=?', [
          _now(),
          next.conversationId,
        ]);
        TaskRecords.link(db, next.id, references, TaskObjectRole.answer);
      }
      return true;
    });
    if (result) notifyListeners();
    return result;
  }

  /// Adds one event to the task's timeline in its own write; `seq` increases
  /// by one per task. Allowed on a finished task too (a closing `done` /
  /// `error` event) and it changes nothing else. [event] has `type` and
  /// optionally `step` and `data`.
  Future<void> appendTaskEvent(
    String taskId,
    Map<String, Object?> event,
  ) async {
    final added = await database.write((db) {
      if (db.select('SELECT 1 FROM execution_records WHERE id=?', [
        taskId,
      ]).isEmpty) {
        return false;
      }
      TaskRecords.append(db, taskId, [
        TaskEventDraft(
          event['type'] as String,
          step: event['step'] as int?,
          data: Map<String, Object?>.from(event['data'] as Map? ?? const {}),
        ),
      ], _now());
      return true;
    });
    if (added) notifyListeners();
  }

  /// The task's timeline in order; tasks from before the event table are
  /// read from their payload's `events`.
  List<TaskEvent> taskEvents(String taskId) =>
      TaskRecords.events(database.raw, taskId);

  /// The objects the task's receipts and answer refer to.
  List<TaskObjectLink> taskObjects(String taskId) =>
      TaskRecords.linksOfTask(database.raw, taskId);

  /// Tasks that touched [ref], newest first (read only; the object page that
  /// shows them is UI-5).
  List<PersonalTask> tasksForObject(ObjectRef ref) {
    final seen = <String>{};
    final found = <PersonalTask>[];
    for (final link in TaskRecords.linksOfObject(database.raw, ref).reversed) {
      if (!seen.add(link.taskId)) continue;
      final t = task(link.taskId);
      if (t != null) found.add(t);
    }
    return found;
  }

  Future<void> recoverInterrupted() async {
    for (final task in tasks()) {
      if ([
        PersonalTaskState.queued,
        PersonalTaskState.running,
      ].contains(task.state)) {
        await updateTask(
          task.copy({
            'state': PersonalTaskState.interrupted.name,
            'stage': 'interrupted',
            'error': '应用中断；继续将创建新尝试并重新确认',
          }),
        );
      }
    }
  }
}
