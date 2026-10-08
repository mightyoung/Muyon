import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/model_request_gate.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_provider.dart';
import 'package:muyon/services/models/openai_compat_provider.dart';

import 'support/agent_loop_fixture.dart';

final class ChangingProvider extends OpenAiCompatProvider {
  int calls = 0;
  @override
  Map<String, Object?> encode(ModelRequest request) {
    final body = super.encode(request);
    if (++calls > 1) {
      body['messages'] = [
        ...body['messages'] as List,
        {'role': 'user', 'content': 'unreviewed wire change'},
      ];
    }
    return body;
  }
}

void main() {
  for (final corruptReview in [false, true]) {
    test(
      'actual gateway rejects changed wire or independent review record / review=$corruptReview',
      () async {
        final loop = await LoopFixture.open();
        final root = Directory.systemTemp.createTempSync('auth-model-binding-');
        final host = await MuyonHost.open(root.path);
        final actor = corruptReview
            ? host.personalAgent
            : PersonalAgent(
                repository: host.foundation,
                gateway: host.services.gateway,
                tools: host.tools,
                gate: HostPolicyModelGate(host.authorizationPolicy),
                modelAuthorization: host.personalAgent.modelAuthorization,
                provider: ChangingProvider(),
              );
        addTearDown(() async {
          if (!corruptReview) await actor.close();
          await host.close();
          root.deleteSync(recursive: true);
        });
        if (corruptReview) {
          await host.foundation.database.write(
            (db) => db.execute(
              "CREATE TRIGGER auth_corrupt_model_review AFTER INSERT ON assistant_review_decisions BEGIN UPDATE assistant_review_decisions SET decision='block' WHERE id=NEW.id; END",
            ),
          );
        }
        final c = await host.foundation.createConversation();
        loop.replies.add(
          LoopReply.sse(sseText('unreviewed effect must not send')),
        );
        final task = await actor.start(
          conversationId: c.id,
          prompt: 'send only the frozen reviewed wire',
          profile: loop.profile(),
        );
        expect(task.state, PersonalTaskState.failed);
        expect(loop.bodies, isEmpty);
        expect(host.outbound.recent(), isEmpty);
        expect(host.assistantGrants.list(), isEmpty);
      },
    );
  }
}
