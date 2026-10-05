import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/services/transfer/task_coordinator.dart';
import 'package:supplier_core/lan.dart';

void main() {
  test('two hosts accept one offer and a closed peer is unreachable', () async {
    final root = Directory.systemTemp.createTempSync('task-hosts-');
    var leftRuns = 0, rightRuns = 0;
    final left = await MuyonHost.open(
      '${root.path}/a',
      taskExecutor: (offer) async {
        leftRuns++;
        return 'left:${offer.taskId}';
      },
    );
    final right = await MuyonHost.open(
      '${root.path}/b',
      taskExecutor: (offer) async {
        rightRuns++;
        return 'right:${offer.taskId}';
      },
    );
    addTearDown(() async {
      await left.close();
      await right.close();
      for (final name in ['a', 'b']) {
        final seen = File('${root.path}/$name/transfer/inbox.seen-pushes.json');
        if (seen.existsSync()) seen.deleteSync();
      }
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    expect(left.dream.runs(), isEmpty, reason: '启动不跑 Dream');
    expect(right.dream.runs(), isEmpty);

    Future<void> listen(MuyonHost host) => host.services.transfer.start(
      deviceId: host.workspaces.setting('deviceId') as String,
      deviceName: 'host',
      discoveryPort: 0,
      httpPort: 0,
      secrets: MemoryLanSecretStore(),
    );

    await listen(left);
    await listen(right);
    final leftPeer = await left.services.transfer.probe(
      '127.0.0.1',
      port: right.services.transfer.httpPort!,
    );
    left.services.transfer.confirmPeer(
      fingerprint: leftPeer.fingerprint,
      confirmedCode: right.services.transfer.localShortCode!,
      certificatePem: leftPeer.certificatePem,
    );
    final rightPeer = await right.services.transfer.probe(
      '127.0.0.1',
      port: left.services.transfer.httpPort!,
    );
    right.services.transfer.confirmPeer(
      fingerprint: rightPeer.fingerprint,
      confirmedCode: left.services.transfer.localShortCode!,
      certificatePem: rightPeer.certificatePem,
    );

    const task = 'loop-task';
    const revision = 'rev-1';
    await left.tasks.offer(
      taskId: task,
      inputRevision: revision,
      idempotencyKey: 'idem-host',
    );

    Future<void> until(bool Function() ready, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            '$label left=${left.tasks.stateOf(task, revision)}/'
            '${left.tasks.ownerOf(task, revision)} '
            'right=${right.tasks.stateOf(task, revision)}/'
            '${right.tasks.ownerOf(task, revision)} runs=$leftRuns+$rightRuns',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    await until(
      () => right.tasks.stateOf(task, revision) == 'offered',
      'offer',
    );
    await right.services.transfer.itemsSettled;
    expect(leftRuns + rightRuns, 0);
    expect(right.services.transfer.items(), isEmpty);
    expect(right.services.transfer.pendingReceivedPaths, isEmpty);

    final leftId = left.workspaces.setting('deviceId') as String;
    final rightId = right.workspaces.setting('deviceId') as String;
    final winner = leftId.compareTo(rightId) < 0 ? leftId : rightId;
    await Future.wait([
      left.tasks.accept(taskId: task, inputRevision: revision),
      right.tasks.accept(taskId: task, inputRevision: revision),
    ]);
    await until(
      () =>
          left.tasks.ownerOf(task, revision) == winner &&
          right.tasks.ownerOf(task, revision) == winner &&
          left.tasks.stateOf(task, revision) == 'accepted' &&
          right.tasks.stateOf(task, revision) == 'accepted',
      'owners',
    );
    expect(leftRuns + rightRuns, 0);

    await Future.wait([
      left.tasks.start(taskId: task, inputRevision: revision),
      right.tasks.start(taskId: task, inputRevision: revision),
    ]);
    expect(leftRuns + rightRuns, 1);
    expect(left.tasks.ownerOf(task, revision), winner);
    expect(right.tasks.ownerOf(task, revision), winner);
    final winnerHost = winner == leftId ? left : right;
    final winnerRuns = winner == leftId ? leftRuns : rightRuns;
    expect(winnerRuns, 1);
    expect(winnerHost.tasks.stateOf(task, revision), 'succeeded');

    final before = left.tasks.stateOf(task, revision);
    await right.services.transfer.close();
    final view = await left.tasks.queryPeer(
      taskId: task,
      inputRevision: revision,
    );
    expect(view, 'unknown');
    expect(view, isNot('failed'));
    expect(view, isNot('succeeded'));
    expect(left.tasks.stateOf(task, revision), before);
    expect(before, isNot('failed'));
    expect(peerTaskLabel(view), '不可达');
    expect(peerTaskLabel(view), isNot('失败'));
    expect(peerTaskLabel(view), isNot('完成'));
    expect(left.tasks.list(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
