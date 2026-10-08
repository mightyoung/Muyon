import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/mcp_adapter.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/grants/host_tool_authorization.dart';
import 'package:muyon/platform/grants/tool_grant_context.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String reference) async =>
      reference == 'mcp-key' ? 'secret-token' : null;
}

class _ReviewRecorder implements OutboundContentReviewer {
  _ReviewRecorder(this.action);
  final ReviewAction action;
  List<int>? bytes;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) async {
    bytes = List.of(request.content);
    return action == ReviewAction.block
        ? const ReviewDecision.block('private')
        : const ReviewDecision.allow();
  }
}

class _GatedSecrets implements SecretStore {
  final entered = Completer<void>(), release = Completer<void>();
  var hold = false;
  @override
  Future<String?> read(String reference) async {
    if (hold) {
      entered.complete();
      await release.future;
    }
    return 'secret-token';
  }
}

/// Minimal Streamable-HTTP MCP server: JSON for most replies, SSE for calls.
class _FakeMcp {
  late HttpServer server;
  final calls = <Map<String, Object?>>[];
  final callBodies = <List<int>>[];
  final sessions = <String?>[];
  final auth = <String?>[];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      sessions.add(request.headers.value('mcp-session-id'));
      auth.add(request.headers.value('authorization'));
      final id = body['id'];
      final method = body['method'];
      final response = request.response;
      if (id == null) {
        response.statusCode = 202; // notification
        await response.close();
        return;
      }
      Object? result;
      if (method == 'initialize') {
        response.headers.set('mcp-session-id', 'sess-1');
        result = {
          'protocolVersion': '2025-06-18',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'fake', 'version': '1'},
        };
      } else if (method == 'tools/list') {
        result = {
          'tools': [
            {
              'name': 'search',
              'description': 'Search remote catalog',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'q': {'type': 'string', 'maxLength': 50},
                },
                'required': ['q'],
              },
            },
            {
              'name': 'fancy',
              'inputSchema': {
                'type': 'object',
                'oneOf': [
                  {
                    'required': ['a'],
                  },
                ],
              },
            },
          ],
        };
      } else if (method == 'tools/call') {
        final params = body['params'] as Map;
        calls.add(Map<String, Object?>.from(params));
        callBodies.add(bytes);
        final q = (params['arguments'] as Map)['q'];
        final payload = jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {'type': 'text', 'text': 'found $q'},
            ],
            'isError': q == 'bad',
          },
        });
        response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        response.write('event: message\ndata: $payload\n\n');
        await response.close();
        return;
      }
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
      );
      await response.close();
    });
  }

  Uri get endpoint => Uri.parse('http://127.0.0.1:${server.port}/mcp');
}

void main() {
  late _FakeMcp mcp;
  late ManagedConnection db;
  late ToolRegistry registry;

  setUp(() async {
    mcp = _FakeMcp();
    await mcp.start();
    db = ManagedConnection(sqlite3.openInMemory());
    installToolRegistrySchema(db.raw);
    registry = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: const []),
    );
  });
  tearDown(() async {
    await mcp.server.close(force: true);
    await db.close();
  });

  Future<McpConnection> connect() => McpAdapter.connect(
    registry,
    McpServerConfig(
      id: 'catalog',
      endpoint: mcp.endpoint,
      credentialRef: 'mcp-key',
    ),
    secrets: _Secrets(),
  );

  ToolCallRequest call(String q, {String? destination, String id = 'c1'}) =>
      ToolCallRequest(
        invocationId: id,
        toolId: 'mcp.catalog.search',
        scope: const AssistantScope.global(),
        parameters: {'q': q},
        destination: destination ?? mcp.endpoint.toString(),
      );

  test(
    'registers supported tools as external, skips unsupported with reason',
    () async {
      final connection = await connect();
      final info = registry.inspect('mcp.catalog.search')!;
      expect(info.accessLevel, ToolAccessLevel.external);
      expect(info.providerId, 'mcp:catalog');
      expect(registry.inspect('mcp.catalog.fancy'), isNull);
      expect(connection.skipped.keys, ['fancy']);
      expect(mcp.sessions.skip(1), everyElement('sess-1'));
      expect(mcp.auth, everyElement('Bearer secret-token'));
    },
  );

  test('calls need host approval and reach the server once', () async {
    await connect();
    await expectLater(
      registry.invoke(call('x')),
      throwsA(
        isA<ToolPlatformException>().having(
          (e) => e.code,
          'code',
          'approval_required',
        ),
      ),
    );
    expect(mcp.calls, isEmpty);

    final approved = call('chips').withApproval(
      await registry.approve(await registry.prepare(call('chips'))),
    );
    final result = await registry.invoke(approved);
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.summary, 'found chips');
    expect(mcp.calls.single['name'], 'search');
    expect(mcp.calls.single['arguments'], {'q': 'chips'});
  });

  test('destination must be the configured server', () async {
    await connect();
    final wrong = call('x', destination: 'https://elsewhere.example');
    await expectLater(
      registry.prepare(wrong),
      throwsA(isA<ToolPlatformException>()),
    );
    expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
    expect(mcp.calls, isEmpty);
  });

  test(
    'same origin is insufficient: full path and query bind before approval',
    () async {
      await connect();
      for (final destination in [
        mcp.endpoint.origin,
        mcp.endpoint.replace(path: '/other').toString(),
        mcp.endpoint.replace(query: 'other=1').toString(),
      ]) {
        await expectLater(
          registry.prepare(call('x', destination: destination)),
          throwsA(isA<ToolPlatformException>()),
        );
        expect(db.raw.select('SELECT * FROM tool_approvals'), isEmpty);
        expect(mcp.calls, isEmpty);
      }
    },
  );

  test('tool-reported errors are failures, not successes', () async {
    await connect();
    final approved = call(
      'bad',
    ).withApproval(await registry.approve(await registry.prepare(call('bad'))));
    final result = await registry.invoke(approved);
    expect(result.status, ToolCallStatus.failed);
    expect(result.summary, contains('found bad'));
  });

  test(
    'parameters are validated by the host before anything is sent',
    () async {
      await connect();
      final tooLong = call('x' * 51);
      await expectLater(registry.prepare(tooLong), throwsA(anything));
      expect(mcp.calls, isEmpty);
    },
  );

  for (final action in [ReviewAction.allow, ReviewAction.block]) {
    test(
      'trusted MCP actual bytes and $action review use real host linkage',
      () async {
        final root = Directory.systemTemp.createTempSync('auth-mcp-host-');
        final storage = StorageManager(root.path);
        final owner = await storage.open('muyon', WorkspaceRepository.schema);
        final hostRegistry = ToolRegistry(
          database: owner,
          resolveScope: (scope) async =>
              ResolvedAssistantScope(requested: scope, objects: const []),
        );
        addTearDown(() async {
          await hostRegistry.close();
          await storage.close();
          root.deleteSync(recursive: true);
        });
        final endpoint = mcp.endpoint.replace(query: 'token=url-private');
        await McpAdapter.connect(
          hostRegistry,
          McpServerConfig(
            id: 'trusted',
            endpoint: endpoint,
            endpointIdentity: 'host-configured',
            credentialRef: 'mcp-key',
          ),
          secrets: _Secrets(),
          trustedEffects: true,
        );
        final request = ToolCallRequest(
          invocationId: 'trusted-call',
          toolId: 'mcp.trusted.search',
          scope: AssistantScope.global(),
          parameters: const {'q': '中文🌍'},
          destination: endpoint.toString(),
        );
        final prepared = await hostRegistry.prepare(request);
        expect(prepared.effectIntent, isNotNull);
        final reviewer = _ReviewRecorder(action);
        final auth = HostToolAuthorization(
          registry: hostRegistry,
          reviewer: reviewer,
          taskFacts: (_) => HostTaskFacts(
            taskId: 'task',
            conversationId: 'conversation',
            taintState: HostTaintState.unknown,
            sourceDigests: const [],
          ),
        );
        final review = await auth.review(prepared);
        final approval = await auth.confirm(review);
        if (action == ReviewAction.block) {
          expect(approval, isNull);
          expect(mcp.calls, isEmpty);
          expect(
            owner.raw.select(
              "SELECT * FROM outbound_tool_requests WHERE tool_id='mcp.trusted.search'",
            ),
            isEmpty,
          );
          return;
        }
        expect(approval, isNotNull);
        final result = await hostRegistry.invoke(
          request.withApproval(approval!),
        );
        expect(result.status, ToolCallStatus.succeeded);
        expect(mcp.callBodies.single, reviewer.bytes);
        expect(mcp.callBodies.single, prepared.effectIntent!.content);
        final row = owner.raw
            .select(
              "SELECT * FROM outbound_tool_requests WHERE tool_id='mcp.trusted.search'",
            )
            .single;
        expect(row['review_decision_id'], review.reviewDecisionId);
        expect(row['authorization_source'], 'manual');
        expect(row['grant_id'], isNull);
        expect(row['bytes_sent'], reviewer.bytes!.length);
        expect(row['payload_digest'], prepared.effectIntent!.payloadDigest);
        expect(
          jsonEncode(Map<String, Object?>.from(row)),
          isNot(contains('url-private')),
        );
        await hostRegistry.invoke(request.withApproval(approval));
        expect(mcp.calls, hasLength(1));
      },
    );
  }
  test('trusted MCP revocation during real credential wait sends zero call bytes', () async {
    final root = Directory.systemTemp.createTempSync('auth-mcp-revoke-');
    final storage = StorageManager(root.path);
    final owner = await storage.open('muyon', WorkspaceRepository.schema);
    final grants = GrantStore(owner);
    final hostRegistry = ToolRegistry(
      database: owner,
      grants: grants,
      grantContext: (_) => ToolGrantContext(
        taskId: 'task',
        conversationId: 'conversation',
        taskTainted: false,
        scopeRevision: 'fixture-host-version',
        allowedModuleIds: const {'prototype'},
      ),
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: const []),
    );
    addTearDown(() async {
      await hostRegistry.close();
      await storage.close();
      root.deleteSync(recursive: true);
    });
    final secrets = _GatedSecrets();
    await McpAdapter.connect(
      hostRegistry,
      McpServerConfig(
        id: 'trusted',
        endpoint: mcp.endpoint,
        endpointIdentity: 'host-configured',
        credentialRef: 'mcp-key',
      ),
      secrets: secrets,
      trustedEffects: true,
    );
    final request = ToolCallRequest(
      invocationId: 'trusted-call',
      toolId: 'mcp.trusted.search',
      scope: AssistantScope.global(),
      parameters: const {'q': 'x'},
      destination: mcp.endpoint.toString(),
    );
    final prepared = await hostRegistry.prepare(request);
    final bound = hostRegistry.authorizationRequest(prepared);
    final source = await withConfirmedHostUiGrant(
      (token) => grants.create(
        token: token,
        draft: GrantDraft(
          category: 'outbound',
          toolId: bound.toolId,
          scopeDigest: bound.scopeDigest,
          destination: bound.destination,
          duration: GrantDuration.once,
          conversationId: 'conversation',
        ),
        now: DateTime.now(),
      ),
    );
    final auth = HostToolAuthorization(
      registry: hostRegistry,
      reviewer: const NoopReviewer(),
      // A trusted fixture proof, not a claim about production B3 input loading.
      taskFacts: (_) => HostTaskFacts(
        taskId: 'task',
        conversationId: 'conversation',
        taintState: HostTaintState.clean,
        sourceDigests: const [],
      ),
    );
    final review = await auth.review(prepared);
    final approval = await auth.sign(review);
    expect(approval, isNotNull);
    secrets.hold = true;
    final running = hostRegistry.invoke(request.withApproval(approval!));
    await secrets.entered.future;
    await grants.revoke(source.id, now: DateTime.now());
    secrets.release.complete();
    expect((await running).status, ToolCallStatus.interrupted);
    expect(mcp.calls, isEmpty);
    expect(
      owner.raw.select(
        "SELECT * FROM outbound_tool_requests WHERE tool_id='mcp.trusted.search'",
      ),
      isEmpty,
    );
    expect(grants.list().single.uses, 1);
  });

  test('remote endpoints must use https', () {
    expect(
      () => McpServerConfig(
        id: 'remote',
        endpoint: Uri.parse('http://example.com/mcp'),
      ),
      throwsArgumentError,
    );
  });
}
