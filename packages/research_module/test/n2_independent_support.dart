// N2-A independent boundary tests: task-local helpers only.
//
// Every database is a real temporary SQLite file migrated through the real
// ResearchModule schema. Business writes go through real production entry
// points (WorkbenchStore.deleteSection, the registered research
// `delete_section` write handler). Fixture rows are synthetic.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

/// ManagedDatabase over a real file connection (same contract as the
/// package's TestDatabase: BEGIN IMMEDIATE / COMMIT / ROLLBACK).
class N2IndependentDatabase implements ManagedDatabase {
  N2IndependentDatabase(this.raw);
  @override
  final Database raw;
  Future<void> _tail = Future.value();
  @override
  Future<T> write<T>(T Function(Database) body) {
    final result = _tail.then((_) {
      raw.execute('BEGIN IMMEDIATE');
      try {
        final value = body(raw);
        raw.execute('COMMIT');
        return value;
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

class N2IndependentFiles implements ModuleFiles {
  N2IndependentFiles(this.rootPath);
  @override
  final String rootPath;
  @override
  Future<SelectedInput> freeze(SelectedInput input) async => input;
}

/// Captures the real research tool handlers exactly as registered.
class N2IndependentRegistrar implements ToolRegistrar {
  final Map<String, ModuleToolHandler> handlers = {};
  final Map<String, ToolSpec> specs = {};
  @override
  String get moduleId => 'research';
  @override
  void read(ToolSpec spec, ModuleToolHandler handler) {
    handlers[spec.name] = handler;
    specs[spec.name] = spec;
  }

  @override
  void write(WriteToolSpec spec, ModuleToolHandler handler) {
    handlers[spec.name] = handler;
    specs[spec.name] = spec;
  }

  @override
  void external(ExternalToolSpec spec, ModuleToolHandler handler) {
    handlers[spec.name] = handler;
    specs[spec.name] = spec;
  }

  @override
  HostChannel channel(ChannelSpec spec) =>
      throw UnsupportedError('N2 tests never open an external channel');
}

class N2IndependentToolContext implements ModuleToolContext {
  N2IndependentToolContext(this.call, this._runtime);
  @override
  final ToolCallContext call;
  final ResearchRuntime _runtime;
  @override
  Future<T> runtime<T extends ModuleRuntime>() async => _runtime as T;
}

/// One migrated research database file plus its real runtime.
class N2IndependentWorkspace {
  N2IndependentWorkspace._(this.root, this.path, this.database, this.runtime);

  final Directory root;
  final String path;
  final N2IndependentDatabase database;
  final ResearchRuntime runtime;

  WorkbenchStore get store => runtime.store;
  Database get raw => database.raw;

  static Future<N2IndependentWorkspace> create(String label) async {
    final root = Directory.systemTemp.createTempSync('n2-independent-$label-');
    final path = '${root.path}/research.sqlite';
    final raw = sqlite3.open(path);
    raw.execute('PRAGMA journal_mode=WAL');
    raw.execute('PRAGMA foreign_keys=ON');
    for (final step in ResearchModule().schema.migrations) {
      step.migrate(raw);
    }
    return _attach(root, path, raw);
  }

  static Future<N2IndependentWorkspace> _attach(
    Directory root,
    String path,
    Database raw,
  ) async {
    final database = N2IndependentDatabase(raw);
    final resources = ModuleResources(
      database: database,
      files: N2IndependentFiles('${root.path}/files'),
      capabilities: CapabilityRegistry().forModule('research', allowed: {}),
    );
    Directory('${root.path}/files').createSync();
    final runtime = await ResearchModule().activate(resources);
    return N2IndependentWorkspace._(root, path, database, runtime);
  }

  /// Byte-identical isolated copy (VACUUM INTO), opened as its own runtime.
  Future<N2IndependentWorkspace> isolatedCopy(String label) async {
    final root = Directory.systemTemp.createTempSync('n2-independent-$label-');
    final path = '${root.path}/research.sqlite';
    raw.execute('VACUUM INTO ?', [path]);
    final copy = sqlite3.open(path);
    copy.execute('PRAGMA journal_mode=WAL');
    copy.execute('PRAGMA foreign_keys=ON');
    return _attach(root, path, copy);
  }

  void close() {
    raw.close();
    root.deleteSync(recursive: true);
  }
}

/// A second, read-only connection to the same file. It never shares the
/// writer's connection state, so total_changes() on the writer is irrelevant.
class N2IndependentReader {
  N2IndependentReader(String path)
    : db = sqlite3.open(path, mode: OpenMode.readOnly);
  final Database db;

  /// `PRAGMA data_version` changes on this connection whenever ANY other
  /// connection commits a change to the file.
  int dataVersion() =>
      db.select('PRAGMA data_version').single.values.first as int;

  /// Every table (business tables, muyon_change_log, imports/receipts/ledgers
  /// living in this database) plus the schema itself, row-order independent.
  Map<String, Object?> snapshot() {
    final out = <String, Object?>{};
    for (final t in db.select(
      "SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
    )) {
      out['schema:${t['type']}:${t['name']}'] = t['sql'];
      if (t['type'] != 'table') continue;
      final rows = [
        for (final r in db.select('SELECT * FROM "${t['name']}"'))
          jsonEncode(Map<String, Object?>.from(r)),
      ]..sort();
      out['rows:${t['name']}'] = rows;
    }
    return out;
  }

  void close() => db.close();
}

String n2IndependentFileDigest(String path) {
  final file = File(path);
  if (!file.existsSync()) return 'absent';
  return sha256.convert(file.readAsBytesSync()).toString();
}

/// Row sets per table, for set-difference comparisons between two files.
Map<String, Set<String>> n2IndependentRowSets(Database db) => {
  for (final t in db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  ))
    t['name'] as String: {
      for (final r in db.select('SELECT * FROM "${t['name']}"'))
        jsonEncode(Map<String, Object?>.from(r)),
    },
};
