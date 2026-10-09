import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import 'foundation_repository.dart';

/// Host-owned relationship. Never constructed from model parameters or an
/// authorization preview. The existing messages/tasks remain the authority.
class SubconversationRef {
  SubconversationRef(Map<String, Object?> value)
    : value = freezeJsonMap(value) {
    for (final key in [
      'parentTaskId',
      'parentConversationId',
      'childConversationId',
      'creationToken',
      'scopeKey',
    ]) {
      if (value[key] is! String || (value[key] as String).isEmpty) {
        throw FormatException('Invalid child relation: $key');
      }
    }
    if (value['readonly'] != true) {
      throw const FormatException('Invalid child readonly relation');
    }
  }
  final Map<String, Object?> value;
  String get parentTaskId => value['parentTaskId'] as String;
  String get parentConversationId => value['parentConversationId'] as String;
  String get childConversationId => value['childConversationId'] as String;
  String get creationToken => value['creationToken'] as String;
  String get scopeKey => value['scopeKey'] as String;
}

class SubconversationWorkspace {
  const SubconversationWorkspace({
    this.draftText = '',
    this.scrollOffset = 0,
    this.selectedProfileId = '',
    this.openState = true,
    this.revision = 0,
  });
  final String draftText, selectedProfileId;
  final double scrollOffset;
  final bool openState;
  final int revision;
  Map<String, Object?> toJson() => {
    'draftText': draftText,
    'scrollOffset': scrollOffset,
    'selectedProfileId': selectedProfileId,
    'openState': openState,
    'revision': revision,
  };
  factory SubconversationWorkspace.fromJson(Map<String, Object?> v) {
    final value = SubconversationWorkspace(
      draftText: v['draftText'] as String,
      scrollOffset: (v['scrollOffset'] as num).toDouble(),
      selectedProfileId: v['selectedProfileId'] as String,
      openState: v['openState'] as bool,
      revision: v['revision'] as int,
    );
    if (!value.scrollOffset.isFinite ||
        value.scrollOffset < 0 ||
        value.revision < 0) {
      throw const FormatException('Invalid child UI state');
    }
    return value;
  }
}

/// Immutable explicit read, including exact message/task/event boundaries and
/// captured ObjectRef revisions. This is display-only, never a loaded-input
/// proof, approval, verified goal receipt or automatic parent model context.
class SubconversationSummary {
  SubconversationSummary(Map<String, Object?> value)
    : value = freezeJsonMap(value) {
    for (final key in [
      'readId',
      'readAt',
      'digest',
      'summary',
      'childConversationId',
      'parentTaskId',
    ]) {
      if (value[key] is! String) {
        throw FormatException('Invalid child read: $key');
      }
    }
    if (value['readonly'] != true ||
        value['authority'] != 'display_only' ||
        value['boundary'] is! Map) {
      throw const FormatException('Invalid child read authority');
    }
  }
  final Map<String, Object?> value;
  String get readId => value['readId'] as String;
  String get readAt => value['readAt'] as String;
  String get digest => value['digest'] as String;
  String get summary => value['summary'] as String;
}

class AssistantSubconversations {
  AssistantSubconversations(this.repository);
  final FoundationRepository repository;
  static String _relation(String id) => 'subconversation:$id';
  static String _workspace(String id) => 'subconversation-ui:$id';
  Map<String, Object?>? _get(String key) {
    final rows = repository.database.raw.select(
      'SELECT value FROM settings WHERE key=?',
      [key],
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(
      jsonDecode(rows.single['value'] as String) as Map,
    );
  }

  SubconversationRef? relation(String conversationId) {
    final value = _get(_relation(conversationId));
    if (value == null) {
      final index = repository.database.raw.select(
        "SELECT 1 FROM settings WHERE substr(key,1,21)='subconversation-open:' AND json_valid(value) AND json_extract(value,'\$.childConversationId')=?",
        [conversationId],
      );
      if (index.isNotEmpty) {
        throw StateError('missing_subconversation_relation');
      }
      return null;
    }
    if (value['childConversationId'] != conversationId ||
        value['readonly'] != true) {
      throw StateError('invalid_subconversation_relation');
    }
    return SubconversationRef(value);
  }

  bool isChild(String id) => repository.database.raw.select(
    "SELECT 1 FROM settings WHERE key=? OR (substr(key,1,21)='subconversation-open:' AND json_valid(value) AND json_extract(value,'\$.childConversationId')=?) LIMIT 1",
    [_relation(id), id],
  ).isNotEmpty;

  /// Rechecked at creation, dispatch and immediately before model/tool use.
  /// A changed parent scope cannot turn an old child into a writable global chat.
  bool validateConversation(String id) {
    final ref = relation(id);
    if (ref == null) return false;
    final task = repository.task(ref.parentTaskId);
    final parent = repository.conversation(ref.parentConversationId);
    final child = repository.conversation(id);
    if (task == null ||
        parent == null ||
        child == null ||
        task.conversationId != parent.id ||
        isChild(parent.id) ||
        jsonEncode(task.scope.toJson()) != ref.scopeKey ||
        jsonEncode(parent.scope.toJson()) != ref.scopeKey ||
        jsonEncode(child.scope.toJson()) != ref.scopeKey) {
      throw StateError('stale_subconversation_scope');
    }
    return true;
  }

  void checkTool(String conversationId, ToolEffect? effect) {
    if (validateConversation(conversationId) && effect != ToolEffect.read) {
      throw StateError('subconversation_read_only');
    }
  }

  void _checkRef(SubconversationRef ref) {
    final actual = relation(ref.childConversationId);
    if (actual == null || jsonEncode(actual.value) != jsonEncode(ref.value)) {
      throw StateError('invalid_subconversation_reference');
    }
    validateConversation(ref.childConversationId);
  }

  Future<SubconversationRef> openSubconversation(
    String parentTaskId,
    String goal, {
    String? creationToken,
  }) async {
    if (goal.trim().isEmpty) throw ArgumentError('Child goal required');
    final token = creationToken ?? const Uuid().v4();
    if (token.isEmpty) throw ArgumentError('Creation token required');
    final ref = await repository.database.write((db) {
      final task = repository.task(parentTaskId);
      final parent = task == null
          ? null
          : repository.conversation(task.conversationId);
      if (task == null ||
          parent == null ||
          isChild(parent.id) ||
          jsonEncode(task.scope.toJson()) !=
              jsonEncode(parent.scope.toJson())) {
        throw StateError('invalid_subconversation_parent');
      }
      final index = 'subconversation-open:${jsonEncode([parentTaskId, token])}';
      final existing = _get(index);
      if (existing != null) {
        final old = relation(existing['childConversationId'] as String)!;
        _checkRef(old);
        return old;
      }
      final id = const Uuid().v4(),
          now = DateTime.now().toUtc().toIso8601String();
      final scopeKey = jsonEncode(parent.scope.toJson());
      final ref = SubconversationRef({
        'parentTaskId': parentTaskId,
        'parentConversationId': parent.id,
        'childConversationId': id,
        'creationToken': token,
        'scopeKey': scopeKey,
        'readonly': true,
      });
      db.execute('INSERT INTO conversations VALUES(?,?,?,?,?)', [
        id,
        goal.trim(),
        scopeKey,
        now,
        now,
      ]);
      db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
        _relation(id),
        jsonEncode(ref.value),
      ]);
      db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
        index,
        jsonEncode({'childConversationId': id}),
      ]);
      db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
        _workspace(id),
        jsonEncode({
          ...SubconversationWorkspace(draftText: goal.trim()).toJson(),
          'scopeKey': scopeKey,
        }),
      ]);
      return ref;
    });
    repository.refresh();
    return ref;
  }

  List<SubconversationRef> children(String parentTaskId) {
    final result = <SubconversationRef>[];
    for (final row in repository.database.raw.select(
      "SELECT key,value FROM settings WHERE substr(key,1,16)='subconversation:'",
    )) {
      try {
        final ref = SubconversationRef(
          Map<String, Object?>.from(jsonDecode(row['value'] as String) as Map),
        );
        if (row['key'] != _relation(ref.childConversationId)) continue;
        if (ref.parentTaskId == parentTaskId) result.add(ref);
      } catch (_) {
        /* Preserved bytes are surfaced by problems(), never treated as writable chat. */
      }
    }
    return result;
  }

  List<String> problems() {
    final result = <String>[];
    for (final row in repository.database.raw.select(
      "SELECT key,value FROM settings WHERE substr(key,1,16)='subconversation:' OR substr(key,1,21)='subconversation-read:'",
    )) {
      try {
        final key = row['key'] as String;
        if (key.startsWith('subconversation-read:')) {
          final read = SubconversationSummary(
            Map<String, Object?>.from(
              jsonDecode(row['value'] as String) as Map,
            ),
          );
          if (key !=
              'subconversation-read:${read.value["childConversationId"]}:${read.readId}') {
            throw const FormatException('Read identity mismatch');
          }
          continue;
        }
        final ref = SubconversationRef(
          Map<String, Object?>.from(jsonDecode(row['value'] as String) as Map),
        );
        if (row['key'] != _relation(ref.childConversationId)) {
          throw const FormatException('Child identity mismatch');
        }
      } catch (_) {
        result.add(row['key'] as String);
      }
    }
    return result;
  }

  /// Old UI remains readable even when the relationship is stale. Mutation and
  /// task start still fail closed. No loss of the pending text on scope change.
  SubconversationWorkspace loadWorkspace(SubconversationRef ref) {
    final value = _get(_workspace(ref.childConversationId));
    if (value == null || value['scopeKey'] != ref.scopeKey) {
      throw StateError('invalid_child_workspace');
    }
    return SubconversationWorkspace.fromJson(value);
  }

  Future<bool> saveWorkspace(
    SubconversationRef ref,
    SubconversationWorkspace value, {
    required int expectedRevision,
  }) => repository.database.write((db) {
    _checkRef(ref);
    if (value.revision != expectedRevision + 1 ||
        !value.scrollOffset.isFinite ||
        value.scrollOffset < 0) {
      return false;
    }
    final old = loadWorkspace(ref);
    if (old.revision != expectedRevision) return false;
    db.execute('UPDATE settings SET value=? WHERE key=?', [
      jsonEncode({...value.toJson(), 'scopeKey': ref.scopeKey}),
      _workspace(ref.childConversationId),
    ]);
    return true;
  });

  List<SubconversationSummary> reads(SubconversationRef ref) {
    final result = <SubconversationSummary>[];
    final prefix = 'subconversation-read:${ref.childConversationId}:';
    for (final row in repository.database.raw.select(
      'SELECT key,value FROM settings WHERE substr(key,1,?)=? ORDER BY rowid',
      [prefix.length, prefix],
    )) {
      try {
        final value = SubconversationSummary(
          Map<String, Object?>.from(jsonDecode(row['value'] as String) as Map),
        );
        if (row['key'] != '$prefix${value.readId}' ||
            value.value['parentTaskId'] != ref.parentTaskId) {
          continue;
        }
        result.add(value);
      } catch (_) {
        /* Preserved and shown by problems(). */
      }
    }
    return result;
  }

  Future<SubconversationSummary> readLatestSubconversation(
    SubconversationRef ref,
  ) async {
    final result = await repository.database.write((db) {
      _checkRef(ref);
      final messages = repository.messages(ref.childConversationId);
      final tasks = repository.tasks(conversationId: ref.childConversationId);
      final boundary = <String, Object?>{
        'messages': [
          for (final m in messages)
            {
              'id': m.id,
              'role': m.role,
              'contentDigest': sha256
                  .convert(utf8.encode(m.content))
                  .toString(),
              'references': [for (final r in m.references) r.toJson()],
            },
        ],
        'tasks': [
          for (final t in tasks)
            {
              'id': t.id,
              'state': t.state.name,
              'payloadDigest': sha256
                  .convert(utf8.encode(jsonEncode(t.payload)))
                  .toString(),
              'references': [for (final r in t.objectRefs) r.toJson()],
              'events': [
                for (final e in repository.taskEvents(t.id))
                  {'seq': e.seq, 'at': e.at, 'type': e.type},
              ],
            },
        ],
      };
      final latest = messages.where((m) => m.role == 'assistant').lastOrNull;
      final summary =
          latest?.content ??
          '尚无助手回复；${messages.length} 条消息，${tasks.length} 个任务';
      final result = SubconversationSummary({
        'readId': const Uuid().v4(),
        'readAt': DateTime.now().toUtc().toIso8601String(),
        'childConversationId': ref.childConversationId,
        'parentTaskId': ref.parentTaskId,
        'digest': sha256.convert(utf8.encode(jsonEncode(boundary))).toString(),
        'boundary': boundary,
        'summary': summary,
        'readonly': true,
        'authority': 'display_only',
        'referenceStatus': 'captured_unverified',
      });
      db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
        'subconversation-read:${ref.childConversationId}:${result.readId}',
        jsonEncode(result.value),
      ]);
      return result;
    });
    repository.refresh();
    return result;
  }
}
