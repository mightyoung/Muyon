import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muspace/assistant/execution_store.dart';
import 'package:muspace/assistant/qa_service.dart';
import 'package:muspace/platform/storage_manager.dart';
import 'package:muspace/services/models/model_gateway.dart';
import 'package:muspace/workspace/workspace_repository.dart';
import 'package:muspace_module_api/muspace_module_api.dart';

import 'model_gateway_test.dart' show TestSecrets, localProfile;

void main() {
  late Directory temp;
  late StorageManager manager;
  late ExecutionStore executions;
  late HttpServer server;
  late QaService service;
  var available = true;
  final context = ContextRef(
    workspaceId: 'w',
    moduleId: 'research',
    nativeProjectId: 'p',
  );
  const evidence = QaEvidence(
    id: 'e1',
    documentId: 'd1',
    contentDigest: 'digest',
    pageIndex: 0,
    text: 'The result is 42.',
  );
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('qa-scope');
    manager = StorageManager(temp.path);
    executions = ExecutionStore(
      await manager.open('muspace', WorkspaceRepository.schema),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    available = true;
    service = QaService(
      gateway: OpenAiModelGateway(TestSecrets()),
      executions: executions,
      evidenceProvider: (context, question) async => [evidence],
      evidenceValidator: (context, evidence) async => available,
    );
  });
  tearDown(() async {
    await server.close(force: true);
    await manager.close();
    temp.deleteSync(recursive: true);
  });
  void answer(String content) {
    server.listen((request) async {
      request.response.write(content);
      await request.response.close();
    });
  }

  Future<QaRequest> prepare() => service.prepare(
    context: context,
    profile: localProfile(server),
    question: 'What result?',
  );
  test(
    'valid citation persists answer; arbitrary citation is rejected',
    () async {
      answer(
        '{"choices":[{"message":{"content":"{\\"answer\\":\\"42\\",\\"citationIds\\":[\\"e1\\"]}"}}]}',
      );
      final request = await prepare();
      final result = await service.run(request, request.approve());
      expect(result.citations.single.id, 'e1');
      expect(
        executions.get(request.executionId)!.state,
        ExecutionState.succeeded,
      );
      expect(executions.answer(request.executionId), contains('42'));
    },
  );
  test(
    'citation outside frozen evidence cannot produce saved answer',
    () async {
      answer(
        '{"choices":[{"message":{"content":"{\\"answer\\":\\"42\\",\\"citationIds\\":[\\"other\\"]}"}}]}',
      );
      final request = await prepare();
      await expectLater(
        service.run(request, request.approve()),
        throwsStateError,
      );
      expect(executions.get(request.executionId)!.state, ExecutionState.failed);
      expect(executions.answer(request.executionId), null);
    },
  );
  test('other request consent and removed evidence cannot send', () async {
    var count = 0;
    server.listen((request) {
      count++;
      request.response.close();
    });
    final first = await prepare();
    final second = await prepare();
    await expectLater(service.run(second, first.approve()), throwsStateError);
    available = false;
    await expectLater(service.run(first, first.approve()), throwsStateError);
    expect(count, 0);
  });
  test(
    'explicit evidence gap permits empty citations and survives reload',
    () async {
      answer(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'answer': 'The supplied evidence does not contain that fact.',
                  'citationIds': <String>[],
                  'insufficientEvidence': true,
                }),
              },
            },
          ],
        }),
      );
      final request = await prepare();
      final result = await service.run(request, request.approve());
      expect(result.insufficientEvidence, true);
      expect(result.citations, isEmpty);
      final saved = jsonDecode(
        ExecutionStore(executions.database).answer(request.executionId)!,
      ) as Map;
      expect(saved['insufficientEvidence'], true);
      expect(saved['question'], 'What result?');
      expect((saved['evidence'] as List).single, {
        'id': 'e1',
        'documentId': 'd1',
        'contentDigest': 'digest',
        'pageIndex': 0,
      });
    },
  );
  test(
    'deletion while response is pending prevents answer persistence',
    () async {
      server.listen((incoming) async {
        available = false;
        incoming.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'answer': '42',
                    'citationIds': ['e1'],
                  }),
                },
              },
            ],
          }),
        );
        await incoming.response.close();
      });
      final request = await prepare();
      await expectLater(
        service.run(request, request.approve()),
        throwsStateError,
      );
      expect(executions.answer(request.executionId), null);
    },
  );
  test('cancel during HTTP leaves no late answer', () async {
    final received = Completer<HttpRequest>();
    server.listen(received.complete);
    final request = await prepare();
    final future = service.run(request, request.approve());
    final assertion = expectLater(future, throwsA(anything));
    final incoming = await received.future;
    await service.cancel(request.executionId);
    incoming.response.write('{"choices":[{"message":{"content":"late"}}]}');
    await incoming.response.close();
    await assertion;
    expect(
      executions.get(request.executionId)!.state,
      ExecutionState.cancelled,
    );
    expect(executions.answer(request.executionId), null);
  });
}
