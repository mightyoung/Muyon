import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import 'workspace_repository.dart';

/// Domain receipt commits before the host binding. Recovery replays the latter.
class ImportCoordinator {
  ImportCoordinator(this.workspaces);
  final WorkspaceRepository workspaces;

  ImportIntent _read(Map<String, Object?> row) => ImportIntent(
    operationId: row['operation_id'] as String,
    workspaceId: row['workspace_id'] as String,
    moduleId: row['module_id'] as String,
    targetProjectId: row['target_project_id'] as String,
    kind: ImportKind.values.byName(row['kind'] as String),
    inputDigest: row['input_digest'] as String,
    stagingToken: row['staging_token'] as String,
  );

  Future<ImportIntent> record(PreparedImport prepared, {String? operationId}) =>
      workspaces.database.write((db) {
        final binding = prepared.target.binding;
        final current = workspaces.binding(
          binding.workspaceId,
          binding.moduleId,
        );
        if (prepared.target.kind == ImportKind.create && current != null) {
          throw StateError('Workspace already bound');
        }
        if (prepared.target.kind == ImportKind.refresh &&
            current?.nativeProjectId != binding.nativeProjectId) {
          throw StateError('scope_mismatch');
        }
        final intent = ImportIntent(
          operationId: operationId ?? const Uuid().v4(),
          workspaceId: binding.workspaceId,
          moduleId: binding.moduleId,
          targetProjectId: binding.nativeProjectId,
          kind: prepared.target.kind,
          inputDigest: prepared.inputDigest,
          stagingToken: prepared.stagingToken,
        );
        final same = db.select(
          'SELECT * FROM import_intents WHERE operation_id=?',
          [intent.operationId],
        );
        if (same.isNotEmpty) {
          final old = _read(same.first);
          if (!old.sameIdentity(intent)) {
            throw StateError('Operation identity conflict');
          }
          return old;
        }
        final pending = db.select(
          "SELECT * FROM import_intents WHERE workspace_id=? AND module_id=? AND kind='create' AND status='pending'",
          [intent.workspaceId, intent.moduleId],
        );
        if (pending.isNotEmpty) {
          throw StateError('An import is pending; recover or retry it first');
        }
        db.execute('INSERT INTO import_intents VALUES(?,?,?,?,?,?,?,?)', [
          intent.operationId,
          intent.workspaceId,
          intent.moduleId,
          intent.targetProjectId,
          intent.kind.name,
          intent.inputDigest,
          intent.stagingToken,
          'pending',
        ]);
        return intent;
      });

  Future<void> activate(ImportReceipt receipt) => workspaces.database.write((
    db,
  ) {
    final intent = receipt.intent;
    final rows = db.select(
      'SELECT * FROM import_intents WHERE operation_id=?',
      [intent.operationId],
    );
    if (rows.isEmpty || !_read(rows.first).sameIdentity(intent)) {
      throw StateError('Receipt does not match intent');
    }
    final current = workspaces.binding(intent.workspaceId, intent.moduleId);
    if (current != null && current.nativeProjectId != intent.targetProjectId) {
      throw StateError('Binding conflict');
    }
    final owner = workspaces.ownerWorkspace(
      intent.moduleId,
      intent.targetProjectId,
    );
    if (owner != null && owner != intent.workspaceId) {
      throw StateError('Project belongs to another workspace');
    }
    if (current == null) {
      db.execute('INSERT INTO workspace_module_bindings VALUES(?,?,?)', [
        intent.workspaceId,
        intent.moduleId,
        intent.targetProjectId,
      ]);
    }
    db.execute(
      "UPDATE import_intents SET status='complete' WHERE operation_id=?",
      [intent.operationId],
    );
  });

  List<ImportIntent> pending(String moduleId) => [
    for (final row in workspaces.database.raw.select(
      "SELECT * FROM import_intents WHERE module_id=? AND status='pending'",
      [moduleId],
    ))
      _read(row),
  ];

  Future<ImportReceipt> commit(
    ModuleRuntime runtime,
    PreparedImport prepared,
    ImportIntent intent, {
    bool interruptBeforeActivation = false,
  }) async {
    if (!prepared.matches(intent)) {
      throw StateError('Prepared input identity mismatch');
    }
    final receipt = await runtime.commitImport(prepared, intent);
    if (interruptBeforeActivation) {
      throw StateError('Simulated activation interruption');
    }
    await activate(receipt);
    return receipt;
  }
}
