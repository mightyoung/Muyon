import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';

class _NoSecrets implements SecretStore {
  @override
  Future<String?> read(String reference) async => null;
}

void main() {
  late Directory root;
  late StorageManager storage;
  late OutboundLedger ledger;
  late HttpServer server;
  late OpenAiModelGateway gateway;
  var reply = 200;
  Completer<void>? hold;
  Completer<void>? arrived;

  ModelProfile profile(ModelPurpose purpose) => ModelProfile(
    id: 'local-$purpose',
    endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/x'),
    location: ModelLocation.local,
    modelId: 'm',
    endpointIdentity: 'fixture',
    purpose: purpose,
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('muyon-outbound-');
    storage = StorageManager(root.path);
    ledger = OutboundLedger(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    reply = 200;
    hold = null;
    arrived = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (arrived != null && !arrived!.isCompleted) arrived!.complete();
      await hold?.future;
      request.response.statusCode = reply;
      request.response.write(
        jsonEncode(
          body.containsKey('input')
              ? {
                  'data': [
                    for (var i = 0; i < (body['input'] as List).length; i++)
                      {
                        'index': i,
                        'embedding': [0.1, 0.2],
                      },
                  ],
                }
              : {
                  'choices': [
                    {
                      'message': {'content': 'ok'},
                    },
                  ],
                },
        ),
      );
      await request.response.close();
    });
    gateway = OpenAiModelGateway(_NoSecrets(), ledger: ledger);
  });
  tearDown(() async {
    await server.close(force: true);
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'every sent request records caller, destination, size and outcome',
    () async {
      await gateway.chat(
        profile: profile(ModelPurpose.chat),
        messages: [
          {'role': 'user', 'content': 'q1'},
          {'role': 'user', 'content': 'q2'},
        ],
        caller: 'assistant',
      );
      await gateway.embed(
        profile: profile(ModelPurpose.embedding),
        texts: ['a', 'b', 'c'],
        beforeSend: () async {},
      );
      final rows = ledger.recent();
      expect(rows, hasLength(2));
      final embed = rows.first, chat = rows.last;
      expect(chat['caller'], 'assistant');
      expect(chat['endpoint'], 'http://127.0.0.1:${server.port}/v1/x');
      expect(chat['location'], 'local');
      expect(chat['cloud_proxy'], 0);
      expect(chat['item_count'], 2);
      expect(chat['status'], 'succeeded');
      expect(chat['http_status'], 200);
      expect((chat['payload_sha256'] as String).length, 64);
      expect(chat['payload_bytes'], greaterThan(0));
      expect(embed['caller'], 'embedding');
      expect(embed['item_count'], 3);
    },
  );

  test('refused confirmation sends and records nothing', () async {
    await expectLater(
      gateway.chat(
        profile: profile(ModelPurpose.chat),
        messages: [
          {'role': 'user', 'content': 'q'},
        ],
        beforeSend: () async => throw StateError('declined'),
      ),
      throwsStateError,
    );
    expect(ledger.recent(), isEmpty);
  });

  test('HTTP failure and cancellation are recorded as such', () async {
    reply = 500;
    await expectLater(
      gateway.chat(
        profile: profile(ModelPurpose.chat),
        messages: [
          {'role': 'user', 'content': 'q'},
        ],
      ),
      throwsA(isA<HttpException>()),
    );
    expect(ledger.recent().single['status'], 'failed');
    expect(ledger.recent().single['http_status'], 500);

    reply = 200;
    hold = Completer<void>();
    arrived = Completer<void>();
    final token = ModelCancellation();
    final call = gateway.chat(
      profile: profile(ModelPurpose.chat),
      messages: [
        {'role': 'user', 'content': 'q'},
      ],
      cancellation: token,
    );
    await arrived!.future; // the payload has reached the endpoint
    token.cancel();
    await expectLater(call, throwsA(anything));
    hold!.complete();
    expect(ledger.recent().first['status'], 'cancelled');
    expect(ledger.recent().first['error'], contains('sent'));
  });

  test(
    'a request left sending by a crash becomes interrupted on recovery',
    () async {
      final id = await ledger.begin(
        caller: 'assistant',
        profile: profile(ModelPurpose.chat),
        payload: '{}',
        itemCount: 1,
      );
      expect(ledger.recent().single['status'], 'sending');
      expect(await ledger.recoverInterrupted(), 1);
      final row = ledger.recent().single;
      expect(row['id'], id);
      expect(row['status'], 'interrupted');
      expect(row['error'], contains('unknown'));
    },
  );

  test('if the ledger cannot record, nothing is sent', () async {
    var hits = 0;
    final counting = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => counting.close(force: true));
    counting.listen((r) {
      hits++;
      r.response.close();
    });
    await storage.close(); // ledger database closed → begin() fails
    await expectLater(
      OpenAiModelGateway(_NoSecrets(), ledger: ledger).chat(
        profile: ModelProfile(
          id: 'p',
          endpoint: Uri.parse('http://127.0.0.1:${counting.port}/v1/x'),
          location: ModelLocation.local,
          modelId: 'm',
          endpointIdentity: 'fixture',
        ),
        messages: [
          {'role': 'user', 'content': 'q'},
        ],
      ),
      throwsStateError,
    );
    expect(hits, 0);
    storage = StorageManager(root.path); // for tearDown
  });
}
