import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/grants/local_export_target.dart';
import 'package:muyon/platform/local_export_ledger.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/isolated_flutter_project.dart';

const _file = 'test/le06_recovery_independent_test.dart';
const _pathCanary = '/synthetic/LE06_PATH_91dfe';
const _uriCanary = 'content://synthetic/LE06_URI_a32cb';
const _handleCanary = 'LE06_HANDLE_473ad';
const _bodyCanary = 'LE06_BODY_731cc';
const _errorCanary = 'le06_private_error_3fa19';

LocalExportPreparation _preparation([String body = _bodyCanary]) =>
    LocalExportPreparation(
      kind: LocalExportKind.report,
      formatVersion: '1',
      mimeType: 'text/markdown',
      generatedAt: DateTime.utc(2026, 10, 12),
      bytes: utf8.encode(body),
      sha256: sha256.convert(utf8.encode(body)).toString(),
      sources: const [],
      dedupedObjectCount: 0,
      exclusions: const [],
      warnings: const [],
      preparationVersion: 1,
      manifestDigest: 'a' * 64,
    );

LocalExportLedgerRequest _request(
  LocalExportTargetIssuer issuer, {
  LocalExportPreparation? preparation,
  String scope = '',
  LocalExportTargetCapability? target,
  Map<String, Object?> metadata = const {},
}) => LocalExportLedgerRequest(
  exportId: 'independent',
  toolId: 'research.export_report',
  invocationId: target == null ? 'generation' : 'saving',
  phase: target == null ? LocalExportPhase.generate : LocalExportPhase.save,
  attemptId: target == null ? null : 'attempt1',
  scopeDigest: scope.isEmpty ? 'b' * 64 : scope,
  preparation: preparation ?? _preparation(),
  targetIssuer: issuer,
  target: target,
  policyVersion: 'p1',
  hostMetadata: metadata,
);

Future<LocalExportStageCompletion> _success(List<int> _) async =>
    LocalExportStageCompletion(LocalExportStage(LocalExportOutcome.succeeded));

Matcher _error(String code) => throwsA(
  isA<LocalExportLedgerException>().having((e) => e.code, 'code', code),
);

// A child is a separate Flutter tester OS process with a separately opened
// SQLite connection. No inherited ledger, issuer, or in-memory running map.
Future<Process> _child(Directory dir, String mode, String name) async {
  final project = IsolatedFlutterProject.create();
  addTearDown(project.dispose);
  final process = await Process.start(
    Platform.environment['LE06_FLUTTER'] ?? 'flutter',
    ['test', '--no-pub', _file, '--plain-name', 'child process fixture'],
    workingDirectory: project.directory.path,
    environment: {
      'LE06_CHILD_DIR': dir.path,
      'LE06_CHILD_MODE': mode,
      'LE06_CHILD_NAME': name,
    },
  );
  addTearDown(() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  });
  return process;
}

Future<void> _finish(Process process) async {
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode.timeout(const Duration(seconds: 90));
  expect(code, 0, reason: '${await output}\n${await errors}');
}

Future<void> _waitFor(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!file.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Child synchronization timed out: ${file.uri.pathSegments.last}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void _noCanaries(Object? model) {
  final encoded = jsonEncode(model);
  for (final canary in [
    _pathCanary,
    _uriCanary,
    _handleCanary,
    _bodyCanary,
    _errorCanary,
  ]) {
    expect(encoded, isNot(contains(canary)), reason: canary);
  }
}

void main() {
  test('child process fixture', () async {
    final root = Platform.environment['LE06_CHILD_DIR'];
    if (root == null) return;
    final dir = Directory(root);
    final mode = Platform.environment['LE06_CHILD_MODE']!;
    final name = Platform.environment['LE06_CHILD_NAME']!;
    final db = ManagedConnection(sqlite3.open('$root/ledger.sqlite'));
    final projectRoot = Directory.current.absolute.uri;
    final nativeManifest = File(
      'build/unit_test_assets/NativeAssetsManifest.json',
    );
    final assetMap =
        (jsonDecode(nativeManifest.readAsStringSync())
                as Map<String, dynamic>)['native-assets']
            as Map<String, dynamic>;
    final libraryPaths = assetMap.values
        .cast<Map<String, dynamic>>()
        .expand((target) => target.values)
        .cast<List<dynamic>>()
        .map((entry) => entry.last as String)
        .toList();
    File('$root/project-$name.json').writeAsStringSync(
      jsonEncode({
        'root': projectRoot.toFilePath(),
        'manifest': nativeManifest.absolute.path,
        'libraries': libraryPaths,
        'config': File('.dart_tool/package_config.json').absolute.path,
      }),
    );
    final issuer = LocalExportTargetIssuer();
    final ledger = LocalExportLedger(db);
    var calls = 0;
    try {
      if (mode == 'pending-failure') {
        LocalExportLedger.createTables(db.raw);
        db.raw.execute('''CREATE TRIGGER deny_pending BEFORE INSERT ON
local_export_attempts BEGIN SELECT RAISE(ABORT, '$_pathCanary'); END''');
      }
      if (mode == 'completion-failure') {
        LocalExportLedger.createTables(db.raw);
        db.raw.execute('''CREATE TRIGGER deny_completion BEFORE UPDATE ON
local_export_attempts BEGIN SELECT RAISE(ABORT, '$_uriCanary'); END''');
      }
      if (mode == 'race') {
        File('$root/ready-$name').writeAsStringSync('ready');
        await _waitFor(File('$root/go'));
      }
      LocalExportLedgerStageRecord? record;
      String? error;
      try {
        record = await ledger.execute(
          _request(issuer),
          operation: (bytes) async {
            calls++;
            expect(db.raw.autocommit, isTrue);
            if (mode != 'pending-failure') {
              expect(
                db.raw
                    .select('SELECT state FROM local_export_attempts')
                    .single['state'],
                'pending',
              );
            }
            if (mode == 'race') {
              File('$root/entered-$name')
                  .writeAsStringSync('pending committed');
              await _waitFor(File('$root/release'));
            }
            return _success(bytes);
          },
        );
      } on LocalExportLedgerException catch (e) {
        error = e.code;
      }
      if (mode == 'cancel') {
        await ledger.cancelSave(
          exportId: 'independent',
          invocationId: 'cancel',
          attemptId: 'cancel1',
        );
      }
      File('${dir.path}/result-$name.json').writeAsStringSync(
        jsonEncode({
          'calls': calls,
          'state': record?.state.name,
          'error': error,
        }),
      );
    } finally {
      await db.close();
    }
  });

  // Parent cases only. Child execution selects the fixture by its exact name.
  late Directory dir;
  late ManagedConnection db;
  late LocalExportLedger ledger;
  late LocalExportTargetIssuer issuer;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('le06-independent-');
    db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
    ledger = LocalExportLedger(db);
    issuer = LocalExportTargetIssuer();
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });
  Map<String, dynamic> result(String name) =>
      jsonDecode(File('${dir.path}/result-$name.json').readAsStringSync())
          as Map<String, dynamic>;

  test('disk pending failure rolls back and executes zero callbacks across process', () async {
    await db.close();
    await _finish(await _child(dir, 'pending-failure', 'writer'));
    db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
    ledger = LocalExportLedger(db);
    expect(result('writer'), {
      'calls': 0,
      'state': null,
      'error': 'ledger_pending_failed',
    });
    expect(ledger.read('independent'), isNull);
    expect(db.raw.select('SELECT * FROM local_export_attempts'), isEmpty);
    expect(db.raw.select('SELECT * FROM local_export_exports'), isEmpty);
    _noCanaries(result('writer'));
  });

  test('process exit after completion failure retains pending and read-only unknown', () async {
    await db.close();
    await _finish(await _child(dir, 'completion-failure', 'writer'));
    db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
    ledger = LocalExportLedger(db);
    expect(result('writer')['calls'], 1);
    expect(result('writer')['state'], 'interrupted');
    expect(
      db.raw.select('SELECT state FROM local_export_attempts').single['state'],
      'pending',
    );
    db.raw.execute('DROP TRIGGER deny_completion');
    final before = db.raw
        .select('SELECT * FROM local_export_attempts')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    var calls = 0, commits = 0, probes = 0;
    db.onCommit = () => commits++;
    expect(
      ledger.read('independent')!.generate!.state,
      LocalExportLedgerState.unknown,
    );
    final replay = await ledger.execute(
      _request(issuer),
      operation: (_) async {
        calls++;
        return _success([]);
      },
    );
    expect(replay.state, LocalExportLedgerState.unknown);
    final observed = await ledger.check(
      'independent',
      probe: (_) async {
        probes++;
        return _success([]);
      },
    );
    expect(observed!.generate!.state, LocalExportLedgerState.succeeded);
    expect(observed.generate!.modelData['status'], 'unknown');
    expect(
      ledger.read('independent')!.generate!.state,
      LocalExportLedgerState.unknown,
    );
    expect(calls, 0);
    expect(commits, 0);
    expect(probes, 1);
    expect(
      db.raw
          .select('SELECT * FROM local_export_attempts')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
      before,
    );
    _noCanaries(observed.modelData);
  });

  test(
    'process reopen separates generated success from save cancellation',
    () async {
      await db.close();
      await _finish(await _child(dir, 'cancel', 'writer'));
      db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
      ledger = LocalExportLedger(db);
      final receipt = ledger.read('independent')!;
      expect(receipt.generate!.state, LocalExportLedgerState.succeeded);
      expect(
        receipt.saveAttempts.single.state,
        LocalExportLedgerState.cancelled,
      );
      expect(receipt.modelData['generate'], {'status': 'succeeded'});
      expect(receipt.modelData['saveAttempts'], [
        {'status': 'cancelled'},
      ]);
      expect(
        (await ledger.cancelSave(
          exportId: 'independent',
          invocationId: 'cancel',
          attemptId: 'cancel1',
        )).state,
        LocalExportLedgerState.cancelled,
      );
      _noCanaries(receipt.modelData);
    },
  );

  test(
    'disk replay rejects changed content scope and target identity',
    () async {
      await ledger.execute(_request(issuer), operation: _success);
      final originalTarget = issuer.issue(_pathCanary);
      final save = _request(issuer, target: originalTarget);
      await ledger.execute(save, operation: _success);
      await db.close();
      db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
      ledger = LocalExportLedger(db);
      var calls = 0;
      for (final changed in [
        _request(issuer, preparation: _preparation('different synthetic body')),
        _request(issuer, scope: 'c' * 64),
        _request(issuer, target: issuer.issue(_uriCanary)),
      ]) {
        await expectLater(
          ledger.execute(
            changed,
            operation: (_) async {
              calls++;
              return _success([]);
            },
          ),
          _error('export_identity_conflict'),
        );
      }
      expect(calls, 0);
      expect(
        db.raw.select('SELECT * FROM local_export_attempts'),
        hasLength(2),
      );
      expect(
        ledger.read('independent')!.saveAttempts.single.targetIdentityDigest,
        save.targetIdentityDigest,
      );
    },
  );

  test('child Flutter runner leaves parent native asset manifest untouched', () async {
    final manifest = File('build/unit_test_assets/NativeAssetsManifest.json');
    expect(manifest.existsSync(), isTrue);
    final before = manifest.statSync();
    final contents = manifest.readAsBytesSync();
    await _finish(await _child(dir, 'pending-failure', 'isolated-assets'));
    final project = jsonDecode(
      File('${dir.path}/project-isolated-assets.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final privateRoot = project['root'] as String;
    expect(privateRoot, isNot(Directory.current.absolute.path));
    expect(project['manifest'], startsWith(privateRoot));
    expect(project['config'], startsWith(privateRoot));
    expect(project['libraries'], isNotEmpty);
    for (final library in project['libraries'] as List<dynamic>) {
      expect(library, startsWith(privateRoot));
      expect(File(library as String).existsSync(), isTrue);
    }
    // ignore: avoid_print
    print('LE06-ASSET-ISOLATION ${jsonEncode(project)}');
    expect(manifest.readAsBytesSync(), contents);
    expect(
      manifest.statSync().modified,
      before.modified,
      reason:
          'nested Flutter builders must not rewrite assets used by other tests',
    );
  });

  test('two independently gated processes contend for one pending reservation', () async {
    LocalExportLedger.createTables(db.raw);
    await db.close();
    final first = await _child(dir, 'race', 'first');
    final firstDone = _finish(first);
    // Each child has private build assets. Release both independent database
    // contenders together after their separate SQLite connections are ready.
    await _waitFor(File('${dir.path}/ready-first'));
    final second = await _child(dir, 'race', 'second');
    final secondDone = _finish(second);
    try {
      await Future.wait([
        _waitFor(File('${dir.path}/ready-first')),
        _waitFor(File('${dir.path}/ready-second')),
      ]);
      File('${dir.path}/go').writeAsStringSync('start both');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!File('${dir.path}/result-first.json').existsSync() &&
          !File('${dir.path}/result-second.json').existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('No losing process result');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      File('${dir.path}/release').writeAsStringSync('release winner');
      await Future.wait([firstDone, secondDone]);
      db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
      ledger = LocalExportLedger(db);
    }
    final firstProject = jsonDecode(
      File('${dir.path}/project-first.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final secondProject = jsonDecode(
      File('${dir.path}/project-second.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(firstProject['root'], isNot(secondProject['root']));
    expect(firstProject['config'], isNot(secondProject['config']));
    expect(firstProject['manifest'], isNot(secondProject['manifest']));
    // ignore: avoid_print
    print('LE06-CHILD-PROJECTS ${jsonEncode([firstProject, secondProject])}');
    final results = [result('first'), result('second')];
    // LE06-RACE evidence: print both child outcomes before asserting.
    // ignore: avoid_print
    print('LE06-RACE results=${jsonEncode(results)}');
    expect(
      results.map((r) => r['calls']).reduce((a, b) => a + b),
      1,
      reason: 'LE06-RACE results=${jsonEncode(results)}',
    );
    expect(
      results.where((r) => r['state'] == 'succeeded'),
      hasLength(1),
      reason: 'LE06-RACE results=${jsonEncode(results)}',
    );
    final loser = results.singleWhere((r) => r['calls'] == 0);
    // SQLite may reject a lock contender; no automatic retry is promised.
    expect(
      loser['state'] == 'unknown' || loser['error'] == 'ledger_pending_failed',
      isTrue,
      reason:
          'LE06-RACE loser=${jsonEncode(loser)} results=${jsonEncode(results)}',
    );
    expect(db.raw.select('SELECT * FROM local_export_attempts'), hasLength(1));
    expect(
      ledger.read('independent')!.generate!.state,
      LocalExportLedgerState.succeeded,
    );
  });

  test('nested audits stay frozen on disk and all model error projections redact canaries', () async {
    final nested = <String, Object?>{
      'list': <Object?>[
        <String, Object?>{'path': _pathCanary, 'uri': _uriCanary},
      ],
    };
    final req = _request(issuer, metadata: nested);
    ((nested['list']! as List).single as Map)['path'] =
        'changed before execute';
    final completionData = <String, Object?>{
      'nested': <Object?>[
        <String, Object?>{'handle': _handleCanary, 'body': _bodyCanary},
      ],
    };
    final completion = LocalExportStageCompletion(
      LocalExportStage(LocalExportOutcome.failed, errorCode: _errorCanary),
      hostMetadata: completionData,
    );
    ((completionData['nested']! as List).single as Map)['body'] = 'changed';
    final returned = await ledger.execute(
      req,
      operation: (_) async => completion,
    );
    _noCanaries(returned.modelData);
    await db.close();
    db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
    ledger = LocalExportLedger(db);
    final receipt = ledger.read('independent')!;
    final audit = receipt.generate!.hostMetadata;
    expect(
      (((audit['request'] as Map)['list'] as List).single as Map)['path'],
      _pathCanary,
    );
    expect(
      (((audit['completion'] as Map)['nested'] as List).single as Map)['body'],
      _bodyCanary,
    );
    expect(
      () =>
          (((audit['request'] as Map)['list'] as List).single as Map)['path'] =
              'changed',
      throwsUnsupportedError,
    );
    expect(receipt.generate!.modelData['errorCode'], 'export_failed');
    _noCanaries(receipt.modelData);
    _noCanaries(jsonDecode(jsonEncode(receipt.modelData)));
    await expectLater(
      ledger.execute(_request(issuer, scope: 'c' * 64), operation: _success),
      _error('export_identity_conflict'),
    );
    _noCanaries(
      const LocalExportLedgerException('ledger_read_failed').toString(),
    );
  });

  test('raw callback error survives disk reopen only in host audit', () async {
    final returned = await ledger.execute(
      _request(issuer),
      operation: (_) async {
        throw StateError(
          '$_pathCanary $_uriCanary $_handleCanary $_bodyCanary',
        );
      },
    );
    expect(returned.state, LocalExportLedgerState.unknown);
    _noCanaries(returned.modelData);
    await db.close();
    db = ManagedConnection(sqlite3.open('${dir.path}/ledger.sqlite'));
    ledger = LocalExportLedger(db);
    final receipt = ledger.read('independent')!;
    final rawError =
        (receipt.generate!.hostMetadata['completion'] as Map)['rawError']
            as String;
    for (final canary in [
      _pathCanary,
      _uriCanary,
      _handleCanary,
      _bodyCanary,
    ]) {
      expect(rawError, contains(canary));
    }
    expect(receipt.generate!.modelData, {
      'status': 'unknown',
      'errorCode': 'export_execution_unknown',
    });
    _noCanaries(receipt.modelData);
    _noCanaries(jsonDecode(jsonEncode(receipt.modelData)));
  });
}
