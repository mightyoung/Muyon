import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// P0-3d: a reply that breaks the assistant protocol (prose, a provider's
/// native tool-call markup, a wrong JSON shape) is never acted on. One
/// corrective round is asked for, confirmed and ledgered like any other;
/// after that the task fails with a fixed reason.
const _prose = '项目「北极星验收项目」的成本预算：成本合计 2080 元，销售合计 2380 元。';
const _dsml =
    '<｜｜DSML｜｜ calls>[{"name":"inquiry__project_budget","arguments":'
    '{"project_id":"p1"}}]</｜｜DSML｜｜ calls>';
const _answer = '{"type":"answer","answer":"成本合计 2080 元"}';
const _readTool = '{"type":"tool","toolId":"read","parameters":{}}';

/// Replies from [replies] in order and records each request's messages.
class _Scripted extends OpenAiModelGateway {
  _Scripted(this.replies) : super(UnavailableSecretStore());
  final List<String> replies;
  final requests = <List<Map<String, String>>>[];
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'chat',
  }) async {
    if (beforeSend != null) await beforeSend();
    requests.add(messages);
    if (requests.length > replies.length) {
      throw StateError('more model requests than scripted');
    }
    return replies[requests.length - 1];
  }
}

final _profile = ModelProfile(
  id: 'local',
  endpoint: Uri.parse('http://127.0.0.1:9/v1'),
  location: ModelLocation.local,
  modelId: 'm',
  endpointIdentity: 'fixture',
);

class _Harness {
  _Harness(this.root, this.storage, this.repo, this.tools, this.db);
  final Directory root;
  final StorageManager storage;
  final FoundationRepository repo;
  final ToolRegistry tools;
  final ManagedConnection db;
  var toolCalls = 0;

  /// Model requests made when the tool ran (set by tests that care).
  int Function()? requestsSoFar;
  final requestsAtToolCall = <int>[];

  static Future<_Harness> open() async {
    final root = Directory.systemTemp.createTempSync('muyon-protocol-');
    final storage = StorageManager(root.path);
    final db = await storage.open('muyon', WorkspaceRepository.schema);
    final repo = FoundationRepository(db);
    final tools = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: const []),
    );
    final harness = _Harness(root, storage, repo, tools, db);
    tools.register(
      providerId: 'test',
      descriptor: ToolDescriptor(
        toolId: 'read',
        moduleId: 'test',
        effect: ToolEffect.read,
        description: '读取测试对象',
        parameterSchema: {
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      handler: (context) async {
        harness.toolCalls++;
        harness.requestsAtToolCall.add(harness.requestsSoFar?.call() ?? -1);
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: 'actual result',
        );
      },
    );
    addTearDown(() async {
      await storage.close();
      root.deleteSync(recursive: true);
    });
    return harness;
  }

  PersonalAgent agent(OpenAiModelGateway gateway) {
    final agent = PersonalAgent(
      repository: repo,
      gateway: gateway,
      tools: tools,
    );
    addTearDown(agent.close);
    return agent;
  }

  /// Starts a task and confirms every model round, never a tool call.
  Future<PersonalTask> runModelRounds(
    PersonalAgent agent, {
    int max = 6,
  }) async {
    final conversation = await repo.createConversation();
    var task = await agent.start(
      conversationId: conversation.id,
      prompt: '项目的成本预算是多少？',
      profile: _profile,
    );
    for (var i = 0; i < max && task.stage == 'model'; i++) {
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = repo.task(task.id)!;
    }
    return task;
  }
}

void main() {
  test(
    'a prose final answer gets one corrective round and then succeeds',
    () async {
      final h = await _Harness.open();
      final gateway = _Scripted([_prose, _answer]);
      final task = await h.runModelRounds(h.agent(gateway));
      expect(task.state, PersonalTaskState.succeeded);
      expect(task.summary, '成本合计 2080 元');
      expect(task.payload['protocolCorrections'], 1);
      expect(gateway.requests, hasLength(2));
      final second = gateway.requests[1];
      expect(second.last['role'], 'user');
      expect(second.last['content'], contains('did not follow the protocol'));
      // The discarded reply is neither sent back nor stored.
      expect(jsonEncode(second), isNot(contains('2380')));
      expect(jsonEncode(task.payload), isNot(contains('2380')));
    },
  );

  test('native tool-call markup is never executed; only the protocol reply '
      'after the correction runs a tool', () async {
    final h = await _Harness.open();
    final gateway = _Scripted([_dsml, _readTool, _answer]);
    h.requestsSoFar = () => gateway.requests.length;
    final task = await h.runModelRounds(h.agent(gateway));
    expect(task.state, PersonalTaskState.succeeded);
    expect(task.payload['protocolCorrections'], 1);
    expect(h.toolCalls, 1);
    expect(h.requestsAtToolCall, [
      2,
    ], reason: 'the tool ran after the corrected (2nd) reply, not the markup');
    expect(jsonEncode(task.payload), isNot(contains('DSML')));
  });

  test('a reply still off-protocol after the correction fails the task with '
      'a fixed reason and no model text', () async {
    final h = await _Harness.open();
    final gateway = _Scripted([_dsml, _prose]);
    final task = await h.runModelRounds(h.agent(gateway));
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('model_reply_not_json'));
    expect(task.error, isNot(contains('DSML')));
    expect(task.error, isNot(contains('2080')));
    expect(h.toolCalls, 0);
  });

  test('corrections are capped at one per task', () async {
    final h = await _Harness.open();
    final gateway = _Scripted([_prose, _prose, _prose, _prose]);
    final task = await h.runModelRounds(h.agent(gateway));
    expect(PersonalAgent.maxProtocolCorrections, 1);
    expect(task.state, PersonalTaskState.failed);
    expect(gateway.requests, hasLength(2), reason: 'one reply, one retry');
  });

  test('a JSON reply of the wrong shape is corrected, not acted on', () async {
    final h = await _Harness.open();
    final gateway = _Scripted([
      '{"type":"tool","parameters":{}}',
      '{"type":"answer"}',
    ]);
    final task = await h.runModelRounds(h.agent(gateway));
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('Invalid assistant protocol'));
    expect(gateway.requests, hasLength(2));
    expect(h.toolCalls, 0);
  });

  group('real gateway', () {
    late HttpServer server;
    final bodies = <Map<String, Object?>>[];
    var rejectFormat = false;
    final replies = <String>[];

    setUp(() async {
      bodies.clear();
      replies.clear();
      rejectFormat = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map<String, Object?>;
        bodies.add(body);
        if (rejectFormat && body.containsKey('response_format')) {
          request.response.statusCode = 400;
          request.response.write('{"error":"response_format unsupported"}');
        } else {
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': replies.removeAt(0),
                  },
                },
              ],
            }),
          );
        }
        await request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    ModelProfile local() => ModelProfile(
      id: 'local',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
      location: ModelLocation.local,
      modelId: 'm',
      endpointIdentity: 'fixture',
    );

    test('the assistant asks for JSON output and the correction round is in '
        'the ledger', () async {
      final h = await _Harness.open();
      replies.addAll([_prose, _answer]);
      final ledger = OutboundLedger(h.db);
      final agent = h.agent(
        OpenAiModelGateway(UnavailableSecretStore(), ledger: ledger),
      );
      final conversation = await h.repo.createConversation();
      var task = await agent.start(
        conversationId: conversation.id,
        prompt: '项目的成本预算是多少？',
        profile: local(),
      );
      for (var i = 0; i < 3 && task.stage == 'model'; i++) {
        await agent.confirm(
          task.id,
          requestDigest: task.payload['requestDigest'] as String,
        );
        task = h.repo.task(task.id)!;
      }
      expect(task.state, PersonalTaskState.succeeded);
      expect(bodies, hasLength(2));
      for (final body in bodies) {
        expect(body['response_format'], {'type': 'json_object'});
      }
      final rows = ledger.recent();
      expect(rows, hasLength(2), reason: 'reply and its correction');
      expect(rows.map((r) => r['caller']), everyElement('assistant'));
      expect(rows.map((r) => r['status']), everyElement('succeeded'));
    });

    test('an endpoint that rejects response_format still works: one retry '
        'without it, remembered, both requests ledgered', () async {
      final h = await _Harness.open();
      rejectFormat = true;
      replies.addAll([_answer, _answer]);
      final ledger = OutboundLedger(h.db);
      final gateway = OpenAiModelGateway(
        UnavailableSecretStore(),
        ledger: ledger,
      );
      final messages = [
        {'role': 'user', 'content': 'json please'},
      ];
      expect(
        await gateway.chat(
          profile: local(),
          messages: messages,
          caller: 'assistant',
        ),
        _answer,
      );
      expect(bodies, hasLength(2));
      expect(bodies[0].containsKey('response_format'), isTrue);
      expect(bodies[1].containsKey('response_format'), isFalse);
      expect(ledger.recent().map((r) => r['status']).toList()..sort(), [
        'failed',
        'succeeded',
      ]);
      // Remembered: the next assistant request goes without it at once.
      await gateway.chat(
        profile: local(),
        messages: messages,
        caller: 'assistant',
      );
      expect(bodies, hasLength(3));
      expect(bodies[2].containsKey('response_format'), isFalse);
    });

    test('other callers keep plain requests', () async {
      replies.add('plain text is fine here');
      await OpenAiModelGateway(UnavailableSecretStore()).chat(
        profile: local(),
        messages: const [
          {'role': 'user', 'content': 'hi'},
        ],
        caller: 'qa',
      );
      expect(bodies.single.containsKey('response_format'), isFalse);
    });
  });
}
