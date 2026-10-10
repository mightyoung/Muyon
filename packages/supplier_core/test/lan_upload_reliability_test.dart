import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supplier_core/src/lan.dart';
import 'package:supplier_core/src/lan_receive_diagnostics.dart';
import 'package:test/test.dart';

// Real filesystem fault: the destination of file.rename is a directory.
// No filesystem exception is mocked.
class RenameBlockedInbox implements Directory {
  RenameBlockedInbox(this.directory);
  final Directory directory;
  final obstacles = <Directory>[];

  @override
  String get path => directory.path;

  @override
  void createSync({bool recursive = false}) =>
      directory.createSync(recursive: recursive);

  @override
  Future<Directory> createTemp([String? prefix]) async {
    final staging = await directory.createTemp(prefix);
    obstacles.add(await Directory('${staging.path}.siq').create());
    return staging;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<int> signedPost(
  LanNode node,
  DeviceIdentity sender, {
  String message = 'rename-failure',
  String nonce = 'first-attempt',
  bool validProof = true,
}) async {
  final client = HttpClient(context: lanTlsContext())
    ..badCertificateCallback = (certificate, host, port) =>
        DeviceIdentity.fingerprintOfDer(certificate.der) ==
        node.identity.fingerprint;
  try {
    final request = await client.postUrl(
      Uri.parse('https://127.0.0.1:${node.httpPort}/push'),
    );
    const bytes = [7];
    final sentAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    request.contentLength = bytes.length;
    request.headers
      ..set('x-muyon-fp', sender.fingerprint)
      ..set('x-muyon-nonce', nonce)
      ..set('x-muyon-msg', message)
      ..set('x-muyon-ts', '$sentAt')
      ..set(
        'x-muyon-sig',
        validProof ? sender.sign(
          pushBinding(
            fingerprint: sender.fingerprint,
            nonce: nonce,
            messageId: message,
            sentAtUnix: sentAt,
            length: bytes.length,
            bodyHash: sha256Hex(bytes),
          ),
        ) : 'AA==',
      );
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  diagnosticTests();
  cleanupDiagnosticTest();
  test('rename failure never records an undelivered message durably', () async {
    final dir = Directory.systemTemp.createTempSync('lan-rename-');
    final inbox = RenameBlockedInbox(dir);
    final pushes = <LanPush>[];
    final events = <LanReceiveEvent>[];
    final node = await LanReceiveDiagnostics(events.add).run(() => LanNode.start(
      id: 'receiver',
      name: 'Receiver',
      inbox: inbox,
      onPush: pushes.add,
      discoveryPort: 0,
      httpPort: 0,
    ));
    final sender = DeviceIdentity.generate();
    node.confirmPeer(
      fingerprint: sender.fingerprint,
      confirmedCode: sender.shortCode,
      certificatePem: sender.certificatePem,
    );
    final seen = File('${dir.path}.seen-pushes.json');
    addTearDown(() async {
      await node.stop();
      dir.deleteSync(recursive: true);
      if (seen.existsSync()) seen.deleteSync();
    });
    expect(await signedPost(node, sender), HttpStatus.badRequest);
    expect(pushes, isEmpty);
    expect(events.where((e) => e.kind == LanReceiveEventKind.failure)
        .map((e) => (e.stage, e.error)),
        [(LanReceiveStage.rename, LanReceiveError.filesystem)],
        reason: events.join('\n'));
    expect(dir.listSync().whereType<File>(), isEmpty);
    expect(dir.listSync().whereType<Directory>().map((d) => d.path),
        inbox.obstacles.map((d) => d.path));
    // A failed rename precedes callback invocation. It must not become a
    // durable claim that this message was delivered across receiver restart.
    expect(seen.existsSync(), isFalse);
    final cleaned = events.where((e) => e.kind == LanReceiveEventKind.cleaned).single;
    expect(cleaned.cleanupSucceeded, isTrue);
    expect(cleaned.activeUploads, 0);
    expect(cleaned.reservedBytes, 0);
    // Before-body reservations still reject the same message in this process.
    expect(await signedPost(node, sender, nonce: 'same-process'), HttpStatus.conflict);
    await node.stop();
    for (final obstacle in inbox.obstacles) {
      await obstacle.delete();
    }
    final restarted = await LanNode.start(
      id: 'receiver', name: 'Receiver', inbox: dir, onPush: pushes.add,
      discoveryPort: 0, httpPort: 0, identity: node.identity,
    );
    addTearDown(restarted.stop);
    restarted.confirmPeer(fingerprint: sender.fingerprint,
        confirmedCode: sender.shortCode, certificatePem: sender.certificatePem);
    expect(await signedPost(restarted, sender, nonce: 'after-restart'), HttpStatus.ok);
    expect(pushes, hasLength(1));
    expect(File(pushes.single.path).readAsBytesSync(), [7]);
    expect(await signedPost(restarted, sender, nonce: 'delivered-replay'),
        HttpStatus.conflict);
  });
}

class ControlledInbox implements Directory {
  ControlledInbox(this.directory);
  final Directory directory;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool pause = true;

  @override
  String get path => directory.path;

  @override
  void createSync({bool recursive = false}) =>
      directory.createSync(recursive: recursive);

  @override
  Future<Directory> createTemp([String? prefix]) async {
    if (pause) {
      entered.complete();
      await release.future;
    }
    return directory.createTemp(prefix);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ReceiveRecorder {
  final events = <LanReceiveEvent>[];
  final deadline = Completer<void>();
  void add(LanReceiveEvent event) {
    events.add(event);
    if (event.kind == LanReceiveEventKind.deadline && !deadline.isCompleted) {
      deadline.complete();
    }
  }

  void expectReleased({required bool retained}) {
    final cleaned = events.where((e) => e.kind == LanReceiveEventKind.cleaned);
    expect(cleaned, isNotEmpty, reason: events.join('\n'));
    expect(cleaned.last.cleanupSucceeded, isTrue, reason: events.join('\n'));
    expect(cleaned.last.activeUploads, 0);
    expect(cleaned.last.reservedBytes, 0);
    expect(cleaned.last.retained, retained);
  }
}

Future<(LanNode, DeviceIdentity, Directory)> observedNode(
  ReceiveRecorder recorder, {
  Directory Function(Directory)? inboxFactory,
  void Function(LanPush)? onPush,
  LanLimits limits = const LanLimits(maxUploads: 1),
}) async {
  final dir = Directory.systemTemp.createTempSync('lan-observed-');
  final node = await LanReceiveDiagnostics(recorder.add).run(
    () => LanNode.start(
      id: 'receiver',
      name: 'Receiver',
      inbox: inboxFactory?.call(dir) ?? dir,
      onPush: onPush ?? (_) {},
      discoveryPort: 0,
      httpPort: 0,
      limits: limits,
    ),
  );
  final sender = DeviceIdentity.generate();
  node.confirmPeer(
    fingerprint: sender.fingerprint,
    confirmedCode: sender.shortCode,
    certificatePem: sender.certificatePem,
  );
  addTearDown(() async {
    await node.stop();
    dir.deleteSync(recursive: true);
    final seen = File('${dir.path}.seen-pushes.json');
    if (seen.existsSync()) seen.deleteSync();
  });
  return (node, sender, dir);
}

// Called from main below; the real receiver deadline is the synchronization
// event. No sleep or client-side latency is used as proof of expiry.
void diagnosticTests() {
  test('malformed HTTP length never reaches upload admission', () async {
    final recorder = ReceiveRecorder();
    final pushes = <LanPush>[];
    final (node, _, dir) = await observedNode(recorder, onPush: pushes.add);
    final socket = await SecureSocket.connect(
      '127.0.0.1', node.httpPort, context: lanTlsContext(),
      onBadCertificate: (certificate) =>
          DeviceIdentity.fingerprintOfDer(certificate.der) == node.identity.fingerprint,
    );
    addTearDown(socket.destroy);
    final reading = socket.fold<List<int>>([], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 3));
    socket.write('POST /push HTTP/1.1\r\nHost: localhost\r\n'
        'Content-Length: invalid\r\nConnection: close\r\n\r\n');
    await socket.flush();
    final response = String.fromCharCodes(await reading);
    final fields = response.split(' ');
    final status = fields.length > 1 ? int.tryParse(fields[1]) : null;
    expect(status, HttpStatus.badRequest, reason: recorder.events.join('\n'));
    expect(pushes, isEmpty);
    expect(dir.listSync(), isEmpty);
    expect(recorder.events.where((e) =>
        e.stage == LanReceiveStage.admission || e.stage == LanReceiveStage.deliver), isEmpty);
    // HttpServer may generate 400 without a request or stream error callback.
    // Absence of an attempt is evidence of pre-dispatch failure, not its cause.
  });

  test('complete legal body held in filesystem hits receiver deadline', () async {
    final recorder = ReceiveRecorder();
    final pushes = <LanPush>[];
    late ControlledInbox controlled;
    final (node, sender, dir) = await observedNode(
      recorder,
      inboxFactory: (dir) => controlled = ControlledInbox(dir),
      onPush: pushes.add,
      limits: const LanLimits(
        maxUploads: 1,
        transferTimeout: Duration(milliseconds: 150),
      ),
    );
    // Registered after node teardown, so release happens first even on failure.
    addTearDown(() {
      if (!controlled.release.isCompleted) controlled.release.complete();
    });
    final status = signedPost(node, sender);
    await controlled.entered.future.timeout(const Duration(seconds: 3));
    await recorder.deadline.future.timeout(const Duration(seconds: 3));
    expect(recorder.events.where((e) => e.kind == LanReceiveEventKind.deadline)
        .single.stage, LanReceiveStage.createTemp);
    controlled.pause = false;
    controlled.release.complete();
    expect(await status, HttpStatus.badRequest, reason: recorder.events.join('\n'));
    expect(pushes, isEmpty);
    expect(dir.listSync(), isEmpty);
    expect(File('${dir.path}.seen-pushes.json').existsSync(), isFalse);
    recorder.expectReleased(retained: false);
    expect(await signedPost(node, sender, message: 'next', nonce: 'next'),
        HttpStatus.ok, reason: recorder.events.join('\n'));
    expect(pushes, hasLength(1));
    recorder.expectReleased(retained: true);
  });

  test('persistence failure is classified and final file removed', () async {
    final recorder = ReceiveRecorder();
    final pushes = <LanPush>[];
    final (node, sender, dir) = await observedNode(recorder, onPush: pushes.add);
    final obstruction = Directory('${dir.path}.seen-pushes.json')..createSync();
    addTearDown(() {
      if (obstruction.existsSync()) obstruction.deleteSync();
    });
    expect(await signedPost(node, sender), HttpStatus.badRequest);
    expect(pushes, isEmpty);
    expect(dir.listSync(), isEmpty);
    expect(recorder.events.where((e) => e.kind == LanReceiveEventKind.failure)
        .map((e) => (e.stage, e.error)),
        [(LanReceiveStage.persist, LanReceiveError.filesystem)]);
    recorder.expectReleased(retained: false);
    obstruction.deleteSync();
    expect(await signedPost(node, sender, message: 'next', nonce: 'next'),
        HttpStatus.ok);
    expect(pushes, hasLength(1));
    recorder.expectReleased(retained: true);
    final persisted = jsonDecode(File('${dir.path}.seen-pushes.json').readAsStringSync()) as Map;
    // A failed persistence write must not leave a tentative in-memory entry
    // that a later unrelated successful upload accidentally writes durably.
    expect(persisted.containsKey('rename-failure'), isFalse);
    expect(persisted.containsKey('next'), isTrue);
  });

  test('bad proof is distinguished from filesystem and deadline failures', () async {
    final recorder = ReceiveRecorder();
    final (node, sender, dir) = await observedNode(recorder);
    expect(await signedPost(node, sender, validProof: false), HttpStatus.badRequest);
    expect(dir.listSync(), isEmpty);
    expect(File('${dir.path}.seen-pushes.json').existsSync(), isFalse);
    expect(recorder.events.where((e) => e.kind == LanReceiveEventKind.failure)
        .map((e) => (e.stage, e.error)),
        [(LanReceiveStage.verify, LanReceiveError.format)]);
    expect(recorder.events.where((e) => e.kind == LanReceiveEventKind.deadline), isEmpty);
    recorder.expectReleased(retained: false);
  });

  test('callback failure preserves replay refusal and hides exception text', () async {
    final recorder = ReceiveRecorder();
    var calls = 0;
    const sensitive = 'private-payload-key-signature';
    final (node, sender, dir) = await observedNode(recorder, onPush: (_) {
      calls++;
      throw StateError(sensitive);
    });
    expect(await signedPost(node, sender), HttpStatus.badRequest);
    expect(calls, 1);
    expect(dir.listSync(), isEmpty);
    expect(File('${dir.path}.seen-pushes.json').existsSync(), isTrue);
    expect(recorder.events.where((e) => e.kind == LanReceiveEventKind.failure)
        .map((e) => (e.stage, e.error)),
        [(LanReceiveStage.deliver, LanReceiveError.state)]);
    expect(recorder.events.join('\n'), isNot(contains(sensitive)));
    expect(recorder.events.join('\n'), isNot(contains(sender.fingerprint)));
    expect(recorder.events.join('\n'), isNot(contains(dir.path)));
    recorder.expectReleased(retained: false);
    expect(await signedPost(node, sender, nonce: 'fresh-nonce'), HttpStatus.conflict);
    expect(calls, 1);
    await node.stop();
    final restarted = await LanNode.start(
      id: 'receiver', name: 'Receiver', inbox: dir, onPush: (_) => calls++,
      discoveryPort: 0, httpPort: 0, identity: node.identity,
    );
    addTearDown(restarted.stop);
    restarted.confirmPeer(fingerprint: sender.fingerprint,
        confirmedCode: sender.shortCode, certificatePem: sender.certificatePem);
    expect(await signedPost(restarted, sender, nonce: 'after-restart'),
        HttpStatus.conflict);
    expect(calls, 1);
  });

  test('observer exceptions cannot reject a valid push', () async {
    final dir = Directory.systemTemp.createTempSync('lan-observer-');
    final pushes = <LanPush>[];
    final node = await LanReceiveDiagnostics((_) => throw StateError('observer'))
        .run(() => LanNode.start(
      id: 'receiver', name: 'Receiver', inbox: dir, onPush: pushes.add,
      discoveryPort: 0, httpPort: 0,
    ));
    final sender = DeviceIdentity.generate();
    node.confirmPeer(fingerprint: sender.fingerprint,
        confirmedCode: sender.shortCode, certificatePem: sender.certificatePem);
    addTearDown(() async {
      await node.stop();
      dir.deleteSync(recursive: true);
      final seen = File('${dir.path}.seen-pushes.json');
      if (seen.existsSync()) seen.deleteSync();
    });
    expect(await signedPost(node, sender), HttpStatus.ok);
    expect(pushes, hasLength(1));
    expect(File(pushes.single.path).readAsBytesSync(), [7]);
  });
}

class CleanupFailureInbox implements Directory {
  CleanupFailureInbox(this.directory);
  final Directory directory;
  bool failCleanup = true;

  @override
  String get path => directory.path;
  @override
  void createSync({bool recursive = false}) =>
      directory.createSync(recursive: recursive);
  @override
  Future<Directory> createTemp([String? prefix]) async =>
      CleanupFailureStaging(await directory.createTemp(prefix), this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CleanupFailureStaging implements Directory {
  CleanupFailureStaging(this.directory, this.inbox);
  final Directory directory;
  final CleanupFailureInbox inbox;
  @override
  String get path => directory.path;
  @override
  Future<bool> exists() => directory.exists();
  @override
  Future<Directory> delete({bool recursive = false}) {
    if (inbox.failCleanup) {
      throw FileSystemException('private cleanup fault', directory.path);
    }
    return directory.delete(recursive: recursive);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void cleanupDiagnosticTest() {
  test('cleanup failure is reported separately and admission still releases', () async {
    final recorder = ReceiveRecorder();
    late CleanupFailureInbox inbox;
    final (node, sender, dir) = await observedNode(recorder,
        inboxFactory: (dir) => inbox = CleanupFailureInbox(dir));
    expect(await signedPost(node, sender, validProof: false), HttpStatus.badRequest);
    expect(recorder.events.where((e) => e.kind == LanReceiveEventKind.failure)
        .map((e) => (e.stage, e.error)), [
      (LanReceiveStage.verify, LanReceiveError.format),
      (LanReceiveStage.cleanup, LanReceiveError.filesystem),
    ], reason: recorder.events.join('\n'));
    final cleanup = recorder.events.where((e) =>
        e.kind == LanReceiveEventKind.cleaned).single;
    expect(cleanup.cleanupSucceeded, isFalse);
    expect(cleanup.activeUploads, 0);
    expect(cleanup.reservedBytes, 0);
    expect(cleanup.retained, isFalse);
    expect(dir.listSync().whereType<Directory>(), hasLength(1));
    expect(File('${dir.path}.seen-pushes.json').existsSync(), isFalse);
    expect(recorder.events.join('\n'), isNot(contains('private cleanup fault')));
    expect(recorder.events.join('\n'), isNot(contains(dir.path)));
    inbox.failCleanup = false;
    for (final entry in dir.listSync()) {
      await entry.delete(recursive: true);
    }
    expect(await signedPost(node, sender, message: 'next', nonce: 'next'),
        HttpStatus.ok);
    recorder.expectReleased(retained: true);
  });
}
