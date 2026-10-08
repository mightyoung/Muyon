import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/tool_names.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/agent_loop_fixture.dart';
import 'support/confirm_model_reviewer.dart';

void main() {
  for (final mode in [
    'disable-before-confirm',
    'revision-before-confirm',
    'readonly-native',
    'readonly-json',
  ]) {
    test('actual host model policy / $mode', () async {
      final loop = await LoopFixture.open();
      final root = Directory.systemTemp.createTempSync('auth-policy-model-');
      final host = await MuyonHost.open(
        root.path,
        localModelReviewer: const ConfirmModelReviewer(),
      );
      addTearDown(() async {
        await host.close();
        root.deleteSync(recursive: true);
      });
      await host.activateInquiry();
      expect(host.tools.inspect('inquiry.set_item_qty'), isNotNull);
      final readonly = mode.startsWith('readonly');
      Future<void> policy(
        AssistantAuthorizationMode value,
        Set<AssistantAuthorizationCategory> enabled,
      ) => withConfirmedHostUiGrant(
        (token) => host.authorizationPolicy.update(
          token: token,
          mode: value,
          enabled: enabled,
        ),
      );
      if (readonly) {
        await policy(
          AssistantAuthorizationMode.readOnly,
          Set.of(AssistantAuthorizationCategory.values),
        );
      }
      final c = await host.foundation.createConversation();
      final native = mode != 'readonly-json';
      loop.replies.add(
        LoopReply.sse(
          sseText(
            native
                ? 'done'
                : jsonEncode({
                    'type': 'answer',
                    'answer': 'done',
                    'citationIds': [],
                  }),
          ),
        ),
      );
      var task = await host.personalAgent.start(
        conversationId: c.id,
        prompt: 'inspect available tool catalog',
        profile: loop.profile(
          capabilities: ModelCapabilities(
            streaming: true,
            nativeTools: native,
            source: CapabilitySource.userDeclared,
          ),
        ),
      );
      expect(task.state, PersonalTaskState.waitingConfirmation);
      if (!readonly) {
        final enabled = Set.of(AssistantAuthorizationCategory.values);
        if (mode == 'disable-before-confirm') {
          enabled.remove(AssistantAuthorizationCategory.model);
        }
        await policy(AssistantAuthorizationMode.standard, enabled);
      }
      await host.personalAgent.confirm(
        task.id,
        requestDigest: task.payload['requestDigest'] as String,
      );
      task = host.foundation.task(task.id)!;
      if (!readonly) {
        expect(task.state, PersonalTaskState.failed);
        expect(loop.bodies, isEmpty);
        expect(host.outbound.recent(), isEmpty);
        return;
      }
      expect(task.state, PersonalTaskState.succeeded);
      expect(loop.bodies, hasLength(1));
      final body = loop.bodies.single;
      final actual = native
          ? [
              for (final t in body['tools'] as List)
                ((t as Map)['function'] as Map)['name'],
            ]
          : [
              for (final t
                  in (jsonDecode(
                        (body['messages'] as List).first['content'] as String,
                      ) as Map)['tools']
                      as List)
                (t as Map)['toolId'],
            ];
      final expected = [
        for (final t in host.tools.list())
          if (t.available &&
              t.descriptor.modelSelectable &&
              t.descriptor.effect == ToolEffect.read)
            native ? encodeToolName(t.descriptor.toolId) : t.descriptor.toolId,
      ];
      expect(actual, unorderedEquals(expected));
      expect(actual, isNotEmpty);
      expect(
        host.foundation.database.raw.select('SELECT * FROM tool_approvals'),
        isEmpty,
      );
      expect(
        host.foundation.database.raw.select(
          'SELECT * FROM tool_invocation_receipts',
        ),
        isEmpty,
      );
    });
  }
}
