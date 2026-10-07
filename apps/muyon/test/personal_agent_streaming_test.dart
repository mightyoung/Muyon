import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/model_request_gate.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// K-2a: the assistant over a stream (compatibility mode) and over native
/// tools, against a loopback endpoint. Nothing here reaches a real model.
const _key = 'sk-agent-secret-0123456789';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String reference) async =>
      reference == 'key' ? _key : null;
}

const _answerJson = '{"type":"answer","answer":"成本合计 2080 元"}';
const _readToolJson = '{"type":"tool","toolId":"read","parameters":{}}';
const _prose = '成本合计 2080 元，销售合计 2380 元。';

String _chunk(Map<String, Object?> delta, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': delta, 'finish_reason': finish},
      ],
    })}\n\n';

/// A streamed text reply, cut into [pieces] pieces.
List<String> _text(String text, {int pieces = 3, String finish = 'stop'}) {
  final size = (text.runes.length / pieces).ceil();
  final runes = text.runes.toList();
  return [
    for (var i = 0; i < runes.length; i += size)
      _chunk({
        'content': String.fromCharCodes(
          runes.sublist(i, i + size > runes.length ? runes.length : i + size),
        ),
      }),
    _chunk({}, finish: finish),
    'data: [DONE]\n\n',
  ];
}

List<String> _toolCall(
  String name,
  String arguments, {
  String id = 'call_1',
  String? text,
}) => [
  if (text != null) _chunk({'content': text}),
  _chunk({
    'tool_calls': [
      {
        'index': 0,
        'id': id,
        'function': {'name': name, 'arguments': ''},
      },
    ],
  }),
  _chunk({
    'tool_calls': [
      {
        'index': 0,
        'function': {'arguments': arguments},
      },
    ],
  }),
  _chunk({}, finish: 'tool_calls'),
  'data: [DONE]\n\n',
];

/// One scripted answer of the loopback endpoint.
class _Reply {
  const _Reply.sse(this.parts) : status = 200;
  const _Reply.status(this.status) : parts = const [];
  final List<String> parts;
  final int status;
}

class _Fixture {
  _Fixture(
    this.root,
    this.storage,
    this.repo,
    this.tools,
    this.ledger,
    this.server,
  );
  final Directory root;
  final StorageManager storage;
  final FoundationRepository repo;
  final ToolRegistry tools;
  final OutboundLedger ledger;
  final HttpServer server;
  final replies = <_Reply>[];
  final bodies = <Map<String, dynamic>>[];
  var readCalls = 0, writeCalls = 0;

  static Future<_Fixture> open() async {
    final root = Directory.systemTemp.createTempSync('muyon-stream-agent-');
    final storage = StorageManager(root.path);
    final db = await storage.open('muyon', WorkspaceRepository.schema);
    final repo = FoundationRepository(db);
    final ref = const ObjectRef(
      moduleId: 'test',
      objectType: 'budget',
      objectId: 'b1',
    );
    final tools = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: [ref]),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final f = _Fixture(root, storage, repo, tools, OutboundLedger(db), server);
    for (final effect in [ToolEffect.read, ToolEffect.write]) {
      tools.register(
        providerId: 'test',
        descriptor: ToolDescriptor(
          toolId: effect.name,
          moduleId: 'test',
          effect: effect,
          description: '测试工具 ${effect.name}',
          parameterSchema: {
            'type': 'object',
            'properties': {
              'note': {'type': 'string'},
            },
            'additionalProperties': false,
          },
        ),
        handler: (context) async {
          effect == ToolEffect.read ? f.readCalls++ : f.writeCalls++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'actual result',
            data: {'value': 42},
            objectRefs: [ref],
          );
        },
      );
    }
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, dynamic>;
      f.bodies.add(body);
      if (f.replies.length < f.bodies.length) {
        request.response.statusCode = 500;
        await request.response.close();
        return;
      }
      final reply = f.replies[f.bodies.length - 1];
      request.response.statusCode = reply.status;
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      for (final part in reply.parts) {
        request.response.write(part);
        await request.response.flush();
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await storage.close();
      root.deleteSync(recursive: true);
    });
    return f;
  }

  ModelProfile profile({
    ModelCapabilities capabilities = const ModelCapabilities(),
    String? credentialRef,
  }) => ModelProfile(
    id: 'local',
    endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
    location: ModelLocation.local,
    modelId: 'm',
    endpointIdentity: 'fixture',
    credentialRef: credentialRef,
    capabilities: capabilities,
  );

  PersonalAgent agent({OutboundLedger? with_}) {
    final agent = PersonalAgent(
      repository: repo,
      gateway: OpenAiModelGateway(_Secrets(), ledger: with_ ?? ledger),
      tools: tools,
    );
    addTearDown(agent.close);
    return agent;
  }

  Future<PersonalTask> start(PersonalAgent agent, ModelProfile profile) async {
    final conversation = await repo.createConversation();
    return agent.start(
      conversationId: conversation.id,
      prompt: '项目的成本预算是多少？',
      profile: profile,
    );
  }

  /// Confirms every model round (and, with [confirmTools], every tool call).
  Future<PersonalTask> run(
    PersonalAgent agent,
    PersonalTask first, {
    int max = 8,
    bool confirmTools = false,
  }) async {
    var task = first;
    for (var i = 0; i < max; i++) {
      if (task.state != PersonalTaskState.waitingConfirmation) break;
      if (task.stage != 'model' && !confirmTools) break;
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = repo.task(task.id)!;
    }
    return task;
  }
}

const _streaming = ModelCapabilities(
  streaming: true,
  source: CapabilitySource.preset,
);
const _native = ModelCapabilities(
  streaming: true,
  nativeTools: true,
  source: CapabilitySource.userDeclared,
);

void main() {
  group('compatibility mode over a stream', () {
    test('a JSON answer is read after Done; the request streams and asks for '
        'JSON output, with the digest in the ledger', () async {
      final f = await _Fixture.open();
      f.replies.add(_Reply.sse(_text(_answerJson, pieces: 5)));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _streaming)),
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(task.summary, '成本合计 2080 元');
      final body = f.bodies.single;
      expect(body['stream'], true);
      expect(body['response_format'], {'type': 'json_object'});
      expect(body.containsKey('tools'), isFalse);
      final row = f.ledger.recent().single;
      expect(row['streamed'], 1);
      expect(row['request_digest'], task.payload['requestDigest']);
      expect(row['status'], 'succeeded');
    });

    test('the strict parse and the one correction are unchanged: prose is '
        'discarded, not saved, not sent back', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(_Reply.sse(_text(_prose)))
        ..add(_Reply.sse(_text(_answerJson)));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _streaming)),
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(task.payload['protocolCorrections'], 1);
      expect(jsonEncode(f.bodies[1]['messages']), isNot(contains('2380')));
      expect(jsonEncode(task.payload), isNot(contains('2380')));
      expect(
        (f.bodies[1]['messages'] as List).last['content'],
        contains('did not follow the protocol'),
      );
      expect(f.ledger.recent(), hasLength(2));
    });

    test('a streamed tool proposal still goes through prepare and the '
        'frozen candidates', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(_Reply.sse(_text(_readToolJson)))
        ..add(_Reply.sse(_text(_answerJson)));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _streaming)),
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(f.readCalls, 1);
    });

    test('an endpoint that rejects stream:true fails with a fixed reason and '
        'is not retried as a non-streaming request', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(const _Reply.status(400))
        ..add(_Reply.sse(_text(_answerJson)));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _streaming)),
      );
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('stream_rejected'));
      // We cannot tell which parameter was rejected: exactly one request.
      expect(f.bodies, hasLength(1));
      expect(f.bodies.single['stream'], true);
      expect(f.ledger.recent(), hasLength(1));
    });

    test('a truncated stream fails the task and saves nothing of the '
        'partial answer', () async {
      final f = await _Fixture.open();
      f.replies.add(
        _Reply.sse([
          _chunk({'content': '{"type":"answer","ans'}),
        ]),
      );
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _streaming)),
      );
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('stream_truncated'));
      expect(task.error, isNot(contains('ans')));
      expect(f.repo.messages(task.conversationId).map((m) => m.role), ['user']);
      expect(f.ledger.recent().single['status'], 'failed');
    });

    test('a reply cut off by the token limit is not acted on', () async {
      final f = await _Fixture.open();
      f.replies.add(_Reply.sse(_text(_readToolJson, finish: 'length')));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _streaming)),
      );
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('model_output_truncated'));
      expect(f.readCalls, 0);
    });
  });

  group('native tools', () {
    test('a streamed call runs the read tool, and the next request carries '
        'the call and its result paired by id', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(_Reply.sse(_toolCall('read', '{"note":"x"}', text: '先查一下')))
        ..add(_Reply.sse(_text('成本合计 2080 元 [r1]')));
      final agent = f.agent();
      final started = await f.start(agent, f.profile(capabilities: _native));
      expect((started.payload['preview'] as Map)['mode'], 'native');
      final task = await f.run(agent, started);
      expect(task.state, PersonalTaskState.succeeded);
      expect(task.summary, '成本合计 2080 元 [r1]');
      expect(task.payload['references'], hasLength(1));
      expect(f.readCalls, 1);
      final first = f.bodies[0];
      expect(first['stream'], true);
      expect(first['stream_options'], {'include_usage': true});
      expect(first.containsKey('response_format'), isFalse);
      final spec = (first['tools'] as List).map((t) => t['function']).toList();
      expect(spec.map((t) => t['name']), containsAll(['read', 'write']));
      expect(
        spec.firstWhere((t) => t['name'] == 'read')['parameters']['properties'],
        {
          'note': {'type': 'string'},
        },
        reason: 'the real parameter schema, not an empty one',
      );
      final second = f.bodies[1]['messages'] as List;
      final call = second[second.length - 2] as Map;
      final result = second.last as Map;
      expect(call['role'], 'assistant');
      expect(call['content'], '先查一下');
      expect(call['tool_calls'][0]['id'], 'call_1');
      expect(call['tool_calls'][0]['function']['name'], 'read');
      expect(result['role'], 'tool');
      expect(result['tool_call_id'], 'call_1');
      expect(result['content'], contains('trustedToolResult'));
      expect(f.ledger.recent(), hasLength(2));
      expect(
        f.ledger.recent().map((r) => r['status']),
        everyElement('succeeded'),
      );
    });

    test('a proposed write still waits for the person and runs only after '
        'the digest-bound confirmation', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(_Reply.sse(_toolCall('write', '{}')))
        ..add(_Reply.sse(_text('已写入')));
      final agent = f.agent();
      var task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _native)),
      );
      expect(task.state, PersonalTaskState.waitingConfirmation);
      expect(task.stage, 'tool');
      expect(f.writeCalls, 0, reason: 'a model call is a proposal');
      await expectLater(
        agent.confirm(task.id, requestDigest: 'not-the-digest'),
        throwsStateError,
      );
      expect(f.writeCalls, 0);
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      expect(f.writeCalls, 1);
      task = await f.run(agent, f.repo.task(task.id)!);
      expect(task.state, PersonalTaskState.succeeded);
      final second = f.bodies[1]['messages'] as List;
      expect((second.last as Map)['tool_call_id'], 'call_1');
    });

    test('a call outside the frozen candidates is a violation: discarded '
        'whole, only the fixed correction is added, nothing runs', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(
          _Reply.sse(_toolCall('delete_everything', '{}', text: 'SECRET-TEXT')),
        )
        ..add(_Reply.sse(_text('好的')));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _native)),
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(f.readCalls + f.writeCalls, 0);
      expect(task.payload['protocolCorrections'], 1);
      final second = jsonEncode(f.bodies[1]['messages']);
      expect(second, isNot(contains('delete_everything')));
      expect(second, isNot(contains('SECRET-TEXT')));
      expect(second, isNot(contains('tool_calls')));
      expect(
        (f.bodies[1]['messages'] as List).last['content'],
        contains('did not follow the protocol'),
      );
      expect(jsonEncode(task.payload), isNot(contains('delete_everything')));
    });

    test('a registered tool that was not a candidate is a violation even '
        'when the model names it correctly encoded', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(_Reply.sse(_toolCall('write', '{}')))
        ..add(_Reply.sse(_text('ok')));
      final agent = f.agent();
      final started = await f.start(agent, f.profile(capabilities: _native));
      // Only `read` stays a candidate for this task.
      final narrowed = started.copy({
        'candidateIds': ['read'],
        'nativeTools': [
          for (final t in started.payload['nativeTools'] as List)
            if ((t as Map)['name'] == 'read') t,
        ],
      });
      await f.repo.updateTask(narrowed);
      final task = await f.run(agent, f.repo.task(started.id)!);
      expect(f.writeCalls, 0);
      expect(task.payload['protocolCorrections'], 1);
    });

    test('bad arguments, a repeated call id and an empty reply are violations; '
        'a second violation fails with a fixed reason', () async {
      for (final bad in [
        _toolCall('read', '{"note":'),
        _toolCall('read', '[1]'),
        [
          _chunk({
            'tool_calls': [
              {
                'index': 0,
                'id': 'c1',
                'function': {'name': 'read', 'arguments': '{}'},
              },
              {
                'index': 1,
                'id': 'c1',
                'function': {'name': 'write', 'arguments': '{}'},
              },
            ],
          }),
          _chunk({}, finish: 'tool_calls'),
          'data: [DONE]\n\n',
        ],
        [_chunk({}, finish: 'stop'), 'data: [DONE]\n\n'],
      ]) {
        final f = await _Fixture.open();
        f.replies
          ..add(_Reply.sse(bad))
          ..add(_Reply.sse(_toolCall('nope', '{}', text: 'MODEL-WORDS')));
        final agent = f.agent();
        final task = await f.run(
          agent,
          await f.start(agent, f.profile(capabilities: _native)),
        );
        expect(task.state, PersonalTaskState.failed);
        expect(task.error, contains('Invalid assistant protocol'));
        expect(task.error, isNot(contains('MODEL-WORDS')));
        expect(task.error, isNot(contains('nope')));
        expect(f.readCalls + f.writeCalls, 0);
        expect(f.bodies, hasLength(2));
      }
    });

    test('the legacy function_call is a violation, never a call', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(
          _Reply.sse([
            _chunk({
              'function_call': {'name': 'read', 'arguments': '{}'},
            }),
            _chunk({}, finish: 'function_call'),
            'data: [DONE]\n\n',
          ]),
        )
        ..add(_Reply.sse(_text('ok')));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _native)),
      );
      expect(task.payload['protocolCorrections'], 1);
      expect(f.readCalls, 0);
    });

    test('an endpoint that rejects tools fails with a fixed reason and sends '
        'nothing else: no JSON protocol, no other model', () async {
      final f = await _Fixture.open();
      f.replies
        ..add(const _Reply.status(400))
        ..add(_Reply.sse(_text(_answerJson)));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _native)),
      );
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('native_tools_rejected'));
      expect(f.bodies, hasLength(1));
      expect(f.bodies.single.containsKey('response_format'), isFalse);
      expect(f.ledger.recent(), hasLength(1));
      expect(f.ledger.recent().single['status'], 'failed');
    });

    test('a non-streaming native reply with no choices is the same fixed '
        'failure; a valid one runs the tool', () async {
      const nonStreaming = ModelCapabilities(nativeTools: true);
      final f = await _Fixture.open();
      f.replies.add(const _Reply.sse(['{"choices":[]}']));
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: nonStreaming)),
      );
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('native_tools_rejected'));
      expect(f.bodies.single['stream'], false);

      final g = await _Fixture.open();
      g.replies
        ..add(
          _Reply.sse([
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'tool_calls',
                  'message': {
                    'content': null,
                    'tool_calls': [
                      {
                        'id': 'w1',
                        'type': 'function',
                        'function': {'name': 'read', 'arguments': '{}'},
                      },
                    ],
                  },
                },
              ],
            }),
          ]),
        )
        ..add(
          _Reply.sse([
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': 'done'},
                },
              ],
            }),
          ]),
        );
      final other = g.agent();
      final ok = await g.run(
        other,
        await g.start(other, g.profile(capabilities: nonStreaming)),
      );
      expect(ok.state, PersonalTaskState.succeeded);
      expect(g.readCalls, 1);
      expect(g.ledger.recent().map((r) => r['streamed']), everyElement(isNull));
    });

    test('a call cut off by the token limit does not run', () async {
      final f = await _Fixture.open();
      f.replies.add(
        _Reply.sse([
          ..._toolCall('read', '{}').take(2),
          _chunk({}, finish: 'length'),
        ]),
      );
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _native)),
      );
      expect(task.error, contains('model_output_truncated'));
      expect(f.readCalls, 0);
    });

    test(
      'a citation that names no tool result is removed and said so',
      () async {
        final f = await _Fixture.open();
        f.replies.add(_Reply.sse(_text('答案 [r7]')));
        final agent = f.agent();
        final task = await f.run(
          agent,
          await f.start(agent, f.profile(capabilities: _native)),
        );
        expect(task.state, PersonalTaskState.succeeded);
        expect(task.summary, isNot(contains('[r7]')));
        expect(task.summary, contains('引用未通过校验'));
        expect(task.payload['references'], isEmpty);
      },
    );

    test('a ledger that cannot record sends nothing', () async {
      final f = await _Fixture.open();
      f.replies.add(_Reply.sse(_text('x')));
      final agent = f.agent(with_: _FailingLedger(f.repo.database));
      final task = await f.run(
        agent,
        await f.start(agent, f.profile(capabilities: _native)),
      );
      expect(task.state, PersonalTaskState.failed);
      expect(f.bodies, isEmpty);
    });

    test('an endpoint that echoes the key puts it nowhere: not in the task, '
        'the notification or the ledger', () async {
      final f = await _Fixture.open();
      f.replies.add(
        _Reply.sse([
          _chunk({'content': 'par'}),
          'data: ${jsonEncode({
            'error': {'message': 'bad key $_key'},
          })}\n\n',
        ]),
      );
      final agent = f.agent();
      final task = await f.run(
        agent,
        await f.start(
          agent,
          f.profile(capabilities: _native, credentialRef: 'key'),
        ),
      );
      expect(task.state, PersonalTaskState.failed);
      expect(jsonEncode(task.payload), isNot(contains(_key)));
      expect(jsonEncode(f.ledger.recent()), isNot(contains(_key)));
      expect(
        f.repo.notifications().map((n) => '${n.title}${n.body}').join(),
        isNot(contains(_key)),
      );
    });
  });

  group('capabilities', () {
    test('a code-constructed profile is compatibility, non-streaming', () {
      final p = ModelProfile(
        id: 'p',
        endpoint: Uri.parse('http://127.0.0.1:1/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'x',
      );
      expect(p.capabilities.nativeTools, isFalse);
      expect(p.capabilities.streaming, isFalse);
      expect(p.capabilities.source, CapabilitySource.unknown);
    });

    test('a non-streaming compatibility task goes through gateway.chat, not '
        'the stream', () async {
      final f = await _Fixture.open();
      final gateway = _ChatOnly();
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: gateway,
        tools: f.tools,
      );
      addTearDown(agent.close);
      final task = await f.run(agent, await f.start(agent, f.profile()));
      expect(task.state, PersonalTaskState.succeeded);
      expect(gateway.chats, 1);
      expect(f.bodies, isEmpty);
    });

    test('the task keeps the capabilities it started with', () async {
      final f = await _Fixture.open();
      f.replies.add(_Reply.sse(_text('hello')));
      final agent = f.agent();
      final started = await f.start(agent, f.profile(capabilities: _native));
      // The person edits the profile while the confirmation card is open.
      final edited = f.profile();
      expect(edited.capabilities.nativeTools, isFalse);
      final frozen = (started.payload['profile'] as Map)['capabilities'] as Map;
      expect(frozen['nativeTools'], true);
      final task = await f.run(agent, started);
      expect(f.bodies.single.containsKey('tools'), isTrue);
      expect(task.state, PersonalTaskState.succeeded);
    });

    test('a compatibility task previews and digests exactly what it did '
        'before capabilities existed', () async {
      final f = await _Fixture.open();
      final agent = f.agent();
      for (final caps in [const ModelCapabilities(), _streaming]) {
        final task = await f.start(agent, f.profile(capabilities: caps));
        final preview = task.payload['preview'] as Map;
        final legacyProfile = Map<String, Object?>.from(
          f.profile(capabilities: caps).toJson(),
        )..remove('capabilities');
        expect(preview.keys.toList(), [
          'endpoint',
          'profile',
          'scope',
          'messages',
          'dataCategories',
        ]);
        expect(preview['profile'], legacyProfile);
        expect(
          task.payload['requestDigest'],
          PersonalAgent.digest({
            'endpoint': preview['endpoint'],
            'profile': legacyProfile,
            'scope': task.scope.toJson(),
            'messages': task.payload['messages'],
            'dataCategories': ['conversation', 'memories', 'tool_results'],
          }),
        );
        expect(
          jsonEncode(task.payload['messages']),
          isNot(contains('tool_calls')),
        );
      }
    });

    test('a gate that does not ask the person stops the request: nothing is '
        'sent', () async {
      final f = await _Fixture.open();
      f.replies.add(_Reply.sse(_text('x')));
      final agent = PersonalAgent(
        repository: f.repo,
        gateway: OpenAiModelGateway(_Secrets(), ledger: f.ledger),
        tools: f.tools,
        gate: _DenyGate(),
      );
      addTearDown(agent.close);
      final task = await f.start(agent, f.profile(capabilities: _native));
      expect(task.state, PersonalTaskState.failed);
      expect(f.bodies, isEmpty);
      expect(f.ledger.recent(), isEmpty);
    });

    test('a native task previews its mode and tools, so the digest covers '
        'what is sent', () async {
      final f = await _Fixture.open();
      final agent = f.agent();
      final task = await f.start(agent, f.profile(capabilities: _native));
      final preview = task.payload['preview'] as Map;
      expect(preview['mode'], 'native');
      expect((preview['tools'] as List).map((t) => t['name']), [
        'read',
        'write',
      ]);
      expect(task.payload['requestDigest'], PersonalAgent.digest(preview));
    });
  });
}

class _DenyGate implements ModelRequestGate {
  @override
  Future<GateDecision> decide(ModelRequestFacts facts) async =>
      const GateDenied('closed');
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

class _ChatOnly extends OpenAiModelGateway {
  _ChatOnly() : super(UnavailableSecretStore());
  var chats = 0;
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'chat',
  }) async {
    if (beforeSend != null) await beforeSend();
    chats++;
    return _answerJson;
  }

  @override
  Stream<ModelEvent> chatStream({
    required ModelProvider provider,
    required ModelRequest request,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    Duration? maxDuration,
  }) => throw StateError('the stream must not be used');
}
