import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  for (final configured in [false, true]) {
    test(
      'actual disk restore profile authority comes from current host config / configured=$configured',
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
        final root = Directory.systemTemp.createTempSync('auth-model-restore-');
        var host = await MuyonHost.open(root.path);
        addTearDown(() async {
          await host.close();
          root.deleteSync(recursive: true);
        });
        final profile = loop.profile(location: ModelLocation.ownDevice);
        if (configured) await ProfileRepository(host.workspaces).save(profile);
        final c = await host.foundation.createConversation();
        loop.replies.add(const LoopReply.status(503));
        final failed = await host.personalAgent.start(
          conversationId: c.id,
          prompt: 'request to resume later',
          profile: profile,
        );
        expect(failed.state, PersonalTaskState.failed);
        expect(loop.bodies, hasLength(1));
        await host.close();
        host = await MuyonHost.open(root.path);
        loop.replies.add(LoopReply.sse(sseText('actual resumed response')));
        final resumed = await host.personalAgent.resume(failed.id);
        expect(
          resumed.state,
          configured
              ? PersonalTaskState.succeeded
              : PersonalTaskState.waitingConfirmation,
        );
        expect(loop.bodies, hasLength(configured ? 2 : 1));
        expect(host.outbound.recent(), hasLength(configured ? 2 : 1));
        if (configured) {
          expect(
            host.outbound.recent().first['authorization_source'],
            'mode_auto',
          );
          expect(host.outbound.recent().first['grant_id'], isNull);
        }
      },
    );
  }
}
