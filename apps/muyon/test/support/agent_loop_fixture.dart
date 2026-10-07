import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_budget.dart';
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

/// K-3 test rig: a real agent, repository, tool registry and ledger against a
/// loopback endpoint that answers from a script. Nothing here reaches a real
/// model.
const loopKey = 'sk-agent-secret-0123456789';

class LoopSecrets implements SecretStore {
  @override
  Future<String?> read(String reference) async =>
      reference == 'key' ? loopKey : null;
}

String sseChunk(Map<String, Object?> delta, {String? finish}) =>
    'data: ${jsonEncode({
      'choices': [
        {'delta': delta, 'finish_reason': finish},
      ],
    })}\n\n';

/// `usage` as the endpoint reports it, before `[DONE]`.
String sseUsage(int prompt, int completion) =>
    'data: ${jsonEncode({
      'choices': [],
      'usage': {'prompt_tokens': prompt, 'completion_tokens': completion},
    })}\n\n';

/// A streamed text reply (optionally with a usage report).
List<String> sseText(String text, {int? prompt, int? completion}) => [
  sseChunk({'content': text}),
  sseChunk({}, finish: 'stop'),
  if (prompt != null) sseUsage(prompt, completion ?? 0),
  'data: [DONE]\n\n',
];

/// One reply carrying [calls] (`id`, wire name, arguments JSON).
List<String> sseCalls(
  List<(String, String, String)> calls, {
  String? text,
  int? prompt,
  int? completion,
}) => [
  if (text != null) sseChunk({'content': text}),
  sseChunk({
    'tool_calls': [
      for (var i = 0; i < calls.length; i++)
        {
          'index': i,
          'id': calls[i].$1,
          'function': {'name': calls[i].$2, 'arguments': calls[i].$3},
        },
    ],
  }),
  sseChunk({}, finish: 'tool_calls'),
  if (prompt != null) sseUsage(prompt, completion ?? 0),
  'data: [DONE]\n\n',
];

class LoopReply {
  const LoopReply.sse(this.parts, {this.hold}) : status = 200;
  const LoopReply.status(this.status) : parts = const [], hold = null;
  final List<String> parts;
  final int status;

  /// When set, the endpoint sends the first part and then waits for it.
  final Future<void>? hold;
}

class LoopFixture {
  LoopFixture._(
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
  final replies = <LoopReply>[];
  final bodies = <Map<String, dynamic>>[];

  /// What the tools' scope resolves to; a handler may change it to simulate
  /// data that moves under a batch.
  late List<ObjectRef> objects;

  /// How often a scope was resolved, and a hook called at each one (a test
  /// may move [objects] at an exact point).
  var resolves = 0;
  void Function(int n)? onResolve;
  final calls = <String, int>{};
  final order = <String>[];
  late final ObjectRef ref;

  static Future<LoopFixture> open() async {
    final root = Directory.systemTemp.createTempSync('muyon-loop-');
    final storage = StorageManager(root.path);
    final db = await storage.open('muyon', WorkspaceRepository.schema);
    final repo = FoundationRepository(db);
    late LoopFixture f;
    final ref = const ObjectRef(
      moduleId: 'test',
      objectType: 'budget',
      objectId: 'b1',
    );
    final tools = ToolRegistry(
      database: db,
      resolveScope: (scope) async {
        f.resolves++;
        f.onResolve?.call(f.resolves);
        return ResolvedAssistantScope(requested: scope, objects: f.objects);
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    f = LoopFixture._(root, storage, repo, tools, OutboundLedger(db), server);
    f.ref = ref;
    f.objects = [ref];
    f.addTool('read', ToolEffect.read);
    f.addTool('write', ToolEffect.write);
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
      var first = true;
      for (final part in reply.parts) {
        request.response.write(part);
        await request.response.flush();
        if (first && reply.hold != null) await reply.hold;
        first = false;
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

  /// Registers a tool; [onCall] runs inside the handler (it may change
  /// [objects], advance a clock, or throw). Returns the result refs [ref].
  void addTool(
    String id,
    ToolEffect effect, {
    Future<ToolCallResult?> Function(ToolCallContext context)? onCall,
    String summary = 'actual result',
  }) {
    tools.register(
      providerId: 'test',
      descriptor: ToolDescriptor(
        toolId: id,
        moduleId: 'test',
        effect: effect,
        description: '测试工具 $id',
        parameterSchema: {
          'type': 'object',
          'properties': {
            'note': {'type': 'string'},
            'destination': {'type': 'string'},
          },
          'additionalProperties': false,
        },
      ),
      handler: (context) async {
        calls[id] = (calls[id] ?? 0) + 1;
        order.add(id);
        final custom = await onCall?.call(context);
        return custom ??
            ToolCallResult(
              status: ToolCallStatus.succeeded,
              summary: summary,
              data: {'value': 42},
              objectRefs: [ref],
            );
      },
    );
  }

  int callsOf(String id) => calls[id] ?? 0;

  ModelProfile profile({
    ModelCapabilities capabilities = const ModelCapabilities(
      streaming: true,
      nativeTools: true,
      source: CapabilitySource.userDeclared,
    ),
    ModelLocation location = ModelLocation.local,
    String id = 'local',
    int? port,
  }) => ModelProfile(
    id: id,
    endpoint: Uri.parse('http://127.0.0.1:${port ?? server.port}/v1'),
    location: location,
    modelId: 'm',
    endpointIdentity: 'fixture-$id',
    credentialRef: location == ModelLocation.local ? null : 'key',
    capabilities: capabilities,
  );

  PersonalAgent agent({
    Budget budget = const Budget(),
    int? maxRounds,
    DateTime Function()? clock,
    OpenAiModelGateway? gateway,
    ModelRequestGate gate = const AlwaysConfirmGate(),
    ModelProfile? compactionProfile,
  }) {
    final agent = PersonalAgent(
      repository: repo,
      gateway: gateway ?? OpenAiModelGateway(LoopSecrets(), ledger: ledger),
      tools: tools,
      budget: budget,
      maxRounds: maxRounds,
      clock: clock,
      gate: gate,
      compactionProfile: compactionProfile,
    );
    addTearDown(agent.close);
    return agent;
  }

  Future<PersonalTask> start(
    PersonalAgent agent,
    ModelProfile profile, {
    String prompt = '项目的成本预算是多少？',
    String? conversationId,
  }) async {
    final conversation = conversationId ?? (await repo.createConversation()).id;
    return agent.start(
      conversationId: conversation,
      prompt: prompt,
      profile: profile,
    );
  }

  /// Confirms every model round; stops at the first tool card unless
  /// [confirmTools], and at a summary-request card unless [confirmSummary].
  Future<PersonalTask> run(
    PersonalAgent agent,
    PersonalTask first, {
    int max = 12,
    bool confirmTools = false,
    bool confirmSummary = false,
  }) async {
    var task = first;
    for (var i = 0; i < max; i++) {
      if (task.state != PersonalTaskState.waitingConfirmation) break;
      if (task.stage == 'tool' && !confirmTools) break;
      if (task.stage == 'compaction' && !confirmSummary) break;
      await agent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = repo.task(task.id)!;
    }
    return task;
  }

  /// Rows of `tool_approvals` (one-use approvals) and receipts.
  List<Map<String, Object?>> approvals() => [
    for (final r in repo.database.raw.select(
      'SELECT * FROM tool_approvals ORDER BY rowid',
    ))
      Map<String, Object?>.from(r),
  ];

  List<Map<String, Object?>> receipts() => [
    for (final r in repo.database.raw.select(
      'SELECT * FROM tool_invocation_receipts ORDER BY rowid',
    ))
      Map<String, Object?>.from(r),
  ];
}
