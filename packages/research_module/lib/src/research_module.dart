import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import 'app/workbench_app.dart';
import 'core/exchange.dart';
import 'core/change_log.dart';
import 'core/store.dart';
import 'cards/card_store.dart';
import 'research_services.dart';
import 'reader/reader_page.dart';

class ResearchModule implements BusinessModule {
  @override
  ModuleManifest get manifest => ModuleManifest(id: 'research');
  @override
  ModuleSchema get schema => ModuleSchema(
    version: 9,
    definitionDigest: 'research-schema-9',
    migrations: [
      for (var i = 0; i < WorkbenchStore.migrations.length; i++)
        ModuleMigration(
          version: i + 1,
          id: 'research-${i + 1}',
          definitionDigest: 'research-schema-${i + 1}',
          migrate: WorkbenchStore.migrations[i],
        ),
      ModuleMigration(
        version: 7,
        id: 'research-7',
        definitionDigest: 'research-schema-7',
        migrate: (db) => db.execute('''
CREATE TABLE import_receipts(operation_id TEXT PRIMARY KEY, identity TEXT NOT NULL, result TEXT NOT NULL, committed_at TEXT NOT NULL);
CREATE TABLE change_log(sequence INTEGER PRIMARY KEY AUTOINCREMENT, project_id TEXT NOT NULL, operation_id TEXT NOT NULL UNIQUE);
'''),
      ),
      ModuleMigration(
        version: 8,
        id: 'research-8',
        definitionDigest: 'research-schema-8',
        migrate: installResearchKnowledgeSchema,
      ),
      ModuleMigration(
        version: 9,
        id: 'research-9',
        definitionDigest: 'research-schema-9',
        migrate: installResearchChangeLog,
      ),
    ],
  );
  @override
  List<ModuleRoute> get routes => [
    ModuleRoute(
      path: '/',
      builder: (context, session) {
        final research = session as ResearchSession;
        research.ensureActive();
        return ResearchHome(
          store: research.store,
          projectId: research.binding.nativeProjectId,
          hosted: true,
        );
      },
    ),
  ];
  @override
  Future<ResearchRuntime> activate(ModuleResources resources) async =>
      ResearchRuntime(resources);
}

class ResearchRuntime implements ModuleRuntime {
  ResearchRuntime(this.resources)
    : store = WorkbenchStore.attach(
        rootPath: resources.files.rootPath,
        database: resources.database.raw,
        managed: resources.database,
      );
  final ModuleResources resources;
  final WorkbenchStore store;

  Future<PreparedTaskSnapshot> prepareTask(SelectedInput input) async {
    final frozen = await resources.files.freeze(input);
    return ResearchExchange(store).prepareTask(frozen.path);
  }

  Future<PreparedImport> prepareTaskImport(
    PreparedTaskSnapshot task,
    ImportTarget target,
  ) async {
    if (target.binding.moduleId != 'research' ||
        target.binding.nativeProjectId != task.projectId) {
      throw StateError('Task native project ID must be preserved');
    }
    final metadata = File(p.join(task.snapshot.path, '.muyon-import.json'));
    if (await metadata.exists()) {
      throw const FormatException('Reserved import metadata path');
    }
    await metadata.writeAsString(
      jsonEncode({
        'sourceName': task.title,
        'root': null,
        'kind': 'task',
        'packageDigest': task.packageDigest,
      }),
      flush: true,
    );
    final contents = <String, List<int>>{};
    await for (final entity in task.snapshot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) contents[entity.path] = await entity.readAsBytes();
    }
    final data = PreparedResearchSnapshot(
      task.snapshot,
      null,
      task.title,
      contents,
    );
    return PreparedImport(
      target: target,
      inputDigest: _digest(data),
      stagingToken: store.storedPath(task.snapshot.path),
    );
  }

  @override
  Future<PreparedImport> prepareImport(
    SelectedInput input,
    ImportTarget target,
  ) async {
    if (target.binding.moduleId != 'research') throw StateError('Wrong module');
    final frozen = await resources.files.freeze(input);
    final snapshot = await ResearchExchange(store).prepareResearch(frozen.path);
    final metadata = File(p.join(snapshot.snapshot.path, '.muyon-import.json'));
    if (await metadata.exists()) {
      throw const FormatException('Reserved import metadata path');
    }
    final metadataBytes = utf8.encode(
      jsonEncode({'sourceName': input.displayName, 'root': snapshot.root}),
    );
    await metadata.writeAsBytes(metadataBytes, flush: true);
    final data = PreparedResearchSnapshot(
      snapshot.snapshot,
      snapshot.root,
      input.displayName,
      {...snapshot.contents, metadata.path: metadataBytes},
    );
    final token = store.storedPath(data.snapshot.path);
    return PreparedImport(
      target: target,
      inputDigest: _digest(data),
      stagingToken: token,
    );
  }

  String _digest(PreparedResearchSnapshot data) {
    final names = data.contents.keys.toList()..sort();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final name in names)
                [
                  p.relative(name, from: data.snapshot.path),
                  sha256.convert(data.contents[name]!).toString(),
                ],
            ]),
          ),
        )
        .toString();
  }

  String _identity(ImportIntent intent) => jsonEncode([
    intent.operationId,
    intent.workspaceId,
    intent.moduleId,
    intent.targetProjectId,
    intent.kind.name,
    intent.inputDigest,
    intent.stagingToken,
  ]);

  @override
  Future<ImportReceipt?> receipt(String operationId) async {
    final rows = store.db.select(
      'SELECT * FROM import_receipts WHERE operation_id=?',
      [operationId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final id = jsonDecode(row['identity'] as String) as List;
    return ImportReceipt(
      intent: ImportIntent(
        operationId: id[0] as String,
        workspaceId: id[1] as String,
        moduleId: id[2] as String,
        targetProjectId: id[3] as String,
        kind: ImportKind.values.byName(id[4] as String),
        inputDigest: id[5] as String,
        stagingToken: id[6] as String,
      ),
      result: Map<String, Object?>.from(
        jsonDecode(row['result'] as String) as Map,
      ),
      committedAt: DateTime.parse(row['committed_at'] as String),
    );
  }

  @override
  Future<ImportReceipt> commitImport(
    PreparedImport input,
    ImportIntent intent,
  ) async {
    if (!input.matches(intent) || intent.moduleId != 'research') {
      throw StateError('Import identity mismatch');
    }
    final identity = _identity(intent);
    ImportReceipt? receipt() {
      final rows = store.db.select(
        'SELECT * FROM import_receipts WHERE operation_id=?',
        [intent.operationId],
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      if (row['identity'] != identity) {
        throw StateError('Operation identity conflict');
      }
      return ImportReceipt(
        intent: intent,
        result: Map<String, Object?>.from(
          jsonDecode(row['result'] as String) as Map,
        ),
        committedAt: DateTime.parse(row['committed_at'] as String),
      );
    }

    final committed = receipt();
    if (committed != null) return committed;
    PreparedResearchSnapshot data;
    Map metadata;
    {
      final absolute = store.resolvePath(input.stagingToken);
      final snapshots = p.join(store.rootPath, 'snapshots');
      if (![
        'research',
        'tasks',
      ].any((group) => p.isWithin(p.join(snapshots, group), absolute))) {
        throw StateError('Invalid staging token');
      }
      final contents = <String, List<int>>{};
      await for (final entity in Directory(
        absolute,
      ).list(recursive: true, followLinks: false)) {
        if (entity is Link) throw StateError('Staging contains symbolic links');
        if (entity is File) contents[entity.path] = await entity.readAsBytes();
      }
      metadata = jsonDecode(
        utf8.decode(contents[p.join(absolute, '.muyon-import.json')]!),
      ) as Map;
      data = PreparedResearchSnapshot(
        Directory(absolute),
        metadata['root'] as String?,
        metadata['sourceName'] as String,
        contents,
      );
    }
    if (_digest(data) != input.inputDigest) {
      throw StateError('Staging digest mismatch');
    }
    final prepared = data;
    return resources.database.write((db) {
      final previous = receipt();
      if (previous != null) return previous;
      final exists = db.select('SELECT 1 FROM projects WHERE id=?', [
        intent.targetProjectId,
      ]).isNotEmpty;
      if (input.target.kind == ImportKind.create && exists) {
        throw StateError('Project already exists');
      }
      if (input.target.kind == ImportKind.refresh && !exists) {
        throw StateError('Project does not exist');
      }
      final Map<String, Object?> result;
      if (metadata['kind'] == 'task') {
        final task = PreparedTaskSnapshot(
          snapshot: prepared.snapshot,
          data: WorkbenchStore.decode(
            utf8.decode(
              prepared.contents[p.join(prepared.snapshot.path, 'task.json')]!,
            ),
          ),
          packageDigest: metadata['packageDigest'] as String,
        );
        if (task.projectId != intent.targetProjectId) {
          throw StateError('Task native identity mismatch');
        }
        final imported = ResearchExchange(store)
            .commitTask(task, ownTransaction: false);
        result = {
          'nativeProjectId': imported.projectId,
          'title': imported.title,
          'taskId': imported.id,
          'taskRevision': imported.revision,
        };
      } else {
        final project = ResearchExchange(store).commitResearch(
          prepared,
          createProjectId: intent.targetProjectId,
          intoProjectId: input.target.kind == ImportKind.refresh
              ? intent.targetProjectId
              : null,
          ownTransaction: false,
        );
        result = {'nativeProjectId': project.id, 'title': project.title};
      }
      final now = DateTime.now().toUtc();
      db.execute('INSERT INTO import_receipts VALUES(?,?,?,?)', [
        intent.operationId,
        identity,
        jsonEncode(result),
        now.toIso8601String(),
      ]);
      db.execute(
        'INSERT INTO change_log(project_id,operation_id) VALUES(?,?)',
        [intent.targetProjectId, intent.operationId],
      );
      return ImportReceipt(intent: intent, result: result, committedAt: now);
    });
  }

  @override
  Future<ResearchSession> openSession(WorkspaceBinding binding) async {
    if (binding.moduleId != 'research' ||
        !store.projects().any((p) => p.id == binding.nativeProjectId)) {
      throw StateError('Missing research workspace binding');
    }
    return ResearchSession(store.scoped(binding.nativeProjectId), binding);
  }
}

class ResearchSession implements ModuleSession {
  ResearchSession(this.store, this.binding);
  final WorkbenchStore store;
  final WorkspaceBinding binding;
  bool _disposed = false;
  late final ResearchServices services = ResearchServices(
    store,
    binding.nativeProjectId,
    ensureActive: ensureActive,
  );
  void ensureActive() {
    if (_disposed) throw StateError('Session disposed');
  }

  @override
  Future<ObjectView?> resolve(ObjectRef ref) async => _resolve(ref);

  ObjectView? _resolve(ObjectRef ref) {
    ensureActive();
    if (ref.moduleId != 'research' ||
        ref.nativeProjectId != binding.nativeProjectId) {
      return null;
    }
    final project = binding.nativeProjectId;
    final id = ref.objectId;
    ObjectView? view(String title, {String? revision, String? digest}) {
      if ((ref.revisionRef != null && ref.revisionRef != revision) ||
          (ref.contentDigest != null && ref.contentDigest != digest)) {
        return null;
      }
      return ObjectView(ref: ref, title: title);
    }

    switch (ref.objectType) {
      case 'document':
        final rows = store.db.select(
          'SELECT relative_path,sha256 FROM documents WHERE id=? AND project_id=?',
          [id, project],
        );
        if (rows.isNotEmpty) {
          return view(
            rows.single['relative_path'] as String,
            digest: rows.single['sha256'] as String?,
          );
        }
        final canonical = store.db.select(
          'SELECT d.file_name,d.digest FROM rk_documents d JOIN canonical_object_map m ON m.object_key=d.object_key WHERE m.local_object_id=? AND m.local_project_id=? AND m.object_type=? AND d.deleted=0',
          [id, project, 'document'],
        );
        if (canonical.length != 1) return null;
        return view(
          canonical.single['file_name'] as String,
          digest: canonical.single['digest'] as String,
        );
      case 'entry':
      case 'outline':
      case 'section':
        final (table, title) = switch (ref.objectType) {
          'entry' => ('entries', 'title'),
          'outline' => ('outline', 'heading'),
          _ => ('sections', 'heading'),
        };
        final rows = store.db.select(
          'SELECT $title FROM $table WHERE id=? AND project_id=?',
          [id, project],
        );
        return rows.isEmpty ? null : view(rows.single[title] as String? ?? id);
      case 'task':
        final rows = store.db.select(
          'SELECT title,revision FROM tasks WHERE id=? AND project_id=? '
          '${ref.revisionRef == null ? '' : 'AND CAST(revision AS TEXT)=? '}ORDER BY revision DESC LIMIT 1',
          [id, project, if (ref.revisionRef != null) ref.revisionRef],
        );
        return rows.isEmpty
            ? null
            : view(
                rows.single['title'] as String? ?? id,
                revision: '${rows.single['revision']}',
              );
      case 'run':
        final rows = store.db.select(
          'SELECT t.title,r.status,r.task_revision FROM runs r JOIN tasks t ON t.id=r.task_id AND t.revision=r.task_revision WHERE r.id=? AND t.project_id=?',
          [id, project],
        );
        return rows.isEmpty
            ? null
            : view(
                '${rows.single['title']} — ${rows.single['status']}',
                revision: '${rows.single['task_revision']}',
              );
      case 'card':
        final rows = store.db.select(
          'SELECT v.envelope,v.revision_id,v.digest FROM canonical_object_map m '
          'JOIN rk_cards c ON c.object_key=m.object_key '
          'JOIN rk_revisions v ON v.object_key=m.object_key AND v.revision_id=${ref.revisionRef == null ? 'c.head_revision_id' : '?'} '
          'WHERE m.local_object_id=? AND m.local_project_id=? AND m.object_type=?',
          [if (ref.revisionRef != null) ref.revisionRef, id, project, 'card'],
        );
        if (rows.isEmpty) return null;
        final body =
            (jsonDecode(rows.single['envelope'] as String)
                    as Map)['bodyMarkdown']
                as String;
        return view(
          body.isEmpty
              ? id
              : body.substring(0, body.length > 240 ? 240 : body.length),
          revision: rows.single['revision_id'] as String,
          digest: rows.single['digest'] as String,
        );
      default:
        return null;
    }
  }

  @override
  Future<void> flush() async {
    ensureActive();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  /// Recheck at navigation time: a previously resolved reference can be stale.
  /// Other object types need B-owned focused UI entry points before wiring.
  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) {
    if (_resolve(ref) == null || ref.objectType != 'document') return null;
    final document = store
        .documents(binding.nativeProjectId)
        .where((doc) => doc.id == ref.objectId)
        .firstOrNull;
    // Canonical package documents have bytes but no existing ReaderPage file
    // adapter yet. Do not advertise a project overview as their object page.
    return document == null
        ? null
        : ReaderPage(store: store, document: document);
  }
}
