import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/supplier_core.dart' show newUuid;

import 'export_file_system.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Cooperative cancellation for one generation. Checked between steps; the
/// committed file is never removed afterwards.
final class ExportCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// The generation stage result, and the committed path on success.
final class ExportGeneration {
  const ExportGeneration({required this.stage, this.path});
  final LocalExportStage stage;
  final String? path;
}

/// Raised inside one generation for a refusal decided before any temp file
/// exists; mapped to a failed stage with nothing to clean.
final class _Refusal implements Exception {
  _Refusal(this.code);
  final String code;
}

/// Generates one export file under `<research>/exports`: exclusive temp file,
/// frozen bytes, read-back digest check, then a no-overwrite commit. Saving to
/// a chosen location is a separate stage and is not done here.
final class LocalExportStager {
  LocalExportStager({
    required ExportFileSystem fileSystem,
    String Function()? newExportId,
  }) : _fs = fileSystem,
       _newExportId = newExportId ?? newUuid;

  final ExportFileSystem _fs;
  final String Function() _newExportId;

  Future<ExportGeneration> generate({
    required LocalExportPreparation preparation,
    required String researchDirectory,
    ExportCancellation? cancellation,
  }) async {
    final exportId = _newExportId();
    if (!_uuid.hasMatch(exportId)) {
      throw ArgumentError.value(
        exportId,
        'exportId',
        'expected a lowercase UUID',
      );
    }
    final name = switch (preparation.kind) {
      LocalExportKind.report => 'report-$exportId.md',
      LocalExportKind.claimDrafts => 'workbench-claims-$exportId.jsonl',
    };
    try {
      final exportsDir = await _safeExportsDirectory(researchDirectory);
      final finalPath = p.join(exportsDir, name);
      await _refuseIfOccupied(finalPath);
      return await _writeAndCommit(
        preparation,
        tempPath: p.join(exportsDir, '.$name.tmp'),
        finalPath: finalPath,
        cancellation: cancellation,
      );
    } on _Refusal catch (refusal) {
      return ExportGeneration(
        stage: LocalExportStage(
          LocalExportOutcome.failed,
          errorCode: refusal.code,
        ),
      );
    }
  }

  /// The exports folder must be a real folder (not a link) inside the research
  /// folder. Containment compares resolved real paths with [p.isWithin], never
  /// raw string prefixes.
  Future<String> _safeExportsDirectory(String researchDirectory) async {
    if (await _fs.typeOf(researchDirectory) != FileSystemEntityType.directory) {
      throw _Refusal('unsafe_directory');
    }
    final exportsDir = p.join(researchDirectory, 'exports');
    final type = await _fs.typeOf(exportsDir);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.file) {
      throw _Refusal('unsafe_directory');
    }
    if (type == FileSystemEntityType.notFound) {
      try {
        await _fs.createDirectory(exportsDir);
      } on Object {
        throw _Refusal('create_failed');
      }
    }
    final realRoot = await _fs.resolveRealPath(researchDirectory);
    final realExports = await _fs.resolveRealPath(exportsDir);
    if (!p.isWithin(realRoot, realExports)) {
      throw _Refusal('unsafe_directory');
    }
    return realExports;
  }

  /// Never overwrite: an existing entry (including a dangling link, which
  /// would otherwise be replaced by the rename) refuses the export.
  Future<void> _refuseIfOccupied(String finalPath) async {
    final type = await _fs.typeOf(finalPath);
    if (type == FileSystemEntityType.link) throw _Refusal('unsafe_target');
    if (type != FileSystemEntityType.notFound) throw _Refusal('name_taken');
  }

  Future<ExportGeneration> _writeAndCommit(
    LocalExportPreparation prep, {
    required String tempPath,
    required String finalPath,
    ExportCancellation? cancellation,
  }) async {
    bool cancelRequested() => cancellation?.isCancelled ?? false;

    try {
      await _fs.createExclusive(tempPath);
    } on Object {
      // Nothing was created by us, so there is nothing to clean up.
      return ExportGeneration(
        stage: LocalExportStage(
          LocalExportOutcome.failed,
          errorCode: 'create_failed',
        ),
      );
    }

    Future<ExportGeneration> failed(String code) async => ExportGeneration(
      stage: LocalExportStage(
        LocalExportOutcome.failed,
        cleanup: await _cleanup(tempPath),
        errorCode: code,
      ),
    );
    Future<ExportGeneration> cancelled() async => ExportGeneration(
      stage: LocalExportStage(
        LocalExportOutcome.cancelled,
        cleanup: await _cleanup(tempPath),
      ),
    );

    try {
      await _fs.writeAll(tempPath, prep.bytes);
    } on Object {
      return failed('write_failed');
    }
    if (cancelRequested()) return cancelled();

    final Uint8List readBack;
    try {
      readBack = await _fs.readAll(tempPath);
    } on Object {
      return failed('verify_failed');
    }
    if (readBack.length != prep.byteCount ||
        sha256.convert(readBack).toString() != prep.sha256) {
      return failed('digest_mismatch');
    }
    if (cancelRequested()) return cancelled();

    try {
      await _refuseIfOccupied(finalPath);
    } on _Refusal catch (refusal) {
      return failed(refusal.code);
    }
    try {
      await _fs.rename(tempPath, finalPath);
    } on Object {
      return failed('commit_failed');
    }
    return ExportGeneration(
      stage: LocalExportStage(LocalExportOutcome.succeeded),
      path: finalPath,
    );
  }

  /// Removes this generation's temp file. A failed removal is reported as
  /// residue, and a failed check as unknown; never as cleaned.
  Future<LocalExportCleanup> _cleanup(String tempPath) async {
    try {
      if (await _fs.typeOf(tempPath) == FileSystemEntityType.notFound) {
        return LocalExportCleanup.cleaned;
      }
    } on Object {
      return LocalExportCleanup.unknown;
    }
    try {
      await _fs.delete(tempPath);
    } on Object {
      return LocalExportCleanup.residue;
    }
    try {
      return await _fs.typeOf(tempPath) == FileSystemEntityType.notFound
          ? LocalExportCleanup.cleaned
          : LocalExportCleanup.residue;
    } on Object {
      return LocalExportCleanup.unknown;
    }
  }
}
