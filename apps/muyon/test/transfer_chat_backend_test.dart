import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/chat/chat_models.dart';
import 'package:muyon/screens/chat/transfer_chat_backend.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/transfer/transfer_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/lan.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('chat-adapter-'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ManagedConnection openDb() {
    final db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in KnowledgeService.schema.migrations) {
      migration.migrate(db.raw);
    }
    return db;
  }

  Future<void> listen(TransferService s, String id) => s.start(
    deviceId: id,
    deviceName: id,
    discoveryPort: 0,
    httpPort: 0,
    secrets: MemoryLanSecretStore(),
  );

  Future<LanPeer> pair(TransferService local, TransferService remote) async {
    final peer = await local.probe('127.0.0.1', port: remote.httpPort!);
    local.confirmPeer(
      fingerprint: peer.fingerprint,
      confirmedCode: remote.localShortCode!,
      certificatePem: peer.certificatePem,
    );
    return peer;
  }

  Future<void> until(bool Function() ready, String label) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) fail(label);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('adapter maps send, delivery, read, acceptance and delete', () async {
    final leftDb = openDb(), rightDb = openDb();
    addTearDown(leftDb.close);
    addTearDown(rightDb.close);
    final left = TransferService(leftDb, '${temp.path}/a');
    final right = TransferService(rightDb, '${temp.path}/b');
    addTearDown(left.close);
    addTearDown(right.close);
    await listen(left, 'left');
    await listen(right, 'right');
    final rightPeer = await pair(left, right);
    await pair(right, left);
    final a = TransferChatBackend(left);
    final b = TransferChatBackend(right);
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    expect(a.listening, isTrue);
    expect(a.sentRetryAfter, left.chatSentRetryAfter);
    // A paired, reachable device is offered before any message exists.
    final fresh = a.threads().singleWhere(
      (t) => t.peerFingerprint == rightPeer.fingerprint,
    );
    expect(fresh.online, isTrue);
    expect(fresh.paired, isTrue);
    expect(fresh.last, isNull);
    expect(a.destination(rightPeer.fingerprint), contains('127.0.0.1'));

    await a.sendText(rightPeer.fingerprint, '你好');
    await until(
      () =>
          a.messages(rightPeer.fingerprint).single.sendState ==
          SendState.delivered,
      'delivered',
    );
    final sent = a.messages(rightPeer.fingerprint).single;
    expect(sent.direction, ChatDirection.outgoing);
    expect(sent.body, '你好');
    expect(sent.sentAt, isNotNull);

    final leftFingerprint = b.threads().single.peerFingerprint;
    await until(() => b.messages(leftFingerprint).isNotEmpty, 'received');
    final incoming = b.messages(leftFingerprint).single;
    expect(incoming.direction, ChatDirection.incoming);
    expect(incoming.sendState, isNull);
    expect(incoming.unread, isTrue);
    expect(b.threads().single.unread, 1);

    await b.markRead(leftFingerprint);
    expect(b.messages(leftFingerprint).single.unread, isFalse);
    expect(b.messages(leftFingerprint).single.acceptance, Acceptance.none);
    await b.accept(leftFingerprint, incoming.id);
    expect(b.messages(leftFingerprint).single.acceptance, Acceptance.accepted);
    expect(
      b.messages(leftFingerprint).single.unread,
      isFalse,
      reason: 'acceptance never changes read',
    );

    await b.delete(leftFingerprint, incoming.id);
    expect(b.messages(leftFingerprint), isEmpty);
    expect(
      a.messages(rightPeer.fingerprint),
      hasLength(1),
      reason: 'local delete does not touch the peer',
    );
  });

  test(
    'sending to a device that is not reachable fails without a row',
    () async {
      final db = openDb();
      addTearDown(db.close);
      final service = TransferService(db, '${temp.path}/solo');
      addTearDown(service.close);
      final backend = TransferChatBackend(service);
      addTearDown(backend.dispose);
      expect(backend.listening, isFalse);
      await expectLater(
        backend.sendText('ff' * 16, 'x'),
        throwsA(isA<StateError>()),
      );
      expect(backend.threads(), isEmpty);
      expect(backend.destination('ff' * 16), isNull);
    },
  );
}
