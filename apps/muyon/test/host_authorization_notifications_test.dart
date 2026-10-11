import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late StorageManager storage;
  late ManagedConnection db;
  late FoundationRepository reader;
  late HostAuthorizationFacts writer;

  HostSourceFact source(String id) => HostSourceFact.project('notes', id);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('host-fact-notifications-');
    storage = StorageManager(root.path);
    db = await storage.open('muyon', WorkspaceRepository.schema);
    reader = FoundationRepository(db);
    writer = HostAuthorizationFacts(db);
    final conversation = (await reader.createConversation()).id;
    await reader.createTask(
      PersonalTask({
        'kind': 'personal',
        'executionId': 'current',
        'conversationId': conversation,
        'prompt': 'notification fixture',
        'scope': const AssistantScope.global().toJson(),
        'executionDeviceId': 'host',
        'state': 'queued',
        'stage': 'queued',
        'createdAt': '2026-10-11T00:00:00.000Z',
        'updatedAt': '2026-10-11T00:00:00.000Z',
      }),
    );
    db.raw.execute('UPDATE settings SET value=? WHERE key=?', [
      jsonEncode({
        'version': 1,
        'taskId': 'current',
        'conversationId': conversation,
        'taintState': 'clean',
        'sourceDigests': <String>[],
      }),
      'auth1b:task:current',
    ]);
    expect(
      reader.authorizationFacts.readTask('current').taintState,
      HostTaintState.clean,
    );
  });

  tearDown(() async {
    reader.dispose();
    await storage.close();
    root.deleteSync(recursive: true);
  });

  Future<void> mark(String method, HostSourceFact fact) => switch (method) {
    'task' => writer.markExternal('current', fact),
    'source' => writer.markSourceExternal(fact),
    _ => db.write((raw) => writer.markSourceExternalInTransaction(raw, fact)),
  };

  for (final method in ['task', 'source', 'transaction']) {
    test('$method publishes shared latched facts before persistence', () async {
      final observed = <HostTaskFacts>[];
      final persistedAtNotification = <bool>[];
      reader.addListener(() {
        observed.add(reader.authorizationFacts.readTask('current'));
        persistedAtNotification.add(
          db.raw.select('SELECT 1 FROM settings WHERE key=?', [
            'auth1b:source:${source('a').identityDigest}',
          ]).isNotEmpty,
        );
      });
      final entered = Completer<void>(), release = Completer<void>();
      final hold = db.exclusiveAsync((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final pending = mark(method, source('a'));
      final immediate = List<HostTaskFacts>.of(observed);
      release.complete();
      await hold;
      await pending;
      if (method != 'transaction') {
        // No pump or microtask: the lock and notification precede queue entry.
        expect(immediate, hasLength(1));
        expect(immediate.single.taintState, HostTaintState.tainted);
        expect(
          immediate.single.sourceDigests,
          contains(source('a').identityDigest),
        );
      } else {
        expect(immediate, isEmpty, reason: 'transaction has not entered yet');
      }
      expect(observed, hasLength(1));
      expect(observed.single.taintState, HostTaintState.tainted);
      expect(
        observed.single.sourceDigests,
        contains(source('a').identityDigest),
      );
      expect(persistedAtNotification, [false]);
    });

    test('$method write failure keeps notification and latch', () async {
      final observed = <HostTaskFacts>[];
      reader.addListener(() {
        observed.add(reader.authorizationFacts.readTask('current'));
      });
      db.raw.execute(
        "CREATE TEMP TRIGGER deny_marker BEFORE INSERT ON settings "
        "WHEN NEW.key LIKE 'auth1b:%' BEGIN SELECT RAISE(ABORT,'injected marker'); END",
      );
      await expectLater(
        mark(method, source('a')),
        throwsA(isA<SqliteException>()),
      );
      expect(observed, hasLength(1));
      expect(observed.single.taintState, HostTaintState.tainted);
      expect(
        observed.single.sourceDigests,
        contains(source('a').identityDigest),
      );
      expect(
        HostAuthorizationFacts(db).readTask('current').taintState,
        HostTaintState.tainted,
      );
      expect(
        db.raw.select('SELECT 1 FROM settings WHERE key=?', [
          'auth1b:source:${source('a').identityDigest}',
        ]),
        isEmpty,
      );
      expect(
        jsonDecode(
          db.raw.select('SELECT value FROM settings WHERE key=?', [
                'auth1b:task:current',
              ]).single['value']
              as String,
        )['taintState'],
        'clean',
      );
      await expectLater(
        mark(method, source('a')),
        throwsA(isA<SqliteException>()),
      );
      expect(
        observed,
        hasLength(1),
        reason: 'failed retries do not undo the latch',
      );
    });

    test(
      '$method deduplicates a source but publishes a second source',
      () async {
        var calls = 0;
        reader.addListener(() => calls++);
        await mark(method, source('a'));
        await mark(method, source('a'));
        expect(calls, 1);
        await mark(method, source('b'));
        expect(calls, 2);
        expect(
          reader.authorizationFacts.readTask('current').sourceDigests,
          containsAll([source('a').identityDigest, source('b').identityDigest]),
        );
      },
    );
  }

  test('a known source still publishes newly latched task history', () async {
    await writer.markSourceExternal(source('a'));
    // Explicit task acceptance also changes history for an already known source.
    db.raw.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
      'auth1b:task:outside',
      jsonEncode({
        'version': 1,
        'taskId': 'outside',
        'conversationId': 'outside-conversation',
        'taintState': 'clean',
        'sourceDigests': <String>[],
      }),
    ]);
    var calls = 0;
    reader.addListener(() => calls++);
    await writer.markExternal('outside', source('a'));
    expect(calls, 1);
    expect(
      reader.authorizationFacts.readTask('outside').sourceDigests,
      contains(source('a').identityDigest),
    );
    await writer.markExternal('outside', source('a'));
    expect(calls, 1);
  });

  test('invalid mark calls do not publish or latch sources', () async {
    var calls = 0;
    reader.addListener(() => calls++);
    await expectLater(
      writer.markExternal('missing', source('a')),
      throwsStateError,
    );
    expect(
      () => writer.markSourceExternalInTransaction(db.raw, source('b')),
      throwsStateError,
    );
    final foreign = sqlite3.openInMemory();
    try {
      foreign.execute('BEGIN');
      expect(
        () => writer.markSourceExternalInTransaction(foreign, source('c')),
        throwsStateError,
      );
    } finally {
      foreign.close();
    }
    expect(calls, 0);
    expect(
      reader.authorizationFacts.readTask('current').taintState,
      HostTaintState.clean,
    );
  });

  test('database channels are isolated', () async {
    final other = await storage.open('other', WorkspaceRepository.schema);
    final otherReader = FoundationRepository(other);
    addTearDown(otherReader.dispose);
    var calls = 0, otherCalls = 0;
    reader.addListener(() => calls++);
    otherReader.addListener(() => otherCalls++);
    await writer.markSourceExternal(source('a'));
    expect(calls, 1);
    expect(otherCalls, 0);
    await HostAuthorizationFacts(other).markSourceExternal(source('a'));
    expect(calls, 1);
    expect(otherCalls, 1);
  });

  test(
    'repository subscribes once and dispose removes only its subscription',
    () async {
      final disposed = FoundationRepository(db);
      var disposedCalls = 0, liveCalls = 0;
      disposed.addListener(() => disposedCalls++);
      reader.addListener(() => liveCalls++);
      // Repeated access must not multiply subscriptions.
      expect(
        identical(disposed.authorizationFacts, disposed.authorizationFacts),
        isTrue,
      );
      await writer.markSourceExternal(source('a'));
      expect(disposedCalls, 1);
      expect(liveCalls, 1);
      disposed.dispose();
      final errors = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await writer.markSourceExternal(source('b'));
      } finally {
        FlutterError.onError = original;
      }
      expect(disposedCalls, 1);
      expect(liveCalls, 2);
      expect(errors, isEmpty, reason: 'disposed notifier must be unsubscribed');
    },
  );
}
