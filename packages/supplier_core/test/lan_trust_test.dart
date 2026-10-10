import 'dart:io';

import 'package:supplier_core/src/lan.dart';
import 'package:test/test.dart';

void main() {
  Future<LanNode> node(String name) async {
    final dir = Directory.systemTemp.createTempSync('lan-trust-');
    final started = await LanNode.start(
      id: name,
      name: name,
      inbox: dir,
      onPush: (_) {},
      discoveryPort: 0,
      httpPort: 0,
      secrets: MemoryLanSecretStore(),
    );
    addTearDown(() async {
      await started.stop();
      dir.deleteSync(recursive: true);
      final seen = File('${dir.path}.seen-pushes.json');
      if (seen.existsSync()) seen.deleteSync();
    });
    return started;
  }

  Future<void> pair(LanNode left, LanNode right) async {
    final seen = await left.probe('127.0.0.1', port: right.httpPort);
    left.confirmPeer(
      fingerprint: seen.fingerprint,
      confirmedCode: right.identity.shortCode,
      certificatePem: seen.certificatePem,
    );
    final back = await right.probe('127.0.0.1', port: left.httpPort);
    right.confirmPeer(
      fingerprint: back.fingerprint,
      confirmedCode: left.identity.shortCode,
      certificatePem: back.certificatePem,
    );
  }

  test('identity survives secure storage and the short code matches', () async {
    final store = MemoryLanSecretStore();
    final dir = Directory.systemTemp.createTempSync('lan-id-');
    final first = await LanNode.start(
      id: 'device',
      name: 'Device',
      inbox: dir,
      onPush: (_) {},
      discoveryPort: 0,
      httpPort: 0,
      secrets: store,
    );
    final fingerprint = first.identity.fingerprint;
    await first.stop();
    final second = await LanNode.start(
      id: 'device',
      name: 'Device',
      inbox: dir,
      onPush: (_) {},
      discoveryPort: 0,
      httpPort: 0,
      secrets: store,
    );
    addTearDown(() async {
      await second.stop();
      dir.deleteSync(recursive: true);
    });
    expect(second.identity.fingerprint, fingerprint);
    expect(
      DeviceIdentity.codeMatches(fingerprint, second.identity.shortCode),
      isTrue,
    );
    expect(
      DeviceIdentity.codeMatches(fingerprint, second.identity.qrPayload),
      isTrue,
    );
  });

  test('discovery and a copied name do not authorize a payload', () async {
    final received = <LanPush>[];
    final alice = await node('alice');
    final inbox = Directory.systemTemp.createTempSync('lan-mallory-');
    final mallory = await LanNode.start(
      id: 'mallory',
      name: 'alice',
      inbox: inbox,
      onPush: received.add,
      discoveryPort: 0,
      httpPort: 0,
    );
    addTearDown(() async {
      await mallory.stop();
      inbox.deleteSync(recursive: true);
    });
    alice.helloTo(InternetAddress.loopbackIPv4, mallory.discoveryPort);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final announced = mallory.peers.single;
    expect(announced.name, 'alice');
    expect(announced.announcedFingerprint, alice.identity.fingerprint);
    expect(mallory.isPaired(announced.announcedFingerprint), isFalse);
    final file = File('${inbox.path}/x')..writeAsBytesSync([1, 2, 3]);
    await expectLater(
      mallory.push(announced, file.path),
      throwsA(isA<LanException>()),
    );
    expect(alice.inbox.listSync(), isEmpty);
  });

  test(
    'a repeated announcement keeps a fingerprint verified by probe',
    () async {
      final alice = await node('alice');
      final bob = await node('bob');
      await pair(alice, bob);
      expect(alice.peers.single.fingerprint, bob.identity.fingerprint);
      bob.helloTo(InternetAddress.loopbackIPv4, alice.discoveryPort);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(alice.peers.single.fingerprint, bob.identity.fingerprint);
    },
  );

  test('wrong comparison code does not pair', () async {
    final alice = await node('alice');
    final bob = await node('bob');
    final seen = await alice.probe('127.0.0.1', port: bob.httpPort);
    expect(
      () => alice.confirmPeer(
        fingerprint: seen.fingerprint,
        confirmedCode: '0000-0000-0000-0000',
        certificatePem: seen.certificatePem,
      ),
      throwsA(isA<LanException>()),
    );
    expect(alice.isPaired(seen.fingerprint), isFalse);
  });

  test('mitm certificate is rejected and no payload is stored', () async {
    final alice = await node('alice');
    final bob = await node('bob');
    final mallory = await node('mallory');
    await pair(alice, bob);
    final file = File('${alice.inbox.path}/secret')..writeAsBytesSync([9, 9]);
    final impersonated = LanPeer(
      bob.id,
      bob.name,
      '127.0.0.1',
      mallory.httpPort,
      DateTime.now(),
      fingerprint: bob.identity.fingerprint,
      certificatePem: bob.identity.certificatePem,
    );
    await expectLater(
      alice.push(impersonated, file.path),
      throwsA(isA<LanException>()),
    );
    expect(mallory.inbox.listSync(), isEmpty);
    expect(bob.inbox.listSync(), isEmpty);
  });

  test(
    'replay of a delivered message is refused before a second copy',
    () async {
      final received = <String>[];
      final alice = await node('alice');
      final dir = Directory.systemTemp.createTempSync('lan-bob-');
      final bob = await LanNode.start(
        id: 'bob',
        name: 'bob',
        inbox: dir,
        onPush: (push) => received.add(push.path),
        discoveryPort: 0,
        httpPort: 0,
      );
      addTearDown(() async {
        await bob.stop();
        dir.deleteSync(recursive: true);
      });
      await pair(alice, bob);
      final seen = await alice.probe('127.0.0.1', port: bob.httpPort);
      final file = File('${dir.path}/once')..writeAsBytesSync([4, 5, 6]);
      await alice.push(seen, file.path, messageId: 'msg-1', nonce: 'nonce-1');
      await expectLater(
        alice.push(seen, file.path, messageId: 'msg-1', nonce: 'nonce-1'),
        throwsA(isA<LanException>()),
      );
      expect(received, hasLength(1));
      expect(File(received.single).readAsBytesSync(), [4, 5, 6]);
    },
  );

  test('tls context refuses versions below 1.3', () {
    final context = lanTlsContext();
    expect(context.minimumTlsProtocolVersion, TlsProtocolVersion.tls1_3);
    // Dart exposes no maximum protocol version, so a TLS 1.2-only handshake
    // cannot be produced portably. The listener and the client both use
    // lanTlsContext, which is what this assertion locks.
  });

  test('a push signed outside the accept window is refused', () async {
    final alice = await node('alice');
    final bob = await node('bob');
    await pair(alice, bob);
    final seen = await alice.probe('127.0.0.1', port: bob.httpPort);
    final file = File('${alice.inbox.path}/stale')..writeAsBytesSync([1]);
    final stale =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 -
        pushAcceptWindow.inSeconds -
        30;
    await expectLater(
      alice.push(
        seen,
        file.path,
        messageId: 'old',
        nonce: 'old',
        sentAtUnix: stale,
      ),
      throwsA(isA<LanException>()),
    );
    expect(bob.inbox.listSync().whereType<File>(), isEmpty);
  });

  test('replay after restart is refused from the persisted window', () async {
    final aliceStore = MemoryLanSecretStore();
    final bobStore = MemoryLanSecretStore();
    final aliceDir = Directory.systemTemp.createTempSync('lan-replay-a-');
    final bobDir = Directory.systemTemp.createTempSync('lan-replay-b-');
    final received = <String>[];
    Future<LanNode> startBob() => LanNode.start(
      id: 'bob',
      name: 'bob',
      inbox: bobDir,
      onPush: (push) => received.add(push.path),
      discoveryPort: 0,
      httpPort: 0,
      secrets: bobStore,
    );
    final alice = await LanNode.start(
      id: 'alice',
      name: 'alice',
      inbox: aliceDir,
      onPush: (_) {},
      discoveryPort: 0,
      httpPort: 0,
      secrets: aliceStore,
    );
    var bob = await startBob();
    addTearDown(() async {
      await alice.stop();
      await bob.stop();
      aliceDir.deleteSync(recursive: true);
      bobDir.deleteSync(recursive: true);
      for (final path in [
        '${aliceDir.path}.seen-pushes.json',
        '${bobDir.path}.seen-pushes.json',
      ]) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    });
    await pair(alice, bob);
    final first = await alice.probe('127.0.0.1', port: bob.httpPort);
    final file = File('${aliceDir.path}/once')..writeAsBytesSync([7, 8]);
    await alice.push(
      first,
      file.path,
      messageId: 'msg-restart',
      nonce: 'nonce-restart',
    );
    expect(received, hasLength(1));
    await bob.stop();
    bob = await startBob();
    final again = await alice.probe('127.0.0.1', port: bob.httpPort);
    await expectLater(
      alice.push(
        again,
        file.path,
        messageId: 'msg-restart',
        nonce: 'nonce-restart',
      ),
      throwsA(isA<LanException>()),
    );
    expect(received, hasLength(1));
    expect(bobDir.listSync().whereType<File>(), hasLength(1));
  });

  test('plaintext is not accepted', () async {
    final bob = await node('bob');
    final client = HttpClient();
    addTearDown(client.close);
    await expectLater(
      client.post('127.0.0.1', bob.httpPort, '/push').then((request) async {
        request.add([1]);
        return request.close();
      }),
      throwsA(isA<Exception>()),
    );
    expect(bob.inbox.listSync(), isEmpty);
  });

  test('revoked peer is refused and a later push is not stored', () async {
    final alice = await node('alice');
    final bob = await node('bob');
    await pair(alice, bob);
    final seen = await alice.probe('127.0.0.1', port: bob.httpPort);
    bob.revoke(alice.identity.fingerprint);
    final file = File('${alice.inbox.path}/stolen')..writeAsBytesSync([7]);
    await expectLater(
      alice.push(seen, file.path),
      throwsA(isA<LanException>()),
    );
    expect(bob.inbox.listSync(), isEmpty);
    expect(bob.isPaired(alice.identity.fingerprint), isFalse);
    expect(
      () => bob.confirmPeer(
        fingerprint: alice.identity.fingerprint,
        confirmedCode: alice.identity.shortCode,
        certificatePem: alice.identity.certificatePem,
      ),
      throwsA(isA<LanException>()),
    );
  });
}
