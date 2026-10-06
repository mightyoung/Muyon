import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test('zip manifest identifies a research package and rejects lookalikes', () {
    final manifest = utf8.encode(
      jsonEncode({'packageType': 'muyon-research', 'schemaVersion': 1}),
    );
    expect(
      TransferService.isResearchPackage(
        _zip({'manifest.json': manifest, 'note.txt': utf8.encode('opaque')}),
      ),
      isTrue,
    );
    expect(
      TransferService.isResearchPackage(
        _zip({'manifest.json': manifest}, deflate: true),
      ),
      isTrue,
    );
    expect(
      TransferService.isResearchPackage(
        _zip({
          'manifest.json': utf8.encode(
            jsonEncode({'packageType': 'other', 'schemaVersion': 1}),
          ),
        }),
      ),
      isFalse,
    );
    expect(
      TransferService.isResearchPackage(
        _zip({'readme.txt': utf8.encode('no manifest')}),
      ),
      isFalse,
    );
    expect(
      TransferService.isResearchPackage(_zip({'../manifest.json': manifest})),
      isFalse,
    );
    expect(
      TransferService.isResearchPackage(_zip({'docs/manifest.json': manifest})),
      isFalse,
    );
    expect(
      TransferService.isResearchPackage(
        _zip({'manifest.json': manifest})
          ..[18] = 0
          ..[19] = 0
          ..[20] = 0
          ..[21] = 0,
      ),
      isFalse,
    );
    expect(TransferService.isResearchPackage(<int>[0x50, 0x4b, 0x03]), isFalse);
    // archive 4.0.9 ZipEncoder, deflate: manifest.json plus project.json.
    expect(
      TransferService.isResearchPackage(
        base64Decode(
          'UEsDBBQAAAgIABy8RF0UBT/gNAAAADIAAAANAAAAbWFuaWZlc3QuanNvbqtWKkhMzk5MTw2pLEhVslLKLa3Mz9MtSi1OTSxKzlDSUSpOzkjNTQxLLSrOzM9TsjKsBQBQSwMEFAAACAgAHLxEXX0a9D0aAAAAGAAAAAwAAABwcm9qZWN0Lmpzb26rVsovykzPzAsoys9KTS7xTq1UslLKVqoFAFBLAQIUABQAAAgIABy8RF0UBT/gNAAAADIAAAANAAAAAAAAAAAAAACkAQAAAABtYW5pZmVzdC5qc29uUEsBAhQAFAAACAgAHLxEXX0a9D0aAAAAGAAAAAwAAAAAAAAAAAAAAKQBXwAAAHByb2plY3QuanNvblBLBQYAAAAAAgACAHUAAACjAAAAAAA=',
        ),
      ),
      isTrue,
    );
    expect(
      TransferService.isResearchPackage(
        utf8.encode(
          jsonEncode({'packageType': 'muyon-research', 'schemaVersion': 1}),
        ),
      ),
      isTrue,
    );
  });

  test(
    'research zip stays pending until accepted and hands off once',
    () async {
      final sender = open('zip-a');
      final receiver = open('zip-b');
      addTearDown(sender.close);
      addTearDown(receiver.close);
      await listen(sender, 'zip-a');
      await listen(receiver, 'zip-b');
      final toReceiver = await pair(sender, receiver);
      await pair(receiver, sender);

      final manifest = utf8.encode(
        jsonEncode({
          'packageType': 'muyon-research',
          'schemaVersion': 1,
          'note': 'zip bytes stay opaque; the research importer is not called',
        }),
      );
      final payload = _zip({
        'manifest.json': manifest,
        'project.json': utf8.encode('{"sourceProjectId":"p"}'),
      }, deflate: true);
      final research = File('${temp.path}/study.zip')
        ..writeAsBytesSync(payload);
      expect(TransferService.isResearchPackage(payload), isTrue);
      await sender.send(toReceiver, research.path);
      await receiver.itemsSettled;

      final item = receiver.items().single;
      expect(item.delivered, isTrue);
      expect(item.attachmentState, 'durable');
      expect(item.attachmentLength, payload.length);
      expect(item.attachmentSha256, sha256.convert(payload).toString());
      expect(item.imported, isFalse);
      expect(item.acceptance, 'pending');
      expect(item.grantsExecution, isFalse);
      expect(await File(item.path!).readAsBytes(), payload);
      expect(receiver.receipts(), isEmpty);
      await expectLater(receiver.importPackage(item.path!), throwsStateError);
      await expectLater(receiver.markImported(item.id), throwsStateError);

      var handoffs = 0;
      receiver.onAccepted = (accepted) {
        handoffs++;
        expect(accepted.imported, isFalse);
        expect(accepted.grantsExecution, isFalse);
        expect(accepted.acceptance, 'accepted');
      };
      await receiver.acceptItem(item.id);
      await receiver.acceptItem(item.id);
      expect(handoffs, 1);
      expect(receiver.items().single.imported, isFalse);
      expect(receiver.items().single.acceptance, 'accepted');
      expect(receiver.receipts(), isEmpty);
      await expectLater(
        receiver.importPackage(item.path!),
        throwsFormatException,
      );
      expect(receiver.items().single.imported, isFalse);

      final other = File('${temp.path}/other.zip')
        ..writeAsBytesSync(
          _zip({
            'manifest.json': utf8.encode(
              jsonEncode({'packageType': 'notes', 'schemaVersion': 1}),
            ),
          }),
        );
      await expectLater(
        sender.send(toReceiver, other.path),
        throwsFormatException,
      );
      await receiver.itemsSettled;
      expect(receiver.items(), hasLength(1));
    },
  );
}

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xedb88320 & mask);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

void _u16(BytesBuilder out, int value) {
  out.addByte(value & 0xff);
  out.addByte((value >> 8) & 0xff);
}

void _u32(BytesBuilder out, int value) {
  out.addByte(value & 0xff);
  out.addByte((value >> 8) & 0xff);
  out.addByte((value >> 16) & 0xff);
  out.addByte((value >> 24) & 0xff);
}

/// Minimal zip: method 0, or raw-deflate method 8. Names are the map keys.
List<int> _zip(Map<String, List<int>> files, {bool deflate = false}) {
  final local = BytesBuilder();
  final central = BytesBuilder();
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final plain = entry.value;
    final compressed = deflate
        ? ZLibEncoder(raw: true, level: 6).convert(plain)
        : plain;
    final crc = _crc32(plain);
    final offset = local.length;
    _u32(local, 0x04034b50);
    _u16(local, 20);
    _u16(local, 0x0800);
    _u16(local, deflate ? 8 : 0);
    _u16(local, 0);
    _u16(local, 0);
    _u32(local, crc);
    _u32(local, compressed.length);
    _u32(local, plain.length);
    _u16(local, name.length);
    _u16(local, 0);
    local.add(name);
    local.add(compressed);

    _u32(central, 0x02014b50);
    _u16(central, 20);
    _u16(central, 20);
    _u16(central, 0x0800);
    _u16(central, deflate ? 8 : 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, crc);
    _u32(central, compressed.length);
    _u32(central, plain.length);
    _u16(central, name.length);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u16(central, 0);
    _u32(central, 0);
    _u32(central, offset);
    central.add(name);
  }
  final cd = central.toBytes();
  final out = BytesBuilder()
    ..add(local.toBytes())
    ..add(cd);
  _u32(out, 0x06054b50);
  _u16(out, 0);
  _u16(out, 0);
  _u16(out, files.length);
  _u16(out, files.length);
  _u32(out, cd.length);
  _u32(out, local.length);
  _u16(out, 0);
  return out.toBytes();
}
