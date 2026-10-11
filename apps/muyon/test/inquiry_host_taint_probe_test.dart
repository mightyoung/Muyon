import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:inquiry_module/src/app/theme.dart';
import 'package:inquiry_module/src/features/ai/ask_page.dart';
import 'package:muyon/app/inquiry_plugin.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

void main() {
  late Directory root;
  late StorageManager storage;
  late ManagedConnection db;
  late FoundationRepository repository;
  late String conversation;

  PersonalTask task(String id) => PersonalTask({
    'kind': 'personal',
    'executionId': id,
    'conversationId': conversation,
    'prompt': 'host probe fixture',
    'scope': const AssistantScope.global().toJson(),
    'profile': null,
    'executionDeviceId': 'host',
    'state': 'queued',
    'stage': 'queued',
    'createdAt': '2026-10-11T00:00:00.000Z',
    'updatedAt': '2026-10-11T00:00:00.000Z',
    'references': <Object?>[],
    'messages': <Object?>[],
  });

  void seedClean(
    String id, {
    String? factsTaskId,
    String? factsConversationId,
  }) {
    db.raw.execute('INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)', [
      'auth1b:task:$id',
      jsonEncode({
        'version': 1,
        'taskId': factsTaskId ?? id,
        'conversationId': factsConversationId ?? conversation,
        'taintState': 'clean',
        'sourceDigests': <String>[],
      }),
    ]);
  }

  Future<InquiryPlugin> attach({
    bool? Function(String, String)? probe,
    String? taskId,
    String? conversationId,
  }) async => InquiryPlugin.attach(
    database: await storage.open('inquiry', InquiryPlugin.schema),
    jobsDatabase: await storage.open('inquiry_jobs', InquiryPlugin.jobsSchema),
    hubDatabase: await storage.open('inquiry_hub', InquiryPlugin.hubSchema),
    filesRoot: '${root.path}/modules/inquiry/files',
    deviceId: 'host',
    modelProfiles: ProfileRepository(WorkspaceRepository(db)),
    modelGateway: OpenAiModelGateway(UnavailableSecretStore()),
    hostTaintProbe: probe,
    hostTaskId: taskId,
    hostConversationId: conversationId,
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('inquiry-host-taint-');
    storage = StorageManager(root.path);
    db = await storage.open('muyon', WorkspaceRepository.schema);
    repository = FoundationRepository(db);
    conversation = (await repository.createConversation()).id;
  });

  tearDown(() async {
    repository.dispose();
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'real host probe rereads clean facts after external acceptance',
    () async {
      await repository.createTask(task('current'));
      seedClean('current');
      final probe = InquiryPlugin.hostTaintProbeFor(repository);
      expect(probe('current', conversation), isFalse);
      await repository.authorizationFacts.markExternal(
        'current',
        HostSourceFact.object(
          const ObjectRef(
            moduleId: 'network',
            objectType: 'response',
            objectId: 'external',
          ),
        ),
      );
      expect(probe('current', conversation), isTrue);
    },
  );

  test('unknown and missing task facts require host confirmation', () async {
    await repository.createTask(task('unknown'));
    final probe = InquiryPlugin.hostTaintProbeFor(repository);
    expect(probe('unknown', conversation), isTrue);
    expect(probe('missing', conversation), isNot(isFalse));
    db.raw.execute('DELETE FROM settings WHERE key=?', ['auth1b:task:unknown']);
    expect(probe('unknown', conversation), isNot(isFalse));
  });

  test('Folio job id cannot impersonate a real PersonalTask', () async {
    final plugin = await attach();
    try {
      final job = plugin.jobs.create(AiTask.conversation, {
        'question': 'fixture',
      });
      seedClean(job.id);
      expect(repository.task(job.id), isNull);
      expect(
        repository.authorizationFacts.readTask(job.id).requiresConfirmation,
        isFalse,
        reason: 'the fake clean row isolates task identity validation',
      );
      expect(
        InquiryPlugin.hostTaintProbeFor(repository)(job.id, conversation),
        isNot(isFalse),
      );
    } finally {
      await plugin.close();
    }
  });

  test('conversation and fact identity mismatch fail closed', () async {
    await repository.createTask(task('current'));
    seedClean('current');
    final otherConversation = (await repository.createConversation()).id;
    final probe = InquiryPlugin.hostTaintProbeFor(repository);
    expect(probe('current', otherConversation), isNot(isFalse));
    seedClean('current', factsConversationId: otherConversation);
    expect(probe('current', conversation), isNot(isFalse));
    seedClean('current', factsTaskId: 'another-task');
    expect(probe('current', conversation), isNot(isFalse));
  });

  test(
    'plugin attach forwards real host facts through runtime to state',
    () async {
      await repository.createTask(task('current'));
      seedClean('current');
      final plugin = await attach(
        probe: InquiryPlugin.hostTaintProbeFor(repository),
        taskId: 'current',
        conversationId: conversation,
      );
      try {
        final state = plugin.runtime.state;
        expect(state.requiresHostConfirmation, isFalse);
        state.assistantPermission = AssistantPermission.bypass;
        expect(state.assistantPermission, AssistantPermission.confirmWrites);
        await repository.authorizationFacts.markExternal(
          'current',
          HostSourceFact.object(
            const ObjectRef(
              moduleId: 'network',
              objectType: 'response',
              objectId: 'runtime-external',
            ),
          ),
        );
        expect(state.requiresHostConfirmation, isTrue);
      } finally {
        await plugin.close();
      }
    },
  );

  test(
    'real host probe read failure remains unknown and requires confirmation',
    () async {
      await repository.createTask(task('current'));
      seedClean('current');
      final probe = InquiryPlugin.hostTaintProbeFor(repository);
      final plugin = await attach(
        probe: probe,
        taskId: 'current',
        conversationId: conversation,
      );
      try {
        expect(plugin.runtime.state.requiresHostConfirmation, isFalse);
        await db.close();
        expect(probe('current', conversation), isNull);
        expect(plugin.runtime.state.requiresHostConfirmation, isTrue);
      } finally {
        await plugin.close();
      }
    },
  );

  testWidgets(
    'real tainted host task displays external notice on write review',
    (tester) async {
      await tester.runAsync(() async {
        await repository.createTask(task('current'));
        await repository.authorizationFacts.markExternal(
          'current',
          HostSourceFact.object(
            const ObjectRef(
              moduleId: 'network',
              objectType: 'response',
              objectId: 'ask-external',
            ),
          ),
        );
      });
      final domain = (await tester.runAsync(
        () => storage.open('inquiry', InquiryPlugin.schema),
      ))!;
      final jobs = (await tester.runAsync(
        () => storage.open('inquiry_jobs', InquiryPlugin.jobsSchema),
      ))!;
      final store = Store.attach(
        domain.raw,
        device: 'host',
        backgroundExecutor: <T>(action) =>
            domain.exclusiveAsync((_) => action()),
      );
      final supplier = store.save('supplier', {
        for (final field in Supplier.fields) field: null,
        'name': '原供应商',
        'aliases': <String>[],
        'categories': <String>[],
      });
      var calls = 0;
      final state = AppState.attach(
        store: store,
        dataDir: root,
        aiJobs: AiJobStore.attach(jobs.raw),
        secrets: _HostSecrets(),
        sharedModelSettings: _HostModels(),
        sharedLlmFactory: ({AiCancellation? cancellation}) async => LlmClient(
          const LlmConfig(apiKey: 'fake'),
          transport: (_) async => {
            'choices': [
              {
                'message': ++calls == 1
                    ? {
                        'tool_calls': [
                          {
                            'id': 'write',
                            'type': 'function',
                            'function': {
                              'name': 'update_record',
                              'arguments': jsonEncode({
                                'type': 'supplier',
                                'id': supplier,
                                'values': {'name': '新供应商'},
                              }),
                            },
                          },
                        ],
                      }
                    : {'content': '完成'},
              },
            ],
          },
        ),
        hostTaintProbe: InquiryPlugin.hostTaintProbeFor(repository),
        hostTaskId: 'current',
        hostConversationId: conversation,
      );
      try {
        state.assistantPermission = AssistantPermission.bypass;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(body: AskPage(state: state)),
          ),
        );
        await tester.enterText(find.byType(TextField), '修改供应商');
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('确认修改供应商'), findsOneWidget);
        expect(find.text('本次任务含外部内容或宿主污染状态无法确认，写入与外发须逐次确认。'), findsOneWidget);
        expect(find.textContaining('会话内允许'), findsNothing);
        expect(state.assistantPermission, AssistantPermission.confirmWrites);
        expect(store.get('supplier', supplier)!.data['name'], '原供应商');
        expect(
          repository.authorizationFacts
              .readTask('current')
              .requiresConfirmation,
          isTrue,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(state.shutdown);
        state.dispose();
      }
    },
  );

  for (final scenario in ['missing', 'throws', 'unknown']) {
    test('plugin attach $scenario probe requires confirmation', () async {
      final plugin = await attach(
        probe: scenario == 'missing'
            ? null
            : (taskId, conversationId) {
                if (scenario == 'throws') throw StateError('facts unavailable');
                return null;
              },
        taskId: 'current',
        conversationId: conversation,
      );
      try {
        expect(plugin.runtime.state.requiresHostConfirmation, isTrue);
        plugin.runtime.state.assistantPermission = AssistantPermission.bypass;
        expect(
          plugin.runtime.state.assistantPermission,
          AssistantPermission.confirmWrites,
        );
      } finally {
        await plugin.close();
      }
    });
  }
}

class _HostSecrets implements InquirySecretStore {
  @override
  Future<String?> read({required String key}) async => null;
  @override
  Future<void> write({required String key, required String value}) async {}
  @override
  Future<void> delete({required String key}) async {}
}

class _HostModels implements InquiryModelSettingsBridge {
  @override
  String get baseUrl => 'https://host.example/v1';
  @override
  String get model => 'fake-model';
  @override
  Future<bool> hasCredential() async => true;
  @override
  Future<void> save({
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {}
}
