import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  for (final provider in ['mcp:fixture', 'inquiry', 'knowledge', 'research']) {
    test('$provider read is persistently tainted before handler', () async {
      final f = await LoopFixture.open();
      var handlers = 0;
      f.tools.register(
        providerId: provider,
        descriptor: ToolDescriptor(
          toolId: 'remote',
          moduleId: provider == 'mcp:fixture' ? 'mcp' : provider,
          effect: ToolEffect.read,
          parameterSchema: const {
            'type': 'object',
            'properties': <String, Object?>{},
          },
        ),
        handler: (_) async {
          handlers++;
          final row = f.repo.database.raw
              .select(
                "SELECT id FROM execution_records WHERE json_extract(payload,'\$.kind')='personal'",
              )
              .single;
          expect(
            f.repo.authorizationFacts.readTask(row['id'] as String).taintState,
            HostTaintState.tainted,
          );
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'external',
            data: {'taskTainted': false, 'taintKnown': true},
            objectRefs: [f.ref],
          );
        },
      );
      final conversation = await f.repo.createConversation();
      final task = await f.agent().startTool(
        conversationId: conversation.id,
        toolId: 'remote',
      );
      expect(task.state, PersonalTaskState.succeeded);
      expect(handlers, 1);
      expect(
        f.repo.authorizationFacts.readTask(task.id).taintState,
        HostTaintState.tainted,
      );
      expect(
        f.repo.authorizationFacts.readTask(task.id).sourceDigests,
        contains(HostSourceFact.object(f.ref).identityDigest),
      );
    });
  }

  test(
    'source marker failure is zero external handlers and no accepted content',
    () async {
      final f = await LoopFixture.open();
      var handlers = 0;
      f.tools.register(
        providerId: 'mcp:fixture',
        descriptor: ToolDescriptor(
          toolId: 'remote',
          moduleId: 'mcp',
          effect: ToolEffect.read,
          parameterSchema: const {
            'type': 'object',
            'properties': <String, Object?>{},
          },
        ),
        handler: (_) async {
          handlers++;
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: 'never accepted',
          );
        },
      );
      f.repo.database.raw.execute(
        "CREATE TEMP TRIGGER deny_marker BEFORE INSERT ON settings WHEN NEW.key LIKE 'auth1b:source:%' BEGIN SELECT RAISE(ABORT,'marker'); END",
      );
      final conversation = await f.repo.createConversation();
      final task = await f.agent().startTool(
        conversationId: conversation.id,
        toolId: 'remote',
      );
      expect(task.state, PersonalTaskState.failed);
      expect(handlers, 0);
      expect(f.receipts(), isEmpty);
      expect(
        f.repo.authorizationFacts.readTask(task.id).requiresConfirmation,
        isTrue,
      );
    },
  );
}
