import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/plugin_contract/process.dart';

import 'support/plugin_fixture.dart';

void main() {
  test('live revoke and scope changes prevent handler execution', () async {
    for (final change in ['read', 'source', 'binding', 'scope']) {
      final f = await PluginFixture.open();
      expect(f.enrolled, isTrue, reason: 'valid fixture enrollment must precede revoke tests');
      var snapshots = 0;
      f.beforeSnapshot = () async {
        snapshots++;
        if (snapshots == 2) {
          if (change == 'read') f.allowed = false;
          if (change == 'source') f.sourceRevision = 's2';
          if (change == 'binding') f.bindingRevision = 'b2';
          if (change == 'scope') f.loop.objects = [];
        }
      };
      await f.runRead();
      expect(snapshots, greaterThanOrEqualTo(2));
      expect(f.handlerCalls, 0);
      expect(f.loop.bodies, hasLength(1));
    }
    for (final change in ['read', 'source', 'binding']) {
      final f = await PluginFixture.open();
      expect(f.enrolled, isTrue);
      final barrier = FixtureBarrier();
      addTearDown(barrier.resume);
      f.beforeSnapshot = () async {
        if (f.receipt != null && !f.projectionReviewed) await barrier.stop();
      };
      final running = f.runRead();
      await barrier.reached(running);
      final identity = f.receipt!.identityDigest;
      if (change == 'read') f.allowed = false;
      if (change == 'source') f.sourceRevision = 'revoked';
      if (change == 'binding') f.bindingRevision = 'revoked';
      barrier.resume();
      await running;
      expect(f.handlerCalls, 1);
      expect(f.receipt!.identityDigest, identity);
      expect(f.receipt!.succeeded, isTrue);
      expect(f.bridge.projectionFor(f.invocationId!, identity), isNull);
      expect(f.loop.bodies, hasLength(1));
    }
  });

  test('owner receipt survives projection rejection', () async {
    for (final invalid in ['schema', 'reference']) {
      final f = await PluginFixture.open();
      expect(f.enrolled, isTrue);
      f.malformedProjection = invalid == 'schema';
      f.foreignRef = invalid == 'reference';
      await f.runRead();
      expect(f.handlerCalls, 1);
      expect(f.receipt!.succeeded, isTrue);
      expect(f.receipt!.result!.summary, PluginFixture.poison);
      expect(f.loop.receipts(), hasLength(1));
      expect(f.bridge.projectionFor(f.invocationId!, f.receipt!.identityDigest), isNull);
      expect(f.loop.bodies, hasLength(1));
    }
  });

  test('cancel and process failure preserve owner semantics', () async {
    final f = await PluginFixture.open();
    expect(f.enrolled, isTrue);
    final barrier = FixtureBarrier();
    addTearDown(barrier.resume);
    f.onHandler = barrier.stop;
    final running = f.runRead();
    await barrier.reached(running);
    final taskRows = f.loop.repo.database.raw.select("SELECT id FROM tasks WHERE state='running'");
    expect(taskRows, hasLength(1));
    final cancellation = f.agent.cancel(taskRows.single['id'] as String);
    barrier.resume();
    await cancellation;
    await running;
    expect(f.handlerCalls, 1);
    expect(f.loop.receipts(), hasLength(1));
    expect(f.bridge.projectionFor(f.invocationId!, f.receipt!.identityDigest), isNull);
    expect(f.loop.bodies, hasLength(1));

    for (final termination in ['deadline', 'eof', 'close']) {
      final process = PluginContractProcess(
        executable: Platform.environment['MUYON_PLUGIN_CONTRACT_BIN']!,
        deadline: const Duration(milliseconds: 100),
      );
      addTearDown(process.close);
      await process.start();
      final exit = process.exitCode!;
      if (termination == 'eof') {
        // Kill only the PID launched by this fixture's concrete transport.
        Process.killPid(process.pid!, ProcessSignal.sigkill);
      } else if (termination == 'deadline') {
        Process.killPid(process.pid!, ProcessSignal.sigstop);
      }
      final response = process.request({'command': 'inspect'});
      if (termination == 'close') await process.close();
      if (termination == 'close') {
        // A request accepted before close can already have a response.
        await response.then<void>((_) {}, onError: (_) {});
      } else {
        await expectLater(response, throwsA(anything));
      }
      await process.close();
      await process.close();
      await exit.timeout(const Duration(seconds: 3));
      expect(process.pendingCount, 0);
      expect(process.isClosed, isTrue);
    }
  });
}
