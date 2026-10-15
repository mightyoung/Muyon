import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/core_agent_lifecycle.dart';
import 'package:muyon/assistant/core_agent_protocol.dart';
import 'package:muyon/assistant/core_agent_process.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

class _HeldUserMessageRepository extends FoundationRepository {
  _HeldUserMessageRepository(super.database);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> appendMessage(
    String conversationId,
    String role,
    String content, {
    List<ObjectRef> references = const [],
  }) async {
    if (role == 'user') {
      entered.complete();
      await release.future;
    }
    await super.appendMessage(
      conversationId,
      role,
      content,
      references: references,
    );
  }
}

void main() {
  test(
    'facade cancel while user message awaits prevents backend ownership launch',
    () async {
      final dir = Directory.systemTemp.createTempSync('core-queued-cancel-');
      final storage = StorageManager(dir.path);
      final repository = _HeldUserMessageRepository(
        await storage.open('muyon', WorkspaceRepository.schema),
      );
      final tools = ToolRegistry(
        database: repository.database,
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: []),
      );
      final agent = PersonalAgent(
        repository: repository,
        gateway: OpenAiModelGateway(UnavailableSecretStore()),
        tools: tools,
        coreAgentProcess: CoreAgentProcessConfig(
          enabled: true,
          executablePath: '${dir.path}/must-never-launch',
          stateRoot: '${dir.path}/core',
        ),
      );
      addTearDown(() async {
        if (!repository.release.isCompleted) repository.release.complete();
        await agent.close();
        await tools.close();
        await storage.close();
        dir.deleteSync(recursive: true);
      });
      final conversation = await repository.createConversation();
      final pending = agent.start(
        conversationId: conversation.id,
        prompt: 'Synthetic request',
        profile: ModelProfile(
          id: 'unit',
          endpoint: Uri.parse('http://127.0.0.1:9/v1'),
          location: ModelLocation.local,
          modelId: 'unit-model',
          endpointIdentity: 'unit-endpoint',
          capabilities: const ModelCapabilities(nativeTools: true),
        ),
      );
      await repository.entered.future;
      final queued = repository.tasks().single;
      expect(queued.payload['backend'], 'rust_core');
      await agent.cancel(queued.id);
      repository.release.complete();
      expect((await pending).state, PersonalTaskState.cancelled);
      expect(Directory('${dir.path}/core').existsSync(), isFalse);
      expect(tools.history(), isEmpty);
    },
  );
  const args = <String, Object?>{'type': 'supplier', 'id': 'supplier-1'};
  ObjectRef ref({String? revision = 'v1', String? digest = 'sha256:abc'}) =>
      ObjectRef(
        moduleId: 'inquiry',
        objectType: 'supplier',
        objectId: 'supplier-1',
        nativeProjectId: 'HOST_PRIVATE_PROJECT',
        revisionRef: revision,
        contentDigest: digest,
      );
  ToolCallResult result(ObjectRef object) => ToolCallResult(
    status: ToolCallStatus.succeeded,
    summary: 'PRIVATE_RAW_SUMMARY',
    data: const {
      'record': {'name': 'PRIVATE_NAME', 'notes': 'PRIVATE_NOTE'},
    },
    objectRefs: [object],
  );
  ResolvedAssistantScope scope(ObjectRef object) => ResolvedAssistantScope(
    requested: AssistantScope.selectedObjects([object]),
    objects: [object],
  );

  test(
    'accepted projection uses real versions and excludes all record strings',
    () {
      final object = ref(revision: null, digest: null);
      final projected = projectCoreInquiryResult(
        result(object),
        scope(object),
        args,
      );
      expect(projected, {
        'found': true,
        'objectRefs': [
          {
            'moduleId': 'inquiry',
            'objectType': 'supplier',
            'objectId': 'supplier-1',
            'revisionRef': null,
            'contentDigest': null,
          },
        ],
      });
      expect(jsonEncode(projected), isNot(contains('PRIVATE')));
    },
  );

  for (final unsafe in ['line\nbreak', 'unsafe value', 'é', '', 'x' * 129]) {
    for (final field in ['revision', 'digest']) {
      test('reject unsafe $field metadata ${jsonEncode(unsafe)}', () {
        final object = field == 'revision'
            ? ref(revision: unsafe)
            : ref(digest: unsafe);
        expect(
          () => projectCoreInquiryResult(result(object), scope(object), args),
          throwsA(
            isA<CoreAgentFailure>().having(
              (e) => e.code,
              'code',
              'projection_rejected',
            ),
          ),
        );
      });
    }
  }

  for (final close in [false, true]) {
    test(
      'admitted read drains genuine receipt across ${close ? 'close' : 'cancel'}',
      () async {
        final db = ManagedConnection(sqlite3.openInMemory());
        installToolRegistrySchema(db.raw);
        addTearDown(db.close);
        final object = ref();
        final entered = Completer<void>();
        final release = Completer<void>();
        final registry = ToolRegistry(
          database: db,
          resolveScope: (requested) async =>
              ResolvedAssistantScope(requested: requested, objects: [object]),
        );
        registry.register(
          providerId: 'unit-read-provider',
          descriptor: ToolDescriptor(
            toolId: 'inquiry.object',
            moduleId: 'inquiry',
            effect: ToolEffect.read,
            parameterSchema: const {
              'type': 'object',
              'properties': {
                'type': {'type': 'string'},
                'id': {'type': 'string'},
              },
              'required': ['type', 'id'],
              'additionalProperties': false,
            },
          ),
          handler: (call) async {
            entered.complete();
            await release.future;
            call.cancellation.throwIfCancelled();
            return result(object);
          },
        );
        final request = ToolCallRequest(
          invocationId: 'host-invocation',
          toolId: 'inquiry.object',
          scope: AssistantScope.selectedObjects([object]),
          parameters: args,
        );
        final prepared = await registry.prepare(request);
        final lifecycle = CoreAgentLifecycle();
        final inFlight = lifecycle.invoke(registry, request);
        await entered.future;
        // Stop is deliberately after registry admission and before real return.
        lifecycle.stop(close: close);
        expect(lifecycle.modelCancellation.isCancelled, isTrue);
        release.complete();
        final original = await inFlight;
        final receipt = registry.receiptFor(request.invocationId)!;
        expect(receipt.succeeded, isTrue);
        expect(receipt.identityDigest, prepared.identityDigest);
        expect(
          receipt.result!.data['record'],
          containsPair('notes', 'PRIVATE_NOTE'),
        );
        expect(original.status, ToolCallStatus.succeeded);
        final projection = projectCoreInquiryResult(
          original,
          prepared.resolvedScope,
          args,
        );
        expect(
          (projection['objectRefs'] as List).single,
          containsPair('revisionRef', 'v1'),
        );
        expect(
          () => lifecycle.invoke(registry, request),
          throwsA(isA<CoreAgentFailure>()),
        );
        expect(registry.history(), hasLength(1));
        await registry.close();
      },
    );
  }
}
