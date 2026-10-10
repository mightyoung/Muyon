import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/agent_budget.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon/workspace/workspace_repository.dart';

/// A real, reopenable database and registry; no model or network is used.
class _Host {
  final root = Directory.systemTemp.createTempSync('manual-resume-hold-');
  late StorageManager storage;
  late FoundationRepository repo;
  late ToolRegistry tools;
  late PersonalAgent agent;
  var invocations = 0;
  var now = DateTime.utc(2026, 10, 10);

  Future<void> open() async {
    storage = StorageManager(root.path);
    final db = await storage.open('muyon', WorkspaceRepository.schema);
    repo = FoundationRepository(db);
    tools = ToolRegistry(
      database: db,
      resolveScope: (scope) async => ResolvedAssistantScope(
        requested: scope, objects: scope.objects,
      ),
    );
    tools.register(
      providerId: 'test',
      descriptor: ToolDescriptor(
        toolId: 'write', moduleId: 'test', effect: ToolEffect.write,
        parameterSchema: {
          'type': 'object',
          'properties': {'note': {'type': 'string'}},
          'additionalProperties': false,
        },
      ),
      handler: (_) async {
        invocations++;
        now = now.add(const Duration(seconds: 20));
        return ToolCallResult(
          status: ToolCallStatus.succeeded, summary: 'effect persisted',
        );
      },
    );
    agent = PersonalAgent(
      repository: repo, tools: tools,
      gateway: OpenAiModelGateway(UnavailableSecretStore()),
      clock: () => now,
    );
  }

  Future<void> reopen() async {
    await agent.close();
    await storage.close();
    await open();
  }

  Future<void> close() async {
    await agent.close();
    await storage.close();
    root.deleteSync(recursive: true);
  }

  int get approvals => repo.database.raw.select(
    'SELECT * FROM tool_approvals',
  ).length;
}

void main() {
  for (final reopen in [false, true]) {
    for (final receiptState in ['succeeded', 'running']) {
      for (final identity in ['mismatch', 'missing', 'malformed', 'matching']) {
        if (identity == 'matching' && receiptState == 'succeeded') continue;
        test('manual $receiptState/$identity hold survives three resumes '
            'with database reopen=$reopen', () async {
          final h = _Host();
          await h.open();
          addTearDown(h.close);
          final conversation = await h.repo.createConversation();
          final original = await h.agent.startTool(
            conversationId: conversation.id, toolId: 'write',
          );
          final call = original.payload['toolCall'] as Map;
          final originalId = call['invocationId'];
          if (receiptState == 'succeeded') {
            // Actual effect and registry receipt, then crash before task state.
            await h.agent.confirm(original.id,
              requestDigest: original.payload['requestDigest'] as String);
            expect(h.invocations, 1);
          } else {
            await h.repo.database.write((db) => db.execute(
              'INSERT INTO tool_invocation_receipts('
              'replay_key,invocation_id,identity_digest,tool_id,state) '
              'VALUES(?,?,?,?,?)',
              [originalId, originalId, original.payload['toolIdentityDigest'],
                'write', receiptState],
            ));
          }
          Object? digest = original.payload['toolIdentityDigest'];
          if (identity == 'mismatch') {
            digest = (await h.tools.prepare(ToolCallRequest(
              invocationId: originalId as String, toolId: 'write',
              scope: original.scope, parameters: const {'note': 'other'},
            ))).identityDigest;
            expect(digest, isNot(original.payload['toolIdentityDigest']));
          } else if (identity == 'missing') {
            digest = null;
          } else if (identity == 'malformed') {
            digest = 17;
          }
          // Preserve a nonzero host checkpoint, including the spent tool time.
          final usage = BudgetUsage.fromPayload(h.repo.task(original.id)!.payload)
              .plus(tokens: 11, estimated: true);
          await h.repo.updateTask(h.repo.task(original.id)!.copy({
            ...usage.toPayload(), 'toolIdentityDigest': digest,
            'state': 'interrupted', 'stage': 'interrupted',
          }));
          final effects = h.invocations;
          final approvals = h.approvals;
          var held = await h.agent.resume(original.id);
          expect(held.stage, 'resume');

          for (var i = 0; i < 3; i++) {
            final priorId = held.id;
            await h.agent.pause(held.id);
            if (reopen) await h.reopen();
            held = await h.agent.resume(held.id);
            expect(held.stage, 'resume',
              reason: 'pause/resume is not acknowledgement of verification');
            expect(held.state, PersonalTaskState.waitingConfirmation);
            expect(held.previousAttemptId, priorId);
            expect((held.payload['toolCall'] as Map)['invocationId'], originalId);
            expect(held.payload['toolIdentityDigest'], digest);
            expect(BudgetUsage.fromPayload(held.payload).toPayload(),
                usage.toPayload());
            expect(h.invocations, effects);
            expect(h.approvals, approvals);
            expect(jsonEncode(held.payload['messages']),
                isNot(contains('effect persisted')));
          }

          // Acknowledgement must consume this stop, and issue a fresh tool card.
          final heldDigest = held.payload['requestDigest'] as String;
          await expectLater(h.agent.confirm(held.id, requestDigest: 'wrong'),
              throwsStateError);
          await h.agent.confirm(held.id, requestDigest: heldDigest);
          final fresh = h.repo.task(held.id)!;
          expect(fresh.stage, 'tool');
          expect(fresh.state, PersonalTaskState.waitingConfirmation);
          expect((fresh.payload['toolCall'] as Map)['invocationId'],
              isNot(originalId));
          expect(h.invocations, effects);
          expect(h.approvals, approvals);
          await expectLater(h.agent.confirm(fresh.id, requestDigest: heldDigest),
              throwsStateError);
          await h.agent.confirm(fresh.id,
              requestDigest: fresh.payload['requestDigest'] as String);
          expect(h.invocations, effects + 1,
              reason: 'only the independent new tool confirmation executes');
          expect(h.approvals, approvals + 1);
          await expectLater(h.agent.confirm(fresh.id,
              requestDigest: fresh.payload['requestDigest'] as String),
              throwsStateError);
          expect(h.invocations, effects + 1);
        });
      }
    }
  }
}
