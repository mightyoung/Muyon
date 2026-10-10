import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/dream/dream_service.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/outbound_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  late Directory dir;
  late StorageManager storage;
  late FoundationRepository repo;
  late DreamService dream;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('dream-');
    storage = StorageManager(dir.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    dream = DreamService(
      repo,
      gateway: OpenAiModelGateway(
        UnavailableSecretStore(),
        clientFactory: () => throw StateError('dream called the network'),
      ),
    );
  });

  tearDown(() async {
    await storage.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'offline dream is incremental, idempotent and does not call a model',
    () async {
      await repo.saveMemory(content: '第一条', source: 'user');
      final first = await dream.run();
      final again = await dream.run();
      expect(again.id, first.id);
      expect(dream.runs().where((run) => run.status == 'done'), hasLength(1));
      await repo.saveMemory(content: '第二条', source: 'user');
      final second = await dream.run();
      expect(second.id, isNot(first.id));
      expect((second.inputs as Map)['changed'], hasLength(1));
      expect(
        repo.database.raw.select('SELECT id FROM outbound_requests'),
        isEmpty,
      );
    },
  );

  test('an interrupted run is not marked done', () async {
    final hanging = await dream.run(leaveRunning: true);
    expect(hanging.status, 'running');
    final next = await dream.run();
    expect(dream.runRecord(hanging.id)!.status, 'interrupted');
    expect(next.status, 'done');
  });

  test(
    'duplicate accept can be reverted and conflicts are not resolved',
    () async {
      await repo.saveMemory(content: '同一句话', source: 'user');
      await repo.saveMemory(content: '同一句话', source: 'user');
      await repo.saveMemory(content: '单价：1', source: '报价');
      await repo.saveMemory(content: '单价：2', source: '合同');
      final run = await dream.run();
      final duplicate = dream
          .proposals(runId: run.id)
          .singleWhere((proposal) => proposal.kind == 'duplicate');
      final conflict = dream
          .proposals(runId: run.id)
          .singleWhere((proposal) => proposal.kind == 'conflict');
      expect(conflict.payload['sources'], hasLength(2));
      await expectLater(dream.accept(conflict.id), throwsStateError);
      await dream.accept(duplicate.id);
      expect(
        repo.memories(includeDisabled: true).where((memory) => memory.disabled),
        hasLength(1),
      );
      await dream.revert(run.id);
      expect(repo.memories().where((memory) => memory.disabled), isEmpty);
      expect(
        repo.memories().where((memory) => memory.content == '同一句话'),
        hasLength(2),
      );
      expect(dream.runRecord(run.id)!.status, 'reverted');
    },
  );

  for (final change in ['delete', 'disable', 'narrow', 'add', 'experience']) {
    test('revert preserves a later user $change', () async {
      final source = await repo.saveMemory(content: '原始事实', source: 'user');
      final run = await dream.run();
      switch (change) {
        case 'delete':
          await repo.deleteMemory(source);
        case 'disable':
          await repo.setMemoryDisabled(source, true);
        case 'narrow':
          await repo.narrowMemoryScope(source, AssistantScope.workspace('w'));
        case 'add':
          await repo.saveMemory(content: '后来添加', source: 'user');
        case 'experience':
          await repo.saveExperience(content: '用户经验', source: 'user', evidence: []);
      }
      final before = jsonEncode(repo.organizationSnapshot());
      await expectLater(dream.revert(run.id), throwsStateError);
      expect(jsonEncode(repo.organizationSnapshot()), before);
      expect(dream.runRecord(run.id)!.status, 'done');
    });
  }

  test('duplicate acceptance rejects an edited source without partial writes', () async {
    await repo.saveMemory(content: '重复内容', source: 'user');
    await repo.saveMemory(content: '重复内容', source: 'user');
    final run = await dream.run();
    final proposal = dream.proposals(runId: run.id).single;
    final target = (proposal.payload['disableIds'] as List).single as String;
    await repo.saveMemory(id: target, content: '独立内容', source: 'user');
    final before = jsonEncode(repo.organizationSnapshot());
    await expectLater(dream.accept(proposal.id), throwsStateError);
    expect(jsonEncode(repo.organizationSnapshot()), before);
    expect(dream.proposals(runId: run.id).single.status, 'proposed');
  });

  for (final kind in ['summary', 'experience']) {
    test('$kind acceptance rolls back artifact when status persistence fails', () async {
      final source = await repo.saveMemory(content: '证据', source: 'user');
      final run = await dream.run();
      final id = 'test-$kind';
      repo.database.raw.execute(
        'INSERT INTO dream_proposals(id,run_id,kind,evidence_json,payload_json,status) VALUES(?,?,?,?,?,?)',
        [id, run.id, kind, jsonEncode([{'id': source, 'revision': 1}]),
          jsonEncode({'content': '整理产物'}), 'proposed'],
      );
      repo.database.raw.execute("CREATE TRIGGER fail_accept BEFORE UPDATE OF status ON dream_proposals WHEN NEW.status='accepted' BEGIN SELECT RAISE(ABORT, 'injected crash boundary'); END");
      final before = jsonEncode(repo.organizationSnapshot());
      await expectLater(dream.accept(id), throwsA(isA<Exception>()));
      expect(jsonEncode(repo.organizationSnapshot()), before);
      expect(dream.proposals(runId: run.id).single.status, 'proposed');
      repo.database.raw.execute('DROP TRIGGER fail_accept');
      await dream.accept(id);
      final artifacts = kind == 'summary'
          ? repo.memories().where((m) => m.source == 'dream').length
          : repo.experiences(includeUnverified: true).length;
      expect(artifacts, 1);
      await expectLater(dream.accept(id), throwsStateError);
    });
  }

  for (final change in ['delete', 'disable', 'narrow', 'expire']) {
    test('duplicate rejects $change to its kept source', () async {
      await repo.saveMemory(content: '重复事实', source: 'user');
      await repo.saveMemory(content: '重复事实', source: 'user');
      final run = await dream.run();
      final proposal = dream.proposals(runId: run.id).single;
      final keep = proposal.payload['keepId'] as String;
      switch (change) {
        case 'delete':
          await repo.deleteMemory(keep);
        case 'disable':
          await repo.setMemoryDisabled(keep, true);
        case 'narrow':
          await repo.narrowMemoryScope(keep, AssistantScope.workspace('w'));
        case 'expire':
          await repo.saveMemory(id: keep, content: '重复事实', source: 'user',
            expiresAt: DateTime.utc(2000));
      }
      final before = jsonEncode(repo.organizationSnapshot());
      await expectLater(dream.accept(proposal.id), throwsStateError);
      expect(jsonEncode(repo.organizationSnapshot()), before);
    });
  }

  test('accept cannot erase an earlier user change from the revert guard', () async {
    await repo.saveMemory(content: '重复', source: 'user');
    await repo.saveMemory(content: '重复', source: 'user');
    final run = await dream.run();
    await repo.saveMemory(content: '新增用户记忆', source: 'user');
    await dream.accept(dream.proposals(runId: run.id).single.id);
    final before = jsonEncode(repo.organizationSnapshot());
    await expectLater(dream.revert(run.id), throwsStateError);
    expect(jsonEncode(repo.organizationSnapshot()), before);
  });

  test('revert and accepted status survive reopening the database', () async {
    await repo.saveMemory(content: '重复', source: 'user');
    await repo.saveMemory(content: '重复', source: 'user');
    final run = await dream.run();
    final proposal = dream.proposals(runId: run.id).single;
    await dream.accept(proposal.id);
    await storage.close();
    storage = StorageManager(dir.path);
    repo = FoundationRepository(await storage.open('muyon', WorkspaceRepository.schema));
    dream = DreamService(repo);
    await expectLater(dream.accept(proposal.id), throwsStateError);
    await dream.revert(run.id);
    expect(repo.memories(), hasLength(2));
    expect(dream.proposals(runId: run.id).single.status, 'reverted');
  });

  test('failed revert rolls back snapshot and proposal state together', () async {
    await repo.saveMemory(content: '重复', source: 'user');
    await repo.saveMemory(content: '重复', source: 'user');
    final run = await dream.run();
    await dream.accept(dream.proposals(runId: run.id).single.id);
    final before = jsonEncode(repo.organizationSnapshot());
    repo.database.raw.execute("CREATE TRIGGER fail_revert BEFORE UPDATE OF status ON dream_runs WHEN NEW.status='reverted' BEGIN SELECT RAISE(ABORT, 'injected crash boundary'); END");
    await expectLater(dream.revert(run.id), throwsA(isA<Exception>()));
    expect(jsonEncode(repo.organizationSnapshot()), before);
    expect(dream.proposals(runId: run.id).single.status, 'accepted');
    expect(dream.runRecord(run.id)!.status, 'done');
    repo.database.raw.execute('DROP TRIGGER fail_revert');
    await dream.revert(run.id);
    expect(repo.memories(), hasLength(2));
  });

  for (final kind in ['summary', 'experience']) {
    test('$kind rechecks a source changed in the pending write queue', () async {
      final source = await repo.saveMemory(content: '证据', source: 'user');
      final run = await dream.run();
      final id = 'queued-$kind';
      _insertProposal(repo, run.id, id, kind, source);
      final pending = repo.setMemoryDisabled(source, true);
      final accepting = dream.accept(id);
      await pending;
      await expectLater(accepting, throwsStateError);
      expect(repo.memories(includeDisabled: true), hasLength(1));
      expect(repo.experiences(includeUnverified: true), isEmpty);
    });

    test('$kind concurrent accepts commit only one artifact', () async {
      final source = await repo.saveMemory(content: '证据', source: 'user');
      final run = await dream.run();
      final id = 'concurrent-$kind';
      _insertProposal(repo, run.id, id, kind, source);
      final outcomes = await Future.wait([
        for (var i = 0; i < 2; i++)
          dream.accept(id).then((_) => true, onError: (Object _) => false),
      ]);
      expect(outcomes.where((accepted) => accepted), hasLength(1));
      expect(kind == 'summary'
          ? repo.memories().where((m) => m.source == 'dream').length
          : repo.experiences(includeUnverified: true).length, 1);
    });
  }

  test('legacy run without a persistent guard cannot restore the database', () async {
    await repo.saveMemory(content: '原始', source: 'user');
    final run = await dream.run();
    repo.database.raw.execute('UPDATE dream_runs SET outputs_json=? WHERE id=?',
      [jsonEncode({'proposals': [], 'error': null}), run.id]);
    final before = jsonEncode(repo.organizationSnapshot());
    await expectLater(dream.revert(run.id), throwsStateError);
    expect(jsonEncode(repo.organizationSnapshot()), before);
  });

  test('pending user deletion wins over revert at the transaction boundary', () async {
    final source = await repo.saveMemory(content: '用户事实', source: 'user');
    final run = await dream.run();
    final pending = repo.deleteMemory(source);
    final reverting = dream.revert(run.id);
    await pending;
    await expectLater(reverting, throwsStateError);
    expect(repo.memories(includeDisabled: true), isEmpty);
    expect(repo.deletedContent('用户事实'), isTrue);
  });

  test('accept rejects a proposal from a running run', () async {
    final source = await repo.saveMemory(content: '证据', source: 'user');
    final run = await dream.run(leaveRunning: true);
    _insertProposal(repo, run.id, 'unfinished', 'summary', source);
    await expectLater(dream.accept('unfinished'), throwsStateError);
    expect(repo.memories(), hasLength(1));
  });

  for (final change in ['verify', 'retire']) {
    test('revert preserves later experience $change', () async {
      final experience = await repo.saveExperience(
        content: '用户经验', source: 'user', evidence: [],
      );
      final run = await dream.run();
      if (change == 'verify') {
        await repo.verifyExperience(experience);
      } else {
        await repo.retireExperience(experience);
      }
      final before = jsonEncode(repo.organizationSnapshot());
      await expectLater(dream.revert(run.id), throwsStateError);
      expect(jsonEncode(repo.organizationSnapshot()), before);
    });
  }

  test('user deletion guard remains durable after reopening', () async {
    final source = await repo.saveMemory(content: '删除的事实', source: 'user');
    final run = await dream.run();
    await repo.deleteMemory(source);
    await storage.close();
    storage = StorageManager(dir.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    dream = DreamService(repo);
    await expectLater(dream.revert(run.id), throwsStateError);
    expect(repo.deletedContent('删除的事实'), isTrue);
    expect(repo.memories(includeDisabled: true), isEmpty);
  });

  test(
    'delete and disable leave assistant context and block reintroduction',
    () async {
      final source = await repo.saveMemory(content: '唯一事实', source: 'user');
      final derived = await repo.saveMemory(
        content: '由唯一事实整理',
        source: 'dream',
        kind: 'summary',
        inference: true,
        verified: false,
        lineage: [
          {'id': source, 'revision': 1},
        ],
      );
      final experience = await repo.saveExperience(
        content: '候选经验',
        source: 'dream',
        evidence: [
          {'id': source, 'revision': 1},
        ],
      );
      await repo.deleteMemory(source);
      final left = repo.memories(includeExpired: true, includeDisabled: true);
      expect(left.map((memory) => memory.id), isNot(contains(source)));
      expect(left.map((memory) => memory.id), isNot(contains(derived)));
      expect(repo.experience(experience)!.status, 'retired');
      await expectLater(
        repo.saveMemory(id: source, content: '唯一事实', source: 'user'),
        throwsStateError,
      );
      await expectLater(
        repo.saveExperience(
          content: '候选经验',
          source: 'dream',
          evidence: const [],
        ),
        throwsStateError,
      );

      final hidden = await repo.saveMemory(content: '停用我', source: 'user');
      await repo.setMemoryDisabled(hidden, true);
      final global = await repo.createConversation();
      final agent = _agent(repo);
      final task = await agent.start(
        conversationId: global.id,
        prompt: 'hello',
      );
      expect(jsonEncode(task.payload['messages']), isNot(contains('停用我')));
      expect(jsonEncode(task.payload['messages']), isNot(contains('候选经验')));
    },
  );

  test(
    'narrowed scope propagates and verified experience is the only one used',
    () async {
      final source = await repo.saveMemory(content: '全局事实', source: 'user');
      await repo.saveMemory(
        content: '派生事实',
        source: 'dream',
        lineage: [
          {'id': source, 'revision': 1},
        ],
      );
      await repo.narrowMemoryScope(source, AssistantScope.workspace('w'));
      expect(repo.memories().map((memory) => memory.scope.kind).toSet(), {
        AssistantScopeKind.workspace,
      });
      final experience = await repo.saveExperience(
        content: '未确认经验',
        source: 'user',
        scope: AssistantScope.workspace('w'),
        evidence: const [],
      );
      final agent = _agent(repo);
      final global = await repo.createConversation();
      final hidden = await agent.start(
        conversationId: global.id,
        prompt: 'hello',
      );
      expect(jsonEncode(hidden.payload['messages']), isNot(contains('全局事实')));
      expect(jsonEncode(hidden.payload['messages']), isNot(contains('未确认经验')));
      await dream.observeSuccess(experience);
      expect(repo.experience(experience)!.status, 'candidate');
      await repo.verifyExperience(experience);
      final workspace = await repo.createConversation(
        scope: AssistantScope.workspace('w'),
      );
      final visible = await agent.start(
        conversationId: workspace.id,
        prompt: 'hello',
      );
      final encoded = jsonEncode(visible.payload['messages']);
      expect(encoded, contains('全局事实'));
      expect(encoded, contains('派生事实'));
      expect(encoded, contains('未确认经验'));
    },
  );

  test(
    'dream holds no tool approval and records a model call only with a profile',
    () async {
      var calls = 0;
      final tools = ToolRegistry(
        database: repo.database,
        resolveScope: (scope) async =>
            ResolvedAssistantScope(requested: scope, objects: const []),
      );
      tools.register(
        providerId: 'test',
        descriptor: ToolDescriptor(
          toolId: 'knowledge.delete',
          moduleId: 'knowledge',
          effect: ToolEffect.write,
          parameterSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        handler: (_) async {
          calls++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'no',
          );
        },
      );
      await dream.run();
      expect(calls, 0);
      expect(repo.database.raw.select('SELECT * FROM tool_approvals'), isEmpty);
      expect(
        repo.database.raw.select('SELECT * FROM tool_invocation_receipts'),
        isEmpty,
      );

      final memory = await repo.saveMemory(content: '需要摘要的笔记', source: 'user');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'summaries': [
                      {
                        'content': '一条摘要',
                        'evidenceIds': [memory],
                      },
                    ],
                    'conflicts': [
                      {
                        'summary': '可能冲突',
                        'evidenceIds': [memory],
                      },
                    ],
                    'experiences': [
                      {
                        'content': '一次成功不是规则',
                        'evidenceIds': [memory],
                      },
                    ],
                  }),
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      final modeled = DreamService(
        repo,
        gateway: OpenAiModelGateway(
          UnavailableSecretStore(),
          ledger: OutboundLedger(repo.database),
        ),
      );
      final run = await modeled.run(
        profile: ModelProfile(
          id: 'dream-local',
          endpoint: Uri.parse(
            'http://127.0.0.1:${server.port}/v1/chat/completions',
          ),
          location: ModelLocation.local,
          modelId: 'fixture',
          endpointIdentity: 'loopback',
        ),
      );
      expect(run.modelProfileId, 'dream-local');
      expect(run.outboundIds, hasLength(1));
      expect(run.tokenCost, isNotNull);
      expect(
        repo.database.raw
            .select('SELECT caller FROM outbound_requests')
            .single['caller'],
        'dream',
      );
      final summary = modeled
          .proposals(runId: run.id)
          .singleWhere((proposal) => proposal.kind == 'summary');
      await modeled.accept(summary.id);
      final created = repo
          .memories(includeDisabled: true)
          .singleWhere((item) => item.kind == 'summary');
      expect(created.verified, isFalse);
      expect(created.inference, isTrue);
      final experience = modeled
          .proposals(runId: run.id)
          .singleWhere((proposal) => proposal.kind == 'experience');
      await modeled.accept(experience.id);
      expect(
        repo
            .experience(repo.experiences(includeUnverified: true).single.id)!
            .status,
        'candidate',
      );
      expect(calls, 0);
      await expectLater(
        modeled.accept(
          modeled
              .proposals(runId: run.id)
              .singleWhere((item) => item.kind == 'conflict')
              .id,
        ),
        throwsStateError,
      );
    },
  );
}

PersonalAgent _agent(FoundationRepository repo) => PersonalAgent(
  repository: repo,
  gateway: OpenAiModelGateway(
    UnavailableSecretStore(),
    clientFactory: () => throw StateError('no model'),
  ),
  tools: ToolRegistry(
    database: repo.database,
    resolveScope: (scope) async =>
        ResolvedAssistantScope(requested: scope, objects: const []),
  ),
);

void _insertProposal(FoundationRepository repo, String runId, String id,
    String kind, String source) {
  repo.database.raw.execute(
    'INSERT INTO dream_proposals(id,run_id,kind,evidence_json,payload_json,status) VALUES(?,?,?,?,?,?)',
    [id, runId, kind, jsonEncode([{'id': source, 'revision': 1}]),
      jsonEncode({'content': '整理产物'}), 'proposed'],
  );
}
