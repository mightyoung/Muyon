import 'dart:async';
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
import 'package:research_module/research_module.dart';

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
  void Function()? afterWrite;
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
  }).then((value) { afterWrite?.call(); return value; });
  void reset() { deltas.clear(); gaps.clear(); last = null; }
}

class _Runtime implements ModuleRuntime, ScopeCandidates, ScopeResolvable {
  @override
  Future<List<ObjectRef>> scopeCandidates() async => [];
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

class _Handlers implements ToolRegistrar {
  @override
  final moduleId = 'platform';
  final handlers = <String, ModuleToolHandler>{};
  @override
  void read(ToolSpec spec, ModuleToolHandler handler) => handlers[spec.name] = handler;
  @override
  void write(WriteToolSpec spec, ModuleToolHandler handler) => throw StateError('not read');
  @override
  void external(ExternalToolSpec spec, ModuleToolHandler handler) => throw StateError('not read');
  @override
  HostChannel channel(ChannelSpec spec) => throw StateError('not read');
}
class _Context implements ModuleToolContext {
  _Context(this.call);
  @override
  final ToolCallContext call;
  @override
  Future<T> runtime<T extends ModuleRuntime>() => throw StateError('no business runtime');
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
  var resolutionCalls = 0;
  var categoryAllowed = true;
  var policySuffix = '';
  PlatformMetadataScopeBinding? binding;
  HostToolScopeResolver? customResolution;
  Future<void> Function(int)? resolutionPause;
  late Future<ResolvedAssistantScope> Function(AssistantScope) fallback;

  void configureScopes() {
    counts = _Counters();
    final scopes = ScopeResolver(sources: [for (final source in host.scopeResolver.sources)
      _Source(source, counts)], workspaces: host.workspaces,
      knowledgeSources: () { counts.knowledge++; return host.scopeResolver.knowledgeSources(); });
    fallback = (scope) { fallbackCalls++; return scopes.resolve(scope); };
  }

  ToolRegistry newRegistry() => ToolRegistry(database: audit,
    categoryAllowed: (effect) => categoryAllowed && host.authorizationPolicy.current.allowsTool(effect),
    policyRevision: () => host.authorizationPolicy.current.revision + policySuffix,
    resolveScope: (scope) => fallback(scope),
    hostToolScopeResolver: (owner, info, call) async {
      final result = customResolution != null ? await customResolution!(owner, info, call) :
        await binding?.resolve(owner, info, call);
      resolutionCalls++;
      await resolutionPause?.call(resolutionCalls);
      return result;
    });

  setUp(() async {
    available = true; fallbackCalls = 0; resolutionCalls = 0;
    categoryAllowed = true; policySuffix = ''; binding = null;
    customResolution = null; resolutionPause = null;
    root = Directory.systemTemp.createTempSync('metadata-scope-');
    runtime = _Runtime();
    module = FakeV2Module('notes', features: {ModuleFeature.importPipeline},
      runtimeFactory: (_) => runtime, ontology: ModuleOntology(objectTypes: [fakeType('item')]));
    host = await MuyonHost.open(root.path, modules: [module]);
    final workspace = await host.workspaces.create('Fixture');
    intent = await ImportCoordinator(host.workspaces).record(PreparedImport(
      target: ImportTarget.create(WorkspaceBinding(workspaceId: workspace.id,
        moduleId: 'notes', nativeProjectId: 'project')),
      inputDigest: 'fixture-digest', stagingToken: 'fixture-stage'));
    runtime.receipts[intent.operationId] = ImportReceipt(intent: intent,
      result: const {}, committedAt: DateTime.utc(2026));
    configureScopes();
    audit = _AuditDatabase(host.foundation.database);
    registry = newRegistry();
    binding = registerPlatformReadTools(registry: registry, foundation: host.foundation,
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
      final receipt = registry.receiptFor(call.invocationId)!;
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

  test('strict scopes parameters category and pre-cancel reject without writes', () async {
    final before = changes(audit.raw);
    for (final id in _ids) {
      for (final scope in [AssistantScope.workspace('missing'),
        AssistantScope.selectedObjects([const ObjectRef(moduleId: 'platform',
          objectType: 'memory', objectId: 'missing')])]) {
        await expectLater(registry.prepare(ToolCallRequest(invocationId: 'bad-scope-$id',
          toolId: id, scope: scope)), throwsA(isA<ToolPlatformException>()));
      }
      await expectLater(registry.prepare(ToolCallRequest(invocationId: 'bad-param-$id',
        toolId: id, scope: const AssistantScope.global(), parameters: {'lane': 'metadata'})),
        throwsA(isA<ToolPlatformException>()));
      await expectLater(registry.invoke(request(id, 'pre-cancel-$id'),
        cancellation: ToolCancellationToken()..cancel()), throwsA(isA<ToolCancelled>()));
    }
    categoryAllowed = false;
    await expectLater(registry.prepare(request(_ids.first, 'category-disabled')),
      throwsA(isA<ToolPlatformException>().having((e) => e.code, 'code', 'category_disabled')));
    expect(fallbackCalls, 0); expect(module.activations, 0);
    expect(changes(audit.raw), before);
  });

  for (final change in ['generation', 'policy', 'host', 'cancel', 'close']) {
    test('first prepare await fences $change before resolution or audit effects', () async {
      final entered = Completer<void>(), release = Completer<void>();
      resolutionPause = (_) async { entered.complete(); await release.future; };
      final token = ToolCancellationToken();
      final before = changes(audit.raw);
      final run = registry.invoke(request(_ids.first, 'race-$change'), cancellation: token);
      final rejected = expectLater(run, throwsA(change == 'cancel' ? isA<ToolCancelled>() :
        change == 'close' ? isA<StateError>() : isA<ToolPlatformException>()));
      await entered.future;
      switch (change) {
        case 'generation':
          registry.setAvailability(_ids.first, available: false);
          registry.setAvailability(_ids.first, available: true);
        case 'policy': policySuffix = ':changed';
        case 'host': available = false;
        case 'cancel': token.cancel();
        case 'close': await registry.close();
      }
      release.complete();
      await rejected;
      expect(fallbackCalls, 0); expect(module.activations, 0);
      expect(changes(audit.raw), before); expect(intentStatus(), 'pending');
    });
  }

  for (final loss in ['binding', 'host', 'bad-key']) {
    test('dispatch $loss refusal precedes fallback with a recoverable pending intent', () async {
      audit.afterWrite = () {
        if (audit.deltas.length != 1) return;
        if (loss == 'binding') binding = null;
        if (loss == 'host') available = false;
        if (loss == 'bad-key') customResolution = (_, _, call) async => HostScopeResolution(
          identityKey: 'wrong', scope: ResolvedAssistantScope(requested: call.scope, objects: []),
          requireCurrent: () {});
      };
      final before = changes(audit.raw), tables = snapshot(audit.raw, receipts: false);
      final receipt = runtime.receipts[intent.operationId];
      final result = await registry.invoke(request(_ids.first, 'lost-$loss'));
      expect(result.status, ToolCallStatus.failed);
      expect(result.summary, contains(loss == 'host' ? 'host_unavailable' : 'scope_resolution_changed'));
      expect(fallbackCalls, 0); expect(counts.prepare, 0); expect(module.activations, 0);
      expect(runtime.receiptReads, 0); expect(runtime.commits, 0);
      expect(intentStatus(), 'pending'); expect(runtime.receipts[intent.operationId], same(receipt));
      expect(snapshot(audit.raw, receipts: false), tables);
      expect(audit.deltas, [1, 1]); expect(audit.gaps, [0]);
      expect(changes(audit.raw) - before, 2);
    });
  }

  for (final change in ['generation', 'policy', 'host', 'cancel', 'close']) {
    test('second prepare await fences $change before handler', () async {
      final entered = Completer<void>(), release = Completer<void>();
      resolutionPause = (n) async { if (n == 2) { entered.complete(); await release.future; } };
      final token = ToolCancellationToken();
      final run = registry.invoke(request(_ids.first, 'second-$change'), cancellation: token);
      await entered.future;
      Future<void>? closed;
      switch (change) {
        case 'generation':
          registry.setAvailability(_ids.first, available: false);
          registry.setAvailability(_ids.first, available: true);
        case 'policy': policySuffix = ':changed';
        case 'host': available = false;
        case 'cancel': token.cancel();
        case 'close': closed = registry.close();
      }
      release.complete();
      final result = await run;
      await closed;
      expect(result.status, anyOf(ToolCallStatus.failed, ToolCallStatus.cancelled));
      if (change == 'host') expect(result.summary, contains('host_unavailable'));
      expect(fallbackCalls, 0); expect(module.activations, 0);
      expect(audit.deltas, [1, 1]); expect(audit.gaps, [0]);
      expect(intentStatus(), 'pending');
    });
  }

  for (final invalid in ['key', 'scope', 'objects']) {
    test('malformed host resolution $invalid is refused without fallback', () async {
      customResolution = (_, _, call) async => HostScopeResolution(
        identityKey: invalid == 'key' ? 'wrong' : 'host_platform_metadata_v1',
        scope: ResolvedAssistantScope(requested: invalid == 'scope' ?
          AssistantScope.workspace('missing') : call.scope,
          objects: invalid == 'objects' ? [const ObjectRef(moduleId: 'notes',
            objectType: 'item', objectId: 'A')] : []), requireCurrent: () {});
      final before = changes(audit.raw);
      await expectLater(registry.prepare(request(_ids.first, 'invalid-$invalid')),
        throwsA(isA<ToolPlatformException>().having((e) => e.code, 'code', 'invalid_scope_resolution')));
      expect(changes(audit.raw), before); expect(fallbackCalls, 0);
    });
  }

  test('write effect cannot be claimed by host metadata resolution', () async {
    registry.register(providerId: 'notes', descriptor: ToolDescriptor(toolId: 'notes.write',
      moduleId: 'notes', effect: ToolEffect.write,
      parameterSchema: const {'type': 'object', 'properties': <String, Object?>{}}),
      handler: (_) async => throw StateError('must not dispatch'));
    customResolution = (_, _, call) async => HostScopeResolution(
      identityKey: 'host_platform_metadata_v1',
      scope: ResolvedAssistantScope(requested: call.scope, objects: []), requireCurrent: () {});
    final before = changes(audit.raw);
    await expectLater(registry.prepare(request('notes.write', 'invalid-effect')),
      throwsA(isA<ToolPlatformException>().having((e) => e.code, 'code', 'invalid_scope_resolution')));
    expect(changes(audit.raw), before); expect(fallbackCalls, 0);
  });

  test('binding refuses value-equal descriptor wrong provider fifth ID and another registry', () async {
    final trusted = registry.inspect(_ids.first)!;
    final descriptor = trusted.descriptor;
    final copy = ToolDescriptor(toolId: descriptor.toolId, moduleId: descriptor.moduleId,
      effect: descriptor.effect, apiVersion: descriptor.apiVersion,
      parameterSchema: descriptor.parameterSchema, resultSchema: descriptor.resultSchema);
    expect(await binding!.resolve(registry, RegisteredToolInfo(providerId: 'platform',
      descriptor: copy, available: true), request(_ids.first, 'copy')), isNull);
    expect(await binding!.resolve(registry, RegisteredToolInfo(providerId: 'forged',
      descriptor: descriptor, available: true), request(_ids.first, 'provider')), isNull);
    final other = ToolRegistry(database: host.foundation.database,
      resolveScope: (scope) async => ResolvedAssistantScope(requested: scope, objects: []));
    try {
      other.register(providerId: 'platform', descriptor: descriptor,
        handler: (_) async => throw StateError('not bound'));
      expect(await binding!.resolve(other, other.inspect(_ids.first)!,
        request(_ids.first, 'cross-registry')), isNull);
    } finally { await other.close(); }
    registry.register(providerId: 'platform', descriptor: ToolDescriptor(toolId: 'platform.fifth',
      moduleId: 'platform', effect: ToolEffect.read,
      parameterSchema: const {'type': 'object', 'properties': <String, Object?>{}}),
      handler: (_) async => throw StateError('not bound'));
    expect(await binding!.resolve(registry, registry.inspect('platform.fifth')!,
      request('platform.fifth', 'fifth')), isNull);
    expect(fallbackCalls, 0);
  });

  test('unclaimed callback preserves legacy scope identity and normal recovery', () async {
    registry.register(providerId: 'notes', descriptor: ToolDescriptor(toolId: 'notes.identity',
      moduleId: 'notes', effect: ToolEffect.read,
      parameterSchema: const {'type': 'object', 'properties': <String, Object?>{}}),
      handler: (_) async => ToolCallResult(status: ToolCallStatus.succeeded, summary: 'identity'));
    final call = request('notes.identity', 'identity');
    final withCallback = await registry.prepare(call);
    final legacy = ToolRegistry(database: host.foundation.database,
      categoryAllowed: (effect) => host.authorizationPolicy.current.allowsTool(effect),
      policyRevision: () => host.authorizationPolicy.current.revision,
      resolveScope: host.scopeResolver.resolve);
    try {
      legacy.register(providerId: 'notes', descriptor: registry.inspect('notes.identity')!.descriptor,
        handler: (_) async => ToolCallResult(status: ToolCallStatus.succeeded, summary: 'identity'));
      expect((await legacy.prepare(call)).identityDigest, withCallback.identityDigest);
    } finally { await legacy.close(); }
    expect(intentStatus(), 'complete'); expect(runtime.commits, 0);
  });

  test('concurrent completed replay and a fresh registry preserve receipt identity', () async {
    final entered = Completer<void>(), release = Completer<void>();
    resolutionPause = (n) async { if (n == 2) { entered.complete(); await release.future; } };
    final call = request(_ids.first, 'concurrent-replay');
    final one = registry.invoke(call);
    await entered.future;
    final two = registry.invoke(call);
    release.complete();
    expect((await one).status, ToolCallStatus.succeeded);
    expect((await two).status, ToolCallStatus.succeeded);
    expect(audit.deltas.where((n) => n != 0), [1, 1]);
    expect(audit.deltas.where((n) => n != 0), [1, 1]);
    await registry.close();
    await host.close();
    host = await MuyonHost.open(root.path, modules: [module]);
    configureScopes();
    audit = _AuditDatabase(host.foundation.database);
    resolutionPause = null; resolutionCalls = 0;
    registry = newRegistry();
    binding = registerPlatformReadTools(registry: registry, foundation: host.foundation,
      executions: ExecutionStore(host.foundation.database), transfer: host.services.transfer,
      isAvailable: () => available);
    final before = changes(audit.raw);
    expect((await registry.invoke(call)).status, ToolCallStatus.succeeded);
    expect(changes(audit.raw), before); expect(fallbackCalls, 0);
    await expectLater(registry.invoke(ToolCallRequest(invocationId: call.invocationId,
      toolId: call.toolId, scope: call.scope, parameters: {'limit': 1})),
      throwsA(isA<ToolPlatformException>().having((e) => e.code, 'code', 'idempotency_conflict')));
  });

  test('business recovery conflict retains original notification and no recommit', () async {
    final rival = await host.workspaces.create('Rival');
    await host.workspaces.bind(WorkspaceBinding(workspaceId: rival.id,
      moduleId: 'notes', nativeProjectId: 'project'));
    final beforeNotifications = host.foundation.notifications().length;
    await registry.prepare(request(_ids.first, 'conflict-metadata'));
    expect(intentStatus(), 'pending'); expect(module.activations, 0);
    registry.register(providerId: 'notes', descriptor: ToolDescriptor(toolId: 'notes.conflict',
      moduleId: 'notes', effect: ToolEffect.read, parameterSchema: const {'type': 'object'}),
      handler: (_) async => throw StateError('prepare only'));
    await registry.prepare(request('notes.conflict', 'conflict-business-control'));
    expect(intentStatus(), 'conflict'); expect(module.activations, 1);
    expect(runtime.commits, 0); expect(runtime.receipts, hasLength(1));
    expect(host.foundation.notifications(), hasLength(beforeNotifications + 1));
    await registry.prepare(request('notes.conflict', 'conflict-again'));
    expect(host.foundation.notifications(), hasLength(beforeNotifications + 1));
  });

  test('metadata leaves accepted research bookkeeping for normal activation recovery', () async {
    final path = '${root.path}/research-recovery';
    var researchHost = await MuyonHost.open(path, modules: [ResearchModule()]);
    ToolRegistry? reads;
    try {
      await researchHost.activateResearch();
      final workspace = await researchHost.workspaces.create('Accepted research');
      const itemId = 'fixture-item', digest = 'fixture-research-digest';
      final operation = await ImportCoordinator(researchHost.workspaces).record(PreparedImport(
        target: ImportTarget.create(WorkspaceBinding(workspaceId: workspace.id,
          moduleId: 'research', nativeProjectId: 'accepted-project')),
        inputDigest: digest, stagingToken: 'transfer-research:$itemId:$digest'),
        operationId: 'transfer-research:$itemId');
      final identity = {'operationId': operation.operationId, 'workspaceId': operation.workspaceId,
        'moduleId': 'research', 'targetProjectId': operation.targetProjectId,
        'kind': operation.kind.name, 'inputDigest': digest, 'stagingToken': operation.stagingToken};
      await researchHost.research!.resources.database.write((db) => db.execute(
        'INSERT INTO rk_import_receipts VALUES(?,?,?,?)', [operation.operationId,
          jsonEncode(identity), '{}', '2026-10-09T00:00:00Z']));
      await researchHost.services.transfer.database.write((db) => db.execute(
        'INSERT INTO transfer_items(item_id,peer_fingerprint,path,delivered,attachment_state,'
        'attachment_length,attachment_sha256,imported,acceptance,created_at) '
        'VALUES(?,?,?,?,?,?,?,?,?,?)', [itemId, 'fixture-peer', '$path/accepted.zip',
          1, 'durable', 1, digest, 0, 'accepted', '2026-10-09T00:00:00Z']));
      final originalReceipt = jsonEncode(researchHost.research!.store.db.select(
        'SELECT * FROM rk_import_receipts').map((r) => r.values.toList()).toList());
      await researchHost.close();
      researchHost = await MuyonHost.open(path, modules: [ResearchModule()]);
      PlatformMetadataScopeBinding? researchBinding;
      reads = ToolRegistry(database: researchHost.foundation.database,
        resolveScope: researchHost.scopeResolver.resolve,
        hostToolScopeResolver: (owner, info, call) async =>
          await researchBinding?.resolve(owner, info, call));
      researchBinding = registerPlatformReadTools(registry: reads, foundation: researchHost.foundation,
        executions: ExecutionStore(researchHost.foundation.database), transfer: researchHost.services.transfer,
        isAvailable: () => true);
      final before = changes(researchHost.foundation.database.raw);
      await reads.prepare(request(_ids.first, 'research-metadata'));
      expect(changes(researchHost.foundation.database.raw), before);
      expect(researchHost.services.transfer.items().single.imported, isFalse);
      expect(researchHost.foundation.database.raw.select('SELECT status FROM import_intents '
        'WHERE operation_id=?', [operation.operationId]).single['status'], 'pending');
      await researchHost.activateResearch();
      expect(researchHost.services.transfer.items().single.imported, isTrue);
      expect(researchHost.foundation.database.raw.select('SELECT status FROM import_intents '
        'WHERE operation_id=?', [operation.operationId]).single['status'], 'complete');
      expect(jsonEncode(researchHost.research!.store.db.select('SELECT * FROM rk_import_receipts')
        .map((r) => r.values.toList()).toList()), originalReceipt);
      final transferChanges = changes(researchHost.services.transfer.database.raw);
      await researchHost.activateResearch();
      expect(changes(researchHost.services.transfer.database.raw), transferChanges);
      expect(researchHost.services.transfer.listening, isFalse);
      expect(researchHost.services.transfer.peers, isEmpty);
    } finally { await reads?.close(); await researchHost.close(); }
  });
  test('handler rechecks host authorization after registrar async preparation', () async {
    final handlers = _Handlers();
    PlatformReadTools(foundation: host.foundation,
      executions: ExecutionStore(host.foundation.database), transfer: host.services.transfer)
      .registerTools(handlers);
    var checks = 0;
    final before = changes(audit.raw);
    for (final entry in handlers.handlers.entries) {
      final call = request('platform.${entry.key}', 'handler-${entry.key}');
      await expectLater(entry.value(_Context(ToolCallContext(request: call,
        resolvedScope: ResolvedAssistantScope(requested: call.scope, objects: []),
        cancellation: ToolCancellationToken(), checkAuthorization: () {
          checks++;
          throw const ToolPlatformException('host_unavailable', 'Host metadata is unavailable');
        }))), throwsA(isA<ToolPlatformException>().having((e) => e.code, 'code', 'host_unavailable')));
    }
    expect(checks, 4); expect(changes(audit.raw), before);
    expect(module.activations, 0);
  });

}
