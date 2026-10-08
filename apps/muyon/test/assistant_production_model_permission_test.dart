import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_provider.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  for (final (native, location) in [
    (true, ModelLocation.local),
    (false, ModelLocation.local),
    (true, ModelLocation.ownDevice),
  ]) {
    test(
      'actual host local model has explicit mode_auto source / native=$native location=$location',
      () async {
        const channel = MethodChannel('com.mightyoung.muyon/secrets');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (call) async => call.method == 'read' ? loopKey : null,
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final loop = await LoopFixture.open();
        final root = Directory.systemTemp.createTempSync(
          'auth-model-permission-',
        );
        final host = await MuyonHost.open(root.path);
        addTearDown(() async {
          await host.close();
          root.deleteSync(recursive: true);
        });
        final conversation = await host.foundation.createConversation();
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
        final task = await host.personalAgent.start(
          conversationId: conversation.id,
          prompt: 'answer directly',
          profile: loop.profile(
            location: location,
            capabilities: ModelCapabilities(
              streaming: true,
              nativeTools: native,
              source: CapabilitySource.userDeclared,
            ),
          ),
        );
        expect(task.state, PersonalTaskState.succeeded);
        expect(loop.bodies, hasLength(1));
        final row = host.outbound.recent().single;
        expect(row['authorization_source'], 'mode_auto');
        expect(row['grant_id'], isNull);
        expect(row['review_decision_id'], isNotNull);
        final review = host.foundation.database.raw.select(
          'SELECT * FROM assistant_review_decisions WHERE id=?',
          [row['review_decision_id']],
        ).single;
        expect(review['reviewed'], 0);
        expect(review['decision'], 'allow');
        expect(review['payload_digest'], row['payload_sha256']);
        expect(
          host.foundation.database.raw.select(
            'SELECT * FROM assistant_grant_audit',
          ),
          isEmpty,
        );
      },
    );
  }
}
