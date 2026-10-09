import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import 'app/object_pages.dart';
import 'core/card_title.dart';
import 'core/exchange.dart';
import 'core/change_log.dart';
import 'core/models.dart';
import 'core/research_kinds.dart';
import 'core/store.dart';
import 'cards/card_store.dart';
import 'exchange/research_package.dart';
import 'research_services.dart';
import 'module_tools.dart';
import 'module_declarations.dart';
import 'reader/reader_page.dart';

class ResearchModule implements BusinessModuleV2 {
  @override
  ModuleManifest get manifest => ModuleManifest(
    id: 'research', apiVersion: 2, displayName: '科研工作台',
    tagline: '原文阅读、批注、研究过程和成果', iconKey: 'menu_book',
    capabilities: {
      const CapabilityRequest(id: 'knowledge', reason: '科研检索；scoped facade 未就绪时拒绝'),
      const CapabilityRequest(id: 'models', reason: '科研模型；scoped facade 未就绪时拒绝'),
    },
    features: {ModuleFeature.importPipeline},
  );
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
  List<ModuleRoute> get routes => const [];
  @override
  ModuleOntology get ontology => researchOntology;
  @override
  CapabilityCoverage get coverage => researchCoverage;
  @override
  List<AuxiliarySchema> get auxiliarySchemas => const [];
  @override
  List<SearchSource> get searchSources => const []; // REG-3b preserves host search.
  @override
  List<ModuleSection> get sections => [ModuleSection(
    id: 'research', label: '科研工作台', requiresWorkspace: true,
    // The host retains its workspace navigation bridge for this bound section.
    builder: (context, host) => host is WorkspaceSectionHost
      ? host.workspacePage(context) : const Text('请在工作区打开科研项目'),
  )];
  @override
  void registerTools(ToolRegistrar registrar) => registerResearchTools(registrar);

  @override
  Future<ResearchRuntime> activate(ModuleResources resources) async =>
      ResearchRuntime(resources);
}

class ResearchRuntime implements ModuleRuntime, ImportCapable, ScopeResolvable, ScopeCandidates {
  ResearchRuntime(this.resources)
    : store = WorkbenchStore.attach(
        rootPath: resources.files.rootPath,
        database: resources.database.raw,
        managed: resources.database,
      );
  final ModuleResources resources;
  final WorkbenchStore store;

  @override
  Future<ModuleSession> openScopeSession() async => _ResearchScopeSession(this);

  @override
  Future<List<ObjectRef>> scopeCandidates() async => [
    for (final project in store.projects()) ...[
      ObjectRef(moduleId: 'research', objectType: 'project', objectId: project.id,
        nativeProjectId: project.id),
      for (final document in store.documents(project.id))
        ObjectRef(moduleId: 'research', objectType: 'document', objectId: document.id,
          nativeProjectId: project.id),
      for (final entry in store.entries(project.id))
        ObjectRef(moduleId: 'research', objectType: 'entry', objectId: entry.id,
          nativeProjectId: project.id),
    ],
  ];

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
    if (rows.isEmpty) {
      final canonical = store.db.select(
        'SELECT * FROM rk_import_receipts WHERE operation_id=?',
        [operationId],
      );
      if (canonical.isEmpty) return null;
      final row = canonical.single;
      final identity = jsonDecode(row['identity'] as String) as Map;
      return ImportReceipt(
        intent: ImportIntent(
          operationId: identity['operationId'] as String,
          workspaceId: identity['workspaceId'] as String,
          moduleId: identity['moduleId'] as String,
          targetProjectId: identity['targetProjectId'] as String,
          kind: ImportKind.values.byName(identity['kind'] as String),
          inputDigest: identity['inputDigest'] as String,
          stagingToken: identity['stagingToken'] as String,
        ),
        result: Map<String, Object?>.from(
          jsonDecode(row['result'] as String) as Map,
        ),
        committedAt: DateTime.parse(row['committed_at'] as String),
      );
    }
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
    // Canonical ZIP imports use the same host intent/receipt protocol.
    if (input is PreparedResearchPackage) {
      return ResearchPackageExchange(CardStore(resources.database))
          .commitImport(input, intent);
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
      return ObjectView(ref: ObjectRef(
        moduleId: 'research', objectType: ref.objectType, objectId: id,
        nativeProjectId: project, revisionRef: revision, contentDigest: digest,
      ), title: title);
    }

    switch (ref.objectType) {
      case 'project':
        if (id != project) return null;
        final row = store.projects().where((p) => p.id == id).firstOrNull;
        return row == null ? null : view(row.title, digest: sha256.convert(
          utf8.encode(jsonEncode([row.title, row.question, row.nextStep])),
        ).toString());
      case 'document':
        final rows = store.db.select(
          'SELECT relative_path,sha256 FROM documents WHERE id=? AND project_id=?',
          [id, project],
        );
        if (rows.isNotEmpty) {
          return view(
            rows.single['relative_path'] as String,
            digest: (() {
              final document = store.documents(project).where((d) => d.id == id).single;
              final file = File(document.absolutePath);
              return file.existsSync() ? sha256.convert(file.readAsBytesSync()).toString() : 'missing';
            })(),
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
      case 'note':
        final notes = store.db.select('SELECT n.* FROM notes n JOIN documents d ON d.id=n.document_id WHERE n.id=? AND d.project_id=?', [id, project]);
        return notes.isEmpty ? null : view(notes.single['text'] as String,
          digest: sha256.convert(utf8.encode(jsonEncode(Map<String,Object?>.from(notes.single)))).toString());
      case 'entry':
        final rows = store.db.select(
          'SELECT title,data FROM entries WHERE id=? AND project_id=?',
          [id, project],
        );
        return rows.isEmpty
            ? null
            : view(
                rows.single['title'] as String? ?? id,
                // The host object catalog digests an entry by its decoded
                // data, so a matching digest must resolve here.
                digest: sha256
                    .convert(
                      utf8.encode(
                        jsonEncode(
                          WorkbenchStore.decode(rows.single['data'] as String),
                        ),
                      ),
                    )
                    .toString(),
              );
      case 'outline':
      case 'section':
        final (table, title) = switch (ref.objectType) {
          'outline' => ('outline', 'heading'),
          _ => ('sections', 'heading'),
        };
        final rows = store.db.select(
          'SELECT * FROM $table WHERE id=? AND project_id=?',
          [id, project],
        );
        return rows.isEmpty ? null : view(rows.single[title] as String? ?? id,
          digest: sha256.convert(utf8.encode(jsonEncode(Map<String,Object?>.from(rows.single)))).toString());
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
          'SELECT t.title,r.status,r.task_revision,r.accepted,r.data FROM runs r JOIN tasks t ON t.id=r.task_id AND t.revision=r.task_revision WHERE r.id=? AND t.project_id=?',
          [id, project],
        );
        return rows.isEmpty
            ? null
            : view(
                '${rows.single['title']} — ${rows.single['status']}',
                revision: '${rows.single['task_revision']}',
                digest: sha256.convert(utf8.encode(jsonEncode([rows.single['status'], rows.single['accepted'], WorkbenchStore.decode(rows.single['data'] as String)]))).toString(),
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
          cardTitleFromMarkdown(body, fallback: id),
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
  /// Documents open the reader; the other resolved types open read-only detail
  /// pages. Every failure path (module, project, id, revision or digest
  /// mismatch) returns null so the caller can fall back.
  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) {
    if (_resolve(ref) == null) return null;
    final project = binding.nativeProjectId;
    final id = ref.objectId;
    switch (ref.objectType) {
      case 'document':
        final document = store
            .documents(project)
            .where((doc) => doc.id == id)
            .firstOrNull;
        // Canonical package documents have bytes but no existing ReaderPage file
        // adapter yet. Do not advertise a project overview as their object page.
        return document == null
            ? null
            : ReaderPage(store: store, document: document);
      case 'entry':
        final rows = store.db.select(
          'SELECT * FROM entries WHERE id=? AND project_id=?',
          [id, project],
        );
        if (rows.isEmpty) return null;
        return ResearchEntryPage(
          entry: ResearchEntry(
            id: id,
            projectId: project,
            kind: rows.single['kind'] as String,
            title: rows.single['title'] as String,
            data: WorkbenchStore.decode(rows.single['data'] as String),
          ),
        );
      case 'outline':
        final rows = store.db.select(
          'SELECT o.heading,o.evidence_id,s.heading AS section_heading '
          'FROM outline o LEFT JOIN sections s ON s.id=o.section_id '
          'WHERE o.id=? AND o.project_id=?',
          [id, project],
        );
        if (rows.isEmpty) return null;
        return ResearchOutlinePage(
          heading: rows.single['heading'] as String? ?? id,
          sectionHeading: rows.single['section_heading'] as String?,
          content: _evidenceSummary(
            project,
            rows.single['evidence_id'] as String?,
          ),
        );
      case 'section':
        final rows = store.db.select(
          'SELECT s.heading,s.argument,p.title AS project_title '
          'FROM sections s LEFT JOIN projects p ON p.id=s.project_id '
          'WHERE s.id=? AND s.project_id=?',
          [id, project],
        );
        if (rows.isEmpty) return null;
        return ResearchSectionPage(
          heading: rows.single['heading'] as String,
          projectTitle: rows.single['project_title'] as String? ?? project,
          argument: rows.single['argument'] as String? ?? '',
        );
      case 'task':
        final rows = store.db.select(
          'SELECT * FROM tasks WHERE id=? AND project_id=? '
          '${ref.revisionRef == null ? '' : 'AND CAST(revision AS TEXT)=? '}'
          'ORDER BY revision DESC LIMIT 1',
          [id, project, if (ref.revisionRef != null) ref.revisionRef],
        );
        if (rows.isEmpty) return null;
        final task = store.taskFromRow(rows.single);
        final latest =
            store.db.select(
                  'SELECT MAX(revision) AS latest FROM tasks WHERE id=?',
                  [id],
                ).first['latest']
                as int?;
        // The status belongs to the shown revision, not to the latest run of
        // the task (review F1).
        final runStatus = store.db.select(
          'SELECT status FROM runs WHERE task_id=? AND task_revision=? '
          'ORDER BY rowid DESC LIMIT 1',
          [id, task.revision],
        );
        return ResearchTaskPage(
          task: task,
          revisionRunStatus: runStatus.isEmpty
              ? null
              : runStatus.single['status'] as String,
          isLatestRevision: task.revision == latest,
        );
      case 'run':
        final rows = store.db.select(
          'SELECT r.*,t.title AS task_title FROM runs r '
          'JOIN tasks t ON t.id=r.task_id AND t.revision=r.task_revision '
          'WHERE r.id=? AND t.project_id=?',
          [id, project],
        );
        if (rows.isEmpty) return null;
        final run = store.runFromRow(rows.single);
        final latest =
            store.db.select(
                  'SELECT MAX(revision) AS latest FROM tasks WHERE id=?',
                  [run.taskId],
                ).first['latest']
                as int?;
        return ResearchRunPage(
          run: run,
          taskTitle: rows.single['task_title'] as String? ?? run.taskId,
          isLatestRevision: run.taskRevision == latest,
        );
      case 'card':
        final revisionId = ref.revisionRef;
        final rows = store.db.select(
          'SELECT v.envelope,v.revision_id,c.head_revision_id FROM canonical_object_map m '
          'JOIN rk_cards c ON c.object_key=m.object_key '
          'JOIN rk_revisions v ON v.object_key=m.object_key AND v.revision_id=${revisionId == null ? 'c.head_revision_id' : '?'} '
          'WHERE m.local_object_id=? AND m.local_project_id=? AND m.object_type=?',
          [?revisionId, id, project, 'card'],
        );
        if (rows.isEmpty) return null;
        final envelope = jsonDecode(
          rows.single['envelope'] as String,
        ) as Map<String, Object?>;
        return ResearchCardPage(
          bodyMarkdown: '${envelope['bodyMarkdown'] ?? ''}',
          revisionId: rows.single['revision_id'] as String,
          citations: [
            for (final raw in (envelope['citationRefs'] as List? ?? const []))
              _citationLine(Map<String, Object?>.from(raw as Map)),
          ],
          isLatestRevision:
              rows.single['revision_id'] == rows.single['head_revision_id'],
        );
      default:
        return null;
    }
  }

  /// Human summary of an outline link's evidence, or the raw id when it
  /// cannot be described. Never invents a record.
  String? _evidenceSummary(String project, String? evidenceId) {
    if (evidenceId == null || evidenceId.isEmpty) return null;
    final entry = store.db.select(
      'SELECT kind,title FROM entries WHERE id=? AND project_id=?',
      [evidenceId, project],
    );
    if (entry.isNotEmpty) {
      final kind = '${entry.single['kind']}';
      return '${recordKinds[kind] ?? kind} · ${entry.single['title']}';
    }
    final note = store.db.select(
      'SELECT n.text,d.relative_path FROM notes n JOIN documents d ON d.id=n.document_id '
      'WHERE n.id=? AND d.project_id=?',
      [evidenceId, project],
    );
    if (note.isNotEmpty) {
      return '精读证据 · ${note.single['relative_path']} · ${note.single['text']}';
    }
    final run = store.db.select(
      'SELECT r.status,t.title FROM runs r JOIN tasks t ON t.id=r.task_id AND t.revision=r.task_revision '
      'WHERE r.id=? AND t.project_id=?',
      [evidenceId, project],
    );
    if (run.isNotEmpty) {
      return '运行结果 · ${run.single['title']} · ${run.single['status']}';
    }
    return evidenceId;
  }

  static String _citationLine(Map<String, Object?> citation) {
    final source = citation['source'] is Map
        ? Map<String, Object?>.from(citation['source'] as Map)
        : const <String, Object?>{};
    final documentRef = source['documentRef'] is Map
        ? Map<String, Object?>.from(source['documentRef'] as Map)
        : const <String, Object?>{};
    final page = source['pageIndex'];
    final quote = '${source['quote'] ?? ''}'.trim();
    return [
      '${citation['citationId'] ?? ''}',
      if (documentRef['objectUuid'] != null)
        '${documentRef['objectType'] ?? 'document'} ${documentRef['objectUuid']}',
      if (page is int) '第${page + 1}页',
      if (quote.isNotEmpty) '“$quote”',
    ].where((part) => part.isNotEmpty).join(' · ');
  }
}

/// Cross-project authority delegates to the same bound-session resolver.
class _ResearchScopeSession implements ModuleSession {
  _ResearchScopeSession(this.runtime);
  final ResearchRuntime runtime;
  bool _disposed = false;
  @override
  Future<ObjectView?> resolve(ObjectRef ref) async {
    if (_disposed) throw StateError('Session disposed');
    final project = ref.nativeProjectId;
    if (ref.moduleId != 'research' || project == null ||
        !runtime.store.projects().any((p) => p.id == project)) return null;
    final session = await runtime.openSession(WorkspaceBinding(
      workspaceId: '', moduleId: 'research', nativeProjectId: project,
    ));
    try { return await session.resolve(ref); }
    finally { await session.dispose(); }
  }
  @override
  Widget? objectPage(BuildContext context, ObjectRef ref) => null;
  @override
  Future<void> flush() async {
    if (_disposed) throw StateError('Session disposed');
  }
  @override
  Future<void> dispose() async { _disposed = true; }
}
