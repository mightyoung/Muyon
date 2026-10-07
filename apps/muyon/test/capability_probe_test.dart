import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/model_request_gate.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/models/capability_probe.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_presets.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';

/// K-2b: "测试连接" against a loopback endpoint. Nothing here reaches a real
/// model; the endpoint is a fake that answers as each case needs.
const _key = 'sk-probe-secret-0123456789';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String reference) async =>
      reference == 'key' ? _key : null;
}

class _Gate implements ModelRequestGate {
  _Gate([this.answer = const GateConfirm()]);
  final GateDecision answer;
  final facts = <ModelRequestFacts>[];
  @override
  Future<GateDecision> decide(ModelRequestFacts f) async {
    facts.add(f);
    return answer;
  }
}

String _chunk(Map<String, Object?> delta, {String? finish, Object? usage}) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': delta, 'finish_reason': finish},
      ],
      'usage': ?usage,
    })}\n\n';

List<String> _calls(int n, {bool usage = true}) => [
  for (var i = 0; i < n; i++)
    _chunk({
      'tool_calls': [
        {
          'index': i,
          'id': 'call_$i',
          'function': {'name': probeToolName, 'arguments': '{"value":"ok"}'},
        },
      ],
    }),
  _chunk({}, finish: 'tool_calls'),
  if (usage)
    'data: ${jsonEncode({
      'choices': [],
      'usage': {'prompt_tokens': 60, 'completion_tokens': 9},
    })}\n\n',
  'data: [DONE]\n\n',
];

void main() {
  late Directory root;
  late StorageManager storage;
  late OutboundLedger ledger;
  late HttpServer server;
  final bodies = <Map<String, dynamic>>[];
  final auth = <String?>[];
  late Future<void> Function(HttpRequest r, int n) respond;

  ModelProfile profile({
    String model = 'unlisted-model',
    ModelCapabilities capabilities = ModelCapabilities.compat,
  }) => ModelProfile(
    id: 'p1',
    endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
    location: ModelLocation.local,
    modelId: model,
    endpointIdentity: 'fixture',
    credentialRef: 'key',
    capabilities: capabilities,
  );

  Future<void> sse(HttpRequest r, List<String> parts) async {
    r.response.headers.contentType = ContentType('text', 'event-stream');
    for (final part in parts) {
      r.response.add(utf8.encode(part));
      await r.response.flush();
    }
    await r.response.close();
  }

  Future<void> status(HttpRequest r, int code) async {
    r.response.statusCode = code;
    r.response.write('{"error":"$code $_key"}');
    await r.response.close();
  }

  CapabilityProbe probe([ModelRequestGate? gate]) => CapabilityProbe(
    gateway: OpenAiModelGateway(
      _Secrets(),
      ledger: ledger,
      idleTimeout: const Duration(milliseconds: 600),
    ),
    gate: gate ?? _Gate(),
    clock: () => DateTime.utc(2026, 10, 7, 12),
  );

  var asked = <ProbeConfirmation>[];
  Future<bool> yes(ProbeConfirmation c) async {
    asked.add(c);
    return true;
  }

  setUp(() async {
    root = Directory.systemTemp.createTempSync('muyon-probe-');
    storage = StorageManager(root.path);
    ledger = OutboundLedger(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    bodies.clear();
    auth.clear();
    asked = [];
    respond = (r, n) => sse(r, _calls(1));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var n = 0;
    server.listen((r) async {
      bodies.add(
        jsonDecode(await utf8.decoder.bind(r).join()) as Map<String, dynamic>,
      );
      auth.add(r.headers.value('authorization'));
      await respond(r, n++);
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await storage.close();
    root.deleteSync(recursive: true);
  });

  group('the fixed payload', () {
    test('is a constant with no user data, and its digest is pinned', () {
      expect(
        probeContentDigest(),
        'da8f7d8fb08556d369a9eec66e175bbc21198e3ccc5fd49d0e0e082163346bbb',
      );
      expect(probeContentDigest(extended: true), isNot(probeContentDigest()));
      final request = probeRequest(profile());
      expect(request.caller, 'capability_probe');
      expect(request.tools.single.name, 'probe_echo');
      expect([for (final m in request.messages) m.role], ['system', 'user']);
      // The digest does not depend on the profile (endpoint, model, key).
      expect(
        probeRequest(profile(model: 'other')).requestDigest,
        request.requestDigest,
      );
    });

    test('goes out as sent: stream, usage, one tool, ledger caller', () async {
      final outcome = await probe().run(profile(), confirm: yes);
      expect(outcome.stoppedBy, isNull);
      final body = bodies.single;
      // The digest in the card and the ledger is that of the bytes sent.
      expect(
        sha256
            .convert(utf8.encode(jsonEncode(Map.of(body)..remove('model'))))
            .toString(),
        probeContentDigest(),
      );
      expect(body['stream'], isTrue);
      expect(body['stream_options'], {'include_usage': true});
      expect(body.containsKey('response_format'), isFalse);
      expect(
        [for (final t in body['tools'] as List) t['function']['name']],
        ['probe_echo'],
      );
      expect(body['messages'][1]['content'], probeUserSentence);
      expect(auth.single, 'Bearer $_key');
      final rows = ledger.recent();
      expect(rows, hasLength(1));
      expect(rows.single['caller'], 'capability_probe');
      expect(rows.single['status'], 'succeeded');
      expect(rows.single['streamed'], 1);
      expect(rows.single['request_digest'], probeContentDigest());
      expect(rows.single['prompt_tokens'], 60);
      expect(outcome.detected!.ledgerIds, [rows.single['id']]);
      expect(outcome.detected!.payloadDigest, probeContentDigest());
      // Nothing of the credential is kept.
      expect(jsonEncode(rows), isNot(contains(_key)));
      expect(jsonEncode(outcome.detected!.toJson()), isNot(contains(_key)));
    });
  });

  group('the gate and the confirmation', () {
    test('a probe asks the gate with no task, scope or data', () async {
      final gate = _Gate();
      await probe(gate).run(profile(), confirm: yes);
      final f = gate.facts.single;
      expect(f.dataCategories, isEmpty);
      expect(f.step, 0);
      expect(f.endpoint, contains('/v1/chat/completions'));
      expect(f.requestDigest, probeContentDigest());
      expect(asked.single.notice, '将向该端点发送凭据与固定探测内容');
      expect(asked.single.digest, probeContentDigest());
      expect(asked.single.payload['stream'], isTrue);
    });

    test('declining sends nothing and writes no ledger row', () async {
      final outcome = await probe().run(profile(), confirm: (_) async => false);
      expect(outcome.stoppedBy, 'declined');
      expect(outcome.detected, isNull);
      expect(bodies, isEmpty);
      expect(ledger.recent(), isEmpty);
    });

    test('a gate that denies stops before any request', () async {
      final outcome = await probe(_Gate(const GateDenied('no')))
          .run(profile(), confirm: yes);
      expect(outcome.stoppedBy, 'denied');
      expect(bodies, isEmpty);
      expect(ledger.recent(), isEmpty);
      expect(asked, isEmpty);
    });

    test('a ledger that cannot record means nothing is sent', () async {
      final failing = _FailingLedger(ledger.database);
      final p = CapabilityProbe(
        gateway: OpenAiModelGateway(_Secrets(), ledger: failing),
        gate: _Gate(),
      );
      final outcome = await p.run(profile(), confirm: yes);
      expect(bodies, isEmpty);
      expect(outcome.detected!.nativeTools, ProbeVerdict.undetermined);
    });

    test('an embedding profile cannot be tested', () {
      final embedding = ModelProfile(
        id: 'e',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        location: ModelLocation.local,
        modelId: 'e',
        endpointIdentity: 'e',
        purpose: ModelPurpose.embedding,
      );
      expect(
        () => probe().run(embedding, confirm: yes),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the verdicts', () {
    test('yes: tool call, stream and usage', () async {
      final outcome = await probe().run(profile(), confirm: yes);
      final d = outcome.detected!;
      expect(outcome.rejected, isFalse);
      expect(d.nativeTools, ProbeVerdict.yes);
      expect(d.streaming, ProbeVerdict.yes);
      expect(d.reportsUsage, ProbeVerdict.yes);
      expect(d.jsonObject, ProbeVerdict.notTested);
      expect(d.parallelToolCalls, ProbeVerdict.notTested);
    });

    test('no usage chunk: usage is "no", the rest unchanged', () async {
      respond = (r, n) => sse(r, _calls(1, usage: false));
      final d = (await probe().run(profile(), confirm: yes)).detected!;
      expect(d.reportsUsage, ProbeVerdict.no);
      expect(d.nativeTools, ProbeVerdict.yes);
    });

    test('400 / 422 name no parameter: nothing is concluded', () async {
      for (final code in [400, 422]) {
        respond = (r, n) => status(r, code);
        final outcome = await probe().run(profile(), confirm: yes);
        final d = outcome.detected!;
        expect(outcome.rejected, isTrue, reason: '$code');
        expect(d.nativeTools, ProbeVerdict.undetermined, reason: '$code');
        expect(d.streaming, ProbeVerdict.undetermined);
        expect(d.reportsUsage, ProbeVerdict.undetermined);
      }
      expect(ledger.recent().every((r) => r['status'] == 'failed'), isTrue);
    });

    test('accepted but no tool call: unconfirmed, treated as no', () async {
      respond = (r, n) => sse(r, [
        _chunk({'content': '好的'}),
        _chunk({}, finish: 'stop'),
        'data: [DONE]\n\n',
      ]);
      final d = (await probe().run(profile(), confirm: yes)).detected!;
      expect(d.nativeTools, ProbeVerdict.unconfirmed);
      expect(d.streaming, ProbeVerdict.yes);
      expect(
        d.adoptedOver(const ModelCapabilities(nativeTools: true)).nativeTools,
        isFalse,
      );
    });

    test('a call to another tool is not a native-tools "yes"', () async {
      respond = (r, n) => sse(r, [
        _chunk({
          'tool_calls': [
            {
              'index': 0,
              'id': 'c',
              'function': {'name': 'delete_everything', 'arguments': '{}'},
            },
          ],
        }),
        _chunk({}, finish: 'tool_calls'),
        'data: [DONE]\n\n',
      ]);
      final d = (await probe().run(profile(), confirm: yes)).detected!;
      expect(d.nativeTools, ProbeVerdict.unconfirmed);
    });

    test('401, 403, 500, a cut stream: cannot be determined', () async {
      for (final code in [401, 403, 500]) {
        respond = (r, n) => status(r, code);
        final d = (await probe().run(profile(), confirm: yes)).detected!;
        expect(d.nativeTools, ProbeVerdict.undetermined, reason: '$code');
        expect(d.streaming, ProbeVerdict.undetermined);
      }
      respond = (r, n) => sse(r, [
        _chunk({'content': 'par'}),
      ]);
      final cut = (await probe().run(profile(), confirm: yes)).detected!;
      expect(cut.nativeTools, ProbeVerdict.undetermined);
      expect(cut.streaming, ProbeVerdict.undetermined);
      expect(jsonEncode(ledger.recent()), isNot(contains(_key)));
    });

    test('a silent endpoint times out: cannot be determined', () async {
      respond = (r, n) => Completer<void>().future;
      final d = (await probe().run(profile(), confirm: yes)).detected!;
      expect(d.nativeTools, ProbeVerdict.undetermined);
      expect(ledger.recent().single['status'], 'timeout');
    });
  });

  group('the optional second request', () {
    test('JSON mode and parallel calls, in their own ledger row', () async {
      respond = (r, n) => sse(r, _calls(n == 0 ? 1 : 2));
      final d = (await probe().run(
        profile(),
        extended: true,
        confirm: yes,
      )).detected!;
      expect(bodies, hasLength(2));
      expect(bodies[1]['response_format'], {'type': 'json_object'});
      expect(bodies[1]['messages'][1]['content'], probeExtendedUserSentence);
      expect(d.jsonObject, ProbeVerdict.yes);
      expect(d.parallelToolCalls, ProbeVerdict.yes);
      expect(asked.map((c) => '${c.index}/${c.total}'), ['1/2', '2/2']);
      final rows = ledger.recent();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r['caller'] == 'capability_probe'), isTrue);
      expect(d.ledgerIds, hasLength(2));
    });

    test('one call only: parallel is unconfirmed', () async {
      final d = (await probe().run(
        profile(),
        extended: true,
        confirm: yes,
      )).detected!;
      expect(d.jsonObject, ProbeVerdict.yes);
      expect(d.parallelToolCalls, ProbeVerdict.unconfirmed);
    });

    test('a 400 on the second request: JSON mode cannot be told', () async {
      respond = (r, n) => n == 0 ? sse(r, _calls(1)) : status(r, 400);
      final outcome = await probe().run(
        profile(),
        extended: true,
        confirm: yes,
      );
      final d = outcome.detected!;
      expect(outcome.rejected, isTrue);
      expect(d.nativeTools, ProbeVerdict.yes);
      expect(d.jsonObject, ProbeVerdict.undetermined);
      expect(d.parallelToolCalls, ProbeVerdict.undetermined);
    });

    test('is not sent after a first request that got no answer', () async {
      respond = (r, n) => status(r, 401);
      final d = (await probe().run(
        profile(),
        extended: true,
        confirm: yes,
      )).detected!;
      expect(bodies, hasLength(1));
      expect(d.jsonObject, ProbeVerdict.undetermined);
    });

    test('each request is confirmed by itself', () async {
      var n = 0;
      final outcome = await probe().run(
        profile(),
        extended: true,
        confirm: (c) async => ++n == 1,
      );
      expect(bodies, hasLength(1));
      expect(outcome.detected!.nativeTools, ProbeVerdict.yes);
      expect(outcome.detected!.jsonObject, ProbeVerdict.notTested);
    });
  });

  group('the result takes effect only when adopted', () {
    test('the profile is unchanged by a probe; adoption writes it', () async {
      final workspaces = WorkspaceRepository(
        await storage.open('profiles', WorkspaceRepository.schema),
      );
      final repo = ProfileRepository(workspaces);
      final original = profile(
        capabilities: const ModelCapabilities(
          streaming: true,
          source: CapabilitySource.preset,
        ),
      );
      await repo.save(original);
      final detected = (await probe().run(original, confirm: yes)).detected!;
      // Detection is stored next to the capabilities, not in them.
      await repo.save(original.copyWith(detectedCapabilities: detected));
      var stored = repo.all().single;
      expect(stored.detectedCapabilities!.nativeTools, ProbeVerdict.yes);
      expect(stored.capabilities.nativeTools, isFalse);
      expect(stored.capabilities.source, CapabilitySource.preset);
      // The task payload sees the profile exactly as before.
      expect(stored.toJson().containsKey('detectedCapabilities'), isFalse);
      expect(stored.toJson(), original.toJson());

      await repo.save(
        stored.copyWith(
          capabilities: stored.detectedCapabilities!.adoptedOver(
            stored.capabilities,
          ),
        ),
      );
      stored = repo.all().single;
      expect(stored.capabilities.nativeTools, isTrue);
      expect(stored.capabilities.reportsUsage, isTrue);
      expect(stored.capabilities.source, CapabilitySource.detected);
      expect(stored.detectedCapabilities, isNotNull);
    });

    test('only definite findings are applied', () {
      final detected = DetectedCapabilities(
        nativeTools: ProbeVerdict.yes,
        streaming: ProbeVerdict.undetermined,
        reportsUsage: ProbeVerdict.notTested,
        detectedAt: DateTime.utc(2026),
        payloadDigest: 'd',
      );
      final next = detected.adoptedOver(
        const ModelCapabilities(streaming: true, reportsUsage: true),
      );
      expect(next.nativeTools, isTrue);
      expect(next.streaming, isTrue);
      expect(next.reportsUsage, isTrue);
      final nothing = DetectedCapabilities(
        streaming: ProbeVerdict.undetermined,
        detectedAt: DateTime.utc(2026),
        payloadDigest: 'd',
      );
      expect(nothing.differsFrom(ModelCapabilities.compat), isFalse);
    });

    test('a damaged stored result reads as none', () {
      expect(DetectedCapabilities.fromJson('x'), isNull);
      expect(DetectedCapabilities.fromJson({'nativeTools': 'yes'}), isNull);
    });
  });

  group('presets', () {
    test('fill the sizes of the result, not the capabilities', () async {
      final p = profile(model: 'deepseek-chat');
      final d = (await probe().run(p, confirm: yes)).detected!;
      expect(d.contextTokens, 128000);
      expect(d.maxOutputTokens, 8192);
      expect(p.capabilities.contextTokens, isNull);
      expect(d.adoptedOver(p.capabilities).contextTokens, 128000);
    });

    test('an unlisted model gets no sizes', () async {
      final d = (await probe().run(profile(), confirm: yes)).detected!;
      expect(d.contextTokens, isNull);
      expect(d.maxOutputTokens, isNull);
    });

    test('the longest prefix wins and vendor prefixes are ignored', () {
      expect(presetFor('GPT-4o-mini')!.prefix, 'gpt-4o');
      expect(presetFor('deepseek/deepseek-reasoner')!.nativeTools, isFalse);
      expect(presetFor('llama3.1:8b')!.contextTokens, 131072);
      expect(presetFor('llama3:8b')!.contextTokens, 8192);
      expect(presetFor('something-else'), isNull);
    });
  });
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
