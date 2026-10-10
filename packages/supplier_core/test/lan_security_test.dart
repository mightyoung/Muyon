import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supplier_core/src/lan.dart';
import 'package:supplier_core/src/lan_receive_diagnostics.dart';
import 'package:test/test.dart';

void main() {
  final clients = <LanNode, DeviceIdentity>{};
  final receiveEvents = <LanNode, List<LanReceiveEvent>>{};
  final responseSummaries = <LanNode, String>{};

  Future<LanNode> start({
    LanLimits limits = const LanLimits(),
    void Function(LanPush)? onPush,
    void Function()? onPeers,
  }) async {
    final dir = Directory.systemTemp.createTempSync('lan-security-');
    final events = <LanReceiveEvent>[];
    final node = await LanReceiveDiagnostics(events.add).run(() => LanNode.start(
      id: 'local',
      name: 'Local',
      inbox: dir,
      onPush: onPush ?? (_) {},
      onPeers: onPeers,
      limits: limits,
      discoveryPort: 0,
      httpPort: 0,
    ));
    receiveEvents[node] = events;
    addTearDown(() async {
      await node.stop();
      dir.deleteSync(recursive: true);
      final seen = File('${dir.path}.seen-pushes.json');
      if (seen.existsSync()) seen.deleteSync();
    });
    final client = DeviceIdentity.generate();
    node.confirmPeer(
      fingerprint: client.fingerprint,
      confirmedCode: client.shortCode,
      certificatePem: client.certificatePem,
    );
    clients[node] = client;
    return node;
  }

  bool pins(LanNode node, X509Certificate certificate) =>
      DeviceIdentity.fingerprintOfDer(certificate.der) ==
      node.identity.fingerprint;

  Future<int> post(LanNode node, List<int> bytes) async {
    final sender = clients[node]!;
    final client = HttpClient(context: lanTlsContext())
      ..badCertificateCallback = (certificate, host, port) =>
          pins(node, certificate);
    try {
      final nonce = randomToken();
      final messageId = randomToken();
      final sentAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final req = await client.postUrl(
        Uri.parse('https://127.0.0.1:${node.httpPort}/push'),
      );
      req.followRedirects = false;
      req.contentLength = bytes.length;
      req.headers
        ..set('x-muyon-fp', sender.fingerprint)
        ..set('x-muyon-nonce', nonce)
        ..set('x-muyon-msg', messageId)
        ..set('x-muyon-ts', '$sentAt')
        ..set(
          'x-muyon-sig',
          sender.sign(
            pushBinding(
              fingerprint: sender.fingerprint,
              nonce: nonce,
              messageId: messageId,
              sentAtUnix: sentAt,
              length: bytes.length,
              bodyHash: sha256Hex(bytes),
            ),
          ),
        );
      req.add(bytes);
      final res = await req.close();
      final bodyBytes = await res.fold<int>(0, (total, chunk) => total + chunk.length);
      responseSummaries[node] = 'HTTP ${res.statusCode}, bodyBytes=$bodyBytes';
      return res.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  Future<SecureSocket> partial(LanNode node, {int length = 100}) async {
    final sender = clients[node]!;
    final socket = await SecureSocket.connect(
      '127.0.0.1',
      node.httpPort,
      context: lanTlsContext(),
      onBadCertificate: (certificate) => pins(node, certificate),
    );
    final nonce = randomToken();
    final sentAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    socket.write(
      'POST /push HTTP/1.1\r\nHost: localhost\r\n'
      'Content-Length: $length\r\n'
      'x-muyon-fp: ${sender.fingerprint}\r\n'
      'x-muyon-nonce: $nonce\r\n'
      'x-muyon-msg: $nonce-msg\r\n'
      'x-muyon-ts: $sentAt\r\n'
      'x-muyon-sig: AA==\r\n'
      'Connection: close\r\n\r\nx',
    );
    await socket.flush();
    addTearDown(socket.destroy);
    return socket;
  }

  /// Waits for the server to admit the upload: it creates the `push-`
  /// staging directory only after parsing the request and before reading the
  /// body, so from then on no request bytes remain unread on its side.
  Future<void> expectUploadPending(LanNode node) async {
    bool pending() => node.inbox.listSync().any(
      (entry) => entry.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last
          .startsWith('push-'),
    );
    for (var attempt = 0; attempt < 200; attempt++) {
      if (pending()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('the upload never became pending on the server');
  }

  Future<void> expectInboxEmpty(LanNode node) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (node.inbox.listSync().isEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(node.inbox.listSync(), isEmpty);
  }

  Future<void> allowConnectionReset(Future<void> completion) async {
    try {
      await completion;
    } on SocketException catch (error) {
      // Cancelling an incomplete HTTP request can send a TCP reset rather
      // than a FIN. Accept only ECONNRESET (macOS/Linux/Windows); timeouts
      // and other socket failures must still fail the regression.
      if (!{54, 104, 10054}.contains(error.osError?.errorCode)) rethrow;
    }
  }

  Future<void> expectPeerClose(Socket socket) async {
    // Socket exposes failures on both its read stream and its write sink.
    // Attach both handlers immediately, including while a timer is writing.
    unawaited(allowConnectionReset(socket.done.then<void>((_) {})));
    try {
      await allowConnectionReset(
        socket.drain<void>().timeout(const Duration(seconds: 2)),
      );
    } finally {
      socket.destroy();
    }
  }

  test('malformed discovery roots do not escape the socket callback', () async {
    final dir = Directory.systemTemp.createTempSync('lan-security-');
    final node = await LanNode.start(
      id: 'local',
      name: 'Local',
      inbox: dir,
      onPush: (_) {},
      discoveryPort: 0,
      httpPort: 0,
    );
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      udp.close();
      await node.stop();
      dir.deleteSync(recursive: true);
    });
    for (final text in ['[]', 'null', '42', '"name"', '{']) {
      udp.send(
        utf8.encode(text),
        InternetAddress.loopbackIPv4,
        node.discoveryPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    udp.send(
      utf8.encode(
        jsonEncode({
          'siq': 1,
          'id': 'valid',
          'name': 'Valid',
          'port': 1234,
          'reply': true,
        }),
      ),
      InternetAddress.loopbackIPv4,
      node.discoveryPort,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(node.peers.map((p) => p.id), ['valid']);
  });

  test(
    'peer flood is capped, invalid fields rejected and expired peers replaced',
    () async {
      var notifications = 0;
      final node = await start(
        limits: const LanLimits(
          maxPeers: 4,
          peerLifetime: Duration(milliseconds: 400),
        ),
        onPeers: () => notifications++,
      );
      final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(udp.close);
      void send(String id, {Object port = 1234, String name = 'Peer'}) {
        udp.send(
          utf8.encode(
            jsonEncode({
              'siq': 1,
              'id': id,
              'name': name,
              'port': port,
              'reply': true,
            }),
          ),
          InternetAddress.loopbackIPv4,
          node.discoveryPort,
        );
      }

      send('zero', port: 0);
      send('negative', port: -1);
      send('overflow', port: 65536);
      send('long', name: 'x' * 257);
      send('x' * 129);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(node.peers, isEmpty);
      for (var i = 0; i < 80; i++) send('peer-$i');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(node.peers, hasLength(4));
      expect(notifications, lessThanOrEqualTo(2));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      send('replacement');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(node.peers.map((p) => p.id), ['replacement']);
    },
  );

  for (final limits in [
    const LanLimits(maxUploads: 1, uploadIdle: Duration(milliseconds: 200)),
    const LanLimits(
      maxUploadsPerAddress: 1,
      uploadIdle: Duration(milliseconds: 200),
    ),
    const LanLimits(
      maxReservedBytes: 100,
      uploadIdle: Duration(milliseconds: 200),
    ),
  ]) {
    test(
      'active upload budgets reject excess and recover after idle timeout $limits',
      () async {
        final received = <LanPush>[];
        final node = await start(limits: limits, onPush: received.add);
        final stalled = await partial(node);
        final response = expectPeerClose(stalled);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(await post(node, [1, 2]), HttpStatus.serviceUnavailable);
        // Cancelling an incomplete HTTP body may close before an error response.
        await response;
        expect(received, isEmpty);
        await expectInboxEmpty(node);
        expect(await post(node, [1, 2]), HttpStatus.ok);
        expect(received, hasLength(1));
        expect(File(received.single.path).readAsBytesSync(), [1, 2]);
      },
    );
  }

  test(
    'absolute deadline ends a trickling upload and removes partial data',
    () async {
      final node = await start(
        limits: const LanLimits(
          uploadIdle: Duration(milliseconds: 300),
          transferTimeout: Duration(milliseconds: 150),
        ),
      );
      final stalled = await partial(node);
      final response = expectPeerClose(stalled);
      final trickle = Timer.periodic(
        const Duration(milliseconds: 25),
        (_) => stalled.add([1]),
      );
      try {
        await response;
      } finally {
        trickle.cancel();
      }
      await expectInboxEmpty(node);
      expect(
        await post(node, [7]),
        HttpStatus.ok,
        reason: '${responseSummaries[node]}\n${receiveEvents[node]!.join('\n')}',
      );
      final deadlines = receiveEvents[node]!.where(
        (event) => event.kind == LanReceiveEventKind.deadline,
      );
      expect(deadlines, hasLength(1), reason: receiveEvents[node]!.join('\n'));
      expect(deadlines.single.deadlineExpired, isTrue);
      expect(receiveEvents[node]!.where(
        (event) => event.kind == LanReceiveEventKind.cleaned,
      ).first.cleanupSucceeded, isTrue);
    },
  );

  test(
    'stop cancels pending uploads and completes cleanup before returning',
    () async {
      // Guards the contract that stop() does not return until the pending
      // upload has ended and its partial data has been cleaned up.
      final node = await start();
      final socket = await partial(node);
      final response = expectPeerClose(socket);
      // Stop only once the upload is pending. A fixed delay let a slow machine
      // stop before the server had read the request; closing with unread data
      // resets the connection and the client's pending TLS write then fails
      // with EPIPE instead of seeing the close this test is about.
      await expectUploadPending(node);
      await node.stop().timeout(const Duration(seconds: 2));
      await response;
      expect(node.inbox.listSync(), isEmpty);
      final cleaned = receiveEvents[node]!.where(
        (event) => event.kind == LanReceiveEventKind.cleaned,
      ).single;
      expect(cleaned.stopped, isTrue);
      expect(cleaned.cleanupSucceeded, isTrue);
      expect(cleaned.activeUploads, 0);
      expect(cleaned.reservedBytes, 0);
    },
  );

  test(
    'callback failure removes the received file and releases admission',
    () async {
      var calls = 0;
      final node = await start(
        limits: const LanLimits(maxUploads: 1),
        onPush: (_) {
          if (calls++ == 0) throw StateError('receiver unavailable');
        },
      );
      expect(await post(node, [1, 2]), HttpStatus.badRequest);
      await expectInboxEmpty(node);
      expect(await post(node, [3, 4]), HttpStatus.ok);
      expect(node.inbox.listSync(), hasLength(1));
    },
  );

  Future<HttpServer> bindTls(DeviceIdentity identity) {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    return HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  }

  Future<LanPeer> trustServer(LanNode node, DeviceIdentity identity, int port) {
    node.confirmPeer(
      fingerprint: identity.fingerprint,
      confirmedCode: identity.shortCode,
      certificatePem: identity.certificatePem,
    );
    return Future.value(
      LanPeer(
        'remote',
        'Remote',
        '127.0.0.1',
        port,
        DateTime.now(),
        fingerprint: identity.fingerprint,
        certificatePem: identity.certificatePem,
      ),
    );
  }

  test('probe bounds malformed, oversized and stalled responses', () async {
    final node = await start(
      limits: const LanLimits(probeTimeout: Duration(milliseconds: 100)),
    );
    for (final body in ['[]', 'x' * 9000, null]) {
      final server = await bindTls(DeviceIdentity.generate());
      server.listen((req) async {
        if (body != null) {
          req.response.write(body);
          await req.response.close();
        }
      });
      try {
        await expectLater(
          node.probe('127.0.0.1', port: server.port),
          throwsA(isA<LanException>()),
        );
      } finally {
        await server.close(force: true);
      }
    }
  });

  test('push bounds a receiver that never responds', () async {
    final node = await start(
      limits: const LanLimits(transferTimeout: Duration(milliseconds: 100)),
    );
    final file = File('${node.inbox.path}/out')..writeAsBytesSync([1]);
    final identity = DeviceIdentity.generate();
    final server = await bindTls(identity);
    server.listen((req) {
      req.drain<void>();
    });
    try {
      await expectLater(
        node.push(await trustServer(node, identity, server.port), file.path),
        throwsA(isA<LanException>()),
      );
    } finally {
      await server.close(force: true);
    }
  });
  test('stop aborts and drains an outgoing push instead of waiting for transfer timeout', () async {
    final node = await start();
    final file = File('${node.inbox.path}/out')..writeAsBytesSync([1]);
    final identity = DeviceIdentity.generate();
    final server = await bindTls(identity);
    final arrived = Completer<void>();
    server.listen((request) async {
      await request.drain<void>();
      arrived.complete();
      // Deliberately leave the response pending for the normal 15-minute limit.
    });
    addTearDown(() => server.close(force: true));
    final peer = await trustServer(node, identity, server.port);
    final sending = expectLater(
      node.push(peer, file.path),
      throwsA(isA<LanException>()),
    );
    await arrived.future.timeout(const Duration(seconds: 3));
    await node.stop().timeout(const Duration(seconds: 3));
    await sending;
    await expectLater(node.push(peer, file.path), throwsA(isA<LanException>()));
    await expectLater(
      node.probe('127.0.0.1', port: server.port),
      throwsA(isA<LanException>()),
    );
  });
  test('push progress is monotonic and full byte count still awaits receiver response', () async {
    final node = await start();
    final bytes = List<int>.generate(256 * 1024 + 7, (i) => i % 251);
    final file = File('${node.inbox.path}/progress')..writeAsBytesSync(bytes);
    final identity = DeviceIdentity.generate();
    final server = await bindTls(identity);
    final received = Completer<List<int>>();
    final release = Completer<void>();
    server.listen((request) async {
      received.complete(
        await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
      );
      await release.future;
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    });
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await server.close(force: true);
    });
    final progress = <(int, int)>[];
    var completed = false;
    final sending = node
        .push(
          await trustServer(node, identity, server.port),
          file.path,
          onProgress: (sent, total) => progress.add((sent, total)),
        )
        .then((_) => completed = true);
    expect(await received.future.timeout(const Duration(seconds: 3)), bytes);
    expect(progress.length, greaterThan(2));
    expect(progress.first, (0, bytes.length));
    expect(progress.last, (bytes.length, bytes.length));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i].$1, greaterThan(progress[i - 1].$1));
      expect(progress[i].$2, bytes.length);
    }
    expect(completed, isFalse);
    release.complete();
    await sending.timeout(const Duration(seconds: 3));
    expect(completed, isTrue);
  });
}
