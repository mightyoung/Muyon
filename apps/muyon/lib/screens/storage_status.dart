import 'package:flutter/foundation.dart';

import '../app/bootstrap.dart';

/// One row of the host `schema_catalog` table.
@immutable
class CatalogRow {
  const CatalogRow({
    required this.moduleId,
    required this.targetVersion,
    required this.observedVersion,
    required this.status,
    required this.lastError,
  });
  final String moduleId;
  final int targetVersion;
  final int? observedVersion;

  /// `ready` or `blocked`.
  final String status;
  final String? lastError;
  bool get blocked => status != 'ready';
}

/// Read-only snapshot of what the host knows about module and database health.
@immutable
class StorageStatus {
  const StorageStatus({
    required this.rootPath,
    required this.unavailableModules,
    required this.catalog,
    required this.projectionErrors,
  });

  final String rootPath;

  /// `host.registry.unavailable`: module id → reason.
  final Map<String, String> unavailableModules;
  final List<CatalogRow> catalog;

  /// `host.projections.errors`: module id → last projection failure.
  final Map<String, String> projectionErrors;

  bool get hasProblems =>
      unavailableModules.isNotEmpty ||
      projectionErrors.isNotEmpty ||
      catalog.any((row) => row.blocked);

  factory StorageStatus.read(MuyonHost host) {
    final rows = host.workspaces.database.raw.select(
      'SELECT module_id,target_version,observed_version,migration_status,'
      'last_error FROM schema_catalog ORDER BY module_id',
    );
    return StorageStatus(
      rootPath: host.storage.rootPath,
      unavailableModules: host.registry.unavailable,
      catalog: [
        for (final row in rows)
          CatalogRow(
            moduleId: row['module_id'] as String,
            targetVersion: row['target_version'] as int,
            observedVersion: row['observed_version'] as int?,
            status: row['migration_status'] as String,
            lastError: row['last_error'] as String?,
          ),
      ],
      projectionErrors: host.projections.errors,
    );
  }
}
