import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/assistant_control/assistant_control_page.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late ManagedConnection database;
  late GrantStore grants;
  final now = DateTime.utc(2026, 10, 10);
  setUp(() {
    database = ManagedConnection(sqlite3.openInMemory());
    GrantStore.migration.migrate(database.raw);
    grants = GrantStore(database);
  });
  tearDown(() async => database.close());
  Future<AssistantGrant> create({String? destination}) =>
      withConfirmedHostUiGrant((token) => grants.create(
        token: token,
        now: now,
        draft: GrantDraft(
          category: 'write', toolId: 'write.quote',
          scopeDigest: 'private-scope-not-for-display',
          destination: destination, duration: GrantDuration.always,
        ),
      ));
  Widget page({Future<AssistantControlSnapshot> Function()? read}) => MaterialApp(
    home: Scaffold(body: AssistantControlPage(
      read: read ?? () async => AssistantControlSnapshot.read(grants, now: now),
      dataFlow: const Text('existing-ledger-page'),
    )),
  );
  testWidgets('loading then empty records and existing ledger entry', (tester) async {
    final pending = Completer<AssistantControlSnapshot>();
    await tester.pumpWidget(page(read: () => pending.future));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(AssistantControlSnapshot.read(grants, now: now));
    await tester.pumpAndSettle();
    expect(find.text('暂无授权规则'), findsOneWidget);
    await tester.tap(find.text('数据去向'));
    await tester.pumpAndSettle();
    expect(find.text('existing-ledger-page'), findsOneWidget);
  });
  testWidgets('real SQLite grant detail and audit do not mutate records', (tester) async {
    await tester.runAsync(() => create(destination:
      'https://user:credential-secret@api.example.com/v1/send?key=query-secret#fragment-secret'));
    final before = Map<String, Object?>.from(database.raw.select('SELECT * FROM assistant_grants').single);
    final audits = database.raw.select('SELECT * FROM assistant_grant_audit').length;
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('write.quote'), findsOneWidget);
    expect(find.textContaining('api.example.com/v1/send'), findsOneWidget);
    await tester.tap(find.text('write.quote'));
    await tester.pumpAndSettle();
    expect(find.text('变更审计'), findsOneWidget);
    expect(find.text('已创建'), findsOneWidget);
    for (final secret in ['credential-secret', 'query-secret', 'fragment-secret', 'private-scope-not-for-display']) {
      expect(find.textContaining(secret), findsNothing);
    }
    expect(Map<String, Object?>.from(database.raw.select('SELECT * FROM assistant_grants').single), before);
    expect(database.raw.select('SELECT * FROM assistant_grant_audit').length, audits);
    expect(find.text('撤销'), findsNothing);
  });
  testWidgets('failure hides exception details and retry reloads actual store', (tester) async {
    var failing = true;
    await tester.pumpWidget(page(read: () async {
      if (failing) { throw StateError('Authorization Bearer leaked-secret'); }
      return AssistantControlSnapshot.read(grants, now: now);
    }));
    await tester.pumpAndSettle();
    expect(find.text('读取失败，请重试'), findsOneWidget);
    expect(find.textContaining('leaked-secret'), findsNothing);
    failing = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无授权规则'), findsOneWidget);
  });
  test('revoked record and audit are read without promising approval', () async {
    final grant = await create();
    await grants.revoke(grant.id, now: now);
    final snapshot = AssistantControlSnapshot.read(grants, now: now);
    expect(snapshot.rules.single.status, '已撤销');
    expect(snapshot.rules.single.audit.map((event) => event.action), ['已创建', '已撤销']);
  });
  testWidgets('late read after disposal cannot install a page or error', (tester) async {
    final pending = Completer<AssistantControlSnapshot>();
    await tester.pumpWidget(page(read: () => pending.future));
    await tester.pumpWidget(const MaterialApp(home: Text('closed')));
    pending.complete(AssistantControlSnapshot.read(grants, now: now));
    await tester.pumpAndSettle();
    expect(find.text('closed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('expired and exhausted rules are not labelled authorized for execution', () {
    Map<String, Object?> row({String? expires, int uses = 0}) => {
      'grant_id': 'fixture-rule', 'category': 'write', 'tool_id': 'write.quote',
      'scope_digest': 'scope', 'destination': null, 'duration_kind': 'always',
      'task_id': null, 'conversation_id': null, 'expires_at': expires,
      'max_uses': 1, 'uses': uses, 'created_at': now.toIso8601String(),
      'revoked_at': null,
    };
    expect(AssistantControlRule(AssistantGrant.fromRow(row(
      expires: now.toIso8601String())), [], now).status, '已过期');
    expect(AssistantControlRule(AssistantGrant.fromRow(row(uses: 1)), [], now).status, '次数已用尽');
    expect(AssistantControlRule(AssistantGrant.fromRow(row()), [], now).status, '规则已保存');
  });
  test('endpoint display withholds non-web and malformed destinations', () {
    expect(assistantEndpointDisplay(null), '本地');
    expect(assistantEndpointDisplay('https://u:p@safe.example/a?q=secret#secret'), 'safe.example/a');
    expect(assistantEndpointDisplay('token-secret'), '目的地已绑定（详情隐藏）');
    expect(assistantEndpointDisplay('file:///private/secret'), '目的地已绑定（详情隐藏）');
  });
}
