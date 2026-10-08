import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'host_schema_compatibility.dart';

/// The sole connection and transaction owner of one physical database.
class ManagedConnection implements ManagedDatabase, ExclusiveDatabase {
  ManagedConnection(this.raw);
  @override
  final Database raw;
  Future<void> _tail = Future<void>.value();
  bool _closing = false;
  int _pendingAuthorityOperations = 0;

  /// Scope authority cannot use an open transaction or a closed connection.
  bool get scopeAuthorityStable =>
      !_closing && _pendingAuthorityOperations == 0 && raw.autocommit;

  /// Called after every committed write (and every exclusive operation), so
  /// derived projections can catch up without each caller remembering to.
  void Function()? onCommit;
  Future<void>? _closeFuture;

  @override
  Future<T> write<T>(T Function(Database) body) {
    if (_closing) return Future.error(StateError('Database is closing'));
    _pendingAuthorityOperations++;
    final result = Completer<T>();
    _tail = _tail.then((_) {
      var begun = false;
      try {
        raw.execute('BEGIN IMMEDIATE');
        begun = true;
        final value = body(raw);
        if (value is Future) {
          throw StateError('Transaction body must be synchronous');
        }
        raw.execute('COMMIT');
        result.complete(value);
        onCommit?.call();
      } catch (error, stack) {
        if (begun) raw.execute('ROLLBACK');
        result.completeError(error, stack);
      } finally {
        _pendingAuthorityOperations--;
      }
    });
    return result.future;
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    await _tail;
    raw.close();
  }

  /// Existing modules own their short SQL transactions. Serialize the whole
  /// operation without adding an outer BEGIN around asynchronous file work.
  @override
  Future<T> exclusiveAsync<T>(FutureOr<T> Function(Database) body) {
    if (_closing) return Future.error(StateError('Database is closing'));
    _pendingAuthorityOperations++;
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await body(raw));
        onCommit?.call();
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        _pendingAuthorityOperations--;
      }
    });
    return result.future;
  }
}

typedef SchemaOpened = Future<void> Function(
  String moduleId,
  ModuleSchema schema,
  Database db,
);
typedef SchemaFailed = Future<void> Function(
  String moduleId,
  ModuleSchema schema,
  int? observedVersion,
  Object error,
);

class StorageManager {
  StorageManager(this.rootPath);
  final String rootPath;

  /// Catalog hooks; every open result passes through here so no caller can
  /// forget to record it. Set once the host database is available.
  SchemaOpened? onOpened;
  SchemaFailed? onFailed;

  static final Set<String> _openRoots = {};

  /// Whether a manager in this process holds [rootPath]. Other processes are
  /// excluded by the application lock file.
  static bool isOpen(String rootPath) =>
      _openRoots.contains(p.canonicalize(rootPath));

  Future<void>? _gate;

  /// Runs [body] with every open database's write queue held at once and new
  /// opens deferred, so no commit lands mid-snapshot. [body] receives the
  /// open connections by module id and must not write through their queues.
  Future<T> quiesce<T>(
    Future<T> Function(Map<String, ManagedConnection> open) body,
  ) async {
    if (_closing) throw StateError('Storage is closing');
    while (_gate != null) {
      await _gate;
    }
    final done = Completer<void>();
    _gate = done.future;
    try {
      for (final pending in _opening.values.toList()) {
        try {
          await pending;
        } catch (_) {
          /* Failed opens are not part of the snapshot. */
        }
      }
      final open = Map.of(_connections);
      Future<T> hold(List<ManagedConnection> rest) => rest.isEmpty
          ? body(open)
          : rest.first.exclusiveAsync((_) => hold(rest.sublist(1)));
      return await hold(open.values.toList());
    } finally {
      _gate = null;
      done.complete();
    }
  }

  final Map<String, Future<ManagedConnection>> _opening = {};
  final Map<String, ManagedConnection> _connections = {};

  /// Host-only observation; never opens a DB to manufacture authority.
  ManagedConnection? connectionIfOpen(String moduleId) =>
      _connections[moduleId];
  bool _closing = false;
  Future<void>? _closeFuture;
  RandomAccessFile? _applicationLock;

  static String structureDigest(Database db) {
    final rows = db.select(
      "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
    );
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final row in rows)
                [row['type'], row['name'], row['tbl_name'], row['sql']],
            ]),
          ),
        )
        .toString();
  }

  Future<ManagedConnection> open(String moduleId, ModuleSchema schema) {
    if (_closing) return Future.error(StateError('Storage is closing'));
    final gate = _gate;
    if (gate != null) return gate.then((_) => open(moduleId, schema));
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(moduleId)) {
      return Future.error(ArgumentError.value(moduleId, 'moduleId'));
    }
    final existing = _connections[moduleId];
    if (existing != null) return Future.value(existing);
    final pending = _opening[moduleId];
    if (pending != null) return pending;
    final operation = _open(moduleId, schema);
    _opening[moduleId] = operation;
    operation.then(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _opening.remove(moduleId);
      },
    );
    return operation;
  }

  Future<ManagedConnection> _open(String moduleId, ModuleSchema schema) async {
    final directory = Directory(
      moduleId == 'muyon' ? rootPath : p.join(rootPath, 'modules', moduleId),
    );
    directory.createSync(recursive: true);
    if (moduleId == 'muyon' && _applicationLock == null) {
      final lock = File(p.join(rootPath, 'application.lock'))
          .openSync(mode: FileMode.append);
      try {
        lock.lockSync(FileLock.exclusive);
        _applicationLock = lock;
        _openRoots.add(p.canonicalize(rootPath));
      } catch (_) {
        lock.closeSync();
        throw StateError('Muyon data is already open in another process');
      }
    }
    final db = sqlite3.open(p.join(directory.path, '$moduleId.sqlite'));
    final owner = ManagedConnection(db);
    int? observed;
    try {
      db.execute('PRAGMA foreign_keys=ON');
      final version = observed = db.userVersion;
      if (version > schema.version) {
        throw StateError('unsupported_schema: v$version > v${schema.version}');
      }
      if (version > 0) {
        final metadata = db.select(
          'SELECT definition_digest,structure_digest FROM host_schema_state WHERE singleton=1',
        );
        if (metadata.isEmpty ||
            metadata.first['structure_digest'] != structureDigest(db)) {
          throw StateError('Schema structure drift');
        }
        if (version == schema.version &&
            metadata.first['definition_digest'] != schema.definitionDigest) {
          throw StateError('Schema definition drift');
        }
      }
      await owner.write((database) {
        database.execute(
          'CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY,migration_id TEXT UNIQUE NOT NULL,definition_digest TEXT NOT NULL,applied_at TEXT NOT NULL)',
        );
        database.execute(
          'CREATE TABLE IF NOT EXISTS host_schema_state(singleton INTEGER PRIMARY KEY CHECK(singleton=1),definition_digest TEXT NOT NULL,structure_digest TEXT NOT NULL)',
        );
        final repaired =
            moduleId == 'muyon' &&
            HostSchemaCompatibility.prepare(database, schema, structureDigest);
        var current = version;
        for (final migration in schema.migrations) {
          if (migration.version <= current) {
            final rows = database.select(
              'SELECT migration_id,definition_digest,applied_at FROM schema_migrations WHERE version=?',
              [migration.version],
            );
            if (rows.isEmpty ||
                (rows.first['migration_id'] != migration.id &&
                    !(repaired &&
                        migration.version == 9 &&
                        migration.id == HostSchemaCompatibility.canonical &&
                        rows.first['migration_id'] ==
                            HostSchemaCompatibility.reserved)) ||
                rows.first['definition_digest'] != migration.definitionDigest ||
                rows.first['applied_at'] is! String ||
                DateTime.tryParse(rows.first['applied_at'] as String) == null) {
              throw StateError('Migration history drift');
            }
            continue;
          }
          if (migration.version != current + 1) {
            throw StateError('Migration gap');
          }
          migration.migrate(database);
          database.execute('INSERT INTO schema_migrations VALUES(?,?,?,?)', [
            migration.version,
            migration.id,
            migration.definitionDigest,
            DateTime.now().toUtc().toIso8601String(),
          ]);
          current = migration.version;
        }
        if (current != schema.version) {
          throw StateError('Incomplete migrations');
        }
        if (database
                .select('SELECT COUNT(*) AS n FROM schema_migrations')
                .single['n'] !=
            current) {
          throw StateError('Migration history drift');
        }
        if (repaired) {
          HostSchemaCompatibility.validateCompleted(
            database,
            current,
            structureDigest,
          );
        } else if (moduleId == 'muyon' &&
            HostSchemaCompatibility.isCanonicalTarget(schema)) {
          HostSchemaCompatibility.validateCanonical(
            database,
            current,
            structureDigest,
          );
        }
        if (database.select('PRAGMA foreign_key_check').isNotEmpty) {
          throw StateError('Invalid foreign keys');
        }
        database.userVersion = current;
        database.execute(
          'INSERT OR REPLACE INTO host_schema_state VALUES(1,?,?)',
          [schema.definitionDigest, structureDigest(database)],
        );
      });
      await onOpened?.call(moduleId, schema, db);
      _connections[moduleId] = owner;
      return owner;
    } catch (error) {
      await owner.close();
      _opening.remove(moduleId);
      try {
        await onFailed?.call(moduleId, schema, observed, error);
      } catch (_) {
        // The open error below is the one callers must see; a catalog write
        // failure here (e.g. host closing) must not replace it.
      }
      rethrow;
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closing = true;
    for (final opening in _opening.values.toList()) {
      try {
        await opening;
      } catch (_) {
        /* Failed opens already closed. */
      }
    }
    for (final connection in _connections.values) {
      await connection.close();
    }
    _connections.clear();
    _opening.clear();
    if (_applicationLock != null) _openRoots.remove(p.canonicalize(rootPath));
    _applicationLock?.closeSync();
    _applicationLock = null;
  }
}
