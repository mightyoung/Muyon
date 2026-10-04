import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import '../platform/foundation_repository.dart';
import '../platform/outbound_ledger.dart';

class Workspace {
  const Workspace(this.id, this.title);
  final String id;
  final String title;
}

class WorkspaceRepository {
  WorkspaceRepository(this.database);
  final ManagedDatabase database;

  static final schema = ModuleSchema(
    version: 5,
    definitionDigest: 'foundation-v5',
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
    await database.write(
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

  Future<void> bind(WorkspaceBinding binding) => database.write((db) {
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
