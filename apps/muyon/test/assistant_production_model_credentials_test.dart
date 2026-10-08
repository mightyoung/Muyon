import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon/services/models/model_gateway.dart';

import 'support/agent_loop_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'actual credential RPC wait is cancellable before ledger or wire',
    () async {
      const channel = MethodChannel('com.mightyoung.muyon/secrets');
      final entered = Completer<void>();
      final release = Completer<String>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (!entered.isCompleted) entered.complete();
            return release.future;
          });
      final loop = await LoopFixture.open();
      final root = Directory.systemTemp.createTempSync(
        'auth-model-credentials-',
      );
      final host = await MuyonHost.open(root.path);
      addTearDown(() async {
        if (!release.isCompleted) release.complete(loopKey);
        await host.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        root.deleteSync(recursive: true);
      });
      final c = await host.foundation.createConversation();
      loop.replies.add(
        LoopReply.sse(sseText('credentials cancelled must not send')),
      );
      final pending = host.personalAgent.start(
        conversationId: c.id,
        prompt: 'cancel during credential await',
        profile: loop.profile(location: ModelLocation.ownDevice),
      );
      await entered.future.timeout(const Duration(seconds: 5));
      final id = host.foundation.tasks(conversationId: c.id).single.id;
      await withConfirmedHostUiGrant(
        (token) => host.authorizationPolicy.update(
          token: token,
          mode: AssistantAuthorizationMode.standard,
          enabled: Set.of(AssistantAuthorizationCategory.values)
            ..remove(AssistantAuthorizationCategory.model),
        ),
      );
      final task = await pending.timeout(
        const Duration(seconds: 2),
        onTimeout: () => host.foundation.task(id)!,
      );
      expect(task.state, PersonalTaskState.failed);
      expect(loop.bodies, isEmpty);
      expect(host.outbound.recent(), isEmpty);
      expect(
        host.foundation.database.raw.select(
          'SELECT * FROM assistant_grant_audit',
        ),
        isEmpty,
      );
    },
  );
}
