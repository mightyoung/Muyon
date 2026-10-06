import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'storage_manager.dart';

/// Host-coordinated backup of all databases plus the file stores.
///
/// Databases are snapshotted with `VACUUM INTO` while every write queue is
/// held, never by copying a live database file. The manifest (sizes and
/// SHA-256 of every entry) is written last; a directory without a valid
/// manifest is not a backup. Restore only runs with the host closed and
/// moves the current data aside instead of deleting it.
abstract final class BackupService {
  static const format = 'muyon-backup-v1';
  static const manifestName = 'manifest.json';

  /// Re-downloadable, hash-pinned assets that are not user data.
  static const excludedDirs = ['ocr_models/'];
  static const _transientSegments = {'staging', 'tmp'};
  static const _sidecars = ['-wal', '-shm', '-journal'];

  static bool _skip(String rel) {
    if (rel == 'application.lock') return true;
    if (excludedDirs.any(rel.startsWith)) return true;
    if (p.posix.split(rel).any(_transientSegments.contains)) return true;
    return _sidecars.any(rel.endsWith);
  }

  /// Module id owning a database path, or null for non-database files.
  static String? _databaseId(String rel) {
    if (rel == 'muyon.sqlite') return 'muyon';
    final parts = p.posix.split(rel);
    if (parts.length == 3 &&
        parts[0] == 'modules' &&
        parts[2] == '${parts[1]}.sqlite') {
      return parts[1];
    }
    return null;
  }

  static Future<Map<String, Object?>> create(
    StorageManager storage,
    String targetDir,
  ) async {
    final target = Directory(targetDir);
    if (target.existsSync()) {
      throw StateError('Backup target already exists: $targetDir');
    }
    final partial = Directory('$targetDir.partial');
    if (partial.existsSync()) partial.deleteSync(recursive: true);
    partial.createSync(recursive: true);
    final root = storage.rootPath;

    final entries = await storage.quiesce((open) async {
      final result = <Map<String, Object?>>[];
      final files =
          Directory(root)
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .map(
                (f) => p.posix.joinAll(p.split(p.relative(f.path, from: root))),
              )
              .where((rel) => !_skip(rel))
              .toList()
            ..sort();
      for (final rel in files) {
        final source = p.join(root, rel);
        final dest = File(p.join(partial.path, rel));
        dest.parent.createSync(recursive: true);
        final id = _databaseId(rel);
        if (id != null) {
          final live = open[id];
          if (live != null) {
            live.raw.execute('VACUUM INTO ?', [dest.path]);
          } else {
            // Not opened this session, so nothing is writing it.
            final db = sqlite3.open(source, mode: OpenMode.readOnly);
            try {
              db.execute('VACUUM INTO ?', [dest.path]);
            } finally {
              db.close();
            }
          }
        } else {
          File(source).copySync(dest.path);
        }
        result.add(await _describe(partial.path, rel, id != null));
      }
      return result;
    });

    final manifest = <String, Object?>{
      'format': format,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'excluded': excludedDirs,
      'entries': entries,
    };
    File(
      p.join(partial.path, manifestName),
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
    partial.renameSync(targetDir);
    return manifest;
  }

  static Future<Map<String, Object?>> _describe(
    String dir,
    String rel,
    bool database,
  ) async {
    final file = File(p.join(dir, rel));
    return {
      'path': rel,
      'kind': database ? 'database' : 'file',
      'size': file.lengthSync(),
      'sha256': await _hash(file),
    };
  }

  static Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  /// Problems found; empty means every entry is present, unaltered, and
  /// every database passes `PRAGMA integrity_check`.
  static Future<List<String>> verify(String backupDir) async {
    final manifestFile = File(p.join(backupDir, manifestName));
    if (!manifestFile.existsSync()) return ['Missing $manifestName'];
    final Map<String, Object?> manifest;
    try {
      manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    } catch (error) {
      return ['Unreadable manifest: $error'];
    }
    if (manifest['format'] != format) return ['Unsupported format'];
    final problems = <String>[];
    for (final raw in manifest['entries'] as List? ?? const []) {
      final entry = raw as Map;
      final rel = entry['path'] as String;
      final path = p.normalize(p.join(backupDir, rel));
      if (p.isAbsolute(rel) || !p.isWithin(backupDir, path)) {
        problems.add('Unsafe path: $rel');
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) {
        problems.add('Missing: $rel');
        continue;
      }
      if (file.lengthSync() != entry['size'] ||
          await _hash(file) != entry['sha256']) {
        problems.add('Altered: $rel');
        continue;
      }
      if (entry['kind'] == 'database') {
        try {
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            final check = db.select('PRAGMA integrity_check').first.columnAt(0);
            if (check != 'ok') problems.add('Corrupt database: $rel ($check)');
          } finally {
            db.close();
          }
        } catch (error) {
          problems.add('Unreadable database: $rel ($error)');
        }
      }
    }
    return problems;
  }

  /// Replaces [rootPath] with a verified backup. The host must be closed.
  /// Returns where the previous data was moved; nothing is deleted.
  static Future<String> restore(String backupDir, String rootPath) async {
    if (StorageManager.isOpen(rootPath)) {
      throw StateError('Close Muyon before restoring');
    }
    final lockFile = File(p.join(rootPath, 'application.lock'));
    if (lockFile.existsSync()) {
      final lock = lockFile.openSync(mode: FileMode.append);
      try {
        lock.lockSync(FileLock.exclusive);
        lock.unlockSync();
      } catch (_) {
        throw StateError('Muyon data is open in another process');
      } finally {
        lock.closeSync();
      }
    }
    final problems = await verify(backupDir);
    if (problems.isNotEmpty) {
      throw StateError('Backup failed verification: ${problems.join('; ')}');
    }
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final staging = Directory('$rootPath.restore-$stamp')
      ..createSync(recursive: true);
    final manifest = jsonDecode(
      File(p.join(backupDir, manifestName)).readAsStringSync(),
    ) as Map;
    for (final raw in manifest['entries'] as List) {
      final rel = (raw as Map)['path'] as String;
      final dest = File(p.join(staging.path, rel));
      dest.parent.createSync(recursive: true);
      File(p.join(backupDir, rel)).copySync(dest.path);
    }
    final previous = '$rootPath.before-restore-$stamp';
    if (Directory(rootPath).existsSync()) {
      Directory(rootPath).renameSync(previous);
    }
    staging.renameSync(rootPath);
    return previous;
  }
}
