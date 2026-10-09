import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/execution_store.dart';
import 'package:muyon/platform/platform_tools.dart';
import 'package:muyon/platform/scope_resolver.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart' hide Invocation;
import 'package:sqlite3/sqlite3.dart';

import 'support/fake_v2_module.dart';

const _ids = ['platform.executions', 'platform.memories',
  'platform.notifications', 'platform.device_status'];

int changes(Database db) => db.select('SELECT total_changes() AS n').single['n'] as int;
String snapshot(Database db, {bool receipts = true}) => jsonEncode({
  for (final row in db.select("SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name"))
    if (receipts || row['name'] != 'tool_invocation_receipts')
      row['name'] as String: [for (final r in db.select(
          'SELECT * FROM ${row['name']} ORDER BY rowid')) r.values.toList()],
});

class _AuditDatabase implements ManagedDatabase {
  _AuditDatabase(this.owner);
  final ManagedDatabase owner;
  final deltas = <int>[];
  final gaps = <int>[];
  int? last;
  @override
  Database get raw => owner.raw;
  @override
  Future<T> write<T>(T Function(Database) body) => owner.write((db) {
    final before = changes(db);
    if (last != null) gaps.add(before - last!);
    final tables = snapshot(db, receipts: false);
    final value = body(db);
    deltas.add(changes(db) - before);
    expect(snapshot(db, receipts: false), tables);
    last = changes(db);
    return value;
  });
  void reset() { deltas.clear(); gaps.clear(); last = null; }
}

class _Runtime implements ModuleRuntime {
  final receipts = <String, ImportReceipt>{};
  int receiptReads = 0, commits = 0;
  @override
  Future<ImportReceipt?> receipt(String operationId) async {
    receiptReads++;
    return receipts[operationId];
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #commitImport) commits++;
    throw StateError('Unexpected module operation ${invocation.memberName}');
  }
}

class _Counters { int prepare = 0, enumerate = 0, resolve = 0, knowledge = 0; }
class _Source implements ScopeSource {
  _Source(this.source, this.counts);
  final ScopeSource source;
  final _Counters counts;
  @override
  String get moduleId => source.moduleId;
  @override
  bool get resolvesDirectly => source.resolvesDirectly;
  @override
  Future<void> prepare() { counts.prepare++; return source.prepare(); }
  @override
  Future<List<ObjectRef>> enumerate() { counts.enumerate++; return source.enumerate(); }
  @override
  Future<ObjectRef?> resolve(ObjectRef ref) { counts.resolve++; return source.resolve(ref); }
}

void main() {
  late Directory root;
  late MuyonHost host;
  late ToolRegistry registry;
  late _AuditDatabase audit;
  late _Counters counts;
  late _Runtime runtime;
  late FakeV2Module module;
  late ImportIntent intent;
  var available = true;
  var fallbackCalls = 0;

  setUp(() async {
    available = true; fallbackCalls = 0;
    root = Directory.systemTemp.createTempSync('metadata-scope-');
    runtime = _Runtime();
    module = FakeV2Module('notes', features: {ModuleFeature.importPipeline},
      runtimeFactory: (_) => runtime);
    host = await MuyonHost.open(root.path, modules: [module]);
    final workspace = await host.workspaces.create('Fixture');
    intent = await ImportCoordinator(host.workspaces).record(PreparedImport(
      target: ImportTarget.create(WorkspaceBinding(workspaceId: workspace.id,
        moduleId: 'notes', nativeProjectId: 'project')),
      inputDigest: 'fixture-digest', stagingToken: 'fixture-stage'));
    runtime.receipts[intent.operationId] = ImportReceipt(intent: intent,
      result: const {}, committedAt: DateTime.utc(2026));
    counts = _Counters();
    final scopes = ScopeResolver(sources: [for (final source in host.scopeResolver.sources)
      _Source(source, counts)], workspaces: host.workspaces,
      knowledgeSources: () { counts.knowledge++; return host.scopeResolver.knowledgeSources(); });
    audit = _AuditDatabase(host.foundation.database);
    // RED uses the existing shared resolver: the mechanism must replace only
    // metadata resolution, while this actual fallback continues to recover.
    registry = ToolRegistry(database: audit,
      categoryAllowed: (effect) => host.authorizationPolicy.current.allowsTool(effect),
      policyRevision: () => host.authorizationPolicy.current.revision,
      resolveScope: (scope) { fallbackCalls++; return scopes.resolve(scope); });
    registerPlatformReadTools(registry: registry, foundation: host.foundation,
      executions: ExecutionStore(host.foundation.database), transfer: host.services.transfer,
      isAvailable: () => available);
  });
  tearDown(() async {
    available = false;
    await registry.close();
    await host.close();
    root.deleteSync(recursive: true);
  });

  ToolCallRequest request(String id, String invocation) => ToolCallRequest(
    invocationId: invocation, toolId: id, scope: const AssistantScope.global());
  String intentStatus() => host.foundation.database.raw.select(
    'SELECT status FROM import_intents WHERE operation_id=?', [intent.operationId])
    .single['status'] as String;

  test('metadata prepare does not initialize or recover pending imports', () async {
    final db = audit.raw;
    final before = changes(db), state = snapshot(db);
    for (final id in _ids) {
      final prepared = await registry.prepare(request(id, 'prepare-$id'));
      expect(prepared.resolvedScope.objects, isEmpty);
    }
    expect(fallbackCalls, 0);
    expect(counts.prepare, 0); expect(counts.enumerate, 0); expect(counts.knowledge, 0);
    expect(module.activations, 0); expect(runtime.receiptReads, 0);
    expect(changes(db), before); expect(snapshot(db), state);
    expect(intentStatus(), 'pending'); expect(runtime.commits, 0);
  });

  test('new metadata invoke writes exactly two receipt rows and replay writes none', () async {
    for (final id in _ids) {
      audit.reset();
      final before = changes(audit.raw);
      final call = request(id, 'audit-$id');
      expect((await registry.invoke(call)).status, ToolCallStatus.succeeded);
      expect(audit.deltas.where((n) => n != 0), [1, 1]);
      expect(audit.gaps, everyElement(0));
      expect(changes(audit.raw) - before, 2);
      final receipt = registry.receipt(call.invocationId)!;
      expect(receipt.state, 'succeeded'); expect(receipt.toolId, id);
      audit.reset();
      final replayBefore = changes(audit.raw);
      expect((await registry.invoke(call)).data, receipt.result!.data);
      expect(changes(audit.raw), replayBefore);
      expect(audit.deltas, everyElement(0));
    }
    expect(fallbackCalls, 0); expect(module.activations, 0);
    expect(intentStatus(), 'pending');
  });

  test('host unavailable refuses initial preparation before fallback', () async {
    available = false;
    expect(registry.inspect(_ids.first)!.available, isTrue);
    final before = changes(audit.raw);
    await expectLater(registry.prepare(request(_ids.first, 'unavailable')),
      throwsA(isA<ToolPlatformException>().having((e) => e.code, 'code', 'host_unavailable')));
    expect(fallbackCalls, 0); expect(module.activations, 0);
    expect(changes(audit.raw), before); expect(intentStatus(), 'pending');
  });

  test('normal business fallback still completes existing receipt without committing again', () async {
    registry.register(providerId: 'notes', descriptor: ToolDescriptor(
      toolId: 'notes.probe', moduleId: 'notes', effect: ToolEffect.read,
      parameterSchema: const {'type': 'object', 'properties': <String, Object?>{}}),
      handler: (_) async => ToolCallResult(status: ToolCallStatus.succeeded, summary: 'probe'));
    final receipt = runtime.receipts[intent.operationId];
    await registry.prepare(request('notes.probe', 'normal'));
    expect(fallbackCalls, 1); expect(module.activations, 1);
    expect(intentStatus(), 'complete'); expect(runtime.commits, 0);
    expect(runtime.receipts[intent.operationId], same(receipt));
    expect(host.workspaces.binding(intent.workspaceId, 'notes')!.nativeProjectId, 'project');
    final reads = runtime.receiptReads;
    await registry.prepare(request('notes.probe', 'normal-again'));
    expect(module.activations, 1); expect(runtime.receiptReads, reads);
    expect(runtime.receipts, hasLength(1));
  });
}
