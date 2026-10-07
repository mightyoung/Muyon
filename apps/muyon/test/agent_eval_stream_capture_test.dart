import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_eval/agent_eval.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/openai_compat_provider.dart';
import 'package:muyon/workspace/workspace_repository.dart';

import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

/// E-1 follow-up (K-2a review): streaming and native profiles do not go
/// through `request()`, so the evaluation's gateway must record
/// `chatStream` too, or their latency and token data would be lost.
void main() {
  Future<(HttpServer, ModelProfile)> serve(
    List<String> parts, {
    int status = 200,
    Duration pause = Duration.zero,
    bool streaming = true,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = status;
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      var first = true;
      for (final part in parts) {
        if (!first) await Future<void>.delayed(pause);
        first = false;
        request.response.write(part);
        await request.response.flush();
      }
      await request.response.close();
    });
    return (
      server,
      ModelProfile(
        id: 'p',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'loopback',
        capabilities: const ModelCapabilities(
          streaming: true,
          nativeTools: true,
        ),
      ),
    );
  }

  ModelRequest requestFor(ModelProfile profile) => ModelRequest(
    profile: profile,
    messages: const [ModelMessage(role: 'user', content: 'hi')],
    caller: 'assistant',
  );

  test(
    'a streamed response is recorded with its first-event time and usage',
    () async {
      final (_, profile) = await serve([
        sseChunk({'content': '好'}),
        sseChunk({}, finish: 'stop'),
        sseUsage(40, 7),
        'data: [DONE]\n\n',
      ], pause: const Duration(milliseconds: 60));
      final gateway = RecordingGateway(LoopSecrets());
      final events = await gateway
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: requestFor(profile),
          )
          .toList();
      expect(events.whereType<Done>(), hasLength(1));
      expect(gateway.calls, hasLength(1));
      final call = gateway.calls.single;
      expect(call.ok, isTrue);
      expect(call.promptTokens, 40);
      expect(call.completionTokens, 7);
      expect(call.firstEventMs, isNotNull);
      expect(call.firstEventMs!, lessThan(call.ms));
      expect(call.ms - call.firstEventMs!, greaterThan(30));
    },
  );

  test('a stream that fails is recorded as a failure, without usage', () async {
    final (_, profile) = await serve([], status: 503);
    final gateway = RecordingGateway(LoopSecrets());
    await expectLater(
      gateway
          .chatStream(
            provider: const OpenAiCompatProvider(),
            request: requestFor(profile),
          )
          .toList(),
      throwsA(isA<HttpException>()),
    );
    expect(gateway.calls.single.ok, isFalse);
    expect(gateway.calls.single.promptTokens, isNull);
    // A cut-off stream is a failure too.
    final (_, cut) = await serve([
      sseChunk({'content': 'x'}),
    ]);
    final events = await gateway
        .chatStream(
          provider: const OpenAiCompatProvider(),
          request: requestFor(cut),
        )
        .toList();
    expect(events.last, isA<ModelError>());
    expect(gateway.calls.last.ok, isFalse);
  });

  test('the evaluation run reads its first-response time and tokens from a '
      'native profile through the agent', () async {
    final root = Directory.systemTemp.createTempSync('muyon-e1-stream-');
    addTearDown(() => root.deleteSync(recursive: true));
    final storage = StorageManager(root.path);
    addTearDown(storage.close);
    final repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    final tools = ToolRegistry(
      database: repo.database,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: const []),
    );
    final (_, profile) = await serve([
      sseChunk({'content': '成本合计'}),
      sseChunk({}, finish: 'stop'),
      sseUsage(55, 9),
      'data: [DONE]\n\n',
    ]);
    final gateway = RecordingGateway(LoopSecrets());
    final agent = PersonalAgent(
      repository: repo,
      gateway: gateway,
      tools: tools,
    );
    addTearDown(agent.close);
    final c = await repo.createConversation();
    var task = await agent.start(
      conversationId: c.id,
      prompt: '成本？',
      profile: profile,
    );
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    task = repo.task(task.id)!;
    expect(task.state, PersonalTaskState.succeeded);
    final ok = gateway.calls.where((c) => c.ok).toList();
    expect(ok, hasLength(1));
    expect(ok.single.promptTokens, 55);
    expect(ok.single.completionTokens, 9);
    expect(ok.single.firstEventMs, isNotNull);
  });
}
