import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/export_file_system.dart';
import 'package:muyon/platform/local_export_staging.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

const _id = '6f1c2b3a-4d5e-4f60-8a71-92b3c4d5e6f7';
const _root = '/research';
const _exports = '/research/exports';

LocalExportPreparation _prep(
  String text, {
  LocalExportKind kind = LocalExportKind.report,
}) {
  final bytes = utf8.encode(text);
  return LocalExportPreparation(
    kind: kind,
    formatVersion: '1',
    mimeType: 'text/markdown',
    generatedAt: DateTime.utc(2026, 10, 11),
    bytes: bytes,
    sha256: sha256.convert(bytes).toString(),
    sources: const [],
    dedupedObjectCount: 0,
    exclusions: const [],
    warnings: const [],
    preparationVersion: 1,
    manifestDigest: 'a' * 64,
  );
}

String _hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// In-memory adapter with fault injection. Paths are posix-style strings.
final class FakeExportFs implements ExportFileSystem {
  final entries = <String, FileSystemEntityType>{
    _root: FileSystemEntityType.directory,
    _exports: FileSystemEntityType.directory,
  };
  final bytes = <String, Uint8List>{};

  bool failCreate = false;
  bool failWrite = false;
  bool failDelete = false;
  bool failRename = false;
  bool corruptRead = false;
  bool truncateRead = false;
  Future<void> Function(String path)? onWrite;
  Future<void> Function(String path)? onRead;

  @override
  Future<FileSystemEntityType> typeOf(String path) async =>
      entries[path] ?? FileSystemEntityType.notFound;

  @override
  Future<String> resolveRealPath(String path) async => path;

  @override
  Future<void> createDirectory(String path) async =>
      entries[path] = FileSystemEntityType.directory;

  @override
  Future<void> createExclusive(String path) async {
    if (failCreate) throw const FileSystemException('permission denied');
    if (entries.containsKey(path)) {
      throw const FileSystemException('already exists');
    }
    entries[path] = FileSystemEntityType.file;
    bytes[path] = Uint8List(0);
  }

  @override
  Future<void> writeAll(String path, Uint8List data) async {
    await onWrite?.call(path);
    if (failWrite) {
      // Half-written bytes reach the temp file before the failure.
      bytes[path] = Uint8List.fromList(data.sublist(0, data.length ~/ 2));
      throw const FileSystemException('No space left on device');
    }
    bytes[path] = Uint8List.fromList(data);
  }

  @override
  Future<Uint8List> readAll(String path) async {
    await onRead?.call(path);
    final stored = bytes[path]!;
    if (truncateRead) return stored.sublist(0, stored.length - 1);
    if (corruptRead) {
      return Uint8List.fromList(stored.reversed.toList());
    }
    return Uint8List.fromList(stored);
  }

  @override
  Future<void> rename(String from, String to) async {
    if (failRename) throw const FileSystemException('rename refused');
    entries[to] = FileSystemEntityType.file;
    bytes[to] = bytes.remove(from)!;
    entries.remove(from);
  }

  @override
  Future<void> delete(String path) async {
    if (failDelete) throw const FileSystemException('delete refused');
    entries.remove(path);
    bytes.remove(path);
  }

  List<String> get tempFiles =>
      entries.keys.where((k) => k.endsWith('.tmp')).toList();
}

void main() {
  late FakeExportFs fs;
  late LocalExportStager stager;
  late String nextId;

  setUp(() {
    fs = FakeExportFs();
    nextId = _id;
    stager = LocalExportStager(fileSystem: fs, newExportId: () => nextId);
  });

  Future<ExportGeneration> generate(
    LocalExportPreparation prep, {
    ExportCancellation? cancellation,
  }) => stager.generate(
    preparation: prep,
    researchDirectory: _root,
    cancellation: cancellation,
  );

  group('generation with the fake adapter', () {
    test(
      'a normal generation writes the frozen bytes at the host-named path',
      () async {
        final prep = _prep('# 报告\n正文');
        final result = await generate(prep);
        expect(result.stage.outcome, LocalExportOutcome.succeeded);
        expect(result.stage.cleanup, LocalExportCleanup.notNeeded);
        final path = '$_exports/report-$_id.md';
        expect(result.path, path);
        expect(fs.bytes[path], prep.bytes);
        expect(_hex(fs.bytes[path]!), prep.sha256);
        expect(fs.tempFiles, isEmpty);
      },
    );

    test(
      'a disk-full write fails, leaves no temp file and no final file',
      () async {
        fs.failWrite = true;
        final result = await generate(_prep('x'));
        expect(result.stage.outcome, LocalExportOutcome.failed);
        expect(result.stage.errorCode, 'write_failed');
        expect(result.stage.cleanup, LocalExportCleanup.cleaned);
        expect(fs.tempFiles, isEmpty);
        expect(fs.entries.containsKey('$_exports/report-$_id.md'), isFalse);
      },
    );

    test(
      'a half-written temp file never appears under the final name',
      () async {
        fs.failWrite = true;
        await generate(_prep('partial content'));
        expect(fs.entries.containsKey('$_exports/report-$_id.md'), isFalse);
      },
    );

    test(
      'a refused exclusive create fails without touching anything',
      () async {
        fs.failCreate = true;
        final result = await generate(_prep('x'));
        expect(result.stage.outcome, LocalExportOutcome.failed);
        expect(result.stage.errorCode, 'create_failed');
        expect(fs.tempFiles, isEmpty);
      },
    );

    test('cancelling while writing gives cancelled and no residue', () async {
      final cancellation = ExportCancellation();
      fs.onWrite = (_) async => cancellation.cancel();
      final result = await generate(_prep('x'), cancellation: cancellation);
      expect(result.stage.outcome, LocalExportOutcome.cancelled);
      expect(result.stage.cleanup, LocalExportCleanup.cleaned);
      expect(fs.tempFiles, isEmpty);
      expect(fs.entries.containsKey('$_exports/report-$_id.md'), isFalse);
    });

    test(
      'cancelling after the write but before commit leaves no final file',
      () async {
        final cancellation = ExportCancellation();
        fs.onRead = (_) async => cancellation.cancel();
        final result = await generate(_prep('x'), cancellation: cancellation);
        expect(result.stage.outcome, LocalExportOutcome.cancelled);
        expect(fs.entries.containsKey('$_exports/report-$_id.md'), isFalse);
        expect(fs.tempFiles, isEmpty);
      },
    );

    test('a failed cleanup is recorded as residue, never as cleaned', () async {
      fs.failWrite = true;
      fs.failDelete = true;
      final result = await generate(_prep('x'));
      expect(result.stage.outcome, LocalExportOutcome.failed);
      expect(result.stage.cleanup, LocalExportCleanup.residue);
      expect(fs.tempFiles, hasLength(1));
    });

    test('the same export id never overwrites an existing file', () async {
      final first = await generate(_prep('first version'));
      expect(first.stage.outcome, LocalExportOutcome.succeeded);
      final path = '$_exports/report-$_id.md';
      final second = await generate(_prep('second version'));
      expect(second.stage.outcome, LocalExportOutcome.failed);
      expect(second.stage.errorCode, 'name_taken');
      expect(utf8.decode(fs.bytes[path]!), 'first version');
      expect(fs.tempFiles, isEmpty);
    });

    test('a read-back with changed bytes fails the digest check and commits nothing', () async {
      fs.corruptRead = true;
      final result = await generate(_prep('abc'));
      expect(result.stage.outcome, LocalExportOutcome.failed);
      expect(result.stage.errorCode, 'digest_mismatch');
      expect(result.stage.cleanup, LocalExportCleanup.cleaned);
      expect(fs.entries.containsKey('$_exports/report-$_id.md'), isFalse);
      expect(fs.tempFiles, isEmpty);
    });

    test(
      'a read-back of the wrong length fails the digest check too',
      () async {
        fs.truncateRead = true;
        final result = await generate(_prep('abcdef'));
        expect(result.stage.errorCode, 'digest_mismatch');
        expect(fs.entries.containsKey('$_exports/report-$_id.md'), isFalse);
      },
    );

    test(
      'a refused commit cleans the temp file and reports commit_failed',
      () async {
        fs.failRename = true;
        final result = await generate(_prep('x'));
        expect(result.stage.errorCode, 'commit_failed');
        expect(result.stage.cleanup, LocalExportCleanup.cleaned);
        expect(fs.tempFiles, isEmpty);
      },
    );

    test('the claim-drafts kind uses its own host-named file', () async {
      final result = await generate(
        _prep('{"a":1}\n', kind: LocalExportKind.claimDrafts),
      );
      expect(result.path, '$_exports/workbench-claims-$_id.jsonl');
    });

    test('a host export id must be a lowercase UUID', () async {
      nextId = 'Not/An-ID';
      await expectLater(generate(_prep('x')), throwsArgumentError);
    });
  });

  group('real file system and symbolic links', () {
    late Directory tmp;
    late Directory research;
    late IoExportFileSystem io;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('le04-');
      research = Directory(p.join(tmp.path, 'research'))..createSync();
      io = IoExportFileSystem();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    LocalExportStager realStager() =>
        LocalExportStager(fileSystem: io, newExportId: () => _id);

    Future<ExportGeneration> realGenerate(LocalExportPreparation prep) =>
        realStager().generate(
          preparation: prep,
          researchDirectory: research.path,
        );

    test('a real generation writes exactly the frozen bytes', () async {
      final prep = _prep('真实文件');
      final result = await realGenerate(prep);
      expect(result.stage.outcome, LocalExportOutcome.succeeded);
      final file = File(p.join(research.path, 'exports', 'report-$_id.md'));
      expect(file.readAsBytesSync(), prep.bytes);
      expect(
        Directory(p.join(research.path, 'exports'))
            .listSync()
            .where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('an exports directory that is a symbolic link is refused', () async {
      final elsewhere = Directory(p.join(tmp.path, 'elsewhere'))..createSync();
      Link(p.join(research.path, 'exports')).createSync(elsewhere.path);
      final result = await realGenerate(_prep('x'));
      expect(result.stage.outcome, LocalExportOutcome.failed);
      expect(result.stage.errorCode, 'unsafe_directory');
      expect(elsewhere.listSync(), isEmpty);
    });

    test(
      'an exports link pointing inside the research folder is still refused',
      () async {
        final inside = Directory(p.join(research.path, 'inside'))..createSync();
        Link(p.join(research.path, 'exports')).createSync(inside.path);
        final result = await realGenerate(_prep('x'));
        expect(result.stage.errorCode, 'unsafe_directory');
        expect(inside.listSync(), isEmpty);
      },
    );

    test(
      'a dangling symbolic link at the final name is never replaced',
      () async {
        final exports = Directory(p.join(research.path, 'exports'))
          ..createSync();
        final target = p.join(tmp.path, 'outside.md');
        Link(p.join(exports.path, 'report-$_id.md')).createSync(target);
        final result = await realGenerate(_prep('x'));
        expect(result.stage.outcome, LocalExportOutcome.failed);
        expect(result.stage.errorCode, 'unsafe_target');
        expect(
          FileSystemEntity.typeSync(
            p.join(exports.path, 'report-$_id.md'),
            followLinks: false,
          ),
          FileSystemEntityType.link,
        );
        expect(File(target).existsSync(), isFalse);
      },
    );
  });
}
