import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_tool_registrar.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/assistant/execution_store.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/platform_tools.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

const _ids = [
  'platform.executions',
  'platform.memories',
  'platform.notifications',
  'platform.device_status',
];
const _secret = 'sk-private-needle-https://user:password@host/private';

class _Capture implements ToolRegistrar {
  _Capture({this.moduleId = 'platform'});
  final specs = <String, ToolSpec>{};
  final handlers = <String, ModuleToolHandler>{};
  @override
  final String moduleId;
  @override
  void read(ToolSpec spec, ModuleToolHandler handler) {
    expect(specs.containsKey(spec.name), isFalse);
    specs[spec.name] = spec;
    handlers[spec.name] = handler;
  }
  @override
  void write(WriteToolSpec spec, ModuleToolHandler handler) =>
      throw StateError('Unexpected write registration');
  @override
  void external(ExternalToolSpec spec, ModuleToolHandler handler) =>
      throw StateError('Unexpected external registration');
  @override
  HostChannel channel(ChannelSpec spec) =>
      throw StateError('Unexpected channel registration');
}

class _Context implements ModuleToolContext {
  _Context(this.call);
  @override
  final ToolCallContext call;
  @override
  Future<T> runtime<T extends ModuleRuntime>() =>
      throw StateError('Platform must not activate a business runtime');
}

class _Link implements ModuleLink {
  @override
  Future<ModuleState> activate(String moduleId) async =>
      const ModuleState(ModuleStatus.ready);
  @override
  T? runtime<T extends ModuleRuntime>(String moduleId) => null;
}

class _CancellingFoundation extends FoundationRepository {
  _CancellingFoundation(super.database, this.token);
  final ToolCancellationToken token;
  @override
  List<PersonalMemory> memoriesFor(AssistantScope scope) {
    token.cancel();
    return super.memoriesFor(scope);
  }
}

class _NoHttp extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Metadata must not open HTTP clients');
  }
}

void main() {
  late Directory root;
  late MuyonHost host;
  late ToolRegistry tools;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('platform-tools-');
    host = await MuyonHost.open(root.path, modules: []);
    // The shared host resolver can activate business modules, so this slice
    // is deliberately registered into an isolated, pure metadata registry.
    tools = ToolRegistry(database: host.foundation.database,
      resolveScope: (scope) async => ResolvedAssistantScope(requested: scope, objects: []));
    registerPlatformReadTools(registry: tools, foundation: host.foundation,
      executions: ExecutionStore(host.foundation.database), transfer: host.services.transfer,
      isAvailable: () => true);
    for (final id in _ids) {
      expect(tools.inspect(id), isNotNull, reason: '$id not registered');
    }
  });
  tearDown(() async {
    await tools.close();
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ToolCallResult> call(
    String id, {
    Map<String, Object?> parameters = const {},
    AssistantScope scope = const AssistantScope.global(),
    ToolCancellationToken? cancellation,
  }) => tools.invoke(
    ToolCallRequest(
      invocationId: 'platform-test-${invocation++}',
      toolId: id,
      scope: scope,
      parameters: parameters,
    ),
    cancellation: cancellation,
  );

  List<Object?> rows(String table) => [
    for (final row in host.foundation.database.raw.select(
      'SELECT * FROM $table ORDER BY rowid',
    ))
      row.values.toList(),
  ];

  String applicationSnapshot() => jsonEncode({
    for (final row in host.foundation.database.raw.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' "
      "AND name!='tool_invocation_receipts' ORDER BY name",
    ))
      row['name'] as String: rows(row['name'] as String),
  });

  void seedTask(String id, AssistantScope scope, {String state = 'succeeded'}) {
    host.foundation.database.raw.execute(
      'INSERT INTO execution_records VALUES(?,?,?)',
      [id, state, jsonEncode({
        'kind': 'personal', 'executionId': id, 'conversationId': 'conversation',
        'state': state, 'scope': scope.toJson(), 'prompt': _secret,
        'updatedAt': '2026-10-09T00:00:00Z',
        'executionDeviceId': _secret, 'stage': _secret,
        'events': <Object?>[],
      })],
    );
  }

  PlatformReadTools platform({FoundationRepository? foundation}) => PlatformReadTools(
    foundation: foundation ?? host.foundation,
    executions: ExecutionStore(host.foundation.database),
    transfer: host.services.transfer,
  );

  _Context context(String name, {ToolCancellationToken? token,
      AssistantScope scope = const AssistantScope.global()}) => _Context(
    ToolCallContext(
      request: ToolCallRequest(invocationId: 'direct',
        toolId: 'platform.$name', scope: scope),
      resolvedScope: ResolvedAssistantScope(requested: scope,
        objects: scope.objects),
      cancellation: token ?? ToolCancellationToken(),
    ),
  );

  test('C-TOOL captured specs declare scopes and operations; real registrar seals', () async {
    final capture = _Capture();
    platform().registerTools(capture);
    expect(capture.specs.keys.map((n) => 'platform.$n').toSet(), _ids.toSet());
    expect(toolIdsByFunctionNameOf(_ids), hasLength(_ids.length));
    expect(() => platform().registerTools(_Capture(moduleId: 'other')), throwsArgumentError);
    for (final spec in capture.specs.values) {
      expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(spec.name), isTrue);
      expect(spec.operations, isNotEmpty);
      expect(spec.scopes, {AssistantScopeKind.global});
      expect(spec.parameterSchema['type'], 'object');
      expect(spec.resultSchema['type'], 'object');
      expect(spec.parameterSchema['additionalProperties'], isFalse);
      expect(spec.resultSchema['additionalProperties'], isFalse);
    }
    final registry = ToolRegistry(database: host.foundation.database,
      resolveScope: (scope) async => ResolvedAssistantScope(requested: scope, objects: []));
    final registrar = HostToolRegistrar('platform', registry,
      ModuleManifest(id: 'platform', apiVersion: 2), _Link());
    platform().registerTools(registrar);
    expect(() => platform().registerTools(registrar),
      throwsA(isA<ToolPlatformException>()));
    registrar.seal();
    expect(() => registrar.read(capture.specs.values.first,
      capture.handlers.values.first), throwsStateError);
    await registry.close();
  });

  test('host lifecycle link cannot dispatch metadata when unavailable', () async {
    final registry = ToolRegistry(database: host.foundation.database,
      resolveScope: (scope) async => ResolvedAssistantScope(requested: scope, objects: []));
    registerPlatformReadTools(registry: registry, foundation: host.foundation,
      executions: ExecutionStore(host.foundation.database), transfer: host.services.transfer,
      isAvailable: () => false);
    final result = await registry.invoke(ToolCallRequest(invocationId: 'unavailable',
      toolId: 'platform.memories', scope: const AssistantScope.global()));
    expect(result.status, ToolCallStatus.failed);
    expect(result.data, isEmpty);
    await registry.close();
  });

  test('direct handlers make zero DB writes or file changes and no HTTP attempts', () async {
    seedTask('task', const AssistantScope.global());
    await host.foundation.saveMemory(content: _secret, source: _secret);
    await host.foundation.notify(title: _secret, body: _secret);
    final capture = _Capture();
    platform().registerTools(capture);
    String files() {
      final entries = root.listSync(recursive: true).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return jsonEncode({for (final file in entries) file.path: file.readAsBytesSync()});
    }
    final beforeFiles = files();
    final beforeDb = applicationSnapshot();
    final db = host.foundation.database.raw;
    final changes = db.select('SELECT total_changes() AS n').single['n'];
    final guard = _NoHttp();
    await HttpOverrides.runZoned(() async {
      for (final entry in capture.handlers.entries) {
        final result = await entry.value(context(entry.key));
        expect(result.status, ToolCallStatus.succeeded);
      }
    }, createHttpClient: guard.createHttpClient);
    expect(guard.attempts, 0);
    expect(db.select('SELECT total_changes() AS n').single['n'], changes);
    expect(applicationSnapshot(), beforeDb);
    expect(files(), beforeFiles);
    expect(host.services.transfer.listening, isFalse);
  });

  test('handler defence refuses narrow scope even without registry', () async {
    final capture = _Capture();
    platform().registerTools(capture);
    for (final entry in capture.handlers.entries) {
      for (final scope in [AssistantScope.workspace('w'),
        AssistantScope.selectedObjects([const ObjectRef(
          moduleId: 'platform', objectType: 'memory', objectId: 'm')])]) {
        await expectLater(entry.value(context(entry.key, scope: scope)),
          throwsA(isA<ToolPlatformException>().having((e) => e.code,
            'code', 'scope_mismatch')));
      }
    }
  });

  test('cancellation during repository read propagates, not failure', () async {
    final token = ToolCancellationToken();
    final foundation = _CancellingFoundation(host.foundation.database, token);
    final capture = _Capture();
    platform(foundation: foundation).registerTools(capture);
    await expectLater(capture.handlers['memories']!(context('memories', token: token)),
      throwsA(isA<ToolCancelled>()));
    foundation.dispose();
  });

  test('legacy business executions are excluded and event count is capped', () async {
    seedTask('global-task', const AssistantScope.global());
    await ExecutionStore(host.foundation.database).create(AgentExecutionRecord(
      executionId: _secret, toolId: _secret,
      contextSnapshot: ContextRef(workspaceId: 'private-workspace',
        moduleId: 'research', nativeProjectId: 'private-project'),
      executionDeviceId: _secret, state: ExecutionState.queued, stage: _secret,
      createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)));
    for (var i = 1; i <= 110; i++) {
      host.foundation.database.raw.execute('INSERT INTO task_events VALUES(?,?,?,?,?)',
        ['global-task', i, '2026-10-09T00:00:00Z', _secret,
          jsonEncode({'data': {'private': _secret}})]);
    }
    final result = await call('platform.executions');
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.data['items'], [{'state': 'succeeded',
      'updatedAt': '2026-10-09T00:00:00.000Z', 'eventCount': 100}]);
    expect(jsonEncode(result.data), isNot(contains(_secret)));
  });

  test('invalid metadata fails closed without arbitrary stored strings', () async {
    final id = await host.foundation.saveMemory(content: _secret, source: _secret);
    final db = host.foundation.database.raw;
    db.execute('UPDATE memories SET kind=? WHERE id=?', [_secret, id]);
    expect((await call('platform.memories')).status, ToolCallStatus.failed);
    db.execute("UPDATE memories SET kind='fact',revision=-1 WHERE id=?", [id]);
    expect((await call('platform.memories')).status, ToolCallStatus.failed);
    db.execute("UPDATE memories SET revision=9007199254740992 WHERE id=?", [id]);
    expect((await call('platform.memories')).status, ToolCallStatus.failed);
    db.execute("UPDATE memories SET revision=1,updated_at=? WHERE id=?", [_secret, id]);
    final failed = await call('platform.memories');
    expect(failed.status, ToolCallStatus.failed);
    expect(failed.summary, 'Platform metadata is temporarily unavailable.');
    expect(failed.data, isEmpty);
  });

  test('shared global prepare writes lifecycle records before a read handler runs', () async {
    var handlerCalls = 0;
    host.tools.register(providerId: 'platform',
      descriptor: ToolDescriptor(toolId: 'platform.scope_probe', moduleId: 'platform',
        effect: ToolEffect.read, parameterSchema: const {
          'type': 'object', 'properties': <String, Object?>{},
          'additionalProperties': false,
        }),
      dataModuleIds: {'platform'},
      handler: (_) async {
        handlerCalls++;
        return ToolCallResult(status: ToolCallStatus.succeeded, summary: 'probe');
      });
    final db = host.foundation.database.raw;
    final beforeChanges = db.select('SELECT total_changes() AS n').single['n'] as int;
    final notifications = rows('notifications');
    final executions = rows('execution_records');
    final prepared = await host.tools.prepare(ToolCallRequest(invocationId: 'probe-prepare',
      toolId: 'platform.scope_probe', scope: const AssistantScope.global()));
    expect(handlerCalls, 0);
    expect(prepared.resolvedScope.objects, isEmpty);
    expect(db.select('SELECT total_changes() AS n').single['n'] as int,
      greaterThan(beforeChanges));
    final states = db.select('SELECT module_id,status FROM module_registry').map(
      (r) => [r['module_id'], r['status']]).toList();
    expect(states, containsAll([
      ['inquiry', 'failed'], ['research', 'failed'], ['prototype', 'failed'],
    ]));
    expect(rows('notifications'), notifications);
    expect(rows('execution_records'), executions);
    expect(rows('tool_invocation_receipts'), isEmpty);
    // This empty-catalog fixture reproduces activation bookkeeping only.
    // Production research afterActivate may also restore imports and notify;
    // those conditional recovery effects are a separate static risk finding.
  });

  test('C-TOOL isolated host registrar identity, schemas and descriptions', () async {
    for (final id in _ids) {
      final info = tools.inspect(id)!;
      expect(info.providerId, 'platform');
      expect(info.descriptor.moduleId, 'platform');
      expect(info.accessLevel, ToolAccessLevel.read);
      expect(info.descriptor.supportsCancel, isTrue);
      expect(info.descriptor.resultSchema, isNotEmpty);
      expect(info.descriptor.description.length, inInclusiveRange(20, 200));
      for (final word in ['无需确认', '直接执行', '已授权']) {
        expect(info.descriptor.description, isNot(contains(word)));
      }
      final result = await call(id);
      expect(result.status, ToolCallStatus.succeeded);
      expect(result.objectRefs, isEmpty);
      expect(result.artifactRefs, isEmpty);
      expect(result.changes, isEmpty);
    }
  });

  test('rejects unknown fields, types and out of bound limits', () async {
    for (final id in _ids) {
      final invalid = <Map<String, Object?>>[
        {'unexpected': true},
        if (id != 'platform.device_status') ...[
          {'limit': 0}, {'limit': 21}, {'limit': 1.5}, {'limit': '2'},
          {'limit': null},
        ] else {'limit': 1},
        if (id == 'platform.notifications') {'unreadOnly': 'true'},
      ];
      for (final parameters in invalid) {
        await expectLater(call(id, parameters: parameters),
            throwsA(isA<ToolPlatformException>()));
      }
    }
  });

  test('rejects workspace and selected scopes before platform reads', () async {
    for (final id in _ids) {
      for (final scope in [
        AssistantScope.workspace('unbound'),
        AssistantScope.selectedObjects([const ObjectRef(
          moduleId: 'platform', objectType: 'memory', objectId: _secret,
        )]),
      ]) {
        await expectLater(call(id, scope: scope), throwsA(
          isA<ToolPlatformException>().having((e) => e.code, 'code', 'scope_mismatch'),
        ));
      }
    }
  });

  test('global execution metadata excludes project tasks and free text', () async {
    seedTask('global-task', const AssistantScope.global());
    seedTask(_secret, AssistantScope.workspace('private-workspace'));
    final result = await call('platform.executions');
    expect(result.data['items'], [{'state': 'succeeded',
      'updatedAt': '2026-10-09T00:00:00.000Z', 'eventCount': 0}]);
    expect(jsonEncode(result.data), isNot(contains(_secret)));
  });

  test('memory metadata excludes scoped, disabled, expired and unverified', () async {
    await host.foundation.saveMemory(content: _secret, source: _secret);
    await host.foundation.saveMemory(content: _secret, source: _secret,
        scope: AssistantScope.workspace('private-workspace'));
    await host.foundation.saveMemory(content: _secret, source: _secret, disabled: true);
    await host.foundation.saveMemory(content: _secret, source: _secret, verified: false);
    await host.foundation.saveMemory(content: _secret, source: _secret,
        expiresAt: DateTime.utc(2000));
    final result = await call('platform.memories');
    final items = result.data['items'] as List;
    expect(items, hasLength(1));
    expect((items.single as Map).keys.toSet(), {'kind', 'revision', 'updatedAt'});
    expect(jsonEncode(result.data), isNot(contains(_secret)));
  });

  test('notification metadata excludes project and orphan task associations', () async {
    seedTask('global-task', const AssistantScope.global());
    seedTask('project-task', AssistantScope.workspace('private-workspace'));
    for (final task in [null, 'global-task', 'project-task', 'missing-task']) {
      await host.foundation.notify(title: _secret, body: _secret, taskId: task);
    }
    final firstId = host.foundation.notifications().first.id;
    await host.foundation.markNotificationRead(firstId);
    final result = await call('platform.notifications');
    expect(result.data['items'], hasLength(2));
    expect(jsonEncode(result.data), isNot(contains(_secret)));
    final unread = await call('platform.notifications', parameters: {'unreadOnly': true});
    expect((unread.data['items'] as List).every((r) => (r as Map)['read'] == false), isTrue);
  });

  test('list output count and every string are bounded', () async {
    for (var i = 0; i < 25; i++) {
      seedTask('task-$i', const AssistantScope.global());
      await host.foundation.saveMemory(content: _secret * 100, source: _secret);
      await host.foundation.notify(title: _secret * 100, body: _secret * 100);
    }
    void stringsBounded(Object? value) {
      if (value is String) expect(value.length, lessThanOrEqualTo(40));
      if (value is Map) value.values.forEach(stringsBounded);
      if (value is List) value.forEach(stringsBounded);
    }
    for (final id in _ids.take(3)) {
      expect((await call(id)).data['items'], hasLength(10));
      final result = await call(id, parameters: {'limit': 20});
      expect(result.data['items'], hasLength(20));
      stringsBounded(result.data);
      expect(jsonEncode(result.data), isNot(contains(_secret)));
    }
  });

  test('reads preserve application DB, files and disabled network state', () async {
    await host.foundation.saveMemory(content: _secret, source: _secret);
    await host.foundation.notify(title: _secret, body: _secret);
    seedTask('task', const AssistantScope.global());
    final before = applicationSnapshot();
    final files = root.listSync(recursive: true).map((e) => e.path).toSet();
    expect(host.services.transfer.listening, isFalse);
    for (final id in _ids) {
      expect((await call(id)).status, ToolCallStatus.succeeded);
    }
    expect(applicationSnapshot(), before);
    expect(root.listSync(recursive: true).map((e) => e.path).toSet(), files);
    expect(host.services.transfer.listening, isFalse);
    expect(host.services.transfer.peers, isEmpty);
    expect((await call('platform.device_status')).data, {'listening': false});
  });

  test('pre-cancelled calls cannot read or mutate application data', () async {
    final before = applicationSnapshot();
    for (final id in _ids) {
      final token = ToolCancellationToken()..cancel();
      await expectLater(call(id, cancellation: token), throwsA(isA<ToolCancelled>()));
    }
    expect(applicationSnapshot(), before);
  });

  test('malformed stored task returns fixed failure and fresh call can recover', () async {
    seedTask('task', const AssistantScope.global(), state: _secret);
    final failed = await call('platform.executions');
    expect(failed.status, ToolCallStatus.failed);
    expect(failed.summary, 'Platform metadata is temporarily unavailable.');
    expect(failed.data, isEmpty);
    host.foundation.database.raw.execute('DELETE FROM execution_records');
    final recovered = await call('platform.executions');
    expect(recovered.status, ToolCallStatus.succeeded);
    expect(recovered.data['items'], isEmpty);
  });
}
