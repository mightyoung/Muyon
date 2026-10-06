import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon/services/models/credential_redaction.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';

/// Keys dart:io cannot put in a header; the marker must never surface.
const _marker = 'SECRET';
const _badKeys = ['sk-$_marker-42\r', 'sk-$_marker　42', 'sk $_marker 42'];

class _Secrets implements SecretStore {
  _Secrets(this.value);
  final String value;
  @override
  Future<String?> read(String reference) async => value;
}

/// An [HttpClient] whose header setting fails the way dart:io does for a bad
/// value: the exception quotes the whole header value, key included. Used to
/// reach the gateway's error path past its up-front check.
class _HeaderRejectingClient implements HttpClient {
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _Request();
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  @override
  final HttpHeaders headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      throw FormatException('Invalid HTTP header field value: "$value"');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secretsChannel = MethodChannel('com.mightyoung.muyon/secrets');

  group('redactCredentials', () {
    test('withholds text that mentions a bearer token or authorization', () {
      for (final text in [
        'Invalid HTTP header field value: "Bearer abc def"',
        'bearer abc',
        'BEARER abc',
        'authorization: abc',
        'Authorization=abc',
        'AUTHORIZATION abc',
      ]) {
        final out = redactCredentials(FormatException(text));
        expect(out, isNot(contains('abc')), reason: text);
        expect(
          out,
          'FormatException: details withheld (may contain the credential)',
        );
      }
      expect(redactCredentials('Bearer abc'), isNot(contains('abc')));
    });

    test('leaves errors without credentials unchanged', () {
      expect(
        redactCredentials(StateError('model_http_404')),
        'Bad state: model_http_404',
      );
      expect(
        redactCredentials(const FormatException('Unexpected character')),
        'FormatException: Unexpected character',
      );
      expect(redactCredentials('credential_invalid'), 'credential_invalid');
    });

    test('replaces the known secret value, only when it is 8+ chars', () {
      const secret = 'sk-a.b*c(d)[e]';
      expect(
        redactCredentials(
          StateError('invalid key $secret here'),
          secret: secret,
        ),
        'Bad state: invalid key <redacted> here',
      );
      expect(
        redactCredentials('echo $secret', secret: secret),
        'echo <redacted>',
      );
      // Value first, then the keyword rule still applies.
      expect(
        redactCredentials('Bearer $secret', secret: secret),
        'Error: details withheld (may contain the credential)',
      );
      // Too short to replace: unrelated text is left alone.
      expect(
        redactCredentials('a model_http_400', secret: 'a'),
        'a model_http_400',
      );
      expect(
        redactCredentials('x 1234567 y', secret: '1234567'),
        'x 1234567 y',
      );
      expect(
        redactCredentials('x 12345678 y', secret: '12345678'),
        'x <redacted> y',
      );
      expect(redactCredentials('plain', secret: null), 'plain');
    });

    test('sendable credentials are visible ASCII only', () {
      expect(isSendableCredential('sk-abc_123.XYZ'), isTrue);
      for (final bad in [..._badKeys, '', 'sk-abc\n', 'sk-ａbc']) {
        expect(isSendableCredential(bad), isFalse, reason: jsonEncode(bad));
      }
    });
  });

  group('gateway', () {
    late Directory root;
    late StorageManager storage;
    late OutboundLedger ledger;
    late HttpServer server;
    var requests = 0;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('muyon-redaction-');
      storage = StorageManager(root.path);
      ledger = OutboundLedger(
        await storage.open('muyon', WorkspaceRepository.schema),
      );
      requests = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests++;
        await utf8.decoder.bind(request).join();
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          }),
        );
        await request.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      await storage.close();
      root.deleteSync(recursive: true);
    });

    ModelProfile profile() => ModelProfile(
      id: 'keyed',
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1'),
      location: ModelLocation.local,
      modelId: 'm',
      endpointIdentity: 'fixture',
      credentialRef: 'k',
    );

    test('a malformed key fails with credential_invalid before approval, '
        'the ledger and the request', () async {
      for (final key in _badKeys) {
        var beforeSend = 0;
        final gateway = OpenAiModelGateway(_Secrets(key), ledger: ledger);
        await expectLater(
          gateway.request(
            profile: profile(),
            payload: {'model': 'm', 'messages': <Object>[]},
            beforeSend: () async => beforeSend++,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'credential_invalid',
            ),
          ),
        );
        expect(beforeSend, 0, reason: jsonEncode(key));
      }
      expect(requests, 0);
      expect(ledger.recent(), isEmpty);
    });

    test('a header error past the check is redacted in the ledger and in what '
        'callers receive', () async {
      final gateway = OpenAiModelGateway(
        _Secrets('sk-$_marker-ok'),
        ledger: ledger,
        clientFactory: _HeaderRejectingClient.new,
      );
      Object? thrown;
      try {
        await gateway.request(
          profile: profile(),
          payload: {'model': 'm', 'messages': <Object>[]},
        );
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isA<StateError>());
      expect('$thrown', isNot(contains(_marker)));
      expect('$thrown', contains('details withheld'));
      final row = ledger.recent().single;
      expect(row['status'], 'failed');
      expect('${row['error']}', isNot(contains(_marker)));
      expect('${row['error']}', contains('details withheld'));
      expect(jsonEncode(row), isNot(contains(_marker)));
    });
  });

  test('assistant: a malformed key leaves no trace in the task, its '
      'notification or the conversation', () async {
    final root = Directory.systemTemp.createTempSync('muyon-redaction-host-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secretsChannel, (call) async {
          return call.method == 'read' ? _badKeys.first : null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secretsChannel, null);
      root.deleteSync(recursive: true);
    });
    final host = await MuyonHost.open(root.path);
    try {
      final profile = ModelProfile(
        id: 'keyed',
        endpoint: Uri.parse('http://127.0.0.1:9/v1'),
        location: ModelLocation.local,
        modelId: 'm',
        endpointIdentity: 'fixture',
        credentialRef: 'k',
      );
      await ProfileRepository(host.workspaces).save(profile);
      final conversation = await host.foundation.createConversation(
        title: '对话',
      );
      var task = await host.personalAgent.start(
        conversationId: conversation.id,
        prompt: '你好',
        profile: profile,
      );
      expect(task.stage, 'model');
      await host.personalAgent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = host.foundation.task(task.id)!;
      expect(task.state, PersonalTaskState.failed);
      expect(task.error, contains('credential_invalid'));
      final traces = [
        task.error,
        jsonEncode(task.payload),
        for (final n in host.foundation.notifications()) '${n.title} ${n.body}',
        for (final m in host.foundation.messages(conversation.id)) m.content,
        jsonEncode(
          host.foundation.database.raw
              .select('SELECT * FROM outbound_requests')
              .map((r) => Map.of(r))
              .toList(),
        ),
      ];
      expect(host.foundation.notifications(), isNotEmpty);
      for (final trace in traces) {
        expect('$trace', isNot(contains(_marker)));
      }
    } finally {
      await host.close();
    }
  });

  testWidgets('settings refuse a pasted key with a line break and never show '
      'it', (tester) async {
    final writes = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      secretsChannel,
      (call) async {
        if (call.method == 'write') writes.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        secretsChannel,
        null,
      ),
    );
    final root = Directory.systemTemp.createTempSync('muyon-redaction-ui-');
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: PlatformShell(
            host: host,
            themeMode: ThemeMode.light,
            onTheme: (_) {},
            onRestore: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('系统设置').first);
      await tester.pumpAndSettle();
      final add = find.text('添加模型');
      await tester.scrollUntilVisible(
        add,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final profilesBefore = ProfileRepository(host.workspaces).all().length;
      await tester.enterText(
        find.widgetWithText(TextField, '端点 URL'),
        'http://127.0.0.1:11434/v1',
      );
      await tester.enterText(find.widgetWithText(TextField, '模型名称'), 'm');
      await tester.enterText(
        find.widgetWithText(TextField, 'API Key（仅存入系统凭据）'),
        'sk-$_marker-42\r',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text(invalidCredentialMessage), findsOneWidget);
      expect(find.text('添加自选模型'), findsOneWidget, reason: 'still open');
      expect(writes, isEmpty, reason: 'nothing written to the keychain');
      expect(
        ProfileRepository(host.workspaces).all(),
        hasLength(profilesBefore),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains(_marker),
        ),
        findsNothing,
      );
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'API Key（仅存入系统凭据）'),
      );
      expect(field.obscureText, isTrue);
      // Closing the dialog here would hit an existing, unrelated defect
      // (addProfile disposes its controllers while the exit animation still
      // builds the fields); unmount instead.
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
