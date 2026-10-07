import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_event_sink.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/task_records.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// K-4: task events in a table, written with the task state; object links.
void main() {
  group('migration 8', () {
    test('v7 -> v8 keeps tasks and their old payload events readable and '
        'numbered on; reopening changes nothing', () async {
      final dir = Directory.systemTemp.createTempSync('muyon-k4-mig-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final v7 = ModuleSchema(
        version: 7,
        definitionDigest: 'foundation-v7',
        migrations: WorkspaceRepository.schema.migrations.take(7).toList(),
      );
      final first = StorageManager(dir.path);
      final old = await first.open('muyon', v7);
      final payload = {
        'kind': 'personal',
        'executionId': 't-old',
        'conversationId': 'c1',
        'prompt': 'hello',
        'scope': AssistantScope.workspace('w1').toJson(),
        'profile': {'id': 'p1'},
        'executionDeviceId': 'dev',
        'state': 'succeeded',
        'stage': 'completed',
        'createdAt': '2026-10-01T00:00:00.000Z',
        'updatedAt': '2026-10-01T00:05:00.000Z',
        'events': [
          {
            'seq': 1,
            'at': 'a',
            'type': 'wait',
            'step': 0,
            'data': {'x': 1},
          },
          {'seq': 2, 'at': 'b', 'type': 'done', 'step': 1},
        ],
      };
      await old.write(
        (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
          't-old',
          'succeeded',
          jsonEncode(payload),
        ]),
      );
      await first.close();

      final second = StorageManager(dir.path);
      final db = await second.open('muyon', WorkspaceRepository.schema);
      final repo = FoundationRepository(db);
      final row = db.raw.select('SELECT * FROM tasks').single;
      expect(row['id'], 't-old');
      expect(row['kind'], 'personal');
      expect(row['state'], 'succeeded');
      expect(row['workspace_id'], 'w1');
      expect(row['profile_id'], 'p1');
      expect(row['finished_at'], '2026-10-01T00:05:00.000Z');
      final events = repo.taskEvents('t-old').map((e) => e.toJson()).toList();
      expect(events, [
        {
          'seq': 1,
          'at': 'a',
          'type': 'wait',
          'step': 0,
          'data': {'x': 1},
        },
        {'seq': 2, 'at': 'b', 'type': 'done', 'step': 1},
      ]);
      // The payload still has its list, and the next event continues it.
      expect(repo.task('t-old')!.payload['events'], hasLength(2));
      await repo.appendTaskEvent('t-old', {'type': 'note'});
      expect(repo.taskEvents('t-old').map((e) => e.seq), [1, 2, 3]);
      final before = db.raw.select('SELECT COUNT(*) AS n FROM task_events');
      await second.close();

      final third = StorageManager(dir.path);
      addTearDown(third.close);
      final again = await third.open('muyon', WorkspaceRepository.schema);
      expect(
        again.raw.select('SELECT COUNT(*) AS n FROM task_events').first['n'],
        before.first['n'],
      );
      expect(again.raw.select('SELECT * FROM tasks'), hasLength(1));
      expect(
        again.raw.select('PRAGMA user_version').first.values.first,
        isNotNull,
      );
      expect(WorkspaceRepository.schema.version, 8);
    });

    test('a payload events list that the table does not hold (a task written '
        'by older code) is still read and numbered on', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      final legacy = [
        {'seq': 1, 'at': 'a', 'type': 'wait'},
        {'seq': 2, 'at': 'b', 'type': 'approval'},
        {'seq': 3, 'at': 'c', 'type': 'model_request'},
      ];
      await f.repo.database.write(
        (db) => db.execute(
          "UPDATE execution_records SET payload=json_set(payload,'\$.events',json(?)) WHERE id=?",
          [jsonEncode(legacy), task.id],
        ),
      );
      f.repo.database.raw.execute('DELETE FROM task_events WHERE task_id=?', [
        task.id,
      ]);
      expect(f.repo.taskEvents(task.id).map((e) => e.type), [
        'wait',
        'approval',
        'model_request',
      ]);
      await f.repo.appendTaskEvent(task.id, {'type': 'done'});
      expect(f.repo.taskEvents(task.id).map((e) => e.seq), [1, 2, 3, 4]);
    });
  });

  group('events and state share one transaction', () {
    test('a failed event write undoes the state change', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      expect(task.state, PersonalTaskState.waitingConfirmation);
      final events = f.repo.taskEvents(task.id).length;
      f.repo.database.raw.execute(
        "CREATE TRIGGER no_write BEFORE INSERT ON task_events "
        "WHEN NEW.type='done' BEGIN SELECT RAISE(ABORT,'disk full'); END",
      );
      await expectLater(
        f.repo.updateTask(
          task.copy({'state': 'succeeded', 'stage': 'completed'}).withEvents([
            const TaskEventDraft('done'),
          ]),
        ),
        throwsA(anything),
      );
      final after = f.repo.task(task.id)!;
      expect(after.state, PersonalTaskState.waitingConfirmation);
      expect(after.stage, task.stage);
      expect(f.repo.taskEvents(task.id), hasLength(events));
      expect(
        f.repo.database.raw.select('SELECT state FROM tasks WHERE id=?', [
          task.id,
        ]).single['state'],
        'waitingConfirmation',
      );
    });

    test('a failed state write leaves no event', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      final events = f.repo.taskEvents(task.id).length;
      f.repo.database.raw.execute(
        'CREATE TRIGGER no_state BEFORE UPDATE ON tasks '
        "BEGIN SELECT RAISE(ABORT,'readonly'); END",
      );
      await expectLater(
        f.repo.updateTask(
          task.copy({'summary': 'x'}).withEvents([
            const TaskEventDraft('wait'),
          ]),
        ),
        throwsA(anything),
      );
      expect(f.repo.taskEvents(task.id), hasLength(events));
      expect(f.repo.task(task.id)!.summary, isNull);
    });

    test('the loop commits its finishing event with the task: when the event '
        'cannot be written the task does not end succeeded', () async {
      final f = await LoopFixture.open();
      f.replies.add(LoopReply.sse(sseText('好')));
      final agent = f.agent();
      var task = await f.start(agent, f.profile());
      f.repo.database.raw.execute(
        "CREATE TRIGGER no_done BEFORE INSERT ON task_events "
        "WHEN NEW.type='done' BEGIN SELECT RAISE(ABORT,'disk full'); END",
      );
      task = await f.run(agent, task);
      expect(task.state, isNot(PersonalTaskState.succeeded));
      expect(
        f.repo
            .messages(task.conversationId)
            .where((m) => m.role == 'assistant'),
        isEmpty,
      );
      expect(
        f.repo.taskEvents(task.id).map((e) => e.type),
        isNot(contains('done')),
      );
    });

    test('state and event of a normal run agree: every wait has its card, '
        'done has the success', () async {
      final f = await LoopFixture.open();
      f.replies.add(LoopReply.sse(sseText('好')));
      final agent = f.agent();
      var task = await f.start(agent, f.profile());
      final waited = f.repo.taskEvents(task.id);
      expect(waited.map((e) => e.type), ['wait']);
      expect(
        f.repo.task(task.id)!.state,
        PersonalTaskState.waitingConfirmation,
      );
      task = await f.run(agent, task);
      expect(task.state, PersonalTaskState.succeeded);
      expect(f.repo.taskEvents(task.id).last.type, 'done');
      final row = f.repo.database.raw.select('SELECT * FROM tasks WHERE id=?', [
        task.id,
      ]).single;
      expect(row['state'], 'succeeded');
      expect(row['finished_at'], isNotNull);
      expect(row['goal'], task.prompt);
    });
  });

  group('seq', () {
    test('goes up by one per task, also for concurrent appends and mixed '
        'with state writes', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final a = await f.start(agent, f.profile());
      final b = await f.start(agent, f.profile());
      final base = f.repo.taskEvents(a.id).length;
      await Future.wait([
        for (var i = 0; i < 25; i++)
          f.repo.appendTaskEvent(i.isEven ? a.id : b.id, {
            'type': 'note',
            'data': {'i': i},
          }),
        for (var i = 0; i < 5; i++)
          f.repo.updateTask(
            f.repo.task(a.id)!.copy({'summary': 's$i'}).withEvents([
              TaskEventDraft('note', data: {'u': i}),
            ]),
          ),
      ]);
      for (final id in [a.id, b.id]) {
        final seqs = f.repo.taskEvents(id).map((e) => e.seq).toList();
        expect(seqs, [for (var i = 1; i <= seqs.length; i++) i], reason: id);
      }
      expect(f.repo.taskEvents(a.id), hasLength(base + 13 + 5));
    });

    test('the table refuses a repeated seq', () async {
      final f = await LoopFixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile());
      expect(
        () => f.repo.database.raw.execute(
          "INSERT INTO task_events VALUES(?,1,'x','wait','{}')",
          [task.id],
        ),
        throwsA(anything),
      );
    });

    test('an event on a task that does not exist is not stored', () async {
      final f = await LoopFixture.open();
      await f.repo.appendTaskEvent('nobody', {'type': 'wait'});
      expect(f.repo.taskEvents('nobody'), isEmpty);
    });
  });

  group('events carry no text or key', () {
    test('a whole run through the table has digests and codes only', () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'read', '{}')])))
        ..add(LoopReply.sse(sseText('MODEL-ANSWER-TEXT [r1]')));
      final agent = f.agent();
      final task = await f.run(agent, await f.start(agent, f.profile()));
      final text = jsonEncode(
        f.repo.taskEvents(task.id).map((e) => e.toJson()).toList(),
      );
      expect(text, isNot(contains('MODEL-ANSWER-TEXT')));
      expect(text, isNot(contains(loopKey)));
      expect(text, isNot(contains('actual result')));
      final stored = f.repo.database.raw
          .select('SELECT payload_json FROM task_events')
          .map((r) => r['payload_json'])
          .join();
      expect(stored, isNot(contains(loopKey)));
    });
  });

  group('sinks', () {
    test('a sink that is not the table gets the same events one by one after '
        'the state', () async {
      final f = await LoopFixture.open();
      f.replies.add(LoopReply.sse(sseText('好')));
      final seen = <String>[];
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        tools: f.tools,
        events: _Listing(f.repo, seen),
      );
      addTearDown(agent.close);
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.succeeded);
      expect(seen, [
        'wait',
        'approval',
        'model_request',
        'model_response',
        'done',
      ]);
      expect(f.repo.taskEvents(task.id), isEmpty, reason: 'not the table');
    });
  });

  group('task_objects', () {
    test('tool results and the answer link their objects; an object finds '
        'its tasks, newest first', () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'read', '{}')])))
        ..add(LoopReply.sse(sseText('看了 [r1]')))
        ..add(LoopReply.sse(sseCalls([('c1', 'read', '{}')])))
        ..add(LoopReply.sse(sseText('又看了 [r1]')));
      final agent = f.agent();
      final first = await f.run(agent, await f.start(agent, f.profile()));
      expect(first.state, PersonalTaskState.succeeded);
      final links = f.repo.taskObjects(first.id);
      expect(links.map((l) => l.role).toSet(), {'tool_result', 'answer'});
      expect(
        links.every((l) => l.ref.objectId == 'b1' && l.ref.moduleId == 'test'),
        isTrue,
      );
      final second = await f.run(agent, await f.start(agent, f.profile()));
      expect(f.repo.tasksForObject(f.ref).map((t) => t.id), [
        second.id,
        first.id,
      ]);
      expect(
        f.repo.tasksForObject(
          const ObjectRef(
            moduleId: 'test',
            objectType: 'budget',
            objectId: 'zz',
          ),
        ),
        isEmpty,
      );
      // Linking again changes nothing.
      final n = f.repo.database.raw
          .select('SELECT COUNT(*) AS n FROM task_objects')
          .first['n'];
      await f.repo.updateTask(f.repo.task(second.id)!.copy({}));
      expect(
        f.repo.database.raw
            .select('SELECT COUNT(*) AS n FROM task_objects')
            .first['n'],
        n,
      );
    });

    test('a write receipt links its result objects too', () async {
      final f = await LoopFixture.open();
      f.replies
        ..add(LoopReply.sse(sseCalls([('c1', 'write', '{}')])))
        ..add(LoopReply.sse(sseText('写了 [r1]')));
      final agent = f.agent();
      var task = await f.run(agent, await f.start(agent, f.profile()));
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = f.repo.task(task.id)!;
      expect(
        f.repo.taskObjects(task.id).map((l) => l.role),
        contains('tool_result'),
      );
      expect(f.repo.tasksForObject(f.ref).single.id, task.id);
    });
  });
}

class _Listing implements AgentEventSink {
  _Listing(this.repo, this.seen);
  final FoundationRepository repo;
  final List<String> seen;
  @override
  Future<void> append(String taskId, AgentEvent event) async =>
      seen.add(event.type);
}
