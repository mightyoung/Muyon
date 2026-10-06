import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/research_tools_page.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/selection_eval/llm_selection_eval.dart';
import 'package:muyon/assistant/selection_eval/selection_eval.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/credential_redaction.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// Callers must redact on their own, not only rely on the gateway. These
/// gateways skip the gateway's checks and fail the way dart:io does when a
/// header value is malformed: the message quotes the whole header.
const _secret = 'sk-SECRET-7';
const _headerError = 'Invalid HTTP header field value: "Bearer $_secret"';

class _LeakyChatGateway extends OpenAiModelGateway {
  _LeakyChatGateway() : super(UnavailableSecretStore());
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'model',
  }) async => throw const FormatException(_headerError);
}

class _LeakyRequestGateway extends OpenAiModelGateway {
  _LeakyRequestGateway() : super(UnavailableSecretStore());
  @override
  Future<Map<String, dynamic>> request({
    required ModelProfile profile,
    required Map<String, Object?> payload,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'model',
  }) async => throw const FormatException(_headerError);
}

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String reference) async => _secret;
}

ModelProfile _local(int port, {String? credentialRef}) => ModelProfile(
  id: 'local',
  endpoint: Uri.parse('http://127.0.0.1:$port/v1'),
  location: ModelLocation.local,
  modelId: 'm',
  endpointIdentity: 'fixture',
  credentialRef: credentialRef,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('assistant redacts a key quoted by the model error in the task, its '
      'notification and the conversation', () async {
    final db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(db.raw);
    }
    final repo = FoundationRepository(db);
    final tools = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: const []),
    );
    final agent = PersonalAgent(
      repository: repo,
      gateway: _LeakyChatGateway(),
      tools: tools,
    );
    addTearDown(agent.close);
    final conversation = await repo.createConversation();
    var task = await agent.start(
      conversationId: conversation.id,
      prompt: '你好',
      profile: _local(9),
    );
    await agent.confirm(
      task.id,
      requestDigest: task.payload['requestDigest'] as String,
    );
    task = repo.task(task.id)!;
    expect(task.state, PersonalTaskState.failed);
    expect(task.error, contains('details withheld'));
    final traces = [
      task.error,
      jsonEncode(task.payload),
      for (final n in repo.notifications()) '${n.title} ${n.body}',
      for (final m in repo.messages(conversation.id)) m.content,
    ];
    expect(repo.notifications(), isNotEmpty);
    for (final trace in traces) {
      expect('$trace', isNot(contains(_secret)));
    }
  });

  test('selection eval redacts a key quoted by the request error', () async {
    final choice = await chooseWithModel(
      gateway: _LeakyRequestGateway(),
      profile: _local(9),
      tools: evaluationTools(),
      taskId: 't',
      prompt: 'x',
    );
    expect(choice.error, isNotNull);
    expect(choice.error, isNot(contains(_secret)));
    expect(choice.error, contains('details withheld'));
  });

  test('gateway removes the key an endpoint echoes back from the thrown '
      'error and the ledger', () async {
    // The widgets binding replaces HttpClient with one that answers 400.
    HttpOverrides.global = null;
    final root = Directory.systemTemp.createTempSync('muyon-echo-');
    final storage = StorageManager(root.path);
    final ledger = OutboundLedger(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      await storage.close();
      root.deleteSync(recursive: true);
    });
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.write('invalid key $_secret');
      await request.response.close();
    });
    Object? thrown;
    try {
      await OpenAiModelGateway(_Secrets(), ledger: ledger).request(
        profile: _local(server.port, credentialRef: 'k'),
        payload: {'model': 'm', 'messages': <Object>[]},
      );
    } catch (error) {
      thrown = error;
    }
    expect(thrown, isNotNull);
    expect('$thrown', isNot(contains(_secret)));
    expect('$thrown', contains('<redacted>'));
    final row = ledger.recent().single;
    expect(row['status'], 'failed');
    expect(jsonEncode(row), isNot(contains(_secret)));
    expect('${row['error']}', contains('<redacted>'));
  });

  testWidgets('research tools model dialog refuses a pasted key with a line '
      'break and never shows it', (tester) async {
    const channel = MethodChannel('com.mightyoung.muyon/secrets');
    final writes = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'write') writes.add(call.arguments);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final root = Directory.systemTemp.createTempSync('muyon-research-key-');
    final host = (await tester.runAsync(() async {
      final host = await MuyonHost.open(root.path);
      await host.activateResearch();
      return host;
    }))!;
    try {
      final binding = (await tester.runAsync(() async {
        final workspace = await host.workspaces.create('A');
        final binding = WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'research',
          nativeProjectId: 'A',
        );
        await host.workspaces.bind(binding);
        return binding;
      }))!;
      await tester.pumpWidget(
        MaterialApp(
          home: ResearchToolsPage(host: host, binding: binding),
        ),
      );
      await tester.pumpAndSettle();
      final profilesBefore = ProfileRepository(host.workspaces).all().length;
      await tester.tap(find.byTooltip('模型设置'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '模型名'), 'm');
      await tester.enterText(
        find.widgetWithText(TextField, '密钥（仅写入系统密钥库）'),
        '$_secret\r',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text(invalidCredentialMessage), findsOneWidget);
      expect(find.text('配置模型端点'), findsOneWidget, reason: 'still open');
      expect(writes, isEmpty, reason: 'nothing written to the keychain');
      expect(
        ProfileRepository(host.workspaces).all(),
        hasLength(profilesBefore),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains('SECRET'),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
