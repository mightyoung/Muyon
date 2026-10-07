import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'outbound_tool_ledger.dart';

/// Only the published REG-2b placeholder history has a compatibility path.
/// Its applied rows remain evidence; the repair is a separate immutable fact.
class HostSchemaCompatibility {
  static const reserved = 'reserved-reg-2a-outbound-tool-requests';
  static const canonical = 'outbound-tool-requests';
  static const repairId = 'reg2a-reserved9-v1';
  static const fingerprints = {
    9: '9f2d793732ba848118fb58ec2c0fe68b9f12cb581eb85cc3b895ca8ddfc6dc69',
    10: 'b7ee3788ee14c435257b5be0b502fd3499e93401b5c6b7a66665c821574025fe',
  };
  // Captured from the frozen canonical DDL, independently of database metadata.
  static const repairedFingerprints = {
    10: 'dc4f8d2258827295b85efe506c93b522ddd780d0e79716c06ea79f0a2c92e989',
    11: '9e89d824e3856c01f0713b1d66bd711e8562cc0097ef51e088fa2122c438b158',
  };
  static const previousRepairedFingerprints = {
    10: 'a0be1c5a07eacb86c2a419979c8dd71905581493001bc807888899b34cff3c83',
    11: 'a04da65762c20da2be13c17d2440eae79e92a5fc3dd4c22cf01f8242f510af05',
  };
  static const canonicalFingerprints = {
    8: '9f2d793732ba848118fb58ec2c0fe68b9f12cb581eb85cc3b895ca8ddfc6dc69',
    9: '588c43f902108ac5609856ab9aeffa4aabde62269591a51c0bd91b820a55ee32',
    10: '7a4af5e262881d772c83b655b83a07207db39ed7ebd49ef563ce1b858f15feff',
    11: 'd9ced9e0133319bd7c8a6b1c8dc4e6e56d07551316e36ac40dd1ec822280568c',
  };

  static bool isCanonicalTarget(ModuleSchema schema) =>
      (schema.version == 10 || schema.version == 11) &&
      schema.definitionDigest == 'foundation-v${schema.version}' &&
      schema.migrations.length == schema.version &&
      schema.migrations[8].id == canonical &&
      schema.migrations[8].definitionDigest == 'foundation-v9' &&
      schema.migrations[9].id == 'module-grants' &&
      schema.migrations[9].definitionDigest == 'foundation-v10';

  static void validateCanonical(
    Database db,
    int version,
    String Function(Database) digest,
  ) {
    if (digest(db) != canonicalFingerprints[version]) {
      throw StateError('Unknown canonical host schema');
    }
  }

  static void validateCompleted(
    Database db,
    int version,
    String Function(Database) digest,
  ) {
    if (digest(db) != repairedFingerprints[version]) {
      throw StateError('Unknown repaired host schema');
    }
  }

  static const ids = [
    'host-v1',
    'foundation-v2',
    'schema-catalog-errors',
    'import-intent-errors',
    'outbound-requests',
    'dream-and-transfer-tasks',
    'outbound-streaming-columns',
    'task-events',
    reserved,
    'module-grants',
  ];
  // REPLACE does not fire DELETE triggers when recursive_triggers is off.
  // Reject every subsequent insertion before conflict resolution instead.
  static const insertGuardDdl = '''
CREATE TRIGGER host_compatibility_no_insert BEFORE INSERT ON host_migration_compatibility
WHEN EXISTS(SELECT 1 FROM host_migration_compatibility)
BEGIN SELECT RAISE(ABORT,'Migration compatibility facts are immutable'); END;
''';
  static const auditDdl =
      '''
CREATE TABLE host_migration_compatibility(
 repair_id TEXT PRIMARY KEY CHECK(repair_id='reg2a-reserved9-v1'),
 source_version INTEGER NOT NULL CHECK(source_version IN (9,10)),
 source_definition_digest TEXT NOT NULL,
 source_structure_digest TEXT NOT NULL,
 source_history_json TEXT NOT NULL,
 canonical_migration_id TEXT NOT NULL CHECK(canonical_migration_id='outbound-tool-requests'),
 canonical_definition_digest TEXT NOT NULL CHECK(canonical_definition_digest='foundation-v9'),
 completed INTEGER NOT NULL CHECK(completed=1),
 repaired_at TEXT NOT NULL
);
CREATE TRIGGER host_compatibility_no_update BEFORE UPDATE ON host_migration_compatibility
BEGIN SELECT RAISE(ABORT,'Migration compatibility facts are immutable'); END;
CREATE TRIGGER host_compatibility_no_delete BEFORE DELETE ON host_migration_compatibility
BEGIN SELECT RAISE(ABORT,'Migration compatibility facts are immutable'); END;
$insertGuardDdl
''';

  static List<List<Object?>> history(Database db, int version) => [
    for (final row in db.select(
      'SELECT version,migration_id,definition_digest,applied_at FROM schema_migrations WHERE version<=? ORDER BY version',
      [version],
    ))
      row.values.toList(),
  ];

  static void _checkHistory(List<List<Object?>> rows, int version) {
    if (rows.length != version) {
      throw StateError('Unknown host migration history');
    }
    for (var i = 0; i < version; i++) {
      if (rows[i].length != 4 ||
          rows[i][0] != i + 1 ||
          rows[i][1] != ids[i] ||
          rows[i][2] != (i == 0 ? 'muyon-host-v1' : 'foundation-v${i + 1}') ||
          rows[i][3] is! String ||
          DateTime.tryParse(rows[i][3] as String) == null) {
        throw StateError('Unknown host migration history');
      }
    }
  }

  /// Called inside the same transaction as the ordinary migration loop.
  /// Returns true only when version 9 has a proven, completed alias repair.
  static bool prepare(
    Database db,
    ModuleSchema schema,
    String Function(Database) digest,
  ) {
    final version = db.userVersion;
    final hasAudit = db
        .select(
          "SELECT name FROM sqlite_master WHERE name='host_migration_compatibility'",
        )
        .isNotEmpty;
    final hasReserved =
        version >= 9 &&
        db
            .select(
              'SELECT migration_id FROM schema_migrations WHERE version=9',
            )
            .any((r) => r['migration_id'] == reserved);
    if (!hasAudit && !hasReserved) {
      if (version >= 8 &&
          version <= 11 &&
          isCanonicalTarget(schema) &&
          (digest(db) != canonicalFingerprints[version] ||
              db
                      .select(
                        'SELECT definition_digest FROM host_schema_state WHERE singleton=1',
                      )
                      .single['definition_digest'] !=
                  'foundation-v$version')) {
        throw StateError('Unknown canonical host schema');
      }
      return false;
    }
    if ((schema.version != 10 && schema.version != 11) ||
        schema.definitionDigest != 'foundation-v${schema.version}' ||
        (schema.version == 11 &&
            (schema.migrations.length != 11 ||
                schema.migrations.last.id != 'assistant-grants' ||
                schema.migrations.last.definitionDigest != 'foundation-v11'))) {
      throw StateError('Unsupported host compatibility target');
    }
    if (schema.version < 10 ||
        schema.migrations.length < 10 ||
        schema.migrations[8].id != canonical ||
        schema.migrations[8].definitionDigest != 'foundation-v9' ||
        schema.migrations[9].id != ids[9] ||
        schema.migrations[9].definitionDigest != 'foundation-v10') {
      throw StateError('Unsupported host compatibility target');
    }
    for (var i = 0; i < 8; i++) {
      if (schema.migrations[i].version != i + 1 ||
          schema.migrations[i].id != ids[i] ||
          schema.migrations[i].definitionDigest !=
              (i == 0 ? 'muyon-host-v1' : 'foundation-v${i + 1}')) {
        throw StateError('Unsupported host compatibility target');
      }
    }
    if (db.select('PRAGMA integrity_check').single.values.single != 'ok' ||
        db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError('Invalid historical host database');
    }
    if (hasAudit) {
      final rows = db.select('SELECT * FROM host_migration_compatibility');
      if (rows.length != 1) throw StateError('Invalid compatibility facts');
      final fact = rows.single;
      final previous = digest(db) == previousRepairedFingerprints[version];
      if (!previous) validateCompleted(db, version, digest);
      final source = fact['source_version'];
      if (source is! int ||
          !fingerprints.containsKey(source) ||
          fact['repair_id'] != repairId ||
          fact['source_definition_digest'] != 'foundation-v$source' ||
          fact['source_structure_digest'] != fingerprints[source] ||
          fact['completed'] != 1 ||
          fact['canonical_migration_id'] != canonical ||
          fact['canonical_definition_digest'] != 'foundation-v9' ||
          fact['repaired_at'] is! String ||
          DateTime.tryParse(fact['repaired_at'] as String) == null) {
        throw StateError('Invalid compatibility facts');
      }
      final actual = history(db, source);
      _checkHistory(actual, source);
      if (fact['source_history_json'] != jsonEncode(actual)) {
        throw StateError('Compatibility history drift');
      }
      if (db
          .select(
            "SELECT name FROM sqlite_master WHERE name='outbound_tool_requests'",
          )
          .isEmpty) {
        throw StateError('Compatibility repair missing');
      }
      // Only the exact previous repaired shape may receive this additive guard.
      // This runs in the migration transaction, never rewrites the audit row,
      // and is rolled back with later DDL or metadata failures.
      if (previous) db.execute(insertGuardDdl);
      validateCompleted(db, version, digest);
      return true;
    }
    if (!fingerprints.containsKey(version) ||
        digest(db) != fingerprints[version] ||
        db
                .select(
                  'SELECT definition_digest FROM host_schema_state WHERE singleton=1',
                )
                .single['definition_digest'] !=
            'foundation-v$version' ||
        db
            .select(
              "SELECT name FROM sqlite_master WHERE name='outbound_tool_requests'",
            )
            .isNotEmpty ||
        db.select('SELECT COUNT(*) AS n FROM schema_migrations').single['n'] !=
            version) {
      throw StateError('Unknown historical host schema');
    }
    final original = history(db, version);
    _checkHistory(original, version);
    OutboundToolLedger.createTable(db);
    db.execute(auditDdl);
    db.execute(
      'INSERT INTO host_migration_compatibility VALUES(?,?,?,?,?,?,?,?,?)',
      [
        repairId,
        version,
        'foundation-v$version',
        fingerprints[version],
        jsonEncode(original),
        canonical,
        'foundation-v9',
        1,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return true;
  }
}
