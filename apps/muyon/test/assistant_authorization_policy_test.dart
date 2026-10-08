import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/grants/host_authorization_policy.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

void main() {
  final all = Set<AssistantAuthorizationCategory>.of(
    AssistantAuthorizationCategory.values,
  );
  for (final mode in [
    'lifetime',
    'queued',
    'failure',
    'reopen',
    'aba',
    'corrupt-aba',
  ]) {
    test('actual owner policy updates / $mode', () async {
      final root = Directory.systemTemp.createTempSync('auth-policy-owner-');
      var host = await MuyonHost.open(root.path);
      addTearDown(() async {
        await host.close();
        root.deleteSync(recursive: true);
      });
      final owner = host.authorizationPolicy;
      final original = owner.current;
      expect(original.valid, isTrue);
      expect(original.mode, AssistantAuthorizationMode.standard);
      expect(original.allowsTool(ToolEffect.write), isTrue);
      Future<void> update(AssistantAuthorizationMode mode) =>
          withConfirmedHostUiGrant(
            (token) => owner.update(token: token, mode: mode, enabled: all),
          );
      if (mode == 'corrupt-aba') {
        await update(AssistantAuthorizationMode.standard);
        final first = owner.current;
        await host.foundation.database.write(
          (db) => db.execute('UPDATE settings SET value=? WHERE key=?', [
            '{corrupt',
            HostAuthorizationPolicy.settingKey,
          ]),
        );
        expect(owner.current.valid, isFalse);
        await update(AssistantAuthorizationMode.standard);
        expect(owner.current.valid, isTrue);
        expect(
          owner.current.revision,
          isNot(first.revision),
          reason: 'confirmed repair must not revive an old permission after corrupt policy',
        );
        return;
      }
      if (mode == 'lifetime') {
        late HostUiGrantToken expired;
        await withConfirmedHostUiGrant((token) async {
          expired = token;
        });
        await expectLater(
          owner.update(
            token: expired,
            mode: AssistantAuthorizationMode.readOnly,
            enabled: all,
          ),
          throwsStateError,
        );
        expect(owner.current.revision, original.revision);
        expect(owner.current.valid, isTrue);
        return;
      }
      if (mode == 'queued') {
        final entered = Completer<void>(), release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final barrier = (host.foundation.database as ManagedConnection)
            .exclusiveAsync((_) async {
              entered.complete();
              await release.future;
            });
        await entered.future;
        final pending = update(AssistantAuthorizationMode.readOnly);
        expect(owner.current.valid, isFalse);
        expect(
          HostAuthorizationPolicy(host.foundation.database).current
              .allowsTool(ToolEffect.write),
          isFalse,
        );
        release.complete();
        await barrier;
        await pending;
      } else if (mode == 'failure') {
        await host.foundation.database.write(
          (db) => db.execute(
            "CREATE TEMP TRIGGER deny_policy BEFORE INSERT ON settings WHEN NEW.key='auth1b:policy' BEGIN SELECT RAISE(ABORT,'policy refused'); END",
          ),
        );
        await expectLater(
          update(AssistantAuthorizationMode.readOnly),
          throwsA(isA<Exception>()),
        );
        expect(owner.current.valid, isFalse);
        expect(
          HostAuthorizationPolicy(host.foundation.database).current.valid,
          isFalse,
        );
        expect(
          host.foundation.database.raw.select(
            'SELECT value FROM settings WHERE key=?',
            [HostAuthorizationPolicy.settingKey],
          ),
          isEmpty,
        );
        await host.foundation.database.write(
          (db) => db.execute('DROP TRIGGER deny_policy'),
        );
        await update(AssistantAuthorizationMode.readOnly);
      } else {
        await update(AssistantAuthorizationMode.readOnly);
      }
      final closed = owner.current;
      expect(closed.valid, isTrue);
      expect(closed.allowsTool(ToolEffect.read), isTrue);
      expect(closed.allowsTool(ToolEffect.write), isFalse);
      expect(closed.allowsTool(ToolEffect.export), isFalse);
      expect(closed.allowsTool(ToolEffect.network), isFalse);
      expect(closed.revision, isNot(original.revision));
      if (mode == 'aba') {
        await update(AssistantAuthorizationMode.standard);
        final standard = owner.current;
        await update(AssistantAuthorizationMode.readOnly);
        expect(owner.current.revision, isNot(closed.revision));
        expect(owner.current.revision, isNot(standard.revision));
        final stored = jsonDecode(
          host.foundation.database.raw.select(
                'SELECT value FROM settings WHERE key=?',
                [HostAuthorizationPolicy.settingKey],
              ).single['value']
              as String,
        ) as Map;
        expect(stored['revision'], 3);
      }
      if (mode == 'reopen') {
        await host.close();
        host = await MuyonHost.open(root.path);
        expect(host.authorizationPolicy.current.revision, closed.revision);
        expect(
          host.authorizationPolicy.current.allowsTool(ToolEffect.write),
          isFalse,
        );
        expect(
          host.authorizationPolicy.current.allowsTool(ToolEffect.read),
          isTrue,
        );
      }
    });
  }
}
