import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/transfer/task_coordinator.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:supplier_core/lan.dart';

void main() {
  const task = 'task-1';
  const revision = 'rev-1';
  const key = 'idem-1';

  test(
    'duplicate offer, single owner, restart, offline status and late result',
    () async {
      final root = Directory.systemTemp.createTempSync('tasks-');
      final leftStore = StorageManager('${root.path}/a');
      final rightStore = StorageManager('${root.path}/b');
      addTearDown(() async {
        await leftStore.close();
        await rightStore.close();
        root.deleteSync(recursive: true);
      });
      final leftDb = await leftStore.open('muyon', WorkspaceRepository.schema);
      final rightDb = await rightStore.open(
        'muyon',
        WorkspaceRepository.schema,
      );
      var leftCalls = 0, rightCalls = 0;
      var reachable = true;
      late TaskCoordinator left, right;
      left = TaskCoordinator(
        database: leftDb,
        deviceId: 'device-a',
        peerReachable: () => reachable,
        send: (envelope) => right.receive(envelope),
        executor: (offer) async {
          leftCalls++;
          return 'from-a:${offer.taskId}';
        },
      );
      right = TaskCoordinator(
        database: rightDb,
        deviceId: 'device-b',
        send: (envelope) => left.receive(envelope),
        executor: (offer) async {
          rightCalls++;
          return 'from-b:${offer.taskId}';
        },
      );

      await left.offer(
        taskId: task,
        inputRevision: revision,
        idempotencyKey: key,
      );
      await left.offer(
        taskId: task,
        inputRevision: revision,
        idempotencyKey: key,
      );
      expect(left.countOf(task, revision), 1);
      expect(right.countOf(task, revision), 1);
      expect(right.stateOf(task, revision), 'offered');
      expect(leftCalls + rightCalls, 0);

      await right.accept(taskId: task, inputRevision: revision);
      await left.accept(taskId: task, inputRevision: revision);
      await left.start(taskId: task, inputRevision: revision);
      await right.start(taskId: task, inputRevision: revision);
      expect(leftCalls, 1);
      expect(rightCalls, 0);
      expect(left.ownerOf(task, revision), 'device-a');
      expect(right.ownerOf(task, revision), 'device-a');
      expect(left.resultOf(task, revision), 'from-a:$task');

      reachable = false;
      expect(
        await left.queryPeer(taskId: task, inputRevision: revision),
        'unknown',
      );
      expect(left.stateOf(task, revision), 'succeeded');

      await left.applyResult(
        taskId: task,
        inputRevision: revision,
        seq: 2,
        result: 'newer',
      );
      await left.applyResult(
        taskId: task,
        inputRevision: revision,
        seq: 1,
        result: 'older',
      );
      expect(left.resultOf(task, revision), 'newer');
    },
  );

  test('restart while running does not execute again', () async {
    final root = Directory.systemTemp.createTempSync('tasks-restart-');
    final store = StorageManager(root.path);
    addTearDown(() async {
      await store.close();
      root.deleteSync(recursive: true);
    });
    final database = await store.open('muyon', WorkspaceRepository.schema);
    var calls = 0;
    final gate = Completer<void>();
    final first = TaskCoordinator(
      database: database,
      deviceId: 'device-a',
      send: (_) async {},
      executor: (_) async {
        calls++;
        await gate.future;
        return 'done';
      },
    );
    await first.offer(
      taskId: task,
      inputRevision: revision,
      idempotencyKey: key,
    );
    await first.accept(taskId: task, inputRevision: revision);
    final pending = first.start(taskId: task, inputRevision: revision);
    while (calls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restarted = TaskCoordinator(
      database: database,
      deviceId: 'device-a',
      send: (_) async {},
      executor: (_) async {
        calls++;
        return 'again';
      },
    );
    await restarted.start(taskId: task, inputRevision: revision);
    expect(calls, 1);
    expect(restarted.stateOf(task, revision), 'running');
    gate.complete();
    await pending;
    expect(calls, 1);
    expect(first.stateOf(task, revision), 'succeeded');
  });

  test('a task envelope received over paired TLS is not executed', () async {
    final calls = <int>[0];
    Future<LanNode> start(String name) async {
      final inbox = Directory.systemTemp.createTempSync('task-lan-$name-');
      final node = await LanNode.start(
        id: name,
        name: name,
        inbox: inbox,
        onPush: (_) {},
        discoveryPort: 0,
        httpPort: 0,
        secrets: MemoryLanSecretStore(),
      );
      addTearDown(() async {
        await node.stop();
        inbox.deleteSync(recursive: true);
        final seen = File('${inbox.path}.seen-pushes.json');
        if (seen.existsSync()) seen.deleteSync();
      });
      return node;
    }

    final alice = await start('alice');
    final bobInbox = Directory.systemTemp.createTempSync('task-lan-bob-');
    final arrived = Completer<String>();
    final bob = await LanNode.start(
      id: 'bob',
      name: 'bob',
      inbox: bobInbox,
      onPush: (push) {
        if (!arrived.isCompleted) arrived.complete(push.path);
      },
      discoveryPort: 0,
      httpPort: 0,
      secrets: MemoryLanSecretStore(),
    );
    addTearDown(() async {
      await bob.stop();
      bobInbox.deleteSync(recursive: true);
      final seen = File('${bobInbox.path}.seen-pushes.json');
      if (seen.existsSync()) seen.deleteSync();
    });
    final seen = await alice.probe('127.0.0.1', port: bob.httpPort);
    alice.confirmPeer(
      fingerprint: seen.fingerprint,
      confirmedCode: bob.identity.shortCode,
      certificatePem: seen.certificatePem,
    );
    final back = await bob.probe('127.0.0.1', port: alice.httpPort);
    bob.confirmPeer(
      fingerprint: back.fingerprint,
      confirmedCode: alice.identity.shortCode,
      certificatePem: back.certificatePem,
    );
    final store = StorageManager('${bobInbox.path}-db');
    addTearDown(() => store.close());
    final coordinator = TaskCoordinator(
      database: await store.open('muyon', WorkspaceRepository.schema),
      deviceId: 'bob',
      send: (_) async {},
      executor: (_) async {
        calls[0]++;
        return 'ran';
      },
    );
    final file = File('${Directory.systemTemp.path}/muyon-task-offer.json');
    file.writeAsStringSync(
      jsonEncode({
        'muyon': TaskCoordinator.marker,
        'type': 'offer',
        'taskId': task,
        'inputRevision': revision,
        'idempotencyKey': 'tls-1',
        'deviceId': 'alice',
      }),
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    await alice.push(seen, file.path);
    final decoded = TaskCoordinator.decodeFile(
      await arrived.future.timeout(const Duration(seconds: 5)),
    );
    await coordinator.receive(decoded!);
    expect(calls.single, 0);
    expect(coordinator.stateOf(task, revision), 'offered');
  });
}
