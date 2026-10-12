import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:sqlite3/sqlite3.dart';

// Intercept queue errors at their originating zone so a regression is an
// assertion failure, rather than an unhandled error that obscures durability.
Future<void> captureQueueErrors(
  Future<void> Function(List<Object> errors) body,
) {
  final done = Completer<void>();
  final errors = <Object>[];
  runZonedGuarded(() async {
    try {
      await body(errors);
      done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    }
  }, (error, stack) => errors.add(error));
  return done.future;
}

void main() {
  late ManagedConnection connection;
  setUp(() {
    connection = ManagedConnection(sqlite3.openInMemory());
    connection.raw.execute('CREATE TABLE entries(id INTEGER PRIMARY KEY)');
  });
  tearDown(() async {
    try {
      await connection.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // The baseline poisoned queue cannot close its database. This fallback
      // releases only this test's synthetic database; assertions still fail.
      connection.raw.close();
    }
  });

  test('committed write survives observer throw and drains the next write', () {
    return captureQueueErrors((errors) async {
      var notifications = 0;
      connection.onCommit = () {
        notifications++;
        throw StateError('OBSERVER_CANARY /synthetic/private/path');
      };
      expect(
        await connection.write((db) {
          db.execute('INSERT INTO entries VALUES(1)');
          return 'committed';
        }),
        'committed',
      );
      await Future<void>.delayed(Duration.zero);
      expect(connection.raw.select('SELECT id FROM entries').single['id'], 1);
      expect(connection.raw.autocommit, isTrue);
      expect(errors, isEmpty);
      expect(connection.commitObserverError, 'commit_observer_failed');
      expect(
        await connection
            .write((db) {
              db.execute('INSERT INTO entries VALUES(2)');
              return 2;
            })
            .timeout(const Duration(seconds: 2)),
        2,
      );
      expect(notifications, 2);
      expect(
        connection.raw
            .select('SELECT id FROM entries ORDER BY id')
            .map((row) => row['id']),
        [1, 2],
      );
      expect(connection.scopeAuthorityStable, isTrue);
      connection.onCommit = () => notifications++;
      await connection.write((db) => 3);
      expect(connection.commitObserverError, isNull);
      expect(notifications, 3);
      await connection.close().timeout(const Duration(seconds: 2));
      expect(errors, isEmpty);
    });
  });

  test('successful exclusive result survives observer throw and closes', () {
    return captureQueueErrors((errors) async {
      var notifications = 0;
      connection.onCommit = () {
        notifications++;
        throw ArgumentError('synthetic notification error');
      };
      expect(
        await connection.exclusiveAsync((db) async {
          await Future<void>.delayed(Duration.zero);
          db.execute('INSERT INTO entries VALUES(1)');
          return 17;
        }),
        17,
      );
      await Future<void>.delayed(Duration.zero);
      expect(errors, isEmpty);
      expect(
        await connection
            .write((db) {
              db.execute('INSERT INTO entries VALUES(2)');
              return 2;
            })
            .timeout(const Duration(seconds: 2)),
        2,
      );
      expect(notifications, 2);
      expect(
        connection.raw.select('SELECT COUNT(*) AS n FROM entries').single['n'],
        2,
      );
      expect(connection.scopeAuthorityStable, isTrue);
      await connection.close().timeout(const Duration(seconds: 2));
    });
  });

  test('transaction body error rolls back and never notifies', () async {
    var notifications = 0;
    connection.onCommit = () => notifications++;
    final failure = StateError('synthetic transaction failure');
    await expectLater(
      connection.write<void>((db) {
        db.execute('INSERT INTO entries VALUES(1)');
        throw failure;
      }),
      throwsA(same(failure)),
    );
    expect(notifications, 0);
    expect(connection.raw.select('SELECT * FROM entries'), isEmpty);
    await connection.write((db) => db.execute('INSERT INTO entries VALUES(2)'));
    expect(notifications, 1);
    expect(connection.raw.select('SELECT id FROM entries').single['id'], 2);
    expect(connection.scopeAuthorityStable, isTrue);
  });

  test(
    'deferred constraint COMMIT failure rolls back and permits next write',
    () async {
      connection.raw.execute('PRAGMA foreign_keys=ON');
      connection.raw.execute('CREATE TABLE parent(id INTEGER PRIMARY KEY)');
      connection.raw.execute(
        'CREATE TABLE child(parent_id INTEGER REFERENCES '
        'parent(id) DEFERRABLE INITIALLY DEFERRED)',
      );
      var notifications = 0;
      connection.onCommit = () => notifications++;
      await expectLater(
        connection.write((db) {
          db.execute('INSERT INTO child VALUES(42)');
          return 'must not succeed';
        }),
        throwsA(isA<SqliteException>()),
      );
      expect(notifications, 0);
      expect(connection.raw.autocommit, isTrue);
      expect(connection.raw.select('SELECT * FROM child'), isEmpty);
      await connection.write((db) {
        db.execute('INSERT INTO parent VALUES(42)');
        db.execute('INSERT INTO child VALUES(42)');
      });
      expect(notifications, 1);
      expect(
        connection.raw
            .select('SELECT parent_id FROM child')
            .single['parent_id'],
        42,
      );
    },
  );

  test('exclusive body error retains identity without notification', () async {
    var notifications = 0;
    connection.onCommit = () => notifications++;
    final failure = StateError('synthetic exclusive failure');
    await expectLater(
      connection.exclusiveAsync<void>((db) async {
        await Future<void>.delayed(Duration.zero);
        throw failure;
      }),
      throwsA(same(failure)),
    );
    expect(notifications, 0);
    await connection.write((db) => db.execute('INSERT INTO entries VALUES(1)'));
    expect(notifications, 1);
  });

  test(
    'close drains asynchronous exclusive work and its notification',
    () async {
      final release = Completer<void>();
      final events = <String>[];
      connection.onCommit = () => events.add('notify');
      final operation = connection.exclusiveAsync((db) async {
        events.add('body');
        await release.future;
        events.add('completed');
        return 9;
      });
      final closing = connection.close();
      await Future<void>.delayed(Duration.zero);
      expect(events, ['body']);
      await expectLater(connection.write((db) => 10), throwsStateError);
      release.complete();
      expect(await operation, 9);
      await closing;
      expect(events, ['body', 'completed', 'notify']);
    },
  );
}
