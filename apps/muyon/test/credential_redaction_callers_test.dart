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
  _Secrets([this.value = _secret]);
  final String value;
  @override
  Future<String?> read(String reference) async => value;
}

/// A key of realistic length (164 chars): long enough that a parser would
/// quote only a truncated part of it, which value replacement cannot match.
final _longSecret =
    'sk-proj-${List.generate(156, (i) => 'abcdefghijklmnopqrstuvwxyz0123456789'[(i * 7) % 36]).join()}';

/// No 12-character window of [secret] appears in [text].
Matcher _noFragmentOf(String secret) => predicate<Object?>((value) {
  final text = '$value';
  for (var i = 0; i + 12 <= secret.length; i++) {
    if (text.contains(secret.substring(i, i + 12))) return false;
  }
  return true;
}, 'contains no 12-character fragment of the key');

/// Answers every chat request with [text] instead of protocol JSON.
class _EchoChatGateway extends OpenAiModelGateway {
  _EchoChatGateway(this.text) : super(UnavailableSecretStore());
  final String text;
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'model',
  }) async => text;
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
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
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
      request.response.write('invalid key $_longSecret');
      await request.response.close();
    });
    Object? thrown;
    try {
      await OpenAiModelGateway(_Secrets(_longSecret), ledger: ledger).request(
        profile: _local(server.port, credentialRef: 'k'),
        payload: {'model': 'm', 'messages': <Object>[]},
      );
    } catch (error) {
      thrown = error;
    }
    expect(_longSecret.length, greaterThanOrEqualTo(80));
    expect(thrown, isNotNull);
    expect(thrown, _noFragmentOf(_longSecret));
    expect('$thrown', contains('model_response_not_json'));
    final row = ledger.recent().single;
    expect(row['status'], 'failed');
    expect(jsonEncode(row), _noFragmentOf(_longSecret));
    expect('${row['error']}', contains('model_response_not_json'));
  });

  test('assistant does not quote a non-JSON model reply that echoes a long '
      'key in the task, its notification or the conversation', () async {
    final db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(db.raw);
    }
    final repo = FoundationRepository(db);
    final agent = PersonalAgent(
      repository: repo,
      gateway: _EchoChatGateway('Your key $_longSecret is not valid here.'),
      tools: ToolRegistry(
        database: db,
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: const []),
      ),
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
    expect(task.error, contains('model_reply_not_json'));
    expect(repo.notifications(), isNotEmpty);
    for (final trace in [
      task.error,
      jsonEncode(task.payload),
      for (final n in repo.notifications()) '${n.title} ${n.body}',
      for (final m in repo.messages(conversation.id)) m.content,
    ]) {
      expect(trace, _noFragmentOf(_longSecret));
    }
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
      // Opened with real async so the dialog's save path (which awaits the
      // dialog) runs in real time too; see the save tap below.
      await tester.runAsync(() async => tester.tap(find.byTooltip('模型设置')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '模型名'), 'm');
      await tester.enterText(
        find.widgetWithText(TextField, '密钥（仅写入系统密钥库）'),
        '$_secret\r',
      );
      // Tap with real async: the refusal is synchronous, and if the check were
      // missing the save's IO completes here instead of hanging in fake time
      // (which made a broken check surface only at the 10-minute timeout).
      await tester.runAsync(() async {
        await tester.tap(find.text('保存'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

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
