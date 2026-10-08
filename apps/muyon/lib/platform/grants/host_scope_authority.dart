import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../workspace/workspace_repository.dart';
import '../storage_manager.dart';

/// Constructed only by trusted host adapters, never decoded from tool JSON.
/// A nullable root/authority means the adapter cannot prove complete coverage.
class HostScopeSource {
  HostScopeSource({
    required ManagedConnection database,
    required this.authorityRevision,
    required this.managedFilesRoot,
  }) : connection = (() => database);
  HostScopeSource.deferred({
    required this.connection,
    required this.authorityRevision,
    required this.managedFilesRoot,
  });
  final ManagedConnection? Function() connection;
  final String? Function() authorityRevision;
  final String? Function() managedFilesRoot;
  final String _identity = const Uuid().v4();
  final Map<String, String> _managedNamespaces = {};
}

class HostScopeAuthority {
  HostScopeAuthority({
    required this.workspaces,
    required Map<String, HostScopeSource> sources,
    List<HostScopeSource> contextSources = const [],
  }) : sources = Map.unmodifiable(sources),
       contextSources = List.unmodifiable(contextSources);
  final WorkspaceRepository workspaces;
  final Map<String, HostScopeSource> sources;
  final List<HostScopeSource> contextSources;
  static final _ownerIdentities = Expando<String>();

  /// Synchronous source proof, safe to recheck in the host signing queue.
  /// Host grant/review writes do not count as source changes. Null means that
  /// this adapter cannot establish authority, so automatic signing is denied.
  String? stamp(AssistantScope scope, Set<String> allowedModuleIds) {
    try {
      final modules = scope.kind == AssistantScopeKind.selectedObjects
          ? scope.objects.map((r) => r.moduleId).toSet()
          : allowedModuleIds;
      if (modules.isEmpty || !allowedModuleIds.containsAll(modules)) {
        return null;
      }
      final host = _hostSnapshot(scope, modules);
      if (host == null) return null;
      final snapshots = <Object?>[];
      final checks = <(HostScopeSource, Object)>[];
      for (final id in modules.toList()..sort()) {
        final source = sources[id];
        if (source == null) return null;
        final snapshot = _sourceSnapshot(source);
        if (snapshot == null) return null;
        snapshots.add([id, snapshot]);
        checks.add((source, snapshot));
      }
      for (final source in contextSources) {
        final snapshot = _sourceSnapshot(source);
        if (snapshot == null) return null;
        snapshots.add(['context', snapshot]);
        checks.add((source, snapshot));
      }
      // Detect a previous source changing while later sources/files were
      // inspected. Two matching collections are required, not a mixed view.
      for (final check in checks) {
        if (jsonEncode(check.$2) != jsonEncode(_sourceSnapshot(check.$1))) {
          return null;
        }
      }
      if (host != _hostSnapshot(scope, modules)) return null;
      return sha256
          .convert(
            utf8.encode(
              jsonEncode([
                scope.toJson(),
                allowedModuleIds.toList()..sort(),
                host,
                snapshots,
              ]),
            ),
          )
          .toString();
    } catch (_) {
      return null;
    }
  }

  String? _hostSnapshot(AssistantScope scope, Set<String> modules) {
    final authority = workspaces.scopeAuthorityRevision;
    if (authority == null) return null;
    final db = workspaces.database.raw;
    final workspace = scope.workspaceId;
    if (workspace != null &&
        db.select('SELECT id FROM workspaces WHERE id=?', [
          workspace,
        ]).isEmpty) {
      return null;
    }
    final bindings = db
        .select(
          'SELECT workspace_id,module_id,native_project_id FROM workspace_module_bindings ORDER BY workspace_id,module_id',
        )
        .where((r) => modules.contains(r['module_id']))
        .map((r) => [r['workspace_id'], r['module_id'], r['native_project_id']])
        .toList();
    if (workspace != null && scope.kind == AssistantScopeKind.selectedObjects) {
      for (final ref in scope.objects) {
        if (!bindings.any(
          (b) =>
              b[0] == workspace &&
              b[1] == ref.moduleId &&
              b[2] == ref.nativeProjectId,
        )) {
          return null;
        }
      }
    }
    return jsonEncode([
      authority,
      workspace,
      if (scope.kind == AssistantScopeKind.global)
        db
            .select('SELECT id FROM workspaces ORDER BY id')
            .map((r) => r['id'])
            .toList(),
      bindings,
    ]);
  }

  Object? _sourceSnapshot(HostScopeSource source) {
    final database = source.connection();
    if (database == null || !database.scopeAuthorityStable) return null;
    final authority = source.authorityRevision();
    final root = source.managedFilesRoot();
    if (authority == null || root == null) return null;
    final namespace = _namespace(root);
    if (namespace == null ||
        (source._managedNamespaces[root] ??= namespace) != namespace) {
      return null;
    }
    String version() => jsonEncode(
      database.raw
          .select(
            'SELECT total_changes() AS local_changes, data_version FROM pragma_data_version',
          )
          .single
          .values
          .toList(),
    );
    final before = version();
    final files = _files(root);
    if (files == null ||
        before != version() ||
        !database.scopeAuthorityStable ||
        authority != source.authorityRevision() ||
        root != source.managedFilesRoot() ||
        namespace != _namespace(root) ||
        !identical(database, source.connection())) {
      return null;
    }
    final owner = _ownerIdentities[database] ??= const Uuid().v4();
    return [source._identity, owner, authority, before, namespace, files];
  }

  static String? _namespace(String root) {
    if (!p.isAbsolute(root)) return null;
    var anchor = p.normalize(root);
    while (FileSystemEntity.typeSync(anchor, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(anchor);
      if (parent == anchor) return null;
      anchor = parent;
    }
    if (FileSystemEntity.typeSync(anchor, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    return p.normalize(
      p.join(
        Directory(anchor).resolveSymbolicLinksSync(),
        p.relative(root, from: anchor),
      ),
    );
  }

  /// A bounded complete tree, not mtime or projection-only evidence. Large or
  /// unmanaged content stays on the manual path rather than blocking the UI.
  static String? _files(String root) {
    if (!p.isAbsolute(root)) return null;
    final rootType = FileSystemEntity.typeSync(root, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) {
      return sha256
          .convert(utf8.encode(jsonEncode(['absent', root])))
          .toString();
    }
    if (rootType != FileSystemEntityType.directory) {
      return null;
    }
    final entries = Directory(root).listSync(
      recursive: true,
      followLinks: false,
    )..sort((a, b) => a.path.compareTo(b.path));
    if (entries.length > 1024) return null;
    var bytes = 0;
    final content = <Object?>[];
    for (final entry in entries) {
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        content.add([p.relative(entry.path, from: root), 'directory']);
        continue;
      }
      if (type != FileSystemEntityType.file) return null;
      final file = File(entry.path);
      final before = file.statSync();
      bytes += before.size;
      if (bytes > 8 * 1024 * 1024) return null;
      final data = file.readAsBytesSync();
      final after = file.statSync();
      if (data.length != before.size ||
          before.size != after.size ||
          before.modified != after.modified ||
          before.type != after.type) {
        return null;
      }
      content.add([
        p.relative(entry.path, from: root),
        sha256.convert(data).toString(),
      ]);
    }
    final after =
        Directory(root)
            .listSync(recursive: true, followLinks: false)
            .map((e) => e.path)
            .toList()
          ..sort();
    if (jsonEncode(entries.map((e) => e.path).toList()) != jsonEncode(after)) {
      return null;
    }
    return sha256.convert(utf8.encode(jsonEncode(content))).toString();
  }
}
