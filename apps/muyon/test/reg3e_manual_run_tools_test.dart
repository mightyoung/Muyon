import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_tool_registrar.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('reg3e-manual-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
    await host.activateResearch();
    final store = host.research!.store;
    await store.write(() {
      for (final project in ['P', 'Q']) {
        store.db.execute(
          'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
          [project, project, 'question', 'next'],
        );
        final task = store.saveTask(
          id: 'T$project',
          projectId: project,
          title: 'Task $project',
          goal: 'goal',
          spec: {'command': 'must-never-be-executed'},
          expectedRevision: 0,
        );
        store.startManualRun(task);
      }
    });
  });

  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Database db() => host.research!.store.db;
  String runId(String project) =>
      db().select('SELECT id FROM runs WHERE task_id=?', [
            'T$project',
          ]).single['id']
          as String;
  List<Map<String, Object?>> rows(String table) => db()
      .select('SELECT * FROM $table ORDER BY rowid')
      .map((r) => Map<String, Object?>.from(r))
      .toList();

  Future<ObjectRef> current(String type, String id, String project) async {
    final session = await host.research!.openScopeSession();
    try {
      return (await session.resolve(
        ObjectRef(
          moduleId: 'research',
          objectType: type,
          objectId: id,
          nativeProjectId: project,
        ),
      ))!.ref;
    } finally {
      await session.dispose();
    }
  }

  Future<ObjectRef> selected(String tool, [String project = 'P']) => current(
    tool == 'start_manual_run' ? 'task' : 'run',
    tool == 'start_manual_run' ? 'T$project' : runId(project),
    project,
  );

  Map<String, Object?> params(String tool, ObjectRef ref) =>
      tool == 'start_manual_run'
      ? {'task_id': ref.objectId, 'task_revision': int.parse(ref.revisionRef!)}
      : {
          'run_id': ref.objectId,
          'expected_digest': ref.contentDigest,
          'status': 'completed',
          'metrics': {'score': 7},
          'log': 'A log',
          'conclusion': 'A conclusion',
        };

  ToolCallRequest request(
    String tool,
    Map<String, Object?> values,
    List<ObjectRef> refs,
  ) => ToolCallRequest(
    invocationId: 'reg3e-${++invocation}',
    toolId: 'research.$tool',
    parameters: values,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> approved(
    ToolCallRequest call, [
    ToolRegistry? registry,
  ]) async {
    final tools = registry ?? host.tools;
    final approval = await tools.approve(await tools.prepare(call));
    return tools.invoke(call.withApproval(approval));
  }

  for (final tool in ['start_manual_run', 'update_manual_run']) {
    test(
      '$tool approved write returns persisted receipt, run change and log; replay writes once',
      () async {
        final ref = await selected(tool);
        final call = request(tool, params(tool, ref), [ref]);
        final before = ModuleChangeLog.since(db(), 'research', 0);
        final sequence = before.isEmpty ? 0 : before.last.sequence;
        final approval = await host.tools.approve(
          await host.tools.prepare(call),
        );
        final result = await host.tools.invoke(call.withApproval(approval));
        expect(result.status, ToolCallStatus.succeeded, reason: result.summary);
        final returned = result.objectRefs.single;
        expect(returned.objectType, 'run');
        expect(returned.nativeProjectId, 'P');
        expect(returned.contentDigest, isNotEmpty);
        expect(result.changes.single.op, ChangeOp.upsert);
        expect(result.changes.single.ref.toJson(), returned.toJson());
        expect(
          returned.toJson(),
          (await current('run', returned.objectId, 'P')).toJson(),
        );
        final run = db().select('SELECT * FROM runs WHERE id=?', [
          returned.objectId,
        ]).single;
        final data = jsonDecode(run['data'] as String) as Map;
        expect(data['_localManual'], isTrue);
        expect(
          run['status'],
          tool == 'start_manual_run' ? 'running' : 'completed',
        );
        if (tool == 'update_manual_run') {
          expect(data['metrics'], {'score': 7});
          expect(data['logs'], ['A log']);
          expect(data['conclusion'], 'A conclusion');
        }
        expect(
          ModuleChangeLog.since(db(), 'research', sequence).where(
            (c) =>
                c.ref.objectType == 'run' &&
                c.ref.objectId == returned.objectId &&
                c.op == ChangeOp.upsert,
          ),
          isNotEmpty,
        );
        expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
        expect(
          host.tools.receiptFor(call.invocationId)!.result!.toJson(),
          result.toJson(),
        );
        final afterRuns = rows('runs');
        final afterLog = rows('muyon_change_log');
        if (tool == 'start_manual_run') {
          final replay = await host.tools.invoke(call.withApproval(approval));
          expect(replay.toJson(), result.toJson());
        } else {
          // The original run scope is stale after an update. The host refuses
          // it before replay; the operation still cannot execute twice.
          await expectLater(
            host.tools.invoke(call.withApproval(approval)),
            throwsStateError,
          );
          expect(
            host.tools.receiptFor(call.invocationId)!.result!.toJson(),
            result.toJson(),
          );
        }
        expect(rows('runs'), afterRuns);
        expect(rows('muyon_change_log'), afterLog);
      },
    );

    test('$tool without confirmation writes no run or log', () async {
      final ref = await selected(tool);
      final beforeRuns = rows('runs');
      final beforeLog = rows('muyon_change_log');
      final call = request(tool, params(tool, ref), [ref]);
      await expectLater(host.tools.invoke(call), throwsA(isA<Exception>()));
      expect(host.tools.receiptFor(call.invocationId), isNull);
      expect(rows('runs'), beforeRuns);
      expect(rows('muyon_change_log'), beforeLog);
    });

    test(
      '$tool cross-project parameter cannot escape selected scope',
      () async {
        final local = await selected(tool);
        final foreign = await selected(tool, 'Q');
        final beforeRuns = rows('runs');
        final beforeLog = rows('muyon_change_log');
        final call = request(tool, params(tool, foreign), [local]);
        final result = await approved(call);
        expect(result.status, ToolCallStatus.failed, reason: result.summary);
        expect(result.changes, isEmpty);
        expect(rows('runs'), beforeRuns);
        expect(rows('muyon_change_log'), beforeLog);
      },
    );

    test('$tool forged native project is rejected before any write', () async {
      final foreign = await selected(tool, 'Q');
      final forged = ObjectRef(
        moduleId: 'research',
        objectType: foreign.objectType,
        objectId: foreign.objectId,
        nativeProjectId: 'P',
        revisionRef: foreign.revisionRef,
        contentDigest: foreign.contentDigest,
      );
      final beforeRuns = rows('runs');
      final beforeLog = rows('muyon_change_log');
      final call = request(tool, params(tool, foreign), [forged]);
      await expectLater(
        host.tools.prepare(call),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Selected object is missing, changed or outside workspace',
          ),
        ),
      );
      expect(host.tools.receiptFor(call.invocationId), isNull);
      expect(rows('runs'), beforeRuns);
      expect(rows('muyon_change_log'), beforeLog);
    });

    test(
      '$tool mismatched expected value rejects unchanged selected object',
      () async {
        final ref = await selected(tool);
        final values = params(tool, ref);
        values[tool == 'start_manual_run'
            ? 'task_revision'
            : 'expected_digest'] = tool == 'start_manual_run'
            ? 2
            : '0' * 64;
        final beforeRuns = rows('runs');
        final beforeLog = rows('muyon_change_log');
        final result = await approved(request(tool, values, [ref]));
        expect(result.status, ToolCallStatus.failed, reason: result.summary);
        expect(result.changes, isEmpty);
        expect(rows('runs'), beforeRuns);
        expect(rows('muyon_change_log'), beforeLog);
      },
    );

    test(
      '$tool queued cancellation is caught by checkBeforeEffect with zero writes',
      () async {
        final ref = await selected(tool);
        final beforeRuns = rows('runs');
        final beforeLog = rows('muyon_change_log');
        final token = ToolCancellationToken();
        await _queued(host, request(tool, params(tool, ref), [ref]), (_) {}, (
          result,
        ) {
          expect(result.status, isNot(ToolCallStatus.succeeded));
          expect(result.changes, isEmpty);
          expect(rows('runs'), beforeRuns);
          expect(rows('muyon_change_log'), beforeLog);
        }, cancel: token);
      },
    );

    test(
      '$tool queued stale selected object reaches transaction requireCurrent',
      () async {
        final ref = await selected(tool);
        final registry = ToolRegistry(
          database: host.tools.database,
          resolveScope: host.tools.resolveScope,
        );
        final registrar = _ObservedToolRegistrar(registry, host.modules);
        ResearchModule().registerTools(registrar);
        registrar.seal();
        late List<Map<String, Object?>> concurrentRuns;
        late List<Map<String, Object?>> concurrentLog;
        try {
          await _queued(
            host,
            request(tool, params(tool, ref), [ref]),
            (raw) {
              if (tool == 'start_manual_run') {
                // Remove the exact selected revision and its dependent run.
                // Domain unknown-task checking also rejects
                // this; the observed exception proves requireCurrent ran first.
                raw.execute('DELETE FROM runs WHERE task_id=?', [ref.objectId]);
                raw.execute('DELETE FROM tasks WHERE id=?', [ref.objectId]);
              } else {
                raw.execute("UPDATE runs SET status='blocked' WHERE id=?", [
                  ref.objectId,
                ]);
              }
              concurrentRuns = rows('runs');
              concurrentLog = rows('muyon_change_log');
            },
            (result) {
              expect(result.status, ToolCallStatus.failed);
              expect(
                registrar.error,
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  'Selected research object changed',
                ),
              );
              expect(result.changes, isEmpty);
              expect(rows('runs'), concurrentRuns);
              expect(rows('muyon_change_log'), concurrentLog);
            },
            registry: registry,
          );
        } finally {
          await registry.close();
        }
      },
    );

    for (final deleteAfterCommit in [false, true]) {
      test(
        '$tool receipt freezes A when B ${deleteAfterCommit ? 'deletes' : 'updates'} its run after commit',
        () async {
          final ref = await selected(tool);
          final original = host.research!;
          final resources = original.resources;
          final store = original.store;
          late ObjectRef committedA;
          final observed = _AfterCommitDatabase(resources.database, () async {
            expect(db().autocommit, isTrue);
            final id = tool == 'start_manual_run'
                ? db()
                          .select(
                            "SELECT id FROM runs WHERE task_id='TP' ORDER BY rowid DESC LIMIT 1",
                          )
                          .single['id']
                      as String
                : ref.objectId;
            committedA = await current('run', id, 'P');
            await store.write(() {
              if (deleteAfterCommit) {
                store.db.execute('DELETE FROM runs WHERE id=?', [id]);
              } else {
                store.updateManualRun(
                  id,
                  status: 'blocked',
                  metrics: {'score': -1},
                  log: 'B log',
                  conclusion: 'B conclusion',
                );
              }
            });
          });
          host.modules.setRuntimeForTesting(
            'research',
            ResearchRuntime(
              ModuleResources(
                database: observed,
                files: resources.files,
                capabilities: resources.capabilities,
              ),
            ),
          );
          final call = request(tool, params(tool, ref), [ref]);
          final result = await approved(call);
          expect(observed.interceptions, 1);
          expect(
            result.status,
            ToolCallStatus.succeeded,
            reason: result.summary,
          );
          expect(result.objectRefs.single.toJson(), committedA.toJson());
          expect(result.changes.single.ref.toJson(), committedA.toJson());
          final receipt = host.tools.receiptFor(call.invocationId)!;
          expect(receipt.state, 'succeeded');
          expect(
            receipt.result!.objectRefs.single.toJson(),
            committedA.toJson(),
          );
          expect(receipt.result!.toJson(), result.toJson());
          if (!deleteAfterCommit) {
            expect(
              (await current('run', committedA.objectId, 'P')).toJson(),
              isNot(committedA.toJson()),
            );
          }
        },
      );
    }
  }

  test('start refuses an existing old revision even when selected and expected agree', () async {
    final old = await selected('start_manual_run');
    final store = host.research!.store;
    await store.write(
      () => store.saveTask(
        id: 'TP',
        projectId: 'P',
        title: 'Revision 2',
        goal: 'goal',
        spec: {},
        expectedRevision: 1,
      ),
    );
    final beforeRuns = rows('runs');
    final beforeLog = rows('muyon_change_log');
    // The old revision remains resolvable and task_revision matches its ref.
    // Only the latest-revision policy can refuse this otherwise valid request.
    final result = await approved(
      request('start_manual_run', params('start_manual_run', old), [old]),
    );
    expect(result.status, ToolCallStatus.failed, reason: result.summary);
    expect(rows('runs'), beforeRuns);
    expect(rows('muyon_change_log'), beforeLog);
  });

  for (final legacyMarker in [false, true]) {
    test('update refuses real imported spoofed manual run${legacyMarker ? ' persisted before sanitization' : ''} without effects', () async {
      final store = host.research!.store;
      final file = File(p.join(root.path, 'spoofed-result.json'))
        ..writeAsStringSync(jsonEncode({
          'format': 'research-result-v1',
          'runId': 'external-spoof',
          'taskId': 'TP',
          'taskRevision': 1,
          'status': 'running',
          'metrics': {'score': 1},
          'logs': ['external log'],
          'artifacts': <String>[],
          '_localManual': true,
        }));
      final imported = await ResearchExchange(store).importResult(file.path);
      expect(imported.id, 'external-spoof');
      expect(imported.data['_snapshotPath'], isNotEmpty);
      if (legacyMarker) {
        // Model an already persisted result imported by the vulnerable version.
        // Its snapshot provenance still comes from the actual importer.
        await store.write(() {
          final data = WorkbenchStore.decode(db().select(
            'SELECT data FROM runs WHERE id=?', [imported.id],
          ).single['data']);
          data['_localManual'] = true;
          db().execute('UPDATE runs SET data=? WHERE id=?', [jsonEncode(data), imported.id]);
        });
      }
      final ref = await current('run', imported.id, 'P');
      final beforeRuns = rows('runs');
      final beforeLog = rows('muyon_change_log');
      final call = request('update_manual_run', params('update_manual_run', ref), [ref]);
      final result = await approved(call);
      // Check each effect separately so a regression shows the actual mutation.
      expect(rows('runs'), beforeRuns);
      expect(rows('muyon_change_log'), beforeLog);
      expect((await current('run', imported.id, 'P')).toJson(), ref.toJson());
      expect(result.status, ToolCallStatus.failed, reason: result.summary);
      expect(result.objectRefs, isEmpty);
      expect(result.changes, isEmpty);
      final receipt = host.tools.receiptFor(call.invocationId)!;
      expect(receipt.state, 'failed');
      expect(receipt.result!.changes, isEmpty);
    });
  }

  test('update refuses imported run without _localManual', () async {
    final id = runId('P');
    await host.research!.store.write(() {
      final data = jsonDecode(
        db().select('SELECT data FROM runs WHERE id=?', [id]).single['data']
            as String,
      ) as Map<String, dynamic>;
      data.remove('_localManual');
      db().execute('UPDATE runs SET data=? WHERE id=?', [jsonEncode(data), id]);
    });
    final ref = await selected('update_manual_run');
    final beforeRuns = rows('runs');
    final beforeLog = rows('muyon_change_log');
    final result = await approved(
      request('update_manual_run', params('update_manual_run', ref), [ref]),
    );
    expect(result.status, ToolCallStatus.failed);
    expect(rows('runs'), beforeRuns);
    expect(rows('muyon_change_log'), beforeLog);
  });

  test(
    'update refuses status outside running completed failed blocked',
    () async {
      final ref = await selected('update_manual_run');
      final beforeRuns = rows('runs');
      final beforeLog = rows('muyon_change_log');
      final call = request(
        'update_manual_run',
        {...params('update_manual_run', ref), 'status': 'accepted'},
        [ref],
      );
      await expectLater(host.tools.prepare(call), throwsA(isA<Exception>()));
      expect(host.tools.receiptFor(call.invocationId), isNull);
      expect(rows('runs'), beforeRuns);
      expect(rows('muyon_change_log'), beforeLog);
    },
  );

  for (final status in ['running', 'completed', 'failed', 'blocked']) {
    test('update accepts allowed status $status', () async {
      final ref = await selected('update_manual_run');
      final result = await approved(
        request(
          'update_manual_run',
          {...params('update_manual_run', ref), 'status': status},
          [ref],
        ),
      );
      expect(result.status, ToolCallStatus.succeeded, reason: result.summary);
      expect(
        db().select('SELECT status FROM runs WHERE id=?', [
          ref.objectId,
        ]).single['status'],
        status,
      );
    });
  }
}

Future<void> _queued(
  MuyonHost host,
  ToolCallRequest call,
  void Function(Database) concurrent,
  void Function(ToolCallResult) verify, {
  ToolCancellationToken? cancel,
  ToolRegistry? registry,
}) async {
  final resources = host.research!.resources;
  final observed = _ObservedWrite(resources.database);
  host.modules.setRuntimeForTesting(
    'research',
    ResearchRuntime(
      ModuleResources(
        database: observed,
        files: resources.files,
        capabilities: resources.capabilities,
      ),
    ),
  );
  final tools = registry ?? host.tools;
  final approval = await tools.approve(await tools.prepare(call));
  final entered = Completer<void>();
  final release = Completer<void>();
  final holding = (resources.database as ExclusiveDatabase)
      .exclusiveAsync<void>((raw) async {
        entered.complete();
        await release.future;
        concurrent(raw);
      });
  await entered.future;
  try {
    final future = tools.invoke(
      call.withApproval(approval),
      cancellation: cancel ?? ToolCancellationToken(),
    );
    await observed.queued.future.timeout(const Duration(seconds: 5));
    cancel?.cancel();
    release.complete();
    await holding;
    verify(await future);
  } finally {
    if (!release.isCompleted) release.complete();
    await holding;
  }
}

class _ObservedWrite implements ManagedDatabase {
  _ObservedWrite(this.delegate);
  final ManagedDatabase delegate;
  final queued = Completer<void>();
  @override
  Database get raw => delegate.raw;
  @override
  Future<T> write<T>(T Function(Database) body) {
    if (!queued.isCompleted) queued.complete();
    return delegate.write(body);
  }
}

class _AfterCommitDatabase implements ManagedDatabase {
  _AfterCommitDatabase(this.delegate, this.afterCommit);
  final ManagedDatabase delegate;
  final Future<void> Function() afterCommit;
  int interceptions = 0;
  @override
  Database get raw => delegate.raw;
  @override
  Future<T> write<T>(T Function(Database) body) async {
    final result = await delegate.write(body);
    if (interceptions == 0) {
      interceptions++;
      await afterCommit();
    }
    return result;
  }
}

class _ObservedToolRegistrar extends HostToolRegistrar {
  _ObservedToolRegistrar(ToolRegistry registry, ModuleHost modules)
    : super('research', registry, ResearchModule().manifest, modules);
  Object? error;
  @override
  void write(WriteToolSpec spec, ModuleToolHandler handler) {
    super.write(spec, (context) async {
      try {
        return await handler(context);
      } catch (caught) {
        error = caught;
        rethrow;
      }
    });
  }
}
