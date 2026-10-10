import 'dart:io';

import 'package:supplier_core/src/lan.dart';
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
        sender.sign(
          pushBinding(
            fingerprint: sender.fingerprint,
            nonce: nonce,
            messageId: message,
            sentAtUnix: sentAt,
            length: bytes.length,
            bodyHash: sha256Hex(bytes),
          ),
        ),
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
  test('rename failure never records an undelivered message durably', () async {
    final dir = Directory.systemTemp.createTempSync('lan-rename-');
    final inbox = RenameBlockedInbox(dir);
    final pushes = <LanPush>[];
    final node = await LanNode.start(
      id: 'receiver',
      name: 'Receiver',
      inbox: inbox,
      onPush: pushes.add,
      discoveryPort: 0,
      httpPort: 0,
    );
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
    expect(dir.listSync().whereType<File>(), isEmpty);
    expect(dir.listSync().whereType<Directory>().map((d) => d.path),
        inbox.obstacles.map((d) => d.path));
    // A failed rename precedes callback invocation. It must not become a
    // durable claim that this message was delivered across receiver restart.
    expect(seen.existsSync(), isFalse);
  });
}
