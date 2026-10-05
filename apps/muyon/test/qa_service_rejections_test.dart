import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/execution_store.dart';
import 'package:muyon/assistant/qa_service.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// QA rejection paths: invalid or unavailable evidence, duplicate runs,
/// cancelled transitions, evidence revalidated at send time, and failures that
/// must never store an answer.
void main() {
  late ManagedConnection db;
  late ExecutionStore store;
  late List<QaEvidence> evidence;
  late bool Function(int call) validator;
  var validatorCalls = 0;
  late QaService service;

  ManagedConnection database() {
    final value = ManagedConnection(sqlite3.openInMemory());
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(value.raw);
    }
    return value;
  }

  QaEvidence item(String id) => QaEvidence(
    id: id,
    documentId: 'document',
    contentDigest: 'digest-$id',
    pageIndex: 0,
    text: '证据 $id',
  );

  final context = ContextRef(
    workspaceId: 'workspace',
    moduleId: 'test',
    nativeProjectId: 'project',
  );
  final profile = ModelProfile(
    id: 'local',
    endpoint: Uri.parse('http://127.0.0.1:9/v1/chat/completions'),
    location: ModelLocation.local,
    modelId: 'test',
    endpointIdentity: 'test-local',
  );

  setUp(() {
    db = database();
    store = ExecutionStore(db);
    evidence = [item('e1')];
    validator = (_) => true;
    validatorCalls = 0;
    service = QaService(
      gateway: _ScriptedGateway(
        () async => jsonEncode({
          'answer': 'ok',
          'citationIds': ['e1'],
          'insufficientEvidence': false,
        }),
      ),
      executions: store,
      evidenceProvider: (_, _) async => evidence,
      evidenceValidator: (_, _) async {
        validatorCalls++;
        return validator(validatorCalls);
      },
    );
  });
  tearDown(() => db.close());

  Future<QaRequest> prepare() =>
      service.prepare(context: context, profile: profile, question: '问题');

  test('prepare rejects invalid and unavailable evidence', () async {
    evidence = [item('e1'), item('e1')];
    await expectLater(
      prepare(),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'invalid_evidence'),
      ),
    );

    evidence = const [];
    await expectLater(
      prepare(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'insufficient_evidence',
        ),
      ),
    );

    evidence = [item('e1')];
    validator = (_) => false;
    await expectLater(
      prepare(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'evidence_unavailable',
        ),
      ),
    );
  });

  test('the same execution cannot run twice', () async {
    final gateway = _BlockingGateway();
    service = QaService(
      gateway: gateway,
      executions: store,
      evidenceProvider: (_, _) async => evidence,
      evidenceValidator: (_, _) async => true,
    );
    final request = await prepare();
    final first = service.run(request, request.approve());
    await gateway.started.future;
    await expectLater(
      service.run(request, request.approve()),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'Already running'),
      ),
    );
    gateway.release.complete();
    final answer = await first;
    expect(answer.text, 'ok');
  });

  test('a refused running transition cancels without an answer', () async {
    final noRun = _NoRunStore(db);
    service = QaService(
      gateway: _ScriptedGateway(
        () async => jsonEncode({
          'answer': 'late',
          'citationIds': ['e1'],
          'insufficientEvidence': false,
        }),
      ),
      executions: noRun,
      evidenceProvider: (_, _) async => evidence,
      evidenceValidator: (_, _) async => true,
    );
    final request = await prepare();
    await expectLater(
      service.run(request, request.approve()),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'cancelled'),
      ),
    );
    expect(noRun.get(request.executionId)!.state, ExecutionState.failed);
    expect(noRun.answer(request.executionId), isNull);
  });

  test('evidence is revalidated immediately before sending', () async {
    // Calls: prepare, run preflight, beforeSend -> the third one fails.
    validator = (call) => call <= 2;
    final request = await prepare();
    await expectLater(
      service.run(request, request.approve()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'evidence_unavailable',
        ),
      ),
    );
    expect(store.get(request.executionId)!.state, ExecutionState.failed);
    expect(store.answer(request.executionId), isNull);
  });

  test('a refused commit stores no answer', () async {
    final noCommit = _NoCommitStore(db);
    service = QaService(
      gateway: _ScriptedGateway(
        () async => jsonEncode({
          'answer': 'late',
          'citationIds': ['e1'],
          'insufficientEvidence': false,
        }),
      ),
      executions: noCommit,
      evidenceProvider: (_, _) async => evidence,
      evidenceValidator: (_, _) async => true,
    );
    final request = await prepare();
    await expectLater(
      service.run(request, request.approve()),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'cancelled'),
      ),
    );
    expect(noCommit.answer(request.executionId), isNull);
    expect(noCommit.get(request.executionId)!.state, ExecutionState.failed);
  });

  test('a failed model request stores no answer', () async {
    service = QaService(
      gateway: _ScriptedGateway(
        () async => throw StateError('model_request_failed'),
      ),
      executions: store,
      evidenceProvider: (_, _) async => evidence,
      evidenceValidator: (_, _) async => true,
    );
    final request = await prepare();
    await expectLater(
      service.run(request, request.approve()),
      throwsA(isA<StateError>()),
    );
    expect(store.get(request.executionId)!.state, ExecutionState.failed);
    expect(store.answer(request.executionId), isNull);
  });
}

class _NoRunStore extends ExecutionStore {
  _NoRunStore(super.database);
  @override
  Future<bool> transition(
    String id,
    ExecutionState state, {
    String? error,
    String? answer,
    bool Function()? canCommit,
  }) {
    if (state == ExecutionState.running) return Future.value(false);
    return super.transition(
      id,
      state,
      error: error,
      answer: answer,
      canCommit: canCommit,
    );
  }
}

class _NoCommitStore extends ExecutionStore {
  _NoCommitStore(super.database);
  @override
  Future<bool> transition(
    String id,
    ExecutionState state, {
    String? error,
    String? answer,
    bool Function()? canCommit,
  }) {
    if (state == ExecutionState.succeeded) return Future.value(false);
    return super.transition(
      id,
      state,
      error: error,
      answer: answer,
      canCommit: canCommit,
    );
  }
}

class _ScriptedGateway extends OpenAiModelGateway {
  _ScriptedGateway(this.script) : super(UnavailableSecretStore());
  final Future<String> Function() script;
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'chat',
  }) async {
    if (beforeSend != null) await beforeSend();
    return script();
  }
}

class _BlockingGateway extends OpenAiModelGateway {
  _BlockingGateway() : super(UnavailableSecretStore());
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'chat',
  }) async {
    if (beforeSend != null) await beforeSend();
    started.complete();
    await release.future;
    return jsonEncode({
      'answer': 'ok',
      'citationIds': ['e1'],
      'insufficientEvidence': false,
    });
  }
}
