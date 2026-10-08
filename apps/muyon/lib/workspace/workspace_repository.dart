import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';
import 'package:sqlite3/sqlite3.dart';

import '../platform/foundation_repository.dart';
import '../platform/grants/authorization_links.dart';
import '../platform/grants/grant_store.dart';
import '../platform/module_grants.dart';
import '../platform/outbound_ledger.dart';
import '../platform/outbound_tool_ledger.dart';
import '../platform/task_records.dart';

class Workspace {
  const Workspace(this.id, this.title);
  final String id;
  final String title;
}

class WorkspaceRepository {
  WorkspaceRepository(this.database);
  final ManagedDatabase database;
  static final _scopeStates = Expando<_WorkspaceScopeState>();
  _WorkspaceScopeState get _scopeState =>
      _scopeStates[database] ??= _WorkspaceScopeState();

  /// Binding/visibility authority only. Grant/review/audit writes do not
  /// invalidate this version or make their own signing transaction unknown.
  String? get scopeAuthorityRevision {
    final state = _scopeState;
    return state.pending == 0 ? '${state.identity}:${state.epoch}' : null;
  }

  Future<T> writeScopeAuthority<T>(T Function(Database) body) async {
    final state = _scopeState;
    state.pending++;
    state.epoch++;
    try {
      return await database.write(body);
    } finally {
      state.pending--;
    }
  }

  static final schema = ModuleSchema(
    version: 12,
    definitionDigest: 'foundation-v12',
    migrations: [
      ModuleMigration(
        version: 1,
        id: 'host-v1',
        definitionDigest: 'muyon-host-v1',
        migrate: (db) {
          db.execute('''
CREATE TABLE workspaces(id TEXT PRIMARY KEY,title TEXT NOT NULL);
CREATE TABLE workspace_module_bindings(workspace_id TEXT REFERENCES workspaces(id),module_id TEXT NOT NULL,native_project_id TEXT NOT NULL,PRIMARY KEY(workspace_id,module_id),UNIQUE(module_id,native_project_id));
CREATE TABLE module_registry(module_id TEXT PRIMARY KEY,status TEXT NOT NULL,last_error TEXT);
CREATE TABLE schema_catalog(module_id TEXT PRIMARY KEY,target_version INTEGER NOT NULL,target_digest TEXT NOT NULL,observed_version INTEGER,observed_digest TEXT,migration_status TEXT NOT NULL);
CREATE TABLE import_intents(operation_id TEXT PRIMARY KEY,workspace_id TEXT NOT NULL REFERENCES workspaces(id),module_id TEXT NOT NULL,target_project_id TEXT NOT NULL,kind TEXT NOT NULL,input_digest TEXT NOT NULL,staging_token TEXT NOT NULL,status TEXT NOT NULL);
CREATE UNIQUE INDEX active_create_intent ON import_intents(workspace_id,module_id) WHERE kind='create' AND status='pending';
CREATE TABLE object_catalog(module_id TEXT NOT NULL,project_id TEXT NOT NULL,object_type TEXT NOT NULL,object_id TEXT NOT NULL,summary TEXT NOT NULL,PRIMARY KEY(module_id,project_id,object_type,object_id));
CREATE TABLE projection_cursors(module_id TEXT PRIMARY KEY,last_applied_seq INTEGER NOT NULL);
CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE TABLE execution_records(id TEXT PRIMARY KEY,state TEXT NOT NULL,payload TEXT NOT NULL);
''');
        },
      ),
      FoundationRepository.migration,
      ModuleMigration(
        version: 3,
        id: 'schema-catalog-errors',
        definitionDigest: 'foundation-v3',
        migrate: (db) =>
            db.execute('ALTER TABLE schema_catalog ADD COLUMN last_error TEXT'),
      ),
      ModuleMigration(
        version: 4,
        id: 'import-intent-errors',
        definitionDigest: 'foundation-v4',
        migrate: (db) =>
            db.execute('ALTER TABLE import_intents ADD COLUMN last_error TEXT'),
      ),
      ModuleMigration(
        version: 5,
        id: 'outbound-requests',
        definitionDigest: 'foundation-v5',
        migrate: OutboundLedger.createTable,
      ),
      ModuleMigration(
        version: 6,
        id: 'dream-and-transfer-tasks',
        definitionDigest: 'foundation-v6',
        migrate: (db) {
          db.execute('''
ALTER TABLE memories ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE memories ADD COLUMN kind TEXT NOT NULL DEFAULT 'fact';
ALTER TABLE memories ADD COLUMN inference INTEGER NOT NULL DEFAULT 0;
ALTER TABLE memories ADD COLUMN lineage_json TEXT NOT NULL DEFAULT '[]';
CREATE TABLE experiences(
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  source TEXT NOT NULL,
  scope_json TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('candidate','verified','retired')),
  evidence_json TEXT NOT NULL,
  revision INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE memory_tombstones(
  id TEXT NOT NULL,
  kind TEXT NOT NULL,
  revision INTEGER NOT NULL,
  reason TEXT NOT NULL,
  scope_json TEXT,
  content_hash TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE dream_runs(
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK(status IN ('running','done','interrupted','reverted','failed')),
  inputs_json TEXT NOT NULL,
  seen_json TEXT NOT NULL,
  outputs_json TEXT NOT NULL,
  snapshot_json TEXT NOT NULL,
  model_profile_id TEXT,
  outbound_ids_json TEXT NOT NULL,
  token_cost INTEGER,
  token_cost_estimated INTEGER NOT NULL DEFAULT 1,
  elapsed_ms INTEGER,
  started_at TEXT NOT NULL,
  finished_at TEXT
);
CREATE TABLE dream_proposals(
  id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  evidence_json TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('proposed','accepted','reverted'))
);
CREATE TABLE transfer_tasks(
  task_id TEXT NOT NULL,
  input_revision TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  owner_device_id TEXT,
  result_seq INTEGER NOT NULL DEFAULT 0,
  result_json TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(task_id, input_revision)
);
''');
        },
      ),
      ModuleMigration(
        version: 7,
        id: 'outbound-streaming-columns',
        definitionDigest: 'foundation-v7',
        migrate: OutboundLedger.addStreamingColumns,
      ),
      ModuleMigration(
        version: 8,
        id: 'task-events',
        definitionDigest: 'foundation-v8',
        migrate: TaskRecords.migrate,
      ),
      ModuleMigration(
        version: 9,
        id: 'outbound-tool-requests',
        definitionDigest: 'foundation-v9',
        migrate: OutboundToolLedger.createTable,
      ),
      ModuleMigration(
        version: 10,
        id: 'module-grants',
        definitionDigest: 'foundation-v10',
        migrate: ModuleGrants.migrate,
      ),
      GrantStore.migration,
      AuthorizationLinks.migration,
    ],
  );

  List<Workspace> all() => [
    for (final row in database.raw.select(
      'SELECT * FROM workspaces ORDER BY rowid',
    ))
      Workspace(row['id'] as String, row['title'] as String),
  ];

  Future<Workspace> create(String title) async {
    if (title.trim().isEmpty) throw ArgumentError('Empty workspace title');
    final workspace = Workspace(const Uuid().v4(), title.trim());
    await writeScopeAuthority(
      (db) => db.execute('INSERT INTO workspaces VALUES(?,?)', [
        workspace.id,
        workspace.title,
      ]),
    );
    return workspace;
  }

  WorkspaceBinding? binding(String workspaceId, String moduleId) {
    final rows = database.raw.select(
      'SELECT native_project_id FROM workspace_module_bindings WHERE workspace_id=? AND module_id=?',
      [workspaceId, moduleId],
    );
    if (rows.isEmpty) return null;
    return WorkspaceBinding(
      workspaceId: workspaceId,
      moduleId: moduleId,
      nativeProjectId: rows.first['native_project_id'] as String,
    );
  }

  String? ownerWorkspace(String moduleId, String projectId) {
    final rows = database.raw.select(
      'SELECT workspace_id FROM workspace_module_bindings WHERE module_id=? AND native_project_id=?',
      [moduleId, projectId],
    );
    return rows.isEmpty ? null : rows.first['workspace_id'] as String;
  }

  Future<void> bind(WorkspaceBinding binding) => writeScopeAuthority((db) {
    final current = this.binding(binding.workspaceId, binding.moduleId);
    if (current != null && current.nativeProjectId != binding.nativeProjectId) {
      throw StateError('Workspace already bound');
    }
    final owner = ownerWorkspace(binding.moduleId, binding.nativeProjectId);
    if (owner != null && owner != binding.workspaceId) {
      throw StateError('Project already bound to another workspace');
    }
    if (current == null) {
      db.execute('INSERT INTO workspace_module_bindings VALUES(?,?,?)', [
        binding.workspaceId,
        binding.moduleId,
        binding.nativeProjectId,
      ]);
    }
  });

  Future<void> setSetting(String key, Object value) => database.write(
    (db) => db.execute('INSERT OR REPLACE INTO settings VALUES(?,?)', [
      key,
      jsonEncode(value),
    ]),
  );
  Object? setting(String key) {
    final rows = database.raw.select('SELECT value FROM settings WHERE key=?', [
      key,
    ]);
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }
}

class _WorkspaceScopeState {
  final String identity = const Uuid().v4();
  int pending = 0;
  int epoch = 0;
}
