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

const _key = 'sk-stream-secret-0123456789';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String reference) async =>
      reference == 'key' ? _key : null;
}

class _FailingLedger extends OutboundLedger {
  _FailingLedger(super.database);
  @override
  Future<String> begin({
    required String caller,
    required ModelProfile profile,
    required String payload,
    required int itemCount,
    String? requestDigest,
    bool? streamed,
  }) => throw StateError('ledger unavailable');
}

String _chunk(Map<String, Object?> delta, {String? finish, Object? usage}) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': delta, 'finish_reason': finish},
      ],
      'usage': ?usage,
    })}\n\n';

void main() {
  late Directory root;
  late StorageManager storage;
  late OutboundLedger ledger;
  late HttpServer server;
  var requests = 0;
  final bodies = <Map<String, dynamic>>[];
  late Future<void> Function(HttpRequest request, Map<String, dynamic> body)
  respond;

  ModelProfile profile({String? credentialRef}) => ModelProfile(
    id: 'local',
    endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/chat/completions'),
    location: ModelLocation.local,
    modelId: 'm',
    endpointIdentity: 'fixture',
    credentialRef: credentialRef,
    capabilities: const ModelCapabilities(streaming: true, nativeTools: true),
  );

  ModelRequest request({
    String? credentialRef,
    bool jsonObject = false,
    String? digest = 'digest-1',
  }) => ModelRequest(
    profile: profile(credentialRef: credentialRef),
    messages: const [ModelMessage(role: 'user', content: 'hello')],
    jsonObject: jsonObject,
    caller: 'assistant',
    requestDigest: digest,
  );

  OpenAiModelGateway gateway({
    OutboundLedger? with_,
    Duration idle = const Duration(seconds: 5),
    Duration limit = const Duration(seconds: 5),
  }) => OpenAiModelGateway(
    _Secrets(),
    ledger: with_ ?? ledger,
    idleTimeout: idle,
    streamLimit: limit,
  );

  Future<void> sse(HttpRequest r, List<String> parts, {bool end = true}) async {
    r.response.bufferOutput = false;
    r.response.headers.contentType = ContentType('text', 'event-stream');
    for (final part in parts) {
      r.response.write(part);
      await r.response.flush();
    }
    if (end) await r.response.close();
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('muyon-stream-');
    storage = StorageManager(root.path);
    ledger = OutboundLedger(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    requests = 0;
    bodies.clear();
    respond = (r, b) => sse(r, [
      _chunk({'content': 'ok'}),
      _chunk({}, finish: 'stop'),
      'data: [DONE]\n\n',
    ]);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      requests++;
      final body =
          jsonDecode(await utf8.decoder.bind(r).join()) as Map<String, dynamic>;
      bodies.add(body);
      await respond(r, body);
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await storage.close();
    root.deleteSync(recursive: true);
  });

  Map<String, Object?> only() {
    final rows = ledger.recent();
    expect(rows, hasLength(1));
    return rows.single;
  }

  test('the row is written before the endpoint sees the request and one row '
      'covers the whole stream', () async {
    Map<String, Object?>? seenByEndpoint;
    respond = (r, b) {
      seenByEndpoint = ledger.recent().single;
      return sse(r, [
        _chunk({'content': 'ok'}),
        _chunk({}, finish: 'stop'),
        'data: ${jsonEncode({
          'choices': <Object?>[],
          'usage': {'prompt_tokens': 7, 'completion_tokens': 2},
        })}\n\n',
        'data: [DONE]\n\n',
      ]);
    };
    final events = await gateway()
        .chatStream(provider: const OpenAiCompatProvider(), request: request())
        .toList();
    expect((events.last as Done).reason, FinishReason.stop);
    expect(seenByEndpoint!['status'], 'sending');
    expect(seenByEndpoint!['streamed'], 1);
    expect(seenByEndpoint!['request_digest'], 'digest-1');
    expect(bodies.single['stream'], true);
    final row = only();
    expect(row['status'], 'succeeded');
    expect(row['http_status'], 200);
    expect(row['prompt_tokens'], 7);
    expect(row['completion_tokens'], 2);
    expect(row['bytes_received'], greaterThan(0));
    expect(row['first_byte_ms'], isNotNull);
    expect(row['caller'], 'assistant');
    expect(row['payload_sha256'], hasLength(64));
  });

  test('a ledger that cannot record sends nothing', () async {
    final failing = _FailingLedger(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    await expectLater(
      gateway(with_: failing)
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: request(),
          )
          .toList(),
      throwsStateError,
    );
    expect(requests, 0);
    expect(ledger.recent(), isEmpty);
  });

  test('beforeSend and a missing credential stop the request before the '
      'ledger and the network', () async {
    await expectLater(
      gateway()
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: request(),
            beforeSend: () async => throw StateError('stale_confirmation'),
          )
          .toList(),
      throwsStateError,
    );
    await expectLater(
      gateway()
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: request(credentialRef: 'missing'),
          )
          .toList(),
      throwsStateError,
    );
    expect(requests, 0);
    expect(ledger.recent(), isEmpty);
  });

  test('a stream cut before its finish reason is failed with the bytes '
      'received and a fixed reason', () async {
    respond = (r, b) => sse(r, [
      _chunk({'content': 'half an answ'}),
    ]);
    final events = await gateway()
        .chatStream(provider: const OpenAiCompatProvider(), request: request())
        .toList();
    expect(events.whereType<Done>(), isEmpty);
    final failure = events.last as ModelError;
    expect(failure.code, 'stream_truncated');
    expect(failure.partialOutput, isTrue);
    final row = only();
    expect(row['status'], 'failed');
    expect(row['error'], 'stream_truncated');
    expect(row['bytes_received'], greaterThan(0));
  });

  test('cancelling mid-stream ends the row as cancelled', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    respond = (r, b) async {
      await sse(r, [
        _chunk({'content': 'a'}),
      ], end: false);
      started.complete();
      await release.future;
      await r.response.close();
    };
    final token = ModelCancellation();
    final seen = <ModelEvent>[];
    final done = gateway()
        .chatStream(
          provider: const OpenAiCompatProvider(),
          request: request(),
          cancellation: token,
        )
        .listen(seen.add)
        .asFuture<void>();
    await started.future;
    while (seen.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    token.cancel();
    await expectLater(done, throwsStateError);
    release.complete();
    final row = only();
    expect(row['status'], 'cancelled');
    expect(row['error'], contains('may have processed it'));
  });

  test('a listener that goes away mid-stream also ends the row as '
      'cancelled', () async {
    final release = Completer<void>();
    respond = (r, b) async {
      await sse(r, [
        _chunk({'content': 'a'}),
      ], end: false);
      await release.future;
      await r.response.close();
    };
    final stream = gateway().chatStream(
      provider: const OpenAiCompatProvider(),
      request: request(),
    );
    final first = Completer<void>();
    final sub = stream.listen((e) {
      if (!first.isCompleted) first.complete();
    });
    await first.future;
    await sub.cancel();
    release.complete();
    expect(only()['status'], 'cancelled');
  });

  test('silence past the idle limit is a timeout', () async {
    final release = Completer<void>();
    respond = (r, b) async {
      await sse(r, [
        _chunk({'content': 'a'}),
      ], end: false);
      await release.future;
    };
    await expectLater(
      gateway(idle: const Duration(milliseconds: 150))
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: request(),
          )
          .toList(),
      throwsA(isA<TimeoutException>()),
    );
    release.complete();
    final row = only();
    expect(row['status'], 'timeout');
    expect(row['bytes_received'], greaterThan(0));
  });

  test('a slow trickle is stopped by the absolute limit even though it is '
      'never idle', () async {
    respond = (r, b) async {
      r.response.bufferOutput = false;
      r.response.headers.contentType = ContentType('text', 'event-stream');
      try {
        for (var i = 0; i < 200; i++) {
          r.response.write(_chunk({'content': 'x'}));
          await r.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await r.response.close();
      } catch (_) {}
    };
    final watch = Stopwatch()..start();
    await expectLater(
      gateway(idle: const Duration(seconds: 2))
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: request(),
            maxDuration: const Duration(milliseconds: 250),
          )
          .toList(),
      throwsA(isA<TimeoutException>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(only()['status'], 'timeout');
  });

  test('an HTTP rejection is failed and never retried on its own', () async {
    respond = (r, b) async {
      r.response.statusCode = 422;
      await r.response.close();
    };
    await expectLater(
      gateway()
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: request(),
          )
          .toList(),
      throwsA(
        isA<HttpException>().having(
          (e) => e.message,
          'message',
          'model_http_422',
        ),
      ),
    );
    expect(requests, 1);
    final row = only();
    expect(row['status'], 'failed');
    expect(row['http_status'], 422);
  });

  test('a JSON-mode request is resent once without response_format, both '
      'ledgered, and remembered', () async {
    respond = (r, b) async {
      if (b.containsKey('response_format')) {
        r.response.statusCode = 400;
        await r.response.close();
        return;
      }
      await sse(r, [
        _chunk({'content': 'ok'}),
        _chunk({}, finish: 'stop'),
      ]);
    };
    final g = gateway();
    final events = await g
        .chatStream(
          provider: const OpenAiCompatProvider(),
          request: request(jsonObject: true),
        )
        .toList();
    expect((events.last as Done).reason, FinishReason.stop);
    expect(requests, 2);
    expect(ledger.recent().map((r) => r['status']).toList()..sort(), [
      'failed',
      'succeeded',
    ]);
    await g
        .chatStream(
          provider: const OpenAiCompatProvider(),
          request: request(jsonObject: true),
        )
        .toList();
    expect(requests, 3, reason: 'remembered: no second attempt');
    expect(bodies.last.containsKey('response_format'), isFalse);
  });

  test('an endpoint that echoes the key leaks it into no event, error or '
      'ledger row', () async {
    respond = (r, b) => sse(r, [
      _chunk({'content': 'partial'}),
      'data: ${jsonEncode({
        'error': {'message': 'invalid key $_key'},
      })}\n\n',
    ]);
    final events = await gateway()
        .chatStream(
          provider: const OpenAiCompatProvider(),
          request: request(credentialRef: 'key'),
        )
        .toList();
    expect((events.last as ModelError).code, 'provider_error');
    var row = only();
    expect(row['status'], 'failed');
    expect(row['error'], 'provider_error');
    expect(jsonEncode(row), isNot(contains(_key)));

    // A cut stream and an HTTP error body that carries the key.
    respond = (r, b) =>
        sse(r, ['data: {"choices":[{"delta":{"content":"$_key']);
    final cut = await gateway()
        .chatStream(
          provider: const OpenAiCompatProvider(),
          request: request(credentialRef: 'key'),
        )
        .toList();
    expect((cut.last as ModelError).code, 'stream_malformed');
    respond = (r, b) async {
      r.response.statusCode = 401;
      r.response.write('Authorization: Bearer $_key');
      await r.response.close();
    };
    Object? thrown;
    try {
      await gateway()
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: request(credentialRef: 'key'),
          )
          .toList();
    } catch (e) {
      thrown = e;
    }
    expect('$thrown', isNot(contains(_key)));
    expect(jsonEncode(ledger.recent()), isNot(contains(_key)));
    expect(
      jsonEncode(cut.map((e) => e is ModelError ? e.code : '').toList()),
      isNot(contains(_key)),
    );
    row = ledger.recent().first;
    expect(row['status'], 'failed');
  });
}
