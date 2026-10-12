import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/grants/local_export_target.dart';
import 'package:muyon/platform/local_export_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late ManagedConnection db;
  late LocalExportLedger ledger;
  late LocalExportTargetIssuer issuer;
  final now = DateTime.utc(2026, 10, 12);
  Matcher error(String code) => throwsA(
    isA<LocalExportLedgerException>().having((e) => e.code, 'code', code),
  );
  LocalExportPreparation preparation({
    String body = 'synthetic report',
    String? manifest,
  }) => LocalExportPreparation(
    kind: LocalExportKind.report,
    formatVersion: '1',
    mimeType: 'text/markdown',
    generatedAt: now,
    bytes: utf8.encode(body),
    sha256: sha256.convert(utf8.encode(body)).toString(),
    sources: const [
      ObjectRef(
        moduleId: 'research',
        objectType: 'entry',
        objectId: 'e1',
        revisionRef: 'r1',
      ),
    ],
    dedupedObjectCount: 1,
    exclusions: const [],
    warnings: const [],
    preparationVersion: 1,
    manifestDigest: manifest ?? 'a' * 64,
  );
  LocalExportLedgerRequest request({
    String export = 'export1',
    String invocation = 'generate1',
    LocalExportPhase phase = LocalExportPhase.generate,
    String? scope,
    LocalExportPreparation? prep,
    LocalExportTargetCapability? target,
    String? attempt,
    Map<String, Object?> metadata = const {},
  }) => LocalExportLedgerRequest(
    exportId: export,
    toolId: 'research.export_report',
    invocationId: invocation,
    phase: phase,
    scopeDigest: scope ?? 'b' * 64,
    preparation: prep ?? preparation(),
    targetIssuer: issuer,
    target: target,
    attemptId: attempt,
    policyVersion: 'p1',
    hostMetadata: metadata,
  );
  Future<LocalExportStageCompletion> success(List<int> _) async =>
      LocalExportStageCompletion(
        LocalExportStage(LocalExportOutcome.succeeded),
      );
  Future<void> generate() async {
    expect(
      (await ledger.execute(request(), operation: success)).state,
      LocalExportLedgerState.succeeded,
    );
  }

  setUp(() {
    db = ManagedConnection(sqlite3.openInMemory());
    LocalExportLedger.createTables(db.raw);
    ledger = LocalExportLedger(db, clock: () => now);
    issuer = LocalExportTargetIssuer();
  });
  tearDown(() => db.close());

  test(
    'read on an empty connection creates no tables and performs no write',
    () async {
      final empty = ManagedConnection(sqlite3.openInMemory());
      var commits = 0;
      empty.onCommit = () => commits++;
      final reader = LocalExportLedger(empty);
      expect(reader.read('missing'), isNull);
      expect(
        empty.raw.select(
          'SELECT name FROM sqlite_master WHERE type = \'table\'',
        ),
        isEmpty,
      );
      expect(commits, 0);
      await empty.close();
    },
  );

  test('pending insert failure has zero callback executions', () async {
    db.raw.execute(
      'CREATE TRIGGER deny_pending BEFORE INSERT ON local_export_attempts BEGIN SELECT RAISE(ABORT, \'private failure\'); END',
    );
    var calls = 0;
    await expectLater(
      ledger.execute(
        request(),
        operation: (bytes) async {
          calls++;
          return success(bytes);
        },
      ),
      error('ledger_pending_failed'),
    );
    expect(calls, 0);
    expect(ledger.read('export1'), isNull);
  });

  test('pending transaction rollback has zero callback executions', () async {
    final failing = _RollbackDatabase(db);
    final guarded = LocalExportLedger(failing);
    var calls = 0;
    await expectLater(
      guarded.execute(
        request(),
        operation: (bytes) async {
          calls++;
          return success(bytes);
        },
      ),
      error('ledger_pending_failed'),
    );
    expect(calls, 0);
    expect(ledger.read('export1'), isNull);
    expect(db.raw.select('SELECT * FROM local_export_attempts'), isEmpty);
  });

  test('pending is committed before callback; duplicate and concurrent calls run once', () async {
    var calls = 0;
    final entered = Completer<void>(), release = Completer<void>();
    final req = request();
    final first = ledger.execute(
      req,
      operation: (bytes) async {
        calls++;
        expect(db.raw.autocommit, isTrue);
        expect(
          db.raw.select('SELECT * FROM local_export_attempts'),
          hasLength(1),
        );
        expect(
          ledger.read('export1')!.generate!.state,
          LocalExportLedgerState.pending,
        );
        entered.complete();
        await release.future;
        return success(bytes);
      },
    );
    await entered.future;
    final duplicate = ledger.execute(
      req,
      operation: (bytes) async {
        calls++;
        return success(bytes);
      },
    );
    final other = LocalExportLedger(db);
    final observation = await other.execute(
      req,
      operation: (bytes) async {
        calls++;
        return success(bytes);
      },
    );
    expect(observation.state, LocalExportLedgerState.unknown);
    release.complete();
    expect((await first).state, LocalExportLedgerState.succeeded);
    expect((await duplicate).state, LocalExportLedgerState.succeeded);
    expect(
      (await ledger.execute(req, operation: success)).state,
      LocalExportLedgerState.succeeded,
    );
    expect(calls, 1);
    expect(db.raw.select('SELECT * FROM local_export_attempts'), hasLength(1));
  });

  test('changed bytes, manifest, scope and reused invocation conflict without execution', () async {
    await generate();
    var calls = 0;
    for (final req in [
      request(prep: preparation(body: 'changed')),
      request(prep: preparation(manifest: 'c' * 64)),
      request(scope: 'd' * 64),
      request(export: 'another'),
    ]) {
      await expectLater(
        ledger.execute(
          req,
          operation: (bytes) async {
            calls++;
            return success(bytes);
          },
        ),
        error('export_identity_conflict'),
      );
    }
    expect(calls, 0);
    expect(db.raw.select('SELECT * FROM local_export_exports'), hasLength(1));
    expect(db.raw.select('SELECT * FROM local_export_attempts'), hasLength(1));
  });

  test(
    'save target and attempt identity are bound; a distinct retry is separate',
    () async {
      await generate();
      final target = issuer.issue('/private/target-one');
      final req = request(
        invocation: 'save1',
        phase: LocalExportPhase.save,
        target: target,
        attempt: 's1',
      );
      await ledger.execute(req, operation: success);
      expect(
        (await ledger.execute(req, operation: success)).state,
        LocalExportLedgerState.succeeded,
      );
      for (final changed in [
        request(
          invocation: 'save1',
          phase: LocalExportPhase.save,
          target: issuer.issue('/private/target-two'),
          attempt: 's1',
        ),
        request(
          invocation: 'save1',
          phase: LocalExportPhase.save,
          target: target,
          attempt: 's2',
        ),
        request(
          invocation: 'save2',
          phase: LocalExportPhase.save,
          target: target,
          attempt: 's1',
        ),
      ]) {
        await expectLater(
          ledger.execute(changed, operation: success),
          error('export_identity_conflict'),
        );
      }
      await ledger.execute(
        request(
          invocation: 'save2',
          phase: LocalExportPhase.save,
          target: issuer.issue('other'),
          attempt: 's2',
        ),
        operation: success,
      );
      expect(ledger.read('export1')!.saveAttempts, hasLength(2));
    },
  );

  test(
    'cancel records save separately and late cancellation preserves success',
    () async {
      await generate();
      final cancelled = await ledger.cancelSave(
        exportId: 'export1',
        invocationId: 'cancel1',
        attemptId: 'cancel1',
      );
      expect(cancelled.state, LocalExportLedgerState.cancelled);
      expect(
        (await ledger.cancelSave(
          exportId: 'export1',
          invocationId: 'cancel1',
          attemptId: 'cancel1',
        )).state,
        LocalExportLedgerState.cancelled,
      );
      final target = issuer.issue('synthetic target');
      await ledger.execute(
        request(
          invocation: 'save1',
          phase: LocalExportPhase.save,
          target: target,
          attempt: 's1',
        ),
        operation: success,
      );
      expect(
        (await ledger.cancelSave(
          exportId: 'export1',
          invocationId: 'save1',
          attemptId: 's1',
        )).state,
        LocalExportLedgerState.succeeded,
      );
      expect(
        ledger.read('export1')!.generate!.state,
        LocalExportLedgerState.succeeded,
      );
      expect(ledger.read('export1')!.saveAttempts.map((e) => e.state), [
        LocalExportLedgerState.cancelled,
        LocalExportLedgerState.succeeded,
      ]);
    },
  );

  test('save and cancellation require durable successful generation', () async {
    var calls = 0;
    await expectLater(
      ledger.execute(
        request(
          invocation: 'save1',
          phase: LocalExportPhase.save,
          target: issuer.issue('target'),
          attempt: 's1',
        ),
        operation: (bytes) async {
          calls++;
          return success(bytes);
        },
      ),
      error('export_generation_required'),
    );
    await expectLater(
      ledger.cancelSave(
        exportId: 'export1',
        invocationId: 'cancel1',
        attemptId: 's1',
      ),
      error('export_generation_required'),
    );
    expect(calls, 0);
    expect(ledger.read('export1'), isNull);
  });

  test('completion write failure leaves unknown durable state and never repeats callback', () async {
    db.raw.execute(
      'CREATE TRIGGER deny_completion BEFORE UPDATE ON local_export_attempts BEGIN SELECT RAISE(ABORT, \'private completion failure\'); END',
    );
    var calls = 0;
    final record = await ledger.execute(
      request(),
      operation: (bytes) async {
        calls++;
        return success(bytes);
      },
    );
    expect(record.state, LocalExportLedgerState.interrupted);
    expect(record.errorCode, matches(RegExp(r'^[a-z0-9_]{1,64}$')));
    db.raw.execute('DROP TRIGGER deny_completion');
    final reopened = LocalExportLedger(db);
    expect(
      reopened.read('export1')!.generate!.state,
      LocalExportLedgerState.unknown,
    );
    final repeat = await reopened.execute(
      request(),
      operation: (bytes) async {
        calls++;
        return success(bytes);
      },
    );
    expect(repeat.state, LocalExportLedgerState.unknown);
    expect(calls, 1);
  });

  test('reopening persists facts; readonly check neither retries nor revives a target', () async {
    final dir = Directory.systemTemp.createTempSync('le06-ledger-');
    var disk = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
    try {
      LocalExportLedger.createTables(disk.raw);
      var stored = LocalExportLedger(disk);
      await stored.execute(request(), operation: success);
      final target = issuer.issue('file:///private/host-only');
      final save = request(
        invocation: 'save1',
        phase: LocalExportPhase.save,
        target: target,
        attempt: 's1',
      );
      disk.raw.execute(
        'CREATE TRIGGER deny_completion BEFORE UPDATE ON local_export_attempts BEGIN SELECT RAISE(ABORT, \'failure\'); END',
      );
      expect(
        (await stored.execute(save, operation: success)).state,
        LocalExportLedgerState.interrupted,
      );
      await disk.close();
      issuer.revoke(target);
      disk = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
      stored = LocalExportLedger(disk);
      final before = disk.raw
          .select('SELECT * FROM local_export_attempts')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      var probes = 0, commits = 0;
      disk.onCommit = () => commits++;
      var repeatedOperations = 0;
      final recovered = await stored.execute(
        save,
        operation: (bytes) async {
          repeatedOperations++;
          return success(bytes);
        },
      );
      expect(recovered.state, LocalExportLedgerState.unknown);
      expect(repeatedOperations, 0);
      expect(commits, 0, reason: 'a historical duplicate is a readonly lookup');
      final checked = await stored.check(
        'export1',
        probe: (stage) async {
          probes++;
          expect(stage.phase, LocalExportPhase.save);
          expect(stage.targetIdentityDigest, isNotNull);
          return LocalExportStageCompletion(
            LocalExportStage(LocalExportOutcome.succeeded),
          );
        },
      );
      expect(checked!.generate!.state, LocalExportLedgerState.succeeded);
      expect(
        checked.saveAttempts.single.state,
        LocalExportLedgerState.succeeded,
      );
      final durableModel = recovered.modelData;
      expect(
        checked.saveAttempts.single.modelData['status'],
        'unknown',
        reason:
            'a readonly observation cannot issue a committed success receipt',
      );
      expect(
        checked.saveAttempts.single.modelData['errorCode'],
        durableModel['errorCode'],
      );
      final observedModelAttempts =
          checked.modelData['saveAttempts']! as List<Object?>;
      final observedModelStage =
          observedModelAttempts.single! as Map<String, Object?>;
      expect(observedModelStage['status'], 'unknown');
      expect(observedModelStage['errorCode'], durableModel['errorCode']);
      expect(() => observedModelAttempts.clear(), throwsUnsupportedError);
      expect(
        () => observedModelStage['status'] = 'succeeded',
        throwsUnsupportedError,
      );
      expect(
        stored.read('export1')!.saveAttempts.single.state,
        LocalExportLedgerState.unknown,
      );
      expect(
        disk.raw
            .select('SELECT * FROM local_export_attempts')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
        before,
      );
      expect(probes, 1);
      expect(commits, 0);
      expect(issuer.owns(target), isFalse);
    } finally {
      await disk.close();
      dir.deleteSync(recursive: true);
    }
  });

  test(
    'clock failure after callback returns interrupted and never retries',
    () async {
      var calls = 0;
      final unreliable = LocalExportLedger(
        db,
        clock: () {
          if (calls > 0) throw StateError('/PRIVATE_CLOCK');
          return now;
        },
      );
      final req = request();
      final result = await unreliable.execute(
        req,
        operation: (bytes) async {
          calls++;
          return success(bytes);
        },
      );
      expect(result.state, LocalExportLedgerState.interrupted);
      expect(result.errorCode, 'ledger_completion_failed');
      expect(calls, 1);
      expect(
        db.raw
            .select('SELECT state FROM local_export_attempts')
            .single['state'],
        'pending',
      );
      final reopened = LocalExportLedger(db);
      expect(
        reopened.read('export1')!.generate!.state,
        LocalExportLedgerState.unknown,
      );
      var commits = 0;
      db.onCommit = () => commits++;
      final duplicate = await reopened.execute(
        req,
        operation: (bytes) async {
          calls++;
          return success(bytes);
        },
      );
      expect(duplicate.state, LocalExportLedgerState.unknown);
      expect(calls, 1);
      expect(commits, 0);
      expect(
        jsonEncode(reopened.read('export1')!.modelData),
        isNot(contains('PRIVATE_CLOCK')),
      );
    },
  );

  test(
    'readonly check tolerates persistent clock and probe failures',
    () async {
      db.raw.execute(
        'CREATE TRIGGER deny_completion BEFORE UPDATE ON local_export_attempts BEGIN SELECT RAISE(ABORT, \'synthetic failure\'); END',
      );
      expect(
        (await ledger.execute(request(), operation: success)).state,
        LocalExportLedgerState.interrupted,
      );
      db.raw.execute('DROP TRIGGER deny_completion');
      final before = db.raw
          .select('SELECT * FROM local_export_attempts')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final unreliable = LocalExportLedger(
        db,
        clock: () => throw StateError('/PRIVATE_CLOCK'),
      );
      var commits = 0, probes = 0;
      db.onCommit = () => commits++;
      for (final failProbe in [false, true]) {
        final checked = await unreliable.check(
          'export1',
          probe: (stage) async {
            probes++;
            if (failProbe) throw StateError('/PRIVATE_PROBE');
            return LocalExportStageCompletion(
              LocalExportStage(LocalExportOutcome.succeeded),
            );
          },
        );
        expect(checked!.generate!.state, LocalExportLedgerState.unknown);
        expect(checked.generate!.errorCode, 'export_check_failed');
        expect(jsonEncode(checked.modelData), isNot(contains('PRIVATE')));
      }
      expect(probes, 2);
      expect(commits, 0);
      expect(
        db.raw
            .select('SELECT * FROM local_export_attempts')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
        before,
      );
      expect(
        unreliable.read('export1')!.generate!.state,
        LocalExportLedgerState.unknown,
      );
    },
  );

  test('two SQLite connections share a durable pending winner', () async {
    final dir = Directory.systemTemp.createTempSync('le06-concurrent-');
    final firstDb = ManagedConnection(
      sqlite3.open('${dir.path}/ledger.sqlite'),
    );
    final secondDb = ManagedConnection(
      sqlite3.open('${dir.path}/ledger.sqlite'),
    );
    final release = Completer<void>(), entered = Completer<void>();
    var calls = 0;
    try {
      LocalExportLedger.createTables(firstDb.raw);
      final firstLedger = LocalExportLedger(firstDb);
      final secondLedger = LocalExportLedger(secondDb);
      final req = request();
      final winner = firstLedger.execute(
        req,
        operation: (bytes) async {
          calls++;
          entered.complete();
          await release.future;
          return success(bytes);
        },
      );
      await entered.future;
      var otherCommits = 0;
      secondDb.onCommit = () => otherCommits++;
      final loser = await secondLedger.execute(
        req,
        operation: (bytes) async {
          calls++;
          return success(bytes);
        },
      );
      expect(loser.state, LocalExportLedgerState.unknown);
      expect(calls, 1);
      expect(otherCommits, 0);
      release.complete();
      expect((await winner).state, LocalExportLedgerState.succeeded);
      expect(
        (await secondLedger.execute(
          req,
          operation: (bytes) async {
            calls++;
            return success(bytes);
          },
        )).state,
        LocalExportLedgerState.succeeded,
      );
      expect(calls, 1);
      expect(otherCommits, 0);
      expect(
        secondDb.raw.select('SELECT * FROM local_export_attempts'),
        hasLength(1),
      );
    } finally {
      if (!release.isCompleted) release.complete();
      await firstDb.close();
      await secondDb.close();
      dir.deleteSync(recursive: true);
    }
  });

  test('revocation after pending commit prevents callback', () async {
    await generate();
    final target = issuer.issue('host target');
    final req = request(
      invocation: 'save1',
      phase: LocalExportPhase.save,
      target: target,
      attempt: 's1',
    );
    db.onCommit = () => issuer.revoke(target);
    var calls = 0;
    try {
      await ledger.execute(
        req,
        operation: (bytes) async {
          calls++;
          return success(bytes);
        },
      );
    } on Object {
      /* The capability may be refused with a safe error. */
    }
    expect(calls, 0);
  });

  test('request and host audit are deeply frozen; model projection excludes sensitive material', () async {
    final mutable = _MutablePreparation(preparation());
    final nested = <String, Object?>{
      'review': <Object?>[
        'PRIVATE_REVIEW',
        <String, Object?>{'path': '/PRIVATE_PATH'},
      ],
    };
    final req = request(prep: mutable, metadata: nested);
    mutable.bytes[0] = 0;
    mutable.sources.clear();
    (nested['review']! as List<Object?>)[0] = 'changed';
    expect(utf8.decode(req.preparation.bytes), 'synthetic report');
    expect(req.preparation.sources, hasLength(1));
    expect(
      (req.hostMetadata['review']! as List<Object?>).first,
      'PRIVATE_REVIEW',
    );
    expect(() => req.preparation.bytes[0] = 0, throwsUnsupportedError);
    expect(() => req.preparation.sources.clear(), throwsUnsupportedError);
    expect(
      () => (req.hostMetadata['review']! as List<Object?>).clear(),
      throwsUnsupportedError,
    );
    await ledger.execute(
      req,
      operation: (bytes) async {
        expect(() => bytes[0] = 0, throwsUnsupportedError);
        return LocalExportStageCompletion(
          LocalExportStage(LocalExportOutcome.succeeded),
          hostMetadata: {
            'uri': 'file:///PRIVATE_URI',
            'handle': 'PRIVATE_HANDLE',
            'body': 'PRIVATE_BODY',
          },
        );
      },
    );
    final receipt = ledger.read('export1')!;
    expect(() => receipt.saveAttempts.clear(), throwsUnsupportedError);
    final recoveredAudit = receipt.generate!.hostMetadata;
    final requestAudit = recoveredAudit['request']! as Map<String, Object?>;
    final review = requestAudit['review']! as List<Object?>;
    expect(() => requestAudit['review'] = 'altered', throwsUnsupportedError);
    expect(() => review.clear(), throwsUnsupportedError);
    expect(
      () => (review[1]! as Map<String, Object?>)['path'] = 'altered',
      throwsUnsupportedError,
    );
    final completionAudit =
        recoveredAudit['completion']! as Map<String, Object?>;
    expect(() => completionAudit['body'] = 'altered', throwsUnsupportedError);
    final model = receipt.modelData;
    final allowed = {
      'state',
      'status',
      'exportId',
      'sha256',
      'payloadDigest',
      'contentDigest',
      'manifestDigest',
      'byteCount',
      'errorCode',
      'generate',
      'save',
      'saveAttempts',
    };
    void inspect(Object? value) {
      if (value is Map) {
        expect(
          value.keys.every(allowed.contains),
          isTrue,
          reason: '${value.keys}',
        );
        for (final child in value.values) {
          inspect(child);
        }
      }
      if (value is List) {
        for (final child in value) {
          inspect(child);
        }
      }
    }

    inspect(model);
    final encoded = jsonEncode(model);
    for (final forbidden in [
      'PRIVATE',
      'synthetic report',
      'generate1',
      'scopeDigest',
      'invocation',
      'targetIdentity',
      'review',
      'uri',
      'handle',
    ]) {
      expect(encoded, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(() => model['exportId'] = 'changed', throwsUnsupportedError);
  });

  test(
    'unknown save blocks new attempts without running their callback',
    () async {
      await generate();
      final uncertain = await ledger.execute(
        request(
          invocation: 'save1',
          phase: LocalExportPhase.save,
          target: issuer.issue('target one'),
          attempt: 's1',
        ),
        operation: (_) async => throw StateError('possible partial effect'),
      );
      expect(uncertain.state, LocalExportLedgerState.unknown);
      var calls = 0;
      await expectLater(
        ledger.execute(
          request(
            invocation: 'save2',
            phase: LocalExportPhase.save,
            target: issuer.issue('target two'),
            attempt: 's2',
          ),
          operation: (bytes) async {
            calls++;
            return success(bytes);
          },
        ),
        throwsA(isA<LocalExportLedgerException>()),
      );
      expect(calls, 0);
      expect(ledger.read('export1')!.saveAttempts, hasLength(1));
    },
  );

  test(
    'unsafe identifiers and mismatched preparation SHA refuse before execution',
    () async {
      for (final bad in ['', '../escape', 'a/b', r'a\b', 'bad id', '汉字']) {
        expect(() => request(export: bad), throwsArgumentError, reason: bad);
      }
      final bad = _MutablePreparation(preparation());
      bad.bytes[0] = 0;
      expect(() => request(prep: bad), throwsArgumentError);
      expect(ledger.read('export1'), isNull);
      expect(db.raw.select('SELECT * FROM local_export_attempts'), isEmpty);
    },
  );

  test('explicit failed completion retains safe outcome without treating generation as success', () async {
    final result = await ledger.execute(
      request(),
      operation: (_) async => LocalExportStageCompletion(
        LocalExportStage(
          LocalExportOutcome.failed,
          errorCode: 'synthetic_failure',
        ),
        hostMetadata: {'review': 'PRIVATE_REVIEW'},
      ),
    );
    expect(result.state, LocalExportLedgerState.failed);
    expect(result.errorCode, 'synthetic_failure');
    expect(
      ledger.read('export1')!.generate!.state,
      LocalExportLedgerState.failed,
    );
    expect(
      jsonEncode(ledger.read('export1')!.modelData),
      isNot(contains('PRIVATE')),
    );
    await expectLater(
      ledger.cancelSave(
        exportId: 'export1',
        invocationId: 'cancel1',
        attemptId: 's1',
      ),
      error('export_generation_required'),
    );
  });

  test('shape-safe private error tokens stay host-only', () async {
    final result = await ledger.execute(
      request(),
      operation: (_) async => LocalExportStageCompletion(
        LocalExportStage(
          LocalExportOutcome.failed,
          errorCode: 'private_review_token',
        ),
        hostMetadata: {'review': 'private_review_token'},
      ),
    );
    expect(result.errorCode, 'private_review_token');
    final recovered = LocalExportLedger(db).read('export1')!;
    expect(recovered.generate!.errorCode, 'private_review_token');
    expect(
      (recovered.generate!.hostMetadata['completion']! as Map)['review'],
      'private_review_token',
    );
    expect(recovered.generate!.modelData['errorCode'], 'export_failed');
    expect(
      jsonEncode(recovered.modelData),
      isNot(contains('private_review_token')),
    );
  });

  test(
    'raw callback errors remain host-only and use a safe error code',
    () async {
      final failed = await ledger.execute(
        request(),
        operation: (_) async => throw StateError(
          '/PRIVATE_PATH file:///PRIVATE_URI PRIVATE_REVIEW synthetic report',
        ),
      );
      expect(failed.state, LocalExportLedgerState.unknown);
      expect(failed.errorCode, 'export_execution_unknown');
      expect(
        jsonEncode(ledger.read('export1')!.modelData),
        isNot(contains('PRIVATE')),
      );
    },
  );
}

class _RollbackDatabase implements ManagedDatabase {
  _RollbackDatabase(this.connection);
  final ManagedConnection connection;
  @override
  Database get raw => connection.raw;
  @override
  Future<T> write<T>(T Function(Database) body) => connection.write<T>((db) {
    body(db);
    throw StateError('synthetic commit failure');
  });
}

/// A provider may implement the shared interface without its constructor;
/// the host ledger must therefore copy rather than trust provider collections.
class _MutablePreparation implements LocalExportPreparation {
  _MutablePreparation(this.delegate)
    : bytes = Uint8List.fromList(delegate.bytes),
      sources = List.of(delegate.sources);
  final LocalExportPreparation delegate;
  @override
  final Uint8List bytes;
  @override
  final List<ObjectRef> sources;
  @override
  int get byteCount => bytes.length;
  @override
  LocalExportKind get kind => delegate.kind;
  @override
  String get formatVersion => delegate.formatVersion;
  @override
  String get mimeType => delegate.mimeType;
  @override
  DateTime get generatedAt => delegate.generatedAt;
  @override
  String get sha256 => delegate.sha256;
  @override
  int get dedupedObjectCount => delegate.dedupedObjectCount;
  @override
  List<LocalExportExclusion> get exclusions => delegate.exclusions;
  @override
  List<String> get warnings => delegate.warnings;
  @override
  int get preparationVersion => delegate.preparationVersion;
  @override
  String get manifestDigest => delegate.manifestDigest;
}
