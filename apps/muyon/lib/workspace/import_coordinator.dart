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
        db.execute('INSERT INTO import_intents VALUES(?,?,?,?,?,?,?,?,NULL)', [
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

  /// Startup/activation reconciliation for [moduleId]:
  /// - module committed (receipt exists) → bind once and mark complete;
  /// - module never committed → left pending for retry or [abandon];
  /// - binding no longer possible → marked `conflict` with the reason, so one
  ///   bad intent neither blocks the module nor the workspace.
  Future<ImportRecovery> recover(String moduleId, ModuleRuntime runtime) async {
    final activated = <String>[];
    final awaiting = <String>[];
    final conflicts = <String, String>{};
    for (final intent in pending(moduleId)) {
      final receipt = await runtime.receipt(intent.operationId);
      if (receipt == null) {
        awaiting.add(intent.operationId);
        continue;
      }
      try {
        await activate(receipt);
        activated.add(intent.operationId);
      } on StateError catch (error) {
        conflicts[intent.operationId] = error.message;
        await _close(intent.operationId, 'conflict', error.message);
      }
    }
    return ImportRecovery(activated, awaiting, conflicts);
  }

  /// Gives up a pending import the module never committed. Refuses when a
  /// receipt exists: that import happened and must be recovered instead.
  Future<void> abandon(
    String moduleId,
    ModuleRuntime runtime,
    String operationId,
  ) async {
    if (!pending(moduleId).any((i) => i.operationId == operationId)) {
      throw StateError('No pending import $operationId');
    }
    if (await runtime.receipt(operationId) != null) {
      throw StateError('Import was committed; recover it instead');
    }
    await _close(operationId, 'abandoned', null);
  }

  Future<void> _close(String operationId, String status, String? error) =>
      workspaces.database.write(
        (db) => db.execute(
          "UPDATE import_intents SET status=?, last_error=? WHERE operation_id=? AND status='pending'",
          [status, error, operationId],
        ),
      );

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

class ImportRecovery {
  const ImportRecovery(this.activated, this.awaitingCommit, this.conflicts);
  final List<String> activated;
  final List<String> awaitingCommit;

  /// Operation id → reason the binding could not be made.
  final Map<String, String> conflicts;
}
