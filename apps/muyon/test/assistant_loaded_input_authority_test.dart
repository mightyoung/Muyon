import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon/services/models/model_gateway.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  test(
    'public fresh Agent proves actually loaded empty host context',
    () async {
      final f = await LoopFixture.open();
      final agent = PersonalAgent(
        repository: f.repo,
        tools: f.tools,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      );
      addTearDown(agent.close);
      final c = await f.repo.createConversation();
      final task = await agent.start(conversationId: c.id, prompt: 'hello');
      expect(
        f.repo.authorizationFacts.readTask(task.id).taintState,
        HostTaintState.clean,
      );
      final second = await agent.start(conversationId: c.id, prompt: 'again');
      expect(
        f.repo.authorizationFacts.readTask(second.id).taintState,
        HostTaintState.unknown,
        reason: 'old history has no proven input lineage',
      );
    },
  );
  for (final input in ['history', 'memory', 'experience']) {
    test(
      'actual loaded $input is unknown even with no object references',
      () async {
        final f = await LoopFixture.open();
        final agent = PersonalAgent(
          repository: f.repo,
          tools: f.tools,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        );
        addTearDown(agent.close);
        final c = await f.repo.createConversation();
        if (input == 'history') {
          await f.repo.appendMessage(
            c.id,
            'assistant',
            'unproven imported text',
          );
        } else if (input == 'experience') {
          final id = await f.repo.saveExperience(
            content: 'unproven experience',
            source: 'import',
            evidence: [],
          );
          await f.repo.verifyExperience(id);
        } else {
          await f.repo.saveMemory(
            content: 'verified is not clean provenance',
            source: 'import',
          );
        }
        final task = await agent.start(conversationId: c.id, prompt: 'hello');
        expect(task.objectRefs, isEmpty);
        expect(
          f.repo.authorizationFacts.readTask(task.id).taintState,
          HostTaintState.unknown,
        );
      },
    );
  }
  PersonalTask queued(String conversation, String id) => PersonalTask({
    'kind': 'personal',
    'executionId': id,
    'conversationId': conversation,
    'prompt': 'actual host user instruction',
    'state': 'queued',
    'stage': 'queued',
    'executionDeviceId': 'host',
    'scope': const AssistantScope.global().toJson(),
    'messages': <Object?>[],
    'references': <Object?>[],
    'profile': null,
    'createdAt': '2026-10-08T00:00:00.000Z',
    'updatedAt': '2026-10-08T00:00:00.000Z',
  });
  for (final mutation in ['memory', 'history', 'task', 'owner']) {
    test(
      'opaque input proof rejects $mutation change at actual owner create',
      () async {
        final f = await LoopFixture.open();
        final c = await f.repo.createConversation();
        final original = queued(c.id, 'proof-task');
        final bound = f.repo.bindLoadedInputs(
          original,
          history: [],
          memories: [],
        );
        expect(bound.loadedInputProof, isNotNull);
        var submit = bound;
        var owner = f.repo;
        if (mutation == 'memory') {
          await f.repo.saveMemory(
            content: 'arrived after actual load',
            source: 'external',
          );
        } else if (mutation == 'history') {
          await f.repo.appendMessage(
            c.id,
            'assistant',
            'arrived after actual load',
          );
        } else if (mutation == 'task') {
          submit = PersonalTask({
            ...bound.payload,
            'executionId': 'other',
            'clean': true,
          }, loadedInputProof: bound.loadedInputProof);
        } else {
          final other = await LoopFixture.open();
          final otherC = await other.repo.createConversation();
          await other.repo.database.write(
            (db) => db.execute('UPDATE conversations SET id=? WHERE id=?', [
              c.id,
              otherC.id,
            ]),
          );
          owner = other.repo;
          submit = bound; // Same bytes and IDs, different real DB owner.
        }
        await owner.createTask(submit);
        expect(
          owner.authorizationFacts.readTask(submit.id).taintState,
          HostTaintState.unknown,
        );
      },
    );
  }
  test('fresh proof cannot erase prior persisted source taint', () async {
    final f = await LoopFixture.open();
    await f.repo.authorizationFacts.markSourceExternal(
      HostSourceFact.project('inquiry', 'p'),
    );
    final c = await f.repo.createConversation();
    final bound = f.repo.bindLoadedInputs(
      queued(c.id, 'tainted'),
      history: [],
      memories: [],
    );
    await f.repo.createTask(bound);
    expect(
      f.repo.authorizationFacts.readTask(bound.id).taintState,
      HostTaintState.tainted,
    );
  });
  for (final kind in [
    'unknown-source',
    'malformed-source',
    'unknown-conversation',
  ]) {
    test(
      'fresh context does not promote existing $kind authority to clean',
      () async {
        final f = await LoopFixture.open();
        final c = await f.repo.createConversation();
        final key = kind == 'unknown-conversation'
            ? 'auth1b:conversation:${c.id}'
            : 'auth1b:source:old';
        await f.repo.database.write(
          (db) => db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
            key,
            kind == 'malformed-source'
                ? '{broken'
                : jsonEncode({
                    'version': 1,
                    'taintState': 'unknown',
                    'sourceDigests': [],
                  }),
          ]),
        );
        final agent = PersonalAgent(
          repository: f.repo,
          tools: f.tools,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        );
        addTearDown(agent.close);
        final task = await agent.start(conversationId: c.id, prompt: 'hello');
        expect(
          f.repo.authorizationFacts.readTask(task.id).taintState,
          HostTaintState.unknown,
        );
      },
    );
  }
  test(
    'new external source immediately narrows existing clean global task',
    () async {
      final f = await LoopFixture.open();
      final c = await f.repo.createConversation();
      final agent = PersonalAgent(
        repository: f.repo,
        tools: f.tools,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      );
      addTearDown(agent.close);
      final task = await agent.start(conversationId: c.id, prompt: 'hello');
      expect(
        f.repo.authorizationFacts.readTask(task.id).taintState,
        HostTaintState.clean,
      );
      await f.repo.authorizationFacts.markSourceExternal(
        HostSourceFact.project('inquiry', 'p'),
      );
      final facts = f.repo.authorizationFacts.readTask(task.id);
      expect(facts.taintState, HostTaintState.tainted);
      expect(
        jsonDecode(
          f.repo.database.raw.select('SELECT value FROM settings WHERE key=?', [
                'auth1b:task:${task.id}',
              ]).single['value']
              as String,
        )['taintState'],
        'tainted',
      );
      expect(
        facts.sourceDigests,
        contains(HostSourceFact.project('inquiry', 'p').identityDigest),
      );
    },
  );
  for (final matches in [true, false]) {
    test(
      'late source matches selected stable project identity: $matches',
      () async {
        final f = await LoopFixture.open();
        final scope = AssistantScope.selectedObjects([
          const ObjectRef(
            moduleId: 'inquiry',
            objectType: 'project_item',
            objectId: 'i',
            nativeProjectId: 'p',
            revisionRef: 'v2',
          ),
        ]);
        final c = await f.repo.createConversation(scope: scope);
        final agent = PersonalAgent(
          repository: f.repo,
          tools: f.tools,
          gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
        );
        addTearDown(agent.close);
        final task = await agent.start(conversationId: c.id, prompt: 'hello');
        expect(
          f.repo.authorizationFacts.readTask(task.id).taintState,
          HostTaintState.clean,
        );
        await f.repo.authorizationFacts.markSourceExternal(
          HostSourceFact.project('inquiry', matches ? 'p' : 'outside'),
        );
        expect(
          f.repo.authorizationFacts.readTask(task.id).taintState,
          matches ? HostTaintState.tainted : HostTaintState.clean,
        );
      },
    );
  }
  test(
    'queued source acceptance narrows clean facts before its owner write',
    () async {
      final f = await LoopFixture.open();
      final c = await f.repo.createConversation();
      final agent = PersonalAgent(
        repository: f.repo,
        tools: f.tools,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      );
      addTearDown(agent.close);
      final task = await agent.start(conversationId: c.id, prompt: 'hello');
      final entered = Completer<void>(), release = Completer<void>();
      final held = (f.repo.database as ExclusiveDatabase).exclusiveAsync((
        _,
      ) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final marker = f.repo.authorizationFacts.markSourceExternal(
        HostSourceFact.project('inquiry', 'pending'),
      );
      try {
        expect(
          f.repo.authorizationFacts.readTask(task.id).taintState,
          HostTaintState.tainted,
        );
      } finally {
        release.complete();
        await held;
        await marker;
      }
    },
  );
  test('failed source acceptance keeps clean task denial latched', () async {
    final f = await LoopFixture.open();
    final c = await f.repo.createConversation();
    final agent = PersonalAgent(
      repository: f.repo,
      tools: f.tools,
      gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
    );
    addTearDown(agent.close);
    final task = await agent.start(conversationId: c.id, prompt: 'hello');
    f.repo.database.raw.execute(
      "CREATE TEMP TRIGGER deny_source BEFORE INSERT ON settings WHEN NEW.key LIKE 'auth1b:source:%' BEGIN SELECT RAISE(ABORT,'source denied'); END",
    );
    await expectLater(
      f.repo.authorizationFacts.markSourceExternal(
        HostSourceFact.project('inquiry', 'failed'),
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      f.repo.authorizationFacts.readTask(task.id).taintState,
      HostTaintState.tainted,
    );
  });
  test(
    'selected object malformed source metadata never proves clean',
    () async {
      final f = await LoopFixture.open();
      const ref = ObjectRef(
        moduleId: 'inquiry',
        objectType: 'project_item',
        objectId: 'i',
        nativeProjectId: 'p',
      );
      final c = await f.repo.createConversation(
        scope: AssistantScope.selectedObjects([ref]),
      );
      await f.repo.database.write(
        (db) => db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
          'auth1b:source:${HostSourceFact.object(ref).identityDigest}',
          '{broken',
        ]),
      );
      final agent = PersonalAgent(
        repository: f.repo,
        tools: f.tools,
        gateway: OpenAiModelGateway(LoopSecrets(), ledger: f.ledger),
      );
      addTearDown(agent.close);
      final task = await agent.start(conversationId: c.id, prompt: 'hello');
      expect(
        f.repo.authorizationFacts.readTask(task.id).taintState,
        HostTaintState.unknown,
      );
    },
  );
}
