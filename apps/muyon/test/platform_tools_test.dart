import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

const _ids = [
  'platform.executions',
  'platform.memories',
  'platform.notifications',
  'platform.device_status',
];
const _secret = 'sk-private-needle-https://user:password@host/private';

void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('platform-tools-');
    host = await MuyonHost.open(root.path, modules: []);
    // This assertion makes the test-first CI fail on the absent feature,
    // rather than an unknown-tool dispatch or a missing import.
    for (final id in _ids) {
      expect(host.tools.inspect(id), isNotNull, reason: '$id not registered');
    }
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ToolCallResult> call(
    String id, {
    Map<String, Object?> parameters = const {},
    AssistantScope scope = const AssistantScope.global(),
    ToolCancellationToken? cancellation,
  }) => host.tools.invoke(
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
    for (final table in [
      'memories', 'notifications', 'execution_records', 'tasks',
      'task_events', 'task_objects', 'settings', 'outbound_tool_requests',
    ])
      table: rows(table),
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

  test('C-TOOL startup identity, schemas and safe descriptions', () async {
    for (final id in _ids) {
      final info = host.tools.inspect(id)!;
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
