import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import '../workspace/workspace_repository.dart';
import 'storage_manager.dart';

/// Keeps `schema_catalog` in the host database in step with what each
/// physical database actually is. The catalog is for inspection and
/// management only; it never drives migrations.
///
/// Every [StorageManager.open] result is recorded, so a catalog row lagging
/// behind its database (e.g. a crash between module migration and catalog
/// write) is corrected the next time that database is opened.
abstract final class SchemaCatalog {
  static Future<void> attach(
    StorageManager storage,
    ManagedDatabase host,
  ) async {
    storage.onOpened = (id, schema, db) => _ready(host, id, schema, db);
    storage.onFailed = (id, schema, observed, error) =>
        _blocked(host, id, schema, observed, error);
    await _ready(host, 'muyon', WorkspaceRepository.schema, host.raw);
  }

  static Future<void> _ready(
    ManagedDatabase host,
    String id,
    ModuleSchema schema,
    Database db,
  ) {
    final observedVersion = db.userVersion;
    final observedDigest = StorageManager.structureDigest(db);
    return host.write(
      (h) => _upsert(
        h,
        id,
        schema,
        observedVersion,
        observedDigest,
        'ready',
        null,
      ),
    );
  }

  static Future<void> _blocked(
    ManagedDatabase host,
    String id,
    ModuleSchema schema,
    int? observedVersion,
    Object error,
  ) => host.write(
    (h) => _upsert(h, id, schema, observedVersion, null, 'blocked', '$error'),
  );

  static void _upsert(
    Database h,
    String id,
    ModuleSchema schema,
    int? observedVersion,
    String? observedDigest,
    String status,
    String? error,
  ) => h.execute(
    'INSERT OR REPLACE INTO schema_catalog(module_id,target_version,target_digest,'
    'observed_version,observed_digest,migration_status,last_error) '
    'VALUES(?,?,?,?,?,?,?)',
    [
      id,
      schema.version,
      schema.definitionDigest,
      observedVersion,
      observedDigest,
      status,
      error,
    ],
  );
}
