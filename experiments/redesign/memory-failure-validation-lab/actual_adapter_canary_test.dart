// Offline fixture against actual Muyon gateway/provider, not a model of them.
// NOT_RUN on authoring host: no Dart/Flutter SDK. See ADAPTER-LOG-AUDIT.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/openai_compat_provider.dart';
import 'package:muyon/workspace/workspace_repository.dart';

const _canary = 'SYNTHETIC_MEMORY_BODY_CANARY_20261018_7c91';

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
  late Future<void> Function(HttpRequest request) respond;
  final prints = <String>[];
  var received = 0;

  ModelProfile profile(ModelPurpose purpose, {bool streaming = false}) =>
      ModelProfile(
        id: 'synthetic-${purpose.name}',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        location: ModelLocation.local,
        modelId: 'offline-fixture',
        endpointIdentity: 'synthetic-loopback-only',
        purpose: purpose,
        capabilities: ModelCapabilities(streaming: streaming),
      );

  // Captures actual Dart print calls made within this asynchronous call tree.
  // Does NOT intercept stdout.write, stderr, native logging, another isolate,
  // Flutter engine, test-runner reports, INFO/DEBUG modes, or OS crash logs.
  Future<T> capturePrint<T>(Future<T> Function() action) => runZoned(
        action,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => prints.add(line),
        ),
      );

  Future<void> reply(HttpRequest request, Object body, {int status = 200}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<String> chat() => gateway.chat(
        profile: profile(ModelPurpose.chat),
        messages: [
          {'role': 'user', 'content': _canary},
        ],
      );

  Future<List<List<double>>> embed() => gateway.embed(
        profile: profile(ModelPurpose.embedding),
        texts: [_canary],
        beforeSend: () async {},
      );

  Future<List<ModelEvent>> streamChat() => gateway
      .chatStream(
        provider: const OpenAiCompatProvider(),
        request: ModelRequest(
          profile: profile(ModelPurpose.chat, streaming: true),
          messages: const [ModelMessage(role: 'user', content: _canary)],
          caller: 'memory-failure-validation-fixture',
        ),
      )
      .toList();

  Future<void> assertNoBodyInPersistentEvidence(String expectedStatus) async {
    expect(received, 1, reason: 'fixture must reach actual gateway HTTP path once');
    expect(ledger.recent(), hasLength(1));
    expect(ledger.recent().single['status'], expectedStatus);
    expect(jsonEncode(ledger.recent()), isNot(contains(_canary)));
    expect(prints.join('\n'), isNot(contains(_canary)));
    await storage.close();
    // Scan actual files under the isolated storage root after database close.
    // latin1 preserves ASCII canary bytes even in a binary SQLite database.
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      expect(
        latin1.decode(file.readAsBytesSync()),
        isNot(contains(_canary)),
        reason: 'actual isolated storage file ${file.path}',
      );
    }
    storage = StorageManager(root.path);
    ledger = OutboundLedger(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    expect(ledger.recent(), hasLength(1));
    expect(ledger.recent().single['status'], expectedStatus);
    expect(jsonEncode(ledger.recent()), isNot(contains(_canary)));
  }

  setUp(() async {
    prints.clear();
    received = 0;
    root = Directory.systemTemp.createTempSync('muyon-actual-canary-');
    storage = StorageManager(root.path);
    ledger = OutboundLedger(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request) => reply(request, {'error': 'unconfigured fixture'});
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received++;
      expect(body, contains(_canary), reason: 'prove synthetic body reached server');
      await respond(request);
    });
    gateway = OpenAiModelGateway(
      _NoSecrets(),
      ledger: ledger,
      timeout: const Duration(seconds: 3),
      idleTimeout: const Duration(seconds: 3),
      streamLimit: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test('actual generation success keeps body out of persistent evidence/print', () async {
    respond = (request) => reply(request, {
          'choices': [
            {'message': {'content': _canary}},
          ],
        });
    expect(await capturePrint(chat), _canary);
    await assertNoBodyInPersistentEvidence('succeeded');
  });

  test('actual embedding success keeps input out of persistent evidence/print', () async {
    respond = (request) => reply(request, {
          'data': [
            {'index': 0, 'embedding': [0.25, 0.75]},
          ],
        });
    expect(await capturePrint(embed), [[0.25, 0.75]]);
    await assertNoBodyInPersistentEvidence('succeeded');
  });

  for (final purpose in ModelPurpose.values) {
    test('actual ${purpose.name} HTTP failure excludes response body', () async {
      respond = (request) => reply(request, {'error': _canary}, status: 500);
      Object? thrown;
      await capturePrint(() async {
        try {
          if (purpose == ModelPurpose.chat) {
            await chat();
          } else {
            await embed();
          }
        } catch (error) {
          thrown = error;
        }
      });
      expect(thrown, isA<HttpException>());
      expect('$thrown', isNot(contains(_canary)));
      await assertNoBodyInPersistentEvidence('failed');
    });
  }

  for (final failure in [false, true]) {
    test('actual OpenAiCompatProvider SSE ${failure ? 'failure' : 'success'}', () async {
      respond = (request) async {
        request.response.headers.contentType = ContentType('text', 'event-stream');
        final chunk = failure
            ? <String, Object?>{'error': {'message': _canary}}
            : <String, Object?>{
                'choices': [
                  {'delta': {'content': _canary}, 'finish_reason': 'stop'},
                ],
              };
        request.response.write('data: ${jsonEncode(chunk)}\n\ndata: [DONE]\n\n');
        await request.response.close();
      };
      final events = await capturePrint(streamChat);
      if (failure) {
        expect(events.whereType<ModelError>().single.code, 'provider_error');
        expect(events.whereType<Done>(), isEmpty);
        expect(events.whereType<ModelError>().single.code, isNot(contains(_canary)));
      } else {
        expect(events.whereType<TextDelta>().single.text, _canary);
        expect(events.whereType<Done>(), hasLength(1));
      }
      await assertNoBodyInPersistentEvidence(failure ? 'failed' : 'succeeded');
    });
  }

  // Ordinary contract assertions, deliberately NOT skipped/expectedFailure.
  // Static baseline inspection predicts failure: request() records succeeded
  // before chat/embed semantic validation. NOT_RUN on authoring host.
  test('blank chat fails without a succeeded operation ledger', () async {
    respond = (request) => reply(request, {
          'choices': [
            {'message': {'content': '   '}},
          ],
        });
    await capturePrint(() => expectLater(chat(), throwsA(isA<FormatException>())));
    expect(received, 1);
    expect(ledger.recent().single['status'], isNot('succeeded'));
  });

  test('empty embedding result fails without a succeeded operation ledger', () async {
    respond = (request) => reply(request, {'data': <Object>[]});
    await capturePrint(() => expectLater(embed(), throwsA(isA<FormatException>())));
    expect(received, 1);
    expect(ledger.recent().single['status'], isNot('succeeded'));
  });
}
