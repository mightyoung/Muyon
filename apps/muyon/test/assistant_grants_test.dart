import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/host_ui_grant_authority.dart';
import 'package:muyon/platform/grants/grants.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:sqlite3/sqlite3.dart';

final class Reviewer implements OutboundContentReviewer {
  Reviewer(this.operation);
  final Future<ReviewDecision> Function(OutboundReviewRequest) operation;
  @override
  Future<ReviewDecision> review(OutboundReviewRequest request) =>
      operation(request);
}

void main() {
  final now = DateTime.utc(2026, 10, 7);
  late ManagedConnection db;
  late GrantStore store;
  late GrantResolver resolver;
  setUp(() {
    db = ManagedConnection(sqlite3.openInMemory());
    db.raw.execute('PRAGMA foreign_keys=ON');
    GrantStore.migration.migrate(db.raw);
    store = GrantStore(db);
    resolver = GrantResolver(store);
  });
  tearDown(() async {
    await db.close();
  });

  GrantRequest request({
    String category = 'write',
    String toolId = 'write.quote',
    String scope = 'workspace-a/project-a',
    String? destination = 'https://hub.example/path',
    String? taskId = 'task-a',
    String? conversationId = 'conversation-a',
    DateTime? at,
    bool tainted = false,
  }) => GrantRequest(
    category: category,
    toolId: toolId,
    scopeDigest: scope,
    destination: destination,
    taskId: taskId,
    conversationId: conversationId,
    now: at ?? now,
    taskTainted: tainted,
  );

  Future<AssistantGrant> create({
    String category = 'write',
    GrantDuration duration = GrantDuration.task,
    String toolId = 'write.quote',
    String scope = 'workspace-a/project-a',
    String? destination = 'https://hub.example/path',
    String? taskId = 'task-a',
    String? conversationId = 'conversation-a',
    DateTime? expires,
    int? maxUses,
  }) => withConfirmedHostUiGrant(
    (token) => store.create(
      token: token,
      now: now,
      draft: GrantDraft(
        category: category,
        toolId: toolId,
        scopeDigest: scope,
        destination: destination,
        duration: duration,
        taskId: taskId,
        conversationId: conversationId,
        expiresAt: expires,
        maxUses: maxUses,
      ),
    ),
  );

  test('migration 11 installs exact grant and audit columns', () {
    expect(GrantStore.migration.version, 11);
    expect(
      db.raw
          .select('PRAGMA table_info(assistant_grants)')
          .map((r) => r['name']),
      containsAll([
        'grant_id',
        'category',
        'tool_id',
        'scope_digest',
        'destination',
        'duration_kind',
        'task_id',
        'conversation_id',
        'expires_at',
        'max_uses',
        'uses',
        'created_at',
        'revoked_at',
      ]),
    );
    expect(
      db.raw
          .select('PRAGMA table_info(assistant_grant_audit)')
          .map((r) => r['name']),
      containsAll(['grant_id', 'action', 'at', 'task_id', 'detail']),
    );
    expect(db.raw.select('PRAGMA foreign_key_check'), isEmpty);
  });
  test('all three bindings and category must exactly match', () async {
    final grant = await create();
    expect(resolver.resolve(request())?.id, grant.id);
    expect(resolver.resolve(request(toolId: 'write.other')), isNull);
    expect(resolver.resolve(request(scope: 'workspace-a/project-b')), isNull);
    expect(
      resolver.resolve(request(destination: 'https://hub.example/other')),
      isNull,
    );
    expect(
      resolver.resolve(
        request(destination: 'https://hub.example/path?mode=other'),
      ),
      isNull,
    );
    expect(resolver.resolve(request(category: 'model')), isNull);
    expect(await store.recordUse(grant.id, request(scope: 'changed')), isNull);
    expect(store.list().single.uses, 0);
  });
  test(
    'expiry uses the supplied clock and expires at the exact boundary',
    () async {
      final expiry = now.add(const Duration(hours: 1));
      final grant = await create(
        duration: GrantDuration.timed,
        expires: expiry,
      );
      expect(
        resolver
            .resolve(
              request(at: expiry.subtract(const Duration(microseconds: 1))),
            )
            ?.id,
        grant.id,
      );
      expect(resolver.resolve(request(at: expiry)), isNull);
      expect(await store.recordUse(grant.id, request(at: expiry)), isNull);
    },
  );
  test(
    'revocation is immediately visible and stale resolutions cannot consume',
    () async {
      final grant = await create();
      expect(resolver.resolve(request())?.id, grant.id);
      final pending = store.revoke(grant.id, now: now, taskId: 'task-a');
      expect(resolver.resolve(request()), isNull);
      expect(await pending, isTrue);
      expect(await store.recordUse(grant.id, request()), isNull);
      expect(store.list(includeRevoked: false), isEmpty);
      expect(await store.revoke(grant.id, now: now), isFalse);
      expect(
        store.audit(grant.id).where((r) => r['action'] == 'revoked'),
        hasLength(1),
      );
    },
  );
  test('once and limited grants cannot be consumed past their limit', () async {
    final once = await create(duration: GrantDuration.once);
    final results = await Future.wait([
      store.recordUse(once.id, request()),
      store.recordUse(once.id, request()),
    ]);
    expect(results.whereType<AssistantGrant>(), hasLength(1));
    expect(store.list().single.uses, 1);
    expect(resolver.resolve(request()), isNull);
    expect(
      store.audit(once.id).where((r) => r['action'] == 'used'),
      hasLength(1),
    );
    final limited = await create(maxUses: 2);
    expect(await store.recordUse(limited.id, request()), isNotNull);
    expect(await store.recordUse(limited.id, request()), isNotNull);
    expect(await store.recordUse(limited.id, request()), isNull);
    expect(resolver.resolve(request()), isNull);
  });
  test(
    'task and conversation lifetimes respect only their own boundaries',
    () async {
      await create();
      expect(resolver.resolve(request(taskId: 'other')), isNull);
      expect(resolver.resolve(request(taskId: null)), isNull);
      expect(resolver.resolve(request(conversationId: 'other')), isNotNull);
      final conversation = await create(duration: GrantDuration.conversation);
      expect(resolver.resolve(request(taskId: 'other'))?.id, conversation.id);
      expect(
        resolver.resolve(request(taskId: 'other', conversationId: 'other')),
        isNull,
      );
      expect(
        resolver.resolve(request(taskId: 'other', conversationId: null)),
        isNull,
      );
    },
  );
  test('outbound always is rejected at creation', () async {
    await expectLater(
      create(category: 'outbound', duration: GrantDuration.always),
      throwsArgumentError,
    );
    expect(store.list(), isEmpty);
  });
  test(
    'outbound needs a nonempty destination and bounded conversation',
    () async {
      for (final destination in <String?>[null, '', '   ']) {
        await expectLater(
          create(category: 'outbound', destination: destination),
          throwsArgumentError,
        );
      }
      final grant = await create(category: 'outbound');
      expect(resolver.resolve(request(category: 'outbound'))?.id, grant.id);
      expect(
        resolver.resolve(request(category: 'outbound', destination: '')),
        isNull,
      );
      expect(
        resolver.resolve(
          request(category: 'outbound', conversationId: 'other'),
        ),
        isNull,
      );
      await expectLater(
        create(category: 'outbound', conversationId: null),
        throwsArgumentError,
      );
    },
  );
  test('timed outbound cannot escape its conversation before expiry', () async {
    final expiry = now.add(const Duration(hours: 1));
    final grant = await create(
      category: 'outbound',
      duration: GrantDuration.timed,
      expires: expiry,
    );
    expect(resolver.resolve(request(category: 'outbound'))?.id, grant.id);
    expect(
      resolver.resolve(request(category: 'outbound', taskId: 'other'))?.id,
      grant.id,
    );
    expect(
      resolver.resolve(request(category: 'outbound', conversationId: 'other')),
      isNull,
    );
    expect(resolver.resolve(request(category: 'outbound', at: expiry)), isNull);
    await expectLater(
      create(
        category: 'outbound',
        duration: GrantDuration.timed,
        expires: expiry,
        conversationId: null,
      ),
      throwsArgumentError,
    );
  });
  test(
    'tainted tasks never match write or outbound but may match model',
    () async {
      for (final category in ['write', 'outbound', 'model']) {
        final grant = await create(category: category);
        final req = request(category: category, tainted: true);
        if (category == 'model') {
          expect(resolver.resolve(req)?.id, grant.id);
          expect(await store.recordUse(grant.id, req), isNotNull);
        } else {
          expect(resolver.resolve(req), isNull);
          expect(await store.recordUse(grant.id, req), isNull);
        }
      }
    },
  );
  test('read is rejected rather than represented as a grant', () {
    expect(() => request(category: 'read'), throwsArgumentError);
    expect(
      () => GrantDraft(
        category: 'read',
        toolId: 'read',
        scopeDigest: 'scope',
        destination: null,
        duration: GrantDuration.once,
      ),
      throwsArgumentError,
    );
  });
  test('create use and revoke audit records are transactional and contain metadata', () async {
    final grant = await create();
    await store.recordUse(grant.id, request());
    await store.revoke(grant.id, now: now, taskId: 'task-a');
    final audit = store.audit(grant.id);
    expect(audit.map((r) => r['action']), ['created', 'used', 'revoked']);
    expect(audit.map((r) => r['grant_id']), everyElement(grant.id));
    expect(audit.map((r) => r['task_id']), everyElement('task-a'));
    expect(jsonDecode(audit[1]['detail'] as String), {'uses': 1});
    expect(audit.map((r) => r['detail']).join(), isNot(contains('https://')));
    db.raw.execute(
      "CREATE TRIGGER fail_audit BEFORE INSERT ON assistant_grant_audit BEGIN SELECT RAISE(ABORT,'audit unavailable'); END;",
    );
    await expectLater(
      create(toolId: 'write.failed'),
      throwsA(isA<SqliteException>()),
    );
    expect(store.list(), hasLength(1));
  });
  test(
    'failed use audit rolls back uses and failed revoke stays fail closed',
    () async {
      final grant = await create();
      db.raw.execute(
        "CREATE TRIGGER fail_audit BEFORE INSERT ON assistant_grant_audit BEGIN SELECT RAISE(ABORT,'audit unavailable'); END;",
      );
      await expectLater(
        store.recordUse(grant.id, request()),
        throwsA(isA<SqliteException>()),
      );
      expect(store.list().single.uses, 0);
      await expectLater(
        store.revoke(grant.id, now: now),
        throwsA(isA<SqliteException>()),
      );
      expect(resolver.resolve(request()), isNull);
      db.raw.execute('DROP TRIGGER fail_audit');
      expect(await store.revoke(grant.id, now: now), isTrue);
      expect(store.list().single.revokedAt, isNotNull);
    },
  );
  test('creation requires a live host UI token and cannot retain it', () async {
    late HostUiGrantToken escaped;
    await withConfirmedHostUiGrant((token) async {
      escaped = token;
    });
    expect(
      () => store.create(
        token: escaped,
        now: now,
        draft: GrantDraft(
          category: 'write',
          toolId: 'write',
          scopeDigest: 'scope',
          destination: null,
          duration: GrantDuration.once,
        ),
      ),
      throwsStateError,
    );
    dynamic forged = Object();
    expect(
      () => store.create(
        token: forged,
        now: now,
        draft: GrantDraft(
          category: 'write',
          toolId: 'write',
          scopeDigest: 'scope',
          destination: null,
          duration: GrantDuration.once,
        ),
      ),
      throwsA(isA<TypeError>()),
    );
    expect(store.list(), isEmpty);
  });
  test('assistant sources cannot import or call the host UI grant issuer', () {
    final files = Directory('lib/assistant')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      final code = file.readAsStringSync();
      for (final symbol in [
        'HostUiGrantToken',
        'withConfirmedHostUiGrant',
        'host_ui_grant_authority.dart',
      ]) {
        expect(
          code,
          isNot(contains(symbol)),
          reason: '${file.path} must not obtain grant-creation authority',
        );
      }
    }
    final constructor = RegExp(r'HostUiGrantToken(?:\.[\w]+)?\s*\(');
    final issuer = 'lib/app/host_ui_grant_authority.dart';
    final constructors = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              constructor.hasMatch(f.readAsStringSync()),
        )
        .map((f) => f.path)
        .toList();
    expect(constructors, [issuer]);
    final issuance = RegExp(r'withConfirmedHostUiGrant(?:<[^>]+>)?\s*\(');
    final issuingFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              issuance.hasMatch(f.readAsStringSync()),
        )
        .map((f) => f.path)
        .toList();
    expect(issuingFiles, [
      issuer,
    ], reason: 'No non-UI production path may issue tokens');
    final exports = File('lib/platform/grants/grants.dart').readAsStringSync();
    expect(exports, contains('show HostUiGrantToken;'));
    expect(exports, isNot(contains('withConfirmedHostUiGrant')));
  });

  group('content reviewers', () {
    final input = OutboundReviewRequest(
      toolId: 'send',
      endpoint: Uri.parse('https://hub.example/path'),
      content: utf8.encode('private 中文🌍'),
      scopeDigest: 'scope',
    );
    Reviewer returns(ReviewDecision result) => Reviewer((_) async => result);
    ReviewerChain chain(List<OutboundContentReviewer> reviewers) =>
        ReviewerChain(reviewers, timeout: const Duration(milliseconds: 5));
    test('noop and empty chain allow but say not reviewed', () async {
      for (final reviewer in <OutboundContentReviewer>[
        const NoopReviewer(),
        chain([]),
        chain([const NoopReviewer()]),
      ]) {
        final result = await reviewer.review(input);
        expect(result.action, ReviewAction.allow);
        expect(result.reviewed, isFalse);
        expect(result.reviewLabel, '未审查');
      }
      expect(() => input.content.add(1), throwsUnsupportedError);
    });
    test('allow confirm block and most restrictive composition', () async {
      final allow = returns(const ReviewDecision.allow());
      final confirm = returns(const ReviewDecision.confirm('确认内容'));
      final block = returns(const ReviewDecision.block('拒绝内容'));
      expect((await chain([allow]).review(input)).action, ReviewAction.allow);
      final confirmation = await chain([confirm, allow]).review(input);
      expect(confirmation.action, ReviewAction.confirm);
      expect(confirmation.reason, '确认内容');
      for (final reviewers in [
        [block, allow, confirm],
        [allow, confirm, block],
        [confirm, block, allow],
      ]) {
        final result = await chain(reviewers).review(input);
        expect(result.action, ReviewAction.block);
        expect(result.reason, '拒绝内容');
      }
    });
    test(
      'reviewer exceptions require confirmation without echoing data',
      () async {
        final result = await chain([
          Reviewer((_) => throw StateError('private payload SECRET')),
        ]).review(input);
        expect(result.action, ReviewAction.confirm);
        expect(result.reviewed, isFalse);
        expect(result.reason, isNot(contains('SECRET')));
      },
    );
    test(
      'reviewer timeout requires confirmation and cannot weaken a block',
      () async {
        final stalled = Reviewer((_) => Completer<ReviewDecision>().future);
        final result = await chain([stalled]).review(input);
        expect(result.action, ReviewAction.confirm);
        expect(result.reviewed, isFalse);
        expect(
          (await chain([returns(const ReviewDecision.block('拒绝')), stalled])
                  .review(input))
              .action,
          ReviewAction.block,
        );
        expect(
          () => ReviewerChain([], timeout: Duration.zero),
          throwsArgumentError,
        );
      },
    );
  });
}
