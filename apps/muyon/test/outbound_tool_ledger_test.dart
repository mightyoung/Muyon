import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/inquiry_hub_authority.dart';
import 'package:muyon/app/inquiry_web_authority.dart';
import 'package:muyon/platform/mcp_adapter.dart';
import 'package:muyon/platform/outbound_tool_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/transfer/transfer_service.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

const marker = 'token-SECRET-12345678';

class Secrets implements SecretStore {
  @override
  Future<String?> read(String reference) async => marker;
}

void main() {
  late ManagedConnection db;
  late ToolRegistry registry;
  late HttpServer server;
  late Uri destination;
  late List<List<int>> bodies;
  late List<String> methods;
  late List<int> observedPending;
  var fail = false;
  List<Map<String, Object?>> rows() => [
    for (final r in db.raw.select(
      'SELECT * FROM outbound_tool_requests ORDER BY rowid',
    ))
      Map<String, Object?>.from(r),
  ];
  void blockLedger() => db.raw.execute('''
CREATE TRIGGER refuse_outbound BEFORE INSERT ON outbound_tool_requests
BEGIN SELECT RAISE(ABORT, 'ledger_unavailable'); END;
''');
  setUp(() async {
    db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(db.raw);
    }
    registry = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: const []),
    );
    bodies = [];
    methods = [];
    observedPending = [];
    fail = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    destination = Uri.parse(
      'http://127.0.0.1:${server.port}/path?token=$marker#fragment',
    );
    server.listen((req) async {
      final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      bodies.add(body);
      final pending = rows().where((r) => r['state'] == 'pending').toList();
      if (pending.isNotEmpty) {
        expect(pending, hasLength(1));
        expect(
          pending.single['payload_digest'],
          sha256.convert(body).toString(),
        );
      }
      observedPending.add(pending.length);
      if (req.uri.path == '/mcp') {
        final message = jsonDecode(utf8.decode(body)) as Map;
        methods.add(message['method'] as String);
        if (message['id'] == null) {
          req.response.statusCode = 202;
        } else {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': message['id'],
              if (fail) 'error': {'code': -1, 'message': 'rejected $marker'},
              if (!fail)
                'result': message['method'] == 'tools/list'
                    ? {
                        'tools': [
                          {
                            'name': 'echo',
                            'inputSchema': {
                              'type': 'object',
                              'properties': {
                                'text': {'type': 'string'},
                              },
                            },
                          },
                        ],
                      }
                    : message['method'] == 'tools/call'
                    ? {
                        'content': [
                          {'type': 'text', 'text': 'ok'},
                        ],
                      }
                    : {},
            }),
          );
        }
      } else {
        req.response.statusCode = fail ? 422 : 200;
        req.response.write(fail ? 'rejected $marker' : '{}');
      }
      await req.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await db.close();
  });

  Future<void> mcp({bool call = false}) async {
    final config = McpServerConfig(
      id: 'test',
      endpoint: destination.replace(path: '/mcp', fragment: ''),
      credentialRef: 'key',
    );
    await McpAdapter.connect(registry, config, secrets: Secrets());
    if (call) {
      final request = ToolCallRequest(
        invocationId: 'echo-1',
        toolId: 'mcp.test.echo',
        scope: const AssistantScope.global(),
        destination: config.endpoint.origin,
        parameters: {'text': '中文🌍'},
      );
      final prepared = await registry.prepare(request);
      final grant = await registry.approve(prepared);
      final result = await registry.invoke(request.withApproval(grant));
      expect(result.status, ToolCallStatus.succeeded);
    }
  }

  Future<void> exchange(
    Uri uri,
    void Function() guard, {
    HubRequest? hub,
  }) async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      guard();
      final req = await client.openUrl(
        hub?.method ?? 'GET',
        uri.replace(fragment: ''),
      );
      guard();
      if (hub?.encodedBody != null) {
        final payload = utf8.encode(hub!.encodedBody!);
        req.add(payload);
        hub.onBodySent?.call(payload.length);
      }
      final response = await req.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) throw StateError('Bearer $marker $text');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> web() => InquiryWebAuthority(registry).run<void>(
    destination: destination,
    sessionId: 'session',
    cancellation: AiCancellation(),
    review: (_, _) async => true,
    validateSession: () {},
    operation: (guard) => exchange(destination, guard),
  );
  Future<void> hub() {
    final request = HubRequest('POST', destination, {'text': '中文🌍'});
    return InquiryHubAuthority(registry).run<void>(
      request: request,
      cancellation: AiCancellation(),
      review: (_, _) async => true,
      validateSession: () {},
      operation: (guard) => exchange(destination, guard, hub: request),
    );
  }

  for (final channel in ['mcp', 'inquiry_web', 'inquiry_hub']) {
    Future<void> invoke() => switch (channel) {
      'mcp' => mcp(),
      'inquiry_web' => web(),
      _ => hub(),
    };
    test('$channel blocked ledger sends zero requests', () async {
      blockLedger();
      Object? failure;
      try {
        await invoke();
      } catch (error) {
        failure = error;
      }
      // ignore: avoid_print
      print('REG2A_BLOCKED $channel requests=${bodies.length}');
      expect(bodies, isEmpty);
      expect(failure, isNotNull);
      expect(rows(), isEmpty);
    });
    test(
      '$channel succeeds with exact body bytes and safe destination',
      () async {
        if (channel == 'mcp') {
          await mcp(call: true);
        } else {
          await invoke();
        }
        expect(observedPending, everyElement(1));
        final entries = rows();
        expect(entries, hasLength(bodies.length));
        for (var i = 0; i < entries.length; i++) {
          expect(entries[i]['state'], 'succeeded');
          expect(entries[i]['finished_at'], isNotNull);
          expect(entries[i]['bytes_sent'], bodies[i].length);
          expect(
            entries[i]['destination'],
            channel == 'mcp'
                ? 'http://127.0.0.1:${server.port}/mcp'
                : 'http://127.0.0.1:${server.port}/path',
          );
        }
        if (channel == 'mcp') {
          expect(methods, [
            'initialize',
            'notifications/initialized',
            'tools/list',
            'tools/call',
          ]);
        }
      },
    );
    test('$channel failed request leaves safe failed row', () async {
      fail = true;
      await expectLater(invoke(), throwsA(anything));
      expect(rows().last['state'], 'failed');
      expect(rows().last['error'], isNot(contains(marker)));
      expect(rows().last['bytes_sent'], bodies.last.length);
    });
  }

  test('native hub POST counts canonical UTF8 body', () async {
    final client = HubClient(
      Uri.parse('http://127.0.0.1:${server.port}'),
      token: marker,
      journal: HubPublicationJournal(db.raw, write: db.write),
      hosted: true,
      authority: InquiryHubAuthority(registry),
      review: (_, _) async => true,
      validateSession: () {},
    );
    await client.preview({'text': '中文🌍'});
    expect(observedPending, [1]);
    expect(rows().single['state'], 'succeeded');
    expect(rows().single['bytes_sent'], bodies.single.length);
    expect(
      rows().single['payload_digest'],
      sha256.convert(bodies.single).toString(),
    );
  });

  test('web cancellation finalizes as cancelled', () async {
    final cancel = AiCancellation();
    await expectLater(
      InquiryWebAuthority(registry).run<void>(
        destination: destination,
        sessionId: 'session',
        cancellation: cancel,
        review: (_, _) async => true,
        validateSession: () {},
        operation: (guard) async {
          guard();
          cancel.cancel();
          guard();
        },
      ),
      throwsA(anything),
    );
    expect(rows().single['state'], 'cancelled');
    expect(rows().single['bytes_sent'], 0);
    expect(bodies, isEmpty);
  });

  test('MCP timeout finalizes before returning', () async {
    await server.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
    });
    final config = McpServerConfig(
      id: 'timeout',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/mcp'),
    );
    await expectLater(
      McpAdapter.connect(
        registry,
        config,
        secrets: Secrets(),
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(anything),
    );
    expect(rows().single['state'], 'failed');
    expect(rows().single['finished_at'], isNotNull);
  });

  test('closed ledger sends nothing', () async {
    await db.close();
    var effects = 0;
    await expectLater(
      OutboundToolLedger(db).run<void>(
        toolId: 'test',
        channel: 'mcp',
        destination: destination,
        payload: [],
        operation: (_) async {
          effects++;
        },
      ),
      throwsA(anything),
    );
    expect(effects, 0);
  });

  group('transfer', () {
    late Directory root;
    late ManagedConnection business;
    late TransferService service;
    late HttpServer tls;
    late DeviceIdentity identity;
    var requests = 0;
    late List<int> received;
    setUp(() async {
      root = Directory.systemTemp.createTempSync('reg2a-');
      business = ManagedConnection(sqlite3.openInMemory());
      for (final m in KnowledgeService.schema.migrations) {
        m.migrate(business.raw);
      }
      service = TransferService(business, root.path, outboundDatabase: db);
      await service.start(
        deviceId: 'local',
        deviceName: '中文🌍',
        discoveryPort: 0,
        httpPort: 0,
        secrets: MemoryLanSecretStore(),
      );
      identity = DeviceIdentity.generate();
      final context = lanTlsContext()
        ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
        ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
      tls = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      requests = 0;
      received = [];
      tls.listen((req) async {
        requests++;
        received = await req.fold<List<int>>([], (a, b) => a..addAll(b));
        final pending = rows().where((r) => r['state'] == 'pending').toList();
        observedPending.add(pending.length);
        if (pending.isNotEmpty) {
          expect(pending, hasLength(1));
          expect(
            pending.single['payload_digest'],
            sha256.convert(received).toString(),
          );
        }
        if (req.uri.path == '/hello') {
          req.response.write(
            jsonEncode({
              'siq': 1,
              'id': 'remote',
              'name': 'remote',
              'fingerprint': identity.fingerprint,
              'certificate': identity.certificatePem,
            }),
          );
        } else if (fail) {
          req.response.statusCode = 422;
        }
        await req.response.close();
      });
    });
    tearDown(() async {
      await service.close();
      await tls.close(force: true);
      await business.close();
      root.deleteSync(recursive: true);
    });
    Future<LanPeer> peer() async {
      final remote = await service.probe('127.0.0.1', port: tls.port);
      service.confirmPeer(
        fingerprint: remote.fingerprint,
        confirmedCode: identity.shortCode,
        certificatePem: remote.certificatePem,
      );
      return remote;
    }

    Future<void> send(LanPeer to) async {
      final file = File('${root.path}/text')..writeAsStringSync('中文🌍');
      final package = await service.exportFiles([file.path]);
      await service.send(to, package);
    }

    test('transfer listener identity reply is accounted and blocked on write failure', () async {
      final client = HttpClient(context: lanTlsContext())
        ..findProxy = ((_) => 'DIRECT')
        ..badCertificateCallback = (_, _, _) => true;
      try {
        final uri = Uri.parse('https://127.0.0.1:${service.httpPort}/hello');
        final request = await client.getUrl(uri);
        final response = await request.close();
        final body = await response.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(rows().single['state'], 'succeeded');
        expect(rows().single['bytes_sent'], body.length);
        expect(
          rows().single['payload_digest'],
          sha256.convert(body).toString(),
        );
        blockLedger();
        final blocked = await client.getUrl(uri);
        await expectLater(blocked.close(), throwsA(anything));
        expect(rows(), hasLength(1));
      } finally {
        client.close(force: true);
      }
    });
    test('transfer listener empty refusal is accounted and blocked on write failure', () async {
      final client = HttpClient(context: lanTlsContext())
        ..findProxy = ((_) => 'DIRECT')
        ..badCertificateCallback = (_, _, _) => true;
      try {
        final uri = Uri.parse('https://127.0.0.1:${service.httpPort}/push');
        final request = await client.postUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, HttpStatus.unauthorized);
        expect(rows().single['state'], 'succeeded');
        expect(rows().single['bytes_sent'], 0);
        expect(
          rows().single['payload_digest'],
          sha256.convert(const <int>[]).toString(),
        );
        blockLedger();
        final blocked = await client.postUrl(uri);
        await expectLater(blocked.close(), throwsA(anything));
        expect(rows(), hasLength(1));
      } finally {
        client.close(force: true);
      }
    });
    test('transfer blocked ledger sends zero requests', () async {
      blockLedger();
      Object? failure;
      try {
        await service.probe('127.0.0.1', port: tls.port);
      } catch (error) {
        failure = error;
      }
      // ignore: avoid_print
      print('REG2A_BLOCKED transfer requests=$requests');
      expect(requests, 0);
      expect(failure, isNotNull);
    });
    test('transfer push blocked ledger sends zero requests', () async {
      final to = await peer();
      requests = 0;
      blockLedger();
      await expectLater(send(to), throwsA(anything));
      expect(requests, 0);
    });
    test('transfer succeeds with exact body bytes in host ledger', () async {
      await send(await peer());
      expect(observedPending, everyElement(1));
      final entry = rows().last;
      expect(entry['state'], 'succeeded');
      expect(entry['bytes_sent'], received.length);
      expect(entry['payload_digest'], sha256.convert(received).toString());
      expect(entry['destination'], 'https://127.0.0.1:${tls.port}/push');
      expect(
        business.raw.select(
          "SELECT name FROM sqlite_master WHERE name='outbound_tool_requests'",
        ),
        isEmpty,
      );
    });
    test('transfer failed push leaves failed row', () async {
      final to = await peer();
      fail = true;
      await expectLater(send(to), throwsA(anything));
      expect(rows().last['state'], 'failed');
      expect(rows().last['bytes_sent'], received.length);
      expect(rows().last['error'], isNot(contains(marker)));
    });
  });

  test(
    'transfer discovery blocks UDP and records exact datagram bytes',
    () async {
      final root = Directory.systemTemp.createTempSync('reg2a-udp-');
      final receiver = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final node = await LanNode.start(
        id: 'local',
        name: '中文🌍',
        inbox: root,
        onPush: (_) {},
        discoveryPort: 0,
        httpPort: 0,
        identity: DeviceIdentity.generate(),
        outboundLedger: OutboundToolLedger(db),
      );
      try {
        blockLedger();
        await expectLater(
          node.helloTo(InternetAddress.loopbackIPv4, receiver.port),
          throwsA(anything),
        );
        expect(receiver.receive(), isNull);
        db.raw.execute('DROP TRIGGER refuse_outbound');
        await node.helloTo(InternetAddress.loopbackIPv4, receiver.port);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final packet = receiver.receive()!;
        expect(rows().last['state'], 'succeeded');
        expect(rows().last['bytes_sent'], packet.data.length);
        expect(
          rows().last['payload_digest'],
          sha256.convert(packet.data).toString(),
        );
      } finally {
        await node.stop();
        receiver.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
