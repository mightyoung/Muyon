import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'grants/host_effect_intent.dart';
import 'grants/local_export_target.dart';

enum LocalExportLedgerState {
  pending,
  succeeded,
  cancelled,
  failed,
  interrupted,
  unknown,
}

final class LocalExportLedgerException implements Exception {
  const LocalExportLedgerException(this.code);
  final String code;
  @override
  String toString() => 'LocalExportLedgerException($code)';
}

/// Host-only input, with no model decoder. Building an intent grants no
/// permission; the caller must complete LE05 approval before calling execute.
/// The same frozen parameters build the LE05 intent and its audit identity.
final class LocalExportLedgerRequest {
  factory LocalExportLedgerRequest({
    required String exportId,
    required String toolId,
    required String invocationId,
    required LocalExportPhase phase,
    required String scopeDigest,
    required LocalExportPreparation preparation,
    required LocalExportTargetIssuer targetIssuer,
    LocalExportTargetCapability? target,
    LocalExportOverwrite overwrite = LocalExportOverwrite.createNew,
    required String policyVersion,
    String? attemptId,
    Map<String, Object?> hostMetadata = const {},
  }) {
    _requireExportId(exportId);
    if (phase == LocalExportPhase.save) {
      _requireAttempt(attemptId);
    } else if (attemptId != null && attemptId != 'generate') {
      throw ArgumentError('Generation has one attempt');
    }
    final frozen = _copyPreparation(preparation);
    if (_hash(frozen.bytes) != frozen.sha256) {
      throw ArgumentError('Preparation content digest mismatch');
    }
    final intent = HostEffectIntent.localExport(
      toolId: toolId,
      invocationId: invocationId,
      phase: phase,
      scopeDigest: scopeDigest,
      preparationVersion: frozen.preparationVersion,
      fileName: frozen.kind == LocalExportKind.report
          ? 'report-$exportId.md'
          : 'workbench-claims-$exportId.jsonl',
      format: frozen.mimeType,
      content: frozen.bytes,
      sourceObjects: frozen.sources,
      targetIssuer: targetIssuer,
      target: target,
      overwrite: overwrite,
      policyVersion: policyVersion,
    );
    return LocalExportLedgerRequest._(
      exportId,
      scopeDigest,
      frozen,
      intent,
      attemptId ?? 'generate',
      target == null ? null : _hash(utf8.encode(target.identity)),
      _freezeMap(hostMetadata),
    );
  }

  LocalExportLedgerRequest._(
    this.exportId,
    this.scopeDigest,
    this.preparation,
    this._intent,
    this.attemptId,
    this.targetIdentityDigest,
    this.hostMetadata,
  );
  final String exportId, scopeDigest, attemptId;
  final LocalExportPreparation preparation;
  final HostEffectIntent _intent;
  final String? targetIdentityDigest;
  final Map<String, Object?> hostMetadata;
  String get invocationId => _intent.invocationId;
  String get toolId => _intent.toolId;
  LocalExportPhase get phase => _intent.phase;
  String get intentDigest => _intent.digest;
  bool get hasLiveAuthority => _intent.hasLiveAuthority;
  (String, LocalExportPhase) get _key => (invocationId, phase);
  String get _baseJson => jsonEncode({
    'toolId': toolId,
    'scopeDigest': scopeDigest,
    'preparation': _preparationJson(preparation),
  });
  String get _baseDigest => _hash(utf8.encode(_baseJson));
  String get _identityDigest => _hash(
    utf8.encode(
      jsonEncode([
        exportId,
        invocationId,
        phase.name,
        attemptId,
        intentDigest,
        _baseDigest,
        targetIdentityDigest,
      ]),
    ),
  );
}

final class LocalExportStageCompletion {
  LocalExportStageCompletion(
    LocalExportStage stage, {
    Map<String, Object?> hostMetadata = const {},
  }) : stage = LocalExportStage(
         stage.outcome,
         cleanup: stage.cleanup,
         errorCode: stage.errorCode,
       ),
       hostMetadata = _freezeMap(hostMetadata);
  final LocalExportStage stage;
  final Map<String, Object?> hostMetadata;
}

/// This record is for the host. Only modelData is a model-facing projection.
final class LocalExportLedgerStageRecord {
  LocalExportLedgerStageRecord._(
    Map<String, Object?> data, {
    Map<String, Object?>? durableModel,
  }) : _data = Map.unmodifiable(data),
       _durableModel = durableModel == null
           ? null
           : Map.unmodifiable(durableModel),
       hostMetadata = _freezeMap(
         Map<String, Object?>.from(
           jsonDecode(data['host_json']! as String) as Map,
         ),
       );
  final Map<String, Object?> _data;
  final Map<String, Object?>? _durableModel;
  final Map<String, Object?> hostMetadata;
  String get exportId => _data['export_id']! as String;
  String get invocationId => _data['invocation_id']! as String;
  String get attemptId => _data['attempt_id']! as String;
  LocalExportPhase get phase =>
      LocalExportPhase.values.byName(_data['phase']! as String);
  LocalExportLedgerState get state =>
      LocalExportLedgerState.values.byName(_data['state']! as String);
  String? get errorCode => _data['error_code'] as String?;
  String? get targetIdentityDigest =>
      _data['target_identity_digest'] as String?;
  LocalExportCleanup get cleanup =>
      LocalExportCleanup.values.byName(_data['cleanup']! as String);
  DateTime get createdAt => DateTime.parse(_data['created_at']! as String);
  DateTime? get finishedAt => _data['finished_at'] == null
      ? null
      : DateTime.parse(_data['finished_at']! as String);
  Map<String, Object?> get modelData =>
      _durableModel ??
      Map.unmodifiable({
        'status': state.name,
        if (errorCode != null) 'errorCode': _modelCode(errorCode!),
      });

  LocalExportLedgerStageRecord _observed(
    LocalExportStageCompletion completion,
    DateTime at, {
    LocalExportLedgerState? state,
    String? errorCode,
    bool observation = false,
  }) => LocalExportLedgerStageRecord._({
    ..._data,
    'state':
        (state ??
                LocalExportLedgerState.values.byName(
                  completion.stage.outcome.name,
                ))
            .name,
    'cleanup': completion.stage.cleanup.name,
    'error_code': errorCode ?? completion.stage.errorCode,
    'finished_at': at.toUtc().toIso8601String(),
    'host_json': jsonEncode({
      ...hostMetadata,
      'completion': completion.hostMetadata,
    }),
  }, durableModel: observation ? modelData : _durableModel);
}

final class LocalExportLedgerReceipt {
  LocalExportLedgerReceipt._(
    this.exportId,
    this.scopeDigest,
    this.preparation,
    this.generate,
    List<LocalExportLedgerStageRecord> saves,
  ) : saveAttempts = List.unmodifiable(saves);
  final String exportId, scopeDigest;
  final LocalExportPreparation preparation;
  final LocalExportLedgerStageRecord? generate;
  final List<LocalExportLedgerStageRecord> saveAttempts;
  Map<String, Object?> get modelData => _freezeMap({
    'exportId': exportId,
    'contentDigest': preparation.sha256,
    'manifestDigest': preparation.manifestDigest,
    'byteCount': preparation.byteCount,
    'generate': generate?.modelData,
    'saveAttempts': saveAttempts.map((s) => s.modelData).toList(),
  });
}

/// Records effects without implementing them. Tables are installed atomically
/// with the first pending reservation; read/check never install a schema.
/// No target capability is serialized or recovered from an audit identity.
final class LocalExportLedger {
  LocalExportLedger(this.database, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final ManagedDatabase database;
  final DateTime Function() clock;
  final _running =
      <(String, LocalExportPhase), Future<LocalExportLedgerStageRecord>>{};
  final _active = <(String, LocalExportPhase)>{};
  final _interrupted =
      <(String, LocalExportPhase), LocalExportLedgerStageRecord>{};

  static void createTables(Database db) => db.execute('''
CREATE TABLE IF NOT EXISTS local_export_exports(
 export_id TEXT PRIMARY KEY, base_digest TEXT NOT NULL,
 base_json TEXT NOT NULL, content BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS local_export_attempts(
 export_id TEXT NOT NULL REFERENCES local_export_exports(export_id),
 invocation_id TEXT NOT NULL, phase TEXT NOT NULL CHECK(phase IN ('generate','save')),
 attempt_id TEXT NOT NULL, identity_digest TEXT NOT NULL,
 target_identity_digest TEXT,
 state TEXT NOT NULL CHECK(state IN ('pending','succeeded','cancelled','failed','interrupted','unknown')),
 cleanup TEXT NOT NULL, error_code TEXT, host_json TEXT NOT NULL,
 created_at TEXT NOT NULL, finished_at TEXT,
 PRIMARY KEY(invocation_id,phase), UNIQUE(export_id,phase,attempt_id)
);
''');

  bool _installed() {
    final tables = database.raw.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('local_export_exports','local_export_attempts')",
    );
    if (tables.isEmpty) return false;
    if (tables.length != 2) {
      throw const LocalExportLedgerException('ledger_read_failed');
    }
    return true;
  }

  Map<String, Object?>? _find(String invocation, LocalExportPhase phase) {
    try {
      if (!_installed()) return null;
      final rows = database.raw.select(
        'SELECT * FROM local_export_attempts WHERE invocation_id=? AND phase=?',
        [invocation, phase.name],
      );
      return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
    } catch (_) {
      throw const LocalExportLedgerException('ledger_read_failed');
    }
  }

  LocalExportLedgerStageRecord _record(Map<String, Object?> row) {
    final key = (
      row['invocation_id']! as String,
      LocalExportPhase.values.byName(row['phase']! as String),
    );
    final interrupted = _interrupted[key];
    if (interrupted != null) return interrupted;
    if (row['state'] == 'pending' && !_active.contains(key)) {
      return LocalExportLedgerStageRecord._({
        ...row,
        'state': 'unknown',
        'error_code': 'export_result_unknown',
      });
    }
    return LocalExportLedgerStageRecord._(row);
  }

  /// Queries only persisted facts plus this instance's active execution.
  LocalExportLedgerReceipt? read(String exportId) {
    _requireExportId(exportId);
    try {
      if (!_installed()) return null;
      final rows = database.raw.select(
        'SELECT * FROM local_export_exports WHERE export_id=?',
        [exportId],
      );
      if (rows.isEmpty) return null;
      final base = Map<String, Object?>.from(
        jsonDecode(rows.single['base_json']! as String) as Map,
      );
      final preparation = _decodePreparation(
        base['preparation']! as Map,
        rows.single['content']! as List<int>,
      );
      final attempts = database.raw
          .select(
            'SELECT * FROM local_export_attempts WHERE export_id=? ORDER BY rowid',
            [exportId],
          )
          .map((r) => _record(Map<String, Object?>.from(r)))
          .toList();
      return LocalExportLedgerReceipt._(
        exportId,
        base['scopeDigest']! as String,
        preparation,
        attempts.where((s) => s.phase == LocalExportPhase.generate).firstOrNull,
        attempts.where((s) => s.phase == LocalExportPhase.save).toList(),
      );
    } on LocalExportLedgerException {
      rethrow;
    } catch (_) {
      throw const LocalExportLedgerException('ledger_read_failed');
    }
  }

  void _match(LocalExportLedgerRequest request, Map<String, Object?> row) {
    if (row['identity_digest'] != request._identityDigest) {
      throw const LocalExportLedgerException('export_identity_conflict');
    }
  }

  Future<LocalExportLedgerStageRecord> _existing(
    LocalExportLedgerRequest request,
    Map<String, Object?> row,
  ) async {
    _match(request, row);
    return await (_running[request._key] ?? Future.value(_record(row)));
  }

  static void _requireGenerated(Database db, String exportId) {
    final rows = db.select(
      "SELECT state FROM local_export_attempts WHERE export_id=? AND phase='generate'",
      [exportId],
    );
    if (rows.length != 1 || rows.single['state'] != 'succeeded') {
      throw const LocalExportLedgerException('export_generation_required');
    }
    if (db.select(
      "SELECT 1 FROM local_export_attempts WHERE export_id=? AND phase='save' AND state IN ('pending','interrupted','unknown')",
      [exportId],
    ).isNotEmpty) {
      throw const LocalExportLedgerException('export_requires_check');
    }
  }

  Future<LocalExportLedgerStageRecord> execute(
    LocalExportLedgerRequest request, {
    required Future<LocalExportStageCompletion> Function(List<int>) operation,
  }) async {
    // Replays, including unknown outcomes, only read. Expired capabilities
    // cannot turn a historical receipt into a fresh execution.
    // Reservation preflight and BEGIN IMMEDIATE share one failure class: a peer
    // holding the write lock makes SELECT SQLITE_BUSY, which _find wraps as
    // ledger_read_failed — that is pending contention, not a broken ledger.
    final bool inserted;
    try {
      final existing = _find(request.invocationId, request.phase);
      if (existing != null) return await _existing(request, existing);
      inserted = await database.write((db) {
        createTables(db);
        final duplicate = _find(request.invocationId, request.phase);
        if (duplicate != null) {
          _match(request, duplicate);
          return false;
        }
        final collision = db.select(
          'SELECT 1 FROM local_export_attempts WHERE export_id=? AND phase=? AND attempt_id=?',
          [request.exportId, request.phase.name, request.attemptId],
        );
        if (collision.isNotEmpty) {
          throw const LocalExportLedgerException('export_identity_conflict');
        }
        final exports = db.select(
          'SELECT base_digest FROM local_export_exports WHERE export_id=?',
          [request.exportId],
        );
        if (exports.isNotEmpty &&
            exports.single['base_digest'] != request._baseDigest) {
          throw const LocalExportLedgerException('export_identity_conflict');
        }
        if (request.phase == LocalExportPhase.save) {
          _requireGenerated(db, request.exportId);
        } else if (exports.isEmpty) {
          db.execute('INSERT INTO local_export_exports VALUES(?,?,?,?)', [
            request.exportId,
            request._baseDigest,
            request._baseJson,
            request.preparation.bytes,
          ]);
        }
        final at = clock().toUtc().toIso8601String();
        db.execute(
          '''
INSERT INTO local_export_attempts(export_id,invocation_id,phase,attempt_id,identity_digest,target_identity_digest,state,cleanup,host_json,created_at)
VALUES(?,?,?,?,?,?,'pending','notNeeded',?,?)''',
          [
            request.exportId,
            request.invocationId,
            request.phase.name,
            request.attemptId,
            request._identityDigest,
            request.targetIdentityDigest,
            jsonEncode({'request': request.hostMetadata}),
            at,
          ],
        );
        return true;
      });
      if (!inserted) {
        return await _existing(
          request,
          _find(request.invocationId, request.phase)!,
        );
      }
    } on LocalExportLedgerException catch (error) {
      if (error.code == 'ledger_read_failed') {
        throw const LocalExportLedgerException('ledger_pending_failed');
      }
      rethrow;
    } catch (_) {
      throw const LocalExportLedgerException('ledger_pending_failed');
    }
    _active.add(request._key);
    final future = _executeOwned(request, operation);
    _running[request._key] = future;
    try {
      return await future;
    } finally {
      _running.remove(request._key);
      _active.remove(request._key);
    }
  }

  Future<LocalExportLedgerStageRecord> _executeOwned(
    LocalExportLedgerRequest request,
    Future<LocalExportStageCompletion> Function(List<int>) operation,
  ) async {
    final pending = _record(_find(request.invocationId, request.phase)!);
    LocalExportStageCompletion completion;
    try {
      completion = request.hasLiveAuthority
          ? await operation(request.preparation.bytes)
          : LocalExportStageCompletion(
              LocalExportStage(
                LocalExportOutcome.cancelled,
                errorCode: 'export_target_expired',
              ),
            );
    } catch (error) {
      completion = LocalExportStageCompletion(
        LocalExportStage(
          LocalExportOutcome.unknown,
          cleanup: LocalExportCleanup.unknown,
          errorCode: 'export_execution_unknown',
        ),
        hostMetadata: {'rawError': _hostError(error)},
      );
    }
    var completionTime = pending.createdAt;
    try {
      completionTime = clock().toUtc();
      final finished = pending._observed(completion, completionTime);
      await database.write((db) {
        db.execute(
          '''
UPDATE local_export_attempts SET state=?,cleanup=?,error_code=?,host_json=?,finished_at=?
WHERE invocation_id=? AND phase=? AND state='pending'
''',
          [
            finished.state.name,
            finished.cleanup.name,
            finished.errorCode,
            jsonEncode(finished.hostMetadata),
            finished.finishedAt!.toIso8601String(),
            request.invocationId,
            request.phase.name,
          ],
        );
        if (db.updatedRows != 1) {
          throw const LocalExportLedgerException('ledger_completion_failed');
        }
      });
      return finished;
    } catch (_) {
      final interrupted = pending._observed(
        completion,
        completionTime,
        state: LocalExportLedgerState.interrupted,
        errorCode: 'ledger_completion_failed',
      );
      _interrupted[request._key] = interrupted;
      return interrupted;
    }
  }

  /// Choosing no target is a separate save fact, never a generation failure.
  /// A late cancellation returns the already recorded fact unchanged.
  Future<LocalExportLedgerStageRecord> cancelSave({
    required String exportId,
    required String invocationId,
    required String attemptId,
  }) async {
    _requireExportId(exportId);
    _requireAttempt(attemptId);
    if (invocationId.isEmpty) throw ArgumentError('Invocation required');
    LocalExportLedgerStageRecord? existing() {
      final row = _find(invocationId, LocalExportPhase.save);
      if (row == null) return null;
      if (row['export_id'] != exportId || row['attempt_id'] != attemptId) {
        throw const LocalExportLedgerException('export_identity_conflict');
      }
      return _record(row);
    }

    final previous = existing();
    if (previous != null) return previous;
    try {
      return await database.write((db) {
        createTables(db);
        final raced = existing();
        if (raced != null) return raced;
        _requireGenerated(db, exportId);
        if (db.select(
          "SELECT 1 FROM local_export_attempts WHERE export_id=? AND phase='save' AND attempt_id=?",
          [exportId, attemptId],
        ).isNotEmpty) {
          throw const LocalExportLedgerException('export_identity_conflict');
        }
        final at = clock().toUtc().toIso8601String();
        final identity = _hash(
          utf8.encode(
            jsonEncode(['cancel_save', exportId, invocationId, attemptId]),
          ),
        );
        db.execute(
          '''
INSERT INTO local_export_attempts(export_id,invocation_id,phase,attempt_id,identity_digest,state,cleanup,host_json,created_at,finished_at)
VALUES(?,?,'save',?,?,'cancelled','notNeeded','{}',?,?)''',
          [exportId, invocationId, attemptId, identity, at, at],
        );
        return _record(_find(invocationId, LocalExportPhase.save)!);
      });
    } on LocalExportLedgerException {
      rethrow;
    } catch (_) {
      throw const LocalExportLedgerException('ledger_pending_failed');
    }
  }

  /// A probe is a host-supplied read-only observation. It receives no target
  /// capability. Observations are not persisted and never authorize retries.
  /// Model projections retain the durable outcome, not an unrecorded success.
  Future<LocalExportLedgerReceipt?> check(
    String exportId, {
    required Future<LocalExportStageCompletion> Function(
      LocalExportLedgerStageRecord,
    )
    probe,
  }) async {
    final receipt = read(exportId);
    if (receipt == null) return null;
    Future<LocalExportLedgerStageRecord> inspect(
      LocalExportLedgerStageRecord stage,
    ) async {
      if (stage.state != LocalExportLedgerState.unknown &&
          stage.state != LocalExportLedgerState.interrupted) {
        return stage;
      }
      try {
        return stage._observed(await probe(stage), clock(), observation: true);
      } catch (_) {
        return stage._observed(
          LocalExportStageCompletion(
            LocalExportStage(
              LocalExportOutcome.unknown,
              cleanup: LocalExportCleanup.unknown,
              errorCode: 'export_check_failed',
            ),
          ),
          stage.finishedAt ?? stage.createdAt,
          observation: true,
        );
      }
    }

    final generation = receipt.generate == null
        ? null
        : await inspect(receipt.generate!);
    final saves = <LocalExportLedgerStageRecord>[];
    for (final save in receipt.saveAttempts) {
      saves.add(await inspect(save));
    }
    return LocalExportLedgerReceipt._(
      receipt.exportId,
      receipt.scopeDigest,
      receipt.preparation,
      generation,
      saves,
    );
  }
}

void _requireExportId(String id) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(id)) {
    throw ArgumentError('Safe host export ID required');
  }
}

void _requireAttempt(String? id) {
  if (id == null || id.trim().isEmpty || id.length > 128) {
    throw ArgumentError('Save attempt identity required');
  }
}

String _hash(List<int> bytes) => sha256.convert(bytes).toString();
String _hostError(Object error) {
  try {
    return '$error';
  } catch (_) {
    return 'Host error could not be described';
  }
}

LocalExportPreparation _copyPreparation(LocalExportPreparation p) =>
    LocalExportPreparation(
      kind: p.kind,
      formatVersion: p.formatVersion,
      mimeType: p.mimeType,
      generatedAt: p.generatedAt,
      bytes: p.bytes,
      sha256: p.sha256,
      sources: p.sources,
      dedupedObjectCount: p.dedupedObjectCount,
      exclusions: p.exclusions,
      warnings: p.warnings,
      preparationVersion: p.preparationVersion,
      manifestDigest: p.manifestDigest,
    );
Map<String, Object?> _preparationJson(LocalExportPreparation p) => {
  'kind': p.kind.name,
  'formatVersion': p.formatVersion,
  'mimeType': p.mimeType,
  'generatedAt': p.generatedAt.toUtc().toIso8601String(),
  'sha256': p.sha256,
  'manifestDigest': p.manifestDigest,
  'byteCount': p.byteCount,
  'dedupedObjectCount': p.dedupedObjectCount,
  'preparationVersion': p.preparationVersion,
  'sources': p.sources.map((s) => s.toJson()).toList(),
  'exclusions': p.exclusions
      .map((e) => {'id': e.id, 'reason': e.reason})
      .toList(),
  'warnings': p.warnings,
};
LocalExportPreparation _decodePreparation(Map p, List<int> bytes) {
  final result = LocalExportPreparation(
    kind: LocalExportKind.values.byName(p['kind'] as String),
    formatVersion: p['formatVersion'] as String,
    mimeType: p['mimeType'] as String,
    generatedAt: DateTime.parse(p['generatedAt'] as String),
    bytes: bytes,
    sha256: p['sha256'] as String,
    manifestDigest: p['manifestDigest'] as String,
    preparationVersion: p['preparationVersion'] as int,
    dedupedObjectCount: p['dedupedObjectCount'] as int,
    warnings: List<String>.from(p['warnings'] as List),
    sources: [
      for (final s in p['sources'] as List)
        ObjectRef(
          moduleId: s['moduleId'] as String,
          objectType: s['objectType'] as String,
          objectId: s['objectId'] as String,
          nativeProjectId: s['nativeProjectId'] as String?,
          revisionRef: s['revisionRef'] as String?,
          contentDigest: s['contentDigest'] as String?,
        ),
    ],
    exclusions: [
      for (final e in p['exclusions'] as List)
        LocalExportExclusion(e['id'] as String, e['reason'] as String),
    ],
  );
  if (_hash(result.bytes) != result.sha256 ||
      result.byteCount != p['byteCount']) {
    throw const LocalExportLedgerException('ledger_read_failed');
  }
  return result;
}

Map<String, Object?> _freezeMap(Map<String, Object?> value) =>
    _freezeJson(value) as Map<String, Object?>;
Object? _freezeJson(Object? value) {
  if (value == null ||
      value is String ||
      value is bool ||
      (value is num && value.isFinite)) {
    return value;
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeJson));
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries) entry.key: _freezeJson(entry.value),
    });
  }
  throw ArgumentError('Host metadata must be JSON data');
}

String _modelCode(String code) =>
    const {
      'ledger_pending_failed',
      'ledger_completion_failed',
      'ledger_read_failed',
      'export_identity_conflict',
      'export_generation_required',
      'export_requires_check',
      'export_target_expired',
      'export_execution_unknown',
      'export_result_unknown',
      'export_check_failed',
      'export_failed',
    }.contains(code)
    ? code
    : 'export_failed';
