import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/knowledge/embedding_service.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/transfer/transfer_service.dart';
import 'package:muyon/services/ocr/paddle_ocr_service.dart';
import 'package:muyon/services/ocr/ocr_geometry.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory temp;
  late ManagedConnection db;
  late KnowledgeService knowledge;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('public-services-');
    db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in KnowledgeService.schema.migrations) {
      migration.migrate(db.raw);
    }
    knowledge = KnowledgeService(db, '${temp.path}/private');
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });
  Future<KnowledgeDocument> document(String name, String text) async {
    final f = File('${temp.path}/$name')..writeAsStringSync(text);
    final d = await knowledge.importFile(f.path);
    await knowledge.index(d.id);
    return d;
  }

  test(
    'private file copy, page FTS scope, stale source detection and delete',
    () async {
      final a = await document('a.txt', '材料成本与质量检查 supplier alpha');
      final b = await document('b.txt', 'unrelated supplier beta');
      expect(a.path, startsWith('${temp.path}/private/'));
      expect(
        (await knowledge.search('材料成本', documentIds: [a.id])).single.pageIndex,
        0,
      );
      expect(await knowledge.search('材料成本', documentIds: [b.id]), isEmpty);
      File(a.path).writeAsStringSync('tampered');
      expect(await knowledge.search('alpha', documentIds: [a.id]), isEmpty);
      expect(knowledge.require(a.id).status, 'stale');
      await knowledge.delete(a.id);
      expect(knowledge.documents().single.id, b.id);
    },
  );
  test('queued write cancellation leaves no imported document', () async {
    final f = File('${temp.path}/cancel.txt')..writeAsStringSync('data');
    await expectLater(
      knowledge.importFile(
        f.path,
        checkBeforeEffect: () => throw StateError('cancelled'),
      ),
      throwsStateError,
    );
    expect(knowledge.documents(), isEmpty);
  });
  test(
    'real HTTP embeddings persist and can search offline, mismatches reject',
    () async {
      final d = await document(
        'vector.txt',
        'A real endpoint receives these selected words',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var sent = 0, approved = 0;
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['model'], 'test-embedding');
        expect(body['input'], isA<List>());
        sent++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'index': 0,
                'embedding': [.6, .8],
              },
            ],
          }),
        );
        await request.response.close();
      });
      final profile = ModelProfile(
        id: 'explicit',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/embeddings'),
        location: ModelLocation.local,
        modelId: 'test-embedding',
        endpointIdentity: 'loopback-test',
        purpose: ModelPurpose.embedding,
      );
      final embedding = EmbeddingService(
        knowledge,
        OpenAiModelGateway(UnavailableSecretStore()),
      );
      await embedding.index(
        d.id,
        profile: profile,
        beforeSend: () async {
          approved++;
        },
      );
      expect(sent, 1);
      expect(approved, 1);
      await server.close(force: true);
      final hits = await embedding.searchVector(
        [.6, .8],
        profileId: profile.id,
        endpointIdentity: profile.endpointIdentity,
        modelId: profile.modelId,
        documentIds: [d.id],
      );
      expect(hits.single.score, closeTo(1, 1e-9));
      await expectLater(
        embedding.searchVector(
          [1, 2, 3],
          profileId: profile.id,
          endpointIdentity: profile.endpointIdentity,
          modelId: profile.modelId,
          documentIds: [d.id],
        ),
        throwsStateError,
      );
    },
  );
  test(
    'transfer manifest validates hash paths duplicate receipt and cancellation',
    () async {
      final source = File('${temp.path}/file.txt')
        ..writeAsStringSync('transferred bytes');
      final transfer = TransferService(db, '${temp.path}/transfer');
      final package = await transfer.exportFiles([
        source.path,
      ], message: 'hello');
      final receipt = await transfer.importPackage(package);
      expect(receipt.paths, hasLength(2));
      expect((await transfer.importPackage(package)).id, receipt.id);
      final payload = jsonDecode(File(package).readAsStringSync()) as Map;
      payload['files'][0]['name'] = '../escape';
      File(package).writeAsStringSync(jsonEncode(payload));
      await expectLater(transfer.importPackage(package), throwsFormatException);
      payload['files'][0]['name'] = 'file.txt';
      payload['files'][0]['data'] = base64Encode(utf8.encode('evil'));
      File(package).writeAsStringSync(jsonEncode(payload));
      await expectLater(transfer.importPackage(package), throwsFormatException);
      expect(transfer.listening, isFalse);
    },
  );
  test(
    'BGR normalization, blank-aware CTC, detector boxes and projective crop',
    () {
      final pixel = img.Image(width: 1, height: 1)
        ..setPixelRgb(0, 0, 255, 0, 0);
      final bgr = PaddleOcrService.normalizedBgr(pixel, detection: false);
      expect(bgr.toList(), [-1, -1, 1]);
      final (text, score) = PaddleOcrService.ctcDecode(
        [0, .9, .1, 0, .8, .2, 1, 0, 0, 0, .7, .3],
        4,
        3,
        ['', 'A', 'B'],
      );
      expect(text, 'AA');
      expect(score, closeTo(.8, 1e-8));
      final map = List<double>.filled(40 * 20, 0);
      for (var y = 5; y < 15; y++) {
        for (var x = 5; x < 35; x++) {
          map[y * 40 + x] = .95;
        }
      }
      final boxes = detectBoxes(map, 40, 20, 400, 200);
      expect(boxes, hasLength(1));
      expect(boxes.single.score, closeTo(.95, 1e-8));
      final source = img.Image(width: 400, height: 200);
      final crop = perspectiveCrop(source, boxes.single.points);
      expect(crop.width, greaterThan(crop.height));
    },
  );
  test(
    'transfer rejects forged member claims and freezes approved outgoing bytes',
    () async {
      final source = File('${temp.path}/scope.txt')
        ..writeAsStringSync('approved source');
      final transfer = TransferService(db, '${temp.path}/transfer');
      final package = await transfer.exportFiles([source.path]);
      final digest = await KnowledgeService.fileDigest(package),
          sourceDigest = await KnowledgeService.fileDigest(source.path);
      final frozen = await transfer.freezeForSend(
        package,
        expectedDigest: digest,
        allowedMembers: {'scope.txt': sourceDigest},
      );
      final payload = jsonDecode(File(package).readAsStringSync()) as Map;
      payload['files'][0]['data'] = base64Encode(utf8.encode('secret bytes'));
      File(package).writeAsStringSync(jsonEncode(payload));
      expect(await KnowledgeService.fileDigest(frozen), digest);
      await expectLater(
        transfer.freezeForSend(
          package,
          expectedDigest: await KnowledgeService.fileDigest(package),
          allowedMembers: {'scope.txt': sourceDigest},
        ),
        throwsFormatException,
      );
      await expectLater(
        transfer.importPackage(package, expectedDigest: digest),
        throwsFormatException,
      );
      expect(transfer.receipts(), isEmpty);
    },
  );
  test('transfer stop waits for startup and supports reopening', () async {
    final transfer = TransferService(db, '${temp.path}/lifecycle');
    addTearDown(transfer.close);
    final starting = transfer.start(
      deviceId: 'test-device',
      deviceName: 'test',
      discoveryPort: 0,
      httpPort: 0,
    );
    final stopping = transfer.close();
    await Future.wait([starting, stopping]);
    expect(transfer.listening, isFalse);
    await transfer.start(
      deviceId: 'test-device',
      deviceName: 'test',
      discoveryPort: 0,
      httpPort: 0,
    );
    expect(transfer.listening, isTrue);
    await transfer.close();
    expect(transfer.listening, isFalse);
  });
  test(
    'inbox restart restores pending bytes but excludes accepted duplicates',
    () async {
      final root = '${temp.path}/restart';
      final inbox = Directory('$root/inbox')..createSync(recursive: true);
      final first = TransferService(db, root);
      final package = await first.exportFiles([], message: 'pending message');
      final incoming = await File(package).copy('${inbox.path}/incoming.siq');
      await Link('${inbox.path}/linked.siq').create(incoming.path);
      await Directory('${inbox.path}/incomplete-upload').create();
      var notifications = 0;
      final restarted = TransferService(db, root)
        ..onPendingReceived = () => notifications++;
      await restarted.initialize();
      expect(restarted.pendingReceivedPaths, [incoming.path]);
      expect(notifications, 1);
      expect(restarted.receipts(), isEmpty);
      await restarted.importPackage(incoming.path);
      await incoming.copy('${inbox.path}/duplicate.siq');
      final acceptedRestart = TransferService(db, root);
      await acceptedRestart.initialize();
      expect(acceptedRestart.pendingReceivedPaths, isEmpty);
      expect(acceptedRestart.receipts(), hasLength(1));
    },
  );
}
