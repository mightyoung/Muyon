import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/knowledge/registered_research_source.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/documents/document_parser.dart';
import 'package:muyon/services/knowledge/research_search_adapter.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:research_module/research_module.dart';

class _Fixture {
  _Fixture(this.root, this.input, this.host, this.binding);
  final Directory root, input;
  final MuyonHost host;
  final WorkspaceBinding binding;
  static Future<_Fixture> open() async {
    final root = Directory.systemTemp.createTempSync('reg3b-host-');
    final input = Directory.systemTemp.createTempSync('reg3b-input-');
    File('${input.path}/a.md').writeAsStringSync('模型 Evidence recall 数据分析');
    File('${input.path}/b.md').writeAsStringSync('secret unselected');
    final host = await MuyonHost.open(root.path);
    await host.activateResearch();
    final workspace = await host.workspaces.create('A');
    final binding = WorkspaceBinding(workspaceId: workspace.id,
      moduleId: 'research', nativeProjectId: 'A');
    final prepared = await host.research!.prepareImport(
      SelectedInput(path: input.path, displayName: 'A'), ImportTarget.create(binding));
    final coordinator = ImportCoordinator(host.workspaces);
    await coordinator.commit(host.research!, prepared, await coordinator.record(prepared));
    return _Fixture(root, input, host, binding);
  }
  List<SearchSource> sources() => host.registry.modules.whereType<BusinessModuleV2>()
      .where((module) => module.manifest.id == 'research')
      .expand((module) => module.searchSources).toList();
  String? authority() => host.modules.scopeAuthorityRevision('research');
  ResearchSearchAdapter adapter({List<SearchSource> Function()? sources}) =>
      ResearchSearchAdapter.registered(host.services.knowledge, host.workspaces,
        host.research!.store, sources: sources ?? this.sources, authorityRevision: authority);
  RegisteredResearchSources consumer({List<SearchSource> Function()? sources}) =>
      RegisteredResearchSources(workspaces: host.workspaces,
        sources: sources ?? this.sources, authorityRevision: authority);
  Future<void> close() async {
    await host.close();
    root.deleteSync(recursive: true);
    input.deleteSync(recursive: true);
  }
}

/// Retains the real in-flight source future so tests can release and join it
/// after cancellation, without timers or leaving I/O behind at fixture close.
class _HeldSource extends ResearchDocumentSearchSource {
  _HeldSource({required super.currentRuntime, required super.readBytes});
  Future<List<IndexableItem>>? pending;
  @override Future<List<IndexableItem>> list(IndexScope scope) =>
      pending = super.list(scope);
}

class _PausedParser extends DocumentParser {
  final entered = Completer<void>(), release = Completer<void>();
  @override Future<ParsedDocument> parse(ResearchDocument document) async {
    final parsed = await super.parse(document);
    entered.complete();
    await release.future;
    return parsed;
  }
}

void main() {
  test('default unbound module source fails closed without caching activation', () async {
    final source = ResearchModule().searchSources.single;
    await expectLater(source.list(const IndexScope(nativeProjectId: 'A')), throwsStateError);
  });

  test('actual registered module publishes project-pinned current bytes and confirms identity', () async {
    final f = await _Fixture.open();
    try {
      final source = f.sources().single;
      final before = f.host.research!.store.db.select('SELECT * FROM documents')
          .map((row) => Map<String, Object?>.from(row)).toList();
      final items = await f.consumer().begin(f.binding).list();
      expect(items, hasLength(2));
      for (final item in items) {
        expect(item.ref.moduleId, 'research');
        expect(item.ref.nativeProjectId, 'A');
        expect(item.ref.revisionRef, isNull);
        expect(item.contentDigest, sha256.convert(File(item.filePath!).readAsBytesSync()).toString());
        expect((await source.confirm(item.ref))!.ref, item.ref);
        expect(await source.confirm(ObjectRef(moduleId: 'research', objectType: 'document',
          objectId: item.ref.objectId, nativeProjectId: 'A')), isNull);
        expect(await source.confirm(ObjectRef(moduleId: 'research', objectType: 'document',
          objectId: item.ref.objectId, nativeProjectId: 'B', contentDigest: item.contentDigest)), isNull);
        expect(await source.confirm(ObjectRef(moduleId: 'research', objectType: 'document',
          objectId: item.ref.objectId, nativeProjectId: 'A', revisionRef: 'old',
          contentDigest: item.contentDigest)), isNull);
      }
      await expectLater(source.list(const IndexScope()), throwsStateError);
      expect(f.host.research!.store.db.select('SELECT * FROM documents')
          .map((row) => Map<String, Object?>.from(row)).toList(), before);
      expect(f.host.services.knowledge.documents(), isEmpty);
    } finally { await f.close(); }
  });

  test('registered search indexes source-owned path and returns selected verified evidence', () async {
    final f = await _Fixture.open();
    try {
      final adapter = f.adapter();
      final docs = adapter.documents(f.binding);
      final a = docs.firstWhere((doc) => doc.relativePath.endsWith('a.md'));
      final b = docs.firstWhere((doc) => doc.relativePath.endsWith('b.md'));
      expect((await adapter.search(f.binding, '模型', selectedDocumentIds: {a.id}))
          .unavailable[a.id], 'not_indexed');
      // A caller cannot replace the module's real file with an outside file.
      await adapter.index(f.binding, ResearchDocument(id: a.id, projectId: a.projectId,
        relativePath: 'forged', absolutePath: '${f.input.path}/b.md'));
      await adapter.index(f.binding, b);
      final result = await adapter.search(f.binding, '模型 Evidence', selectedDocumentIds: {a.id});
      expect(result.hits.single.document.id, a.id);
      expect(result.hits.single.contentDigest, sha256.convert(File(a.absolutePath).readAsBytesSync()).toString());
      expect((await adapter.search(f.binding, 'secret', selectedDocumentIds: {a.id})).hits, isEmpty);
      await expectLater(adapter.hash(a), throwsUnsupportedError);
      File(a.absolutePath).writeAsStringSync('replacement new');
      expect((await adapter.search(f.binding, '模型', selectedDocumentIds: {a.id}))
          .unavailable[a.id], 'stale');
      await adapter.index(f.binding, a);
      expect((await adapter.search(f.binding, 'new', selectedDocumentIds: {a.id})).hits, hasLength(1));
    } finally { await f.close(); }
  });

  test('old document versions and deleted bytes cannot confirm or be selected', () async {
    final f = await _Fixture.open();
    try {
      final source = f.sources().single;
      final items = await source.list(const IndexScope(nativeProjectId: 'A'));
      final old = items.first;
      final store = f.host.research!.store;
      final document = store.documents('A').firstWhere((doc) => doc.id == old.ref.objectId);
      final replacement = File('${store.rootPath}/replacement.md')..writeAsStringSync('new version');
      await store.write(() => store.db.execute(
        'INSERT INTO documents(id,project_id,relative_path,snapshot_path) VALUES(?,?,?,?)',
        ['replacement', 'A', document.relativePath, store.storedPath(replacement.path)]));
      expect(await source.confirm(old.ref), isNull);
      final current = await source.list(const IndexScope(nativeProjectId: 'A'));
      expect(current.any((item) => item.ref.objectId == old.ref.objectId), isFalse);
      final newItem = current.firstWhere((item) => item.ref.objectId == 'replacement');
      replacement.deleteSync();
      expect(await source.confirm(newItem.ref), isNull);
      expect((await source.list(const IndexScope(nativeProjectId: 'A')))
          .any((item) => item.ref.objectId == 'replacement'), isFalse);
      await expectLater(f.adapter().search(f.binding, 'new', selectedDocumentIds: {old.ref.objectId}), throwsStateError);
    } finally { await f.close(); }
  });

  test('revocation invalidates retained module source and host consumer; reactivation cannot revive proof', () async {
    final f = await _Fixture.open();
    try {
      final source = f.sources().single;
      final read = f.consumer().begin(f.binding);
      final pinned = (await read.list()).first.ref;
      await f.host.modules.revokeCapability('research', 'models');
      await expectLater(source.confirm(pinned), throwsStateError);
      expect(() => read.requireCurrent(), throwsStateError);
      expect(() => f.consumer().begin(f.binding), throwsStateError);
      await f.host.activateResearch();
      expect(f.host.research, isNull);
      await f.host.modules.reconsiderCapability('research', 'models');
      expect(f.host.research, isNotNull);
      expect(() => read.requireCurrent(), throwsStateError);
      expect((await f.consumer().begin(f.binding).list()), hasLength(2));
    } finally { await f.close(); }
  });

  test('cancel returns before blocked read ends and prevents indexing effects', () async {
    final f = await _Fixture.open();
    final entered = Completer<void>(), release = Completer<void>();
    final source = _HeldSource(currentRuntime: () => f.host.research,
      readBytes: (path) async {
        final bytes = File(path).readAsBytesSync();
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return bytes;
      });
    try {
      final adapter = f.adapter(sources: () => [source]);
      final doc = adapter.documents(f.binding).first;
      final token = ToolCancellationToken();
      final pending = adapter.index(f.binding, doc, cancellation: token);
      await entered.future;
      final rejected = expectLater(pending, throwsA(isA<ToolCancelled>()));
      token.cancel();
      await rejected;
      expect(release.isCompleted, isFalse);
      expect(f.host.services.knowledge.documents(), isEmpty);
      release.complete();
      await source.pending;
    } finally {
      if (!release.isCompleted) release.complete();
      await f.close();
    }
  });

  test('module revoke during source I/O rejects proof before knowledge writes', () async {
    final f = await _Fixture.open();
    final entered = Completer<void>(), release = Completer<void>();
    final source = _HeldSource(currentRuntime: () => f.host.research,
      readBytes: (path) async {
        final bytes = File(path).readAsBytesSync();
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return bytes;
      });
    try {
      final adapter = f.adapter(sources: () => [source]);
      final pending = adapter.index(f.binding, adapter.documents(f.binding).first);
      final rejected = expectLater(pending, throwsStateError);
      await entered.future;
      await f.host.modules.revokeCapability('research', 'knowledge');
      release.complete();
      await rejected;
      expect(f.host.services.knowledge.documents(), isEmpty);
    } finally {
      if (!release.isCompleted) release.complete();
      await f.close();
    }
  });

  test('workspace authority change during source I/O invalidates otherwise active module read', () async {
    final f = await _Fixture.open();
    final entered = Completer<void>(), release = Completer<void>();
    final source = _HeldSource(currentRuntime: () => f.host.research,
      readBytes: (path) async {
        final bytes = File(path).readAsBytesSync();
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return bytes;
      });
    try {
      final read = f.consumer(sources: () => [source]).begin(f.binding);
      final pending = read.list();
      final rejected = expectLater(pending, throwsStateError);
      await entered.future;
      final authority = f.host.workspaces.scopeAuthorityRevision;
      final runtime = f.host.research;
      final other = await f.host.workspaces.create('B');
      await f.host.workspaces.bind(WorkspaceBinding(workspaceId: other.id,
        moduleId: 'research', nativeProjectId: 'B'));
      expect(f.host.workspaces.scopeAuthorityRevision, isNot(authority));
      expect(f.host.research, same(runtime));
      expect(f.host.workspaces.binding(f.binding.workspaceId, 'research')!.nativeProjectId, 'A');
      expect(f.host.workspaces.binding(other.id, 'research')!.nativeProjectId, 'B');
      release.complete();
      await rejected;
      expect(f.host.services.knowledge.documents(), isEmpty);
    } finally {
      if (!release.isCompleted) release.complete();
      await f.close();
    }
  });

  test('file replacement during asynchronous read never publishes earlier digest', () async {
    final f = await _Fixture.open();
    try {
      final source = ResearchDocumentSearchSource(currentRuntime: () => f.host.research,
        readBytes: (path) async {
          final bytes = File(path).readAsBytesSync();
          File(path).writeAsStringSync('changed after read');
          return bytes;
        });
      expect(await source.list(const IndexScope(nativeProjectId: 'A')), isEmpty);
    } finally { await f.close(); }
  });

  test('managed-root escape and oversized file fail closed before knowledge effects', () async {
    final f = await _Fixture.open();
    try {
      final store = f.host.research!.store;
      final doc = store.documents('A').first;
      await store.write(() => store.db.execute('UPDATE documents SET snapshot_path=? WHERE id=?',
        [store.storedPath('${f.input.path}/a.md'), doc.id]));
      await expectLater(f.adapter().index(f.binding, doc), throwsStateError);
      expect(f.host.services.knowledge.documents(), isEmpty);
      final large = File('${store.rootPath}/large.md');
      final handle = large.openSync(mode: FileMode.write);
      try { handle.truncateSync(ResearchDocumentSearchSource.maxFileBytes + 1); }
      finally { handle.closeSync(); }
      await store.write(() => store.db.execute('UPDATE documents SET snapshot_path=? WHERE id=?',
        [store.storedPath(large.path), doc.id]));
      await expectLater(f.sources().single.list(const IndexScope(nativeProjectId: 'A')), throwsStateError);
      expect(f.host.services.knowledge.documents(), isEmpty);
    } finally { await f.close(); }
  });

  test('missing registration, unsupported scope and independent cancellation fail closed', () async {
    final f = await _Fixture.open();
    try {
      expect(() => f.consumer(sources: () => []).begin(f.binding), throwsStateError);
      final read = f.consumer().begin(f.binding);
      final token = ToolCancellationToken()..cancel();
      expect(() => f.consumer().begin(f.binding, cancellation: token), throwsA(isA<ToolCancelled>()));
      // Cancellation of a separate read does not revoke this valid read.
      expect(await read.list(), hasLength(2));
      expect(await read.confirm(const ObjectRef(moduleId: 'inquiry', objectType: 'document',
        objectId: 'other', nativeProjectId: 'A')), isNull);
      expect(() => f.consumer().begin(WorkspaceBinding(workspaceId: f.binding.workspaceId,
        moduleId: 'research', nativeProjectId: 'B')), throwsStateError);
    } finally { await f.close(); }
  });
    test('current-version change during parse never commits ready old evidence', () async {
      final f = await _Fixture.open();
      final parser = _PausedParser();
      final database = f.host.services.knowledge.database as ManagedConnection;
      final previous = database.onCommit;
      var observe = false, committedReady = false;
      var readyCommits = 0;
      database.onCommit = () {
        previous?.call();
        if (database.raw.select(
          "SELECT d.id FROM knowledge_documents d JOIN index_documents i "
          "ON i.document_id=d.id WHERE d.status='ready' AND i.state='ready'",
        ).isNotEmpty) {
          readyCommits++;
          if (observe) committedReady = true;
        }
      };
      try {
        final original = f.adapter().documents(f.binding).first;
        await f.adapter().index(f.binding, original);
        expect(readyCommits, greaterThan(0), reason: 'observer sees successful baseline ready commit');
        final oldRef = f.host.services.knowledge.documents().single.source;
        expect(await f.host.services.knowledge.allowModelContent(oldRef), isTrue);
        expect(await f.host.services.knowledge.search('Evidence'), hasLength(1));
        final controlled = KnowledgeService(f.host.services.knowledge.database,
          f.host.services.knowledge.rootPath, parser: parser,
          authorizationFacts: f.host.services.knowledge.authorizationFacts);
        controlled.confirmSource = f.host.services.knowledge.confirmSource;
        final adapter = ResearchSearchAdapter.registered(controlled, f.host.workspaces,
          f.host.research!.store, sources: f.sources, authorityRevision: f.authority);
        final pending = adapter.index(f.binding, original);
        final rejected = expectLater(pending, throwsStateError);
        await parser.entered.future;
        final store = f.host.research!.store;
        final next = File('${store.rootPath}/next.md')..writeAsStringSync('fresh replacement Evidence');
        await store.write(() => store.db.execute(
          'INSERT INTO documents(id,project_id,relative_path,snapshot_path) VALUES(?,?,?,?)',
          ['next', 'A', original.relativePath, store.storedPath(next.path)]));
        expect(File(original.absolutePath).existsSync(), isTrue);
        observe = true;
        parser.release.complete();
        await rejected;
        expect(committedReady, isFalse, reason: 'ready must never commit before cleanup');
        observe = false;
        expect(f.host.services.knowledge.documents(), isEmpty);
        expect(f.host.services.knowledge.database.raw.select(
          "SELECT * FROM index_documents WHERE state='ready'"), isEmpty);
        expect(await f.host.services.knowledge.search('Evidence'), isEmpty);
        expect(await f.host.services.knowledge.allowModelContent(oldRef), isFalse);
        final current = f.adapter().documents(f.binding).firstWhere((doc) => doc.id == 'next');
        await f.adapter().index(f.binding, current);
        expect(await f.host.services.knowledge.search('fresh'), hasLength(1));
      } finally {
        database.onCommit = previous;
        if (!parser.release.isCompleted) parser.release.complete();
        await f.close();
      }
    });

  test('public registered knowledge tool rejects old ready version and accepts newly indexed current version', () async {
    final f = await _Fixture.open();
    try {
      final adapter = f.adapter();
      final original = adapter.documents(f.binding).first;
      await adapter.index(f.binding, original);
      var invocation = 0;
      Future<List<Object?>> ask() async {
        final result = await f.host.tools.invoke(ToolCallRequest(
          invocationId: 'reg3b-public-${invocation++}', toolId: 'knowledge.search',
          scope: const AssistantScope.global(), parameters: {'query': 'Evidence'}));
        expect(result.status, ToolCallStatus.succeeded);
        return (result.data['hits'] as List).cast<Object?>();
      }
      expect(await ask(), hasLength(1));
      final oldRef = f.host.services.knowledge.documents().single.source;
      final store = f.host.research!.store;
      final next = File('${store.rootPath}/next-ready.md')..writeAsStringSync('fresh Evidence');
      await store.write(() => store.db.execute(
        'INSERT INTO documents(id,project_id,relative_path,snapshot_path) VALUES(?,?,?,?)',
        ['next-ready', 'A', original.relativePath, store.storedPath(next.path)]));
      expect(File(original.absolutePath).existsSync(), isTrue);
      // The existing raw cache API retains bytes. The public tool must ask
      // their owning registered source before exposing them as evidence.
      expect(await f.host.services.knowledge.search('Evidence'), hasLength(1));
      expect(await ask(), isEmpty);
      expect(await f.host.services.knowledge.allowModelContent(oldRef), isFalse);
      await expectLater(adapter.search(f.binding, 'Evidence',
        selectedDocumentIds: {original.id}), throwsStateError);
      final current = adapter.documents(f.binding).firstWhere((doc) => doc.id == 'next-ready');
      await adapter.index(f.binding, current);
      expect(await ask(), hasLength(1));
      f.host.services.knowledge.confirmSource = null;
      expect(await ask(), isEmpty, reason: 'registered public publication never falls back to raw cache');
    } finally { await f.close(); }
  });

}
