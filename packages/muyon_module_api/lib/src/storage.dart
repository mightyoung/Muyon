import 'dart:async';

import 'package:sqlite3/sqlite3.dart';

/// The host owns migration and connection lifetime. A write callback must be
/// synchronous; file preparation and network work belong outside the queue.
abstract interface class ManagedDatabase {
  Database get raw;
  Future<T> write<T>(T Function(Database database) body);
}

/// Optional sub-interface for connections that can run one exclusive
/// background body (inquiry's `Store.attach`). [ManagedDatabase] is unchanged.
abstract interface class ExclusiveDatabase implements ManagedDatabase {
  Future<T> exclusiveAsync<T>(FutureOr<T> Function(Database) body);
}

class ModuleMigration {
  const ModuleMigration({
    required this.version,
    required this.id,
    required this.definitionDigest,
    required this.migrate,
  });
  final int version;
  final String id;
  final String definitionDigest;
  final void Function(Database database) migrate;
}

class ModuleSchema {
  ModuleSchema({
    required this.version,
    required this.definitionDigest,
    required List<ModuleMigration> migrations,
  }) : migrations = List.unmodifiable(migrations) {
    if (version < 1 ||
        definitionDigest.isEmpty ||
        migrations.length != version) {
      throw ArgumentError(
        'Schema requires a complete versioned migration list',
      );
    }
    final ids = <String>{};
    for (var i = 0; i < migrations.length; i++) {
      final migration = migrations[i];
      if (migration.version != i + 1 ||
          migration.id.isEmpty ||
          migration.definitionDigest.isEmpty ||
          !ids.add(migration.id)) {
        throw ArgumentError(
          'Migrations must be ordered, contiguous and unique',
        );
      }
    }
    if (migrations.last.definitionDigest != definitionDigest) {
      throw ArgumentError('Latest migration must match schema digest');
    }
  }
  final int version;
  final String definitionDigest;
  final List<ModuleMigration> migrations;
}
