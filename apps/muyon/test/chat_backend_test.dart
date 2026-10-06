import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/transfer/chat_log.dart';
import 'package:muyon/services/transfer/transfer_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/lan.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('chat-backend-');
  });

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

  Future<void> listen(TransferService service, String id) => service.start(
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

  test(
    'text is delivered once, and sent is not failed or retried by itself',
    () async {
      final leftDb = openDb();
      final rightDb = openDb();
      addTearDown(leftDb.close);
      addTearDown(rightDb.close);
      final left = TransferService(leftDb, '${temp.path}/a');
      final right = TransferService(rightDb, '${temp.path}/b');
      addTearDown(left.close);
      addTearDown(right.close);
      var notices = 0;
      right.onPendingReceived = () => notices++;
      await listen(left, 'left');
      await listen(right, 'right');
      final rightPeer = await pair(left, right);
      final leftPeer = await pair(right, left);

      await expectLater(left.sendText(rightPeer, ''), throwsArgumentError);
      await expectLater(
        left.sendText(rightPeer, '字' * 16001),
        throwsArgumentError,
      );
      expect(left.messages(rightPeer.fingerprint), isEmpty);

      final ghost = LanPeer(
        'missing',
        'ghost',
        '127.0.0.1',
        9,
        DateTime.now(),
        fingerprint: rightPeer.fingerprint,
      );
      await expectLater(
        left.sendText(ghost, '离线'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', '对方不在线，没有中继'),
        ),
      );
      expect(left.messages(rightPeer.fingerprint), isEmpty);

      right.acknowledgeChatDelivery = false;
      final sent = await left.sendText(rightPeer, '你好');
      expect(sent.sendState, 'sent');
      expect(sent.grantsExecution, isFalse);
      await until(
        () => right.messages(leftPeer.fingerprint).length == 1,
        'receiver did not store the text',
      );
      expect(right.messages(leftPeer.fingerprint).single.body, '你好');
      expect(right.messages(leftPeer.fingerprint).single.readAt, isNull);
      expect(right.messages(leftPeer.fingerprint).single.acceptance, 'none');
      expect(notices, greaterThan(0));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(left.messages(rightPeer.fingerprint).single.sendState, 'sent');

      await expectLater(
        left.retryText(rightPeer.fingerprint, sent.id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            '发出结果未知，尚未到可重发时间',
          ),
        ),
      );
      await leftDb.write((db) {
        db.execute(
          'UPDATE chat_messages SET sent_at=? WHERE peer_fingerprint=? AND message_id=?',
          [
            DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 5))
                .toIso8601String(),
            rightPeer.fingerprint,
            sent.id,
          ],
        );
      });
      right.acknowledgeChatDelivery = true;
      await left.retryText(rightPeer.fingerprint, sent.id);
      await until(
        () =>
            left.messages(rightPeer.fingerprint).single.sendState ==
            'delivered',
        'explicit retry was not acknowledged',
      );
      expect(right.messages(leftPeer.fingerprint), hasLength(1));
      expect(right.threads().single.unread, 1);
      expect(right.threads().single.paired, isTrue);

      await right.markChatRead(leftPeer.fingerprint);
      expect(right.messages(leftPeer.fingerprint).single.readAt, isNotNull);
      expect(right.threads().single.unread, 0);
      expect(left.messages(rightPeer.fingerprint), hasLength(1));

      await right.acceptChat(leftPeer.fingerprint, sent.id);
      expect(
        right.messages(leftPeer.fingerprint).single.acceptance,
        'accepted',
      );
      expect(right.items(), isEmpty);
      await right.rejectChat(leftPeer.fingerprint, sent.id);
      expect(
        right.messages(leftPeer.fingerprint).single.acceptance,
        'rejected',
      );
      expect(right.messages(leftPeer.fingerprint).single.body, '你好');

      expect(left.messages(rightPeer.fingerprint), hasLength(1));
      left.revoke(rightPeer.fingerprint);
      expect(left.messages(rightPeer.fingerprint), hasLength(1));
      await expectLater(
        left.sendText(rightPeer, '再发'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', '未配对或已撤销'),
        ),
      );
      await left.deleteChat(rightPeer.fingerprint, sent.id);
      expect(left.messages(rightPeer.fingerprint), isEmpty);
      expect(right.messages(leftPeer.fingerprint), hasLength(1));
    },
  );

  test(
    'a package message is chat text and does not import the package',
    () async {
      final leftDb = openDb();
      final rightDb = openDb();
      addTearDown(leftDb.close);
      addTearDown(rightDb.close);
      final left = TransferService(leftDb, '${temp.path}/pack-a');
      final right = TransferService(rightDb, '${temp.path}/pack-b');
      addTearDown(left.close);
      addTearDown(right.close);
      await listen(left, 'pack-left');
      await listen(right, 'pack-right');
      final rightPeer = await pair(left, right);
      final leftPeer = await pair(right, left);
      final source = File('${temp.path}/note.txt')..writeAsStringSync('bytes');
      final package = await left.exportFiles([source.path], message: '包里的一句话');
      await left.send(rightPeer, package);
      await until(
        () =>
            right.messages(leftPeer.fingerprint).any((m) => m.body == '包里的一句话'),
        'package message was not stored',
      );
      final message = right.messages(leftPeer.fingerprint).single;
      expect(message.direction, 'in');
      expect(message.packageItemId, isNotNull);
      expect(message.grantsExecution, isFalse);
      expect(right.items().single.imported, isFalse);
      expect(right.items().single.acceptance, 'pending');
      expect(left.messages(rightPeer.fingerprint), isEmpty);
    },
  );

  test(
    'chat text stays out of the tool registry and assistant memory',
    () async {
      final root = Directory.systemTemp.createTempSync('chat-hosts-');
      final left = await MuyonHost.open('${root.path}/a');
      final right = await MuyonHost.open('${root.path}/b');
      addTearDown(() async {
        await left.close();
        await right.close();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final before = left.tools
          .list()
          .map((tool) => tool.descriptor.toolId)
          .toSet();
      Future<void> listen(MuyonHost host) => host.services.transfer.start(
        deviceId: host.workspaces.setting('deviceId') as String,
        deviceName: 'host',
        discoveryPort: 0,
        httpPort: 0,
        secrets: MemoryLanSecretStore(),
      );
      await listen(left);
      await listen(right);
      final rightPeer = await left.services.transfer.probe(
        '127.0.0.1',
        port: right.services.transfer.httpPort!,
      );
      left.services.transfer.confirmPeer(
        fingerprint: rightPeer.fingerprint,
        confirmedCode: right.services.transfer.localShortCode!,
        certificatePem: rightPeer.certificatePem,
      );
      final leftPeer = await right.services.transfer.probe(
        '127.0.0.1',
        port: left.services.transfer.httpPort!,
      );
      right.services.transfer.confirmPeer(
        fingerprint: leftPeer.fingerprint,
        confirmedCode: left.services.transfer.localShortCode!,
        certificatePem: leftPeer.certificatePem,
      );
      await left.services.transfer.sendText(rightPeer, '不要执行');
      await until(
        () =>
            right.services.transfer
                .messages(leftPeer.fingerprint)
                .any((message) => message.body == '不要执行') &&
            left.services.transfer
                    .messages(rightPeer.fingerprint)
                    .single
                    .sendState ==
                'delivered',
        'host chat was not delivered',
      );
      expect(
        left.tools.list().map((tool) => tool.descriptor.toolId).toSet(),
        before,
      );
      expect(left.tools.history(), isEmpty);
      expect(right.tools.history(), isEmpty);
      expect(
        left.foundation.memories(includeExpired: true, includeDisabled: true),
        isEmpty,
      );
      expect(
        right.foundation.experiences(
          includeUnverified: true,
          includeRetired: true,
        ),
        isEmpty,
      );
      expect(left.dream.runs(), isEmpty);
      expect(
        right.services.transfer
            .messages(leftPeer.fingerprint)
            .single
            .grantsExecution,
        isFalse,
      );
    },
  );

  test('the same message id on two peers stays on its own row', () async {
    final db = openDb();
    addTearDown(db.close);
    final service = TransferService(db, '${temp.path}/collide');
    addTearDown(service.close);
    final created = DateTime.utc(2026, 10, 5);
    ChatLog.insertInbound(
      db.raw,
      peerFingerprint: 'peer-a',
      messageId: 'shared',
      body: '来自甲',
      createdAt: created,
      receivedAt: created,
    );
    ChatLog.insertInbound(
      db.raw,
      peerFingerprint: 'peer-b',
      messageId: 'shared',
      body: '来自乙',
      createdAt: created,
      receivedAt: created,
    );
    ChatLog.insertOutbound(
      db.raw,
      peerFingerprint: 'peer-a',
      messageId: 'shared-out',
      body: '甲发出',
      createdAt: created,
    );
    ChatLog.insertOutbound(
      db.raw,
      peerFingerprint: 'peer-b',
      messageId: 'shared-out',
      body: '乙发出',
      createdAt: created,
    );
    db.raw.execute(
      "UPDATE chat_messages SET send_state='delivered' WHERE peer_fingerprint=? AND message_id=?",
      ['peer-a', 'shared-out'],
    );
    db.raw.execute(
      "UPDATE chat_messages SET send_state='failed' WHERE peer_fingerprint=? AND message_id=?",
      ['peer-b', 'shared-out'],
    );

    await service.acceptChat('peer-a', 'shared');
    expect(
      service.messages('peer-a').singleWhere((m) => m.id == 'shared').acceptance,
      'accepted',
    );
    expect(
      service.messages('peer-b').singleWhere((m) => m.id == 'shared').acceptance,
      'none',
    );
    await service.rejectChat('peer-b', 'shared');
    expect(
      service.messages('peer-b').singleWhere((m) => m.id == 'shared').acceptance,
      'rejected',
    );
    expect(
      service.messages('peer-a').singleWhere((m) => m.id == 'shared').acceptance,
      'accepted',
    );
    await expectLater(
      service.acceptChat('peer-missing', 'shared'),
      throwsA(
        isA<StateError>().having((error) => error.message, 'message', '消息不存在'),
      ),
    );

    await expectLater(
      service.retryText('peer-a', 'shared-out'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '对方已确认保存，不能重发',
        ),
      ),
    );
    await expectLater(
      service.retryText('peer-b', 'shared-out'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '对方不在线，没有中继',
        ),
      ),
    );
    expect(
      service.messages('peer-a').singleWhere((m) => m.id == 'shared-out').sendState,
      'delivered',
    );
    expect(
      service.messages('peer-b').singleWhere((m) => m.id == 'shared-out').sendState,
      'failed',
    );
    expect(
      service.messages('peer-b').singleWhere((m) => m.id == 'shared-out').body,
      '乙发出',
    );

    await service.deleteChat('peer-a', 'shared');
    expect(
      service.messages('peer-a').where((m) => m.id == 'shared'),
      isEmpty,
    );
    expect(
      service.messages('peer-b').singleWhere((m) => m.id == 'shared').body,
      '来自乙',
    );
    await service.deleteChat('peer-b', 'shared-out');
    expect(
      service.messages('peer-b').where((m) => m.id == 'shared-out'),
      isEmpty,
    );
    expect(
      service.messages('peer-a').singleWhere((m) => m.id == 'shared-out').body,
      '甲发出',
    );
    await expectLater(
      service.deleteChat('peer-a', 'shared'),
      throwsA(
        isA<StateError>().having((error) => error.message, 'message', '消息不存在'),
      ),
    );
  });
}
