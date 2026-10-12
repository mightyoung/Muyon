import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('independent disk write queue and close survive an unprintable observer error', () async {
    final temp = Directory.systemTemp.createTempSync('observer-independent-');
    final path = '${temp.path}/synthetic.sqlite';
    final connection = ManagedConnection(sqlite3.open(path));
    connection.raw.execute('CREATE TABLE evidence(id INTEGER PRIMARY KEY)');
    final uncaught = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          connection.onCommit = () => throw const _UnprintableObserverError();
          expect(
            await connection.write((db) {
              db.execute('INSERT INTO evidence VALUES(1)');
              return 'durable';
            }),
            'durable',
          );
          expect(connection.commitObserverError, 'commit_observer_failed');
          expect(connection.raw.autocommit, true);
          expect(connection.scopeAuthorityStable, true);
          // A second write genuinely executes after the observer threw; no retry of the first.
          expect(
            await connection
                .write((db) {
                  db.execute('INSERT INTO evidence VALUES(2)');
                  return 'next';
                })
                .timeout(const Duration(seconds: 2)),
            'next',
          );
          connection.onCommit = () {};
          expect(
            await connection.exclusiveAsync((db) async {
              db.execute('INSERT INTO evidence VALUES(3)');
              return 3;
            }),
            3,
          );
          expect(connection.commitObserverError, isNull);
          await connection.close().timeout(const Duration(seconds: 2));
          expect(uncaught, isEmpty);
          final reopened = sqlite3.open(path);
          try {
            expect(
              reopened
                  .select('SELECT id FROM evidence ORDER BY id')
                  .map((r) => r['id']),
              [1, 2, 3],
            );
          } finally {
            reopened.close();
          }
          done.complete();
        } catch (error, stack) {
          done.completeError(error, stack);
        }
      },
      (error, stack) {
        uncaught.add(error);
      },
    );
    try {
      await done.future.timeout(const Duration(seconds: 4));
    } finally {
      try {
        await connection.close();
      } catch (_) {
        connection.raw.close();
      }
      temp.deleteSync(recursive: true);
    }
  });
  test(
    'failed work does not notify or clear the last failed observer diagnostic',
    () async {
      final connection = ManagedConnection(sqlite3.openInMemory());
      connection.raw.execute('CREATE TABLE evidence(id INTEGER PRIMARY KEY)');
      try {
        var notifications = 0;
        connection.onCommit = () {
          notifications++;
          throw StateError('SYNTHETIC_PRIVATE_OBSERVER');
        };
        await connection.write(
          (db) => db.execute('INSERT INTO evidence VALUES(1)'),
        );
        final original = StateError('synthetic body failure');
        await expectLater(
          connection.write<void>((db) {
            db.execute('INSERT INTO evidence VALUES(2)');
            throw original;
          }),
          throwsA(same(original)),
        );
        expect(notifications, 1);
        expect(connection.commitObserverError, 'commit_observer_failed');
        expect(
          connection.raw.select('SELECT id FROM evidence').single['id'],
          1,
        );
        connection.onCommit = () {
          notifications++;
        };
        await connection.write(
          (db) => db.execute('INSERT INTO evidence VALUES(3)'),
        );
        expect(connection.commitObserverError, isNull);
        expect(notifications, 2);
      } finally {
        await connection.close();
      }
    },
  );
}

class _UnprintableObserverError implements Exception {
  const _UnprintableObserverError();
  @override
  String toString() =>
      throw StateError('DIAGNOSTIC_STRINGIFICATION_MUST_NOT_RUN');
}
