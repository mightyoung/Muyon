import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/transfer/transfer_service.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/lan.dart';

void main() {
  late Directory temp;
  late ManagedConnection db;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('transfer-states-');
    db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in KnowledgeService.schema.migrations) {
      migration.migrate(db.raw);
    }
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  TransferService open(String name) =>
      TransferService(db, '${temp.path}/$name');

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

  test('unverified inbox bytes are not a durable transfer item', () async {
    final root = '${temp.path}/unverified';
    final inbox = Directory('$root/inbox')..createSync(recursive: true);
    final file = File('${inbox.path}/partial.bin')
      ..writeAsStringSync('not a verified push');
    final transfer = open('unverified');
    await transfer.initialize();
    expect(transfer.pendingReceivedPaths, [file.path]);
    expect(transfer.items(), isEmpty);
    expect(transfer.receipts(), isEmpty);
  });

  test('send refuses an unpaired or offline peer before any payload', () async {
    final sender = open('offline-a');
    addTearDown(sender.close);
    await listen(sender, 'offline-a');
    final package = File('${temp.path}/note.txt')..writeAsStringSync('hello');
    final exported = await sender.exportFiles([package.path]);
    final ghost = LanPeer(
      'missing',
      'ghost',
      '127.0.0.1',
      9,
      DateTime.now(),
      fingerprint: 'ab',
    );
    await expectLater(
      sender.send(ghost, exported),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('未配对或已撤销'),
        ),
      ),
    );
    final inbox = Directory('${temp.path}/offline-a/inbox');
    expect(inbox.listSync(), isEmpty);
    expect(sender.items(), isEmpty);
    expect(sender.receipts(), isEmpty);
  });

  test(
    'research package stays pending until accepted and hands off once',
    () async {
      final sender = open('research-a');
      final receiver = open('research-b');
      addTearDown(sender.close);
      addTearDown(receiver.close);
      await listen(sender, 'research-a');
      await listen(receiver, 'research-b');
      final toReceiver = await pair(sender, receiver);
      await pair(receiver, sender);

      final research = File('${temp.path}/study.json')
        ..writeAsStringSync(
          jsonEncode({
            'packageType': 'muyon-research',
            'schemaVersion': 1,
            'packageId': '00000000-0000-4000-8000-000000000001',
            'note':
                'opaque bytes; this test does not call the research importer',
          }),
        );
      final digest = sha256.convert(await research.readAsBytes()).toString();
      final progress = <int>[];
      await sender.send(
        toReceiver,
        research.path,
        onProgress: (sent, total) {
          expect(sent, inInclusiveRange(0, total));
          if (progress.isNotEmpty) {
            expect(sent, greaterThanOrEqualTo(progress.last));
          }
          progress.add(sent);
        },
      );
      expect(progress, isNotEmpty);
      expect(progress.last, await research.length());
      await receiver.itemsSettled;

      final item = receiver.items().single;
      expect(item.delivered, isTrue);
      expect(item.attachmentState, 'durable');
      expect(item.attachmentLength, await research.length());
      expect(item.attachmentSha256, digest);
      expect(item.imported, isFalse);
      expect(item.readAt, isNull);
      expect(item.acceptance, 'pending');
      expect(item.grantsExecution, isFalse);
      expect(receiver.receipts(), isEmpty);
      expect(
        File(item.path!).readAsStringSync(),
        contains('"packageType":"muyon-research"'),
      );
      await expectLater(
        receiver.importPackage(item.path!),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('尚未人工接纳'),
          ),
        ),
      );
      await expectLater(receiver.markImported(item.id), throwsStateError);

      await receiver.markRead(item.id);
      final read = receiver.items().single;
      expect(read.readAt, isNotNull);
      expect(read.imported, isFalse);
      expect(read.acceptance, 'pending');
      expect(read.delivered, isTrue);

      var handoffs = 0;
      receiver.onAccepted = (accepted) {
        handoffs++;
        expect(accepted.acceptance, 'accepted');
        expect(accepted.imported, isFalse);
        expect(accepted.grantsExecution, isFalse);
        expect(accepted.readAt, read.readAt);
        expect(
          File(accepted.path!).readAsStringSync(),
          contains('muyon-research'),
        );
      };
      await receiver.acceptItem(item.id);
      await receiver.acceptItem(item.id);
      expect(handoffs, 1);
      expect(receiver.items().single.imported, isFalse);
      expect(receiver.items().single.acceptance, 'accepted');
      expect(receiver.receipts(), isEmpty);

      await receiver.markImported(item.id);
      final imported = receiver.items().single;
      expect(imported.imported, isTrue);
      expect(imported.acceptance, 'accepted');
      expect(imported.readAt, read.readAt);
      expect(imported.grantsExecution, isFalse);

      await sender.send(toReceiver, research.path);
      await receiver.itemsSettled;
      expect(receiver.items(), hasLength(1));

      final offline = LanPeer(
        'not-listed',
        'gone',
        '10.255.255.1',
        9,
        DateTime.now(),
        fingerprint: toReceiver.fingerprint,
      );
      await expectLater(
        sender.send(offline, research.path),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('不在线'),
          ),
        ),
      );
      sender.revoke(toReceiver.fingerprint);
      await expectLater(
        sender.send(toReceiver, research.path),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('未配对或已撤销'),
          ),
        ),
      );
    },
  );

  test(
    'transfer package import stays independent of delivery read and acceptance',
    () async {
      final sender = open('pkg-a');
      final receiver = open('pkg-b');
      addTearDown(sender.close);
      addTearDown(receiver.close);
      await listen(sender, 'pkg-a');
      await listen(receiver, 'pkg-b');
      final toReceiver = await pair(sender, receiver);
      await pair(receiver, sender);
      final source = File('${temp.path}/notes.txt')
        ..writeAsStringSync('paired attachment');
      final package = await sender.exportFiles([source.path], message: 'hello');
      await sender.send(toReceiver, package);
      await receiver.itemsSettled;
      final item = receiver.items().single;
      expect(item.delivered, isTrue);
      expect(item.imported, isFalse);
      expect(item.acceptance, 'pending');
      var handoffs = 0;
      receiver.onAccepted = (_) => handoffs++;
      await receiver.acceptItem(item.id);
      expect(handoffs, 1);
      expect(receiver.receipts(), isEmpty);
      expect(receiver.items().single.imported, isFalse);
      final receipt = await receiver.importPackage(item.path!);
      expect(receipt.paths, isNotEmpty);
      expect(receiver.items().single.imported, isTrue);
      expect(receiver.items().single.readAt, isNull);
      expect((await receiver.importPackage(item.path!)).id, receipt.id);
    },
  );

  test('restart keeps an unaccepted verified package pending', () async {
    final sender = open('restart-a');
    final receiver = open('restart-b');
    addTearDown(sender.close);
    await listen(sender, 'restart-a');
    await listen(receiver, 'restart-b');
    final toReceiver = await pair(sender, receiver);
    await pair(receiver, sender);
    final research = File('${temp.path}/again.json')
      ..writeAsStringSync(
        jsonEncode({'packageType': 'muyon-research', 'schemaVersion': 1}),
      );
    await sender.send(toReceiver, research.path);
    await receiver.itemsSettled;
    final path = receiver.items().single.path!;
    await receiver.close();

    final restarted = open('restart-b');
    await restarted.initialize();
    final item = restarted.items().single;
    expect(item.path, path);
    expect(item.acceptance, 'pending');
    expect(item.imported, isFalse);
    expect(item.attachmentState, 'durable');
    expect(restarted.pendingReceivedPaths, contains(path));
    expect(restarted.receipts(), isEmpty);
    await expectLater(restarted.importPackage(path), throwsStateError);
  });
}
