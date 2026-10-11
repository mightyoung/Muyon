import 'dart:io';
import 'dart:typed_data';

/// The file-system operations the export stager needs, behind an adapter so
/// tests can inject disk-full, permission, close and cleanup failures.
///
/// [typeOf] never follows links: a symbolic link reports as
/// [FileSystemEntityType.link]. [createExclusive] must fail if the path exists.
abstract interface class ExportFileSystem {
  Future<FileSystemEntityType> typeOf(String path);

  /// Fully resolved path (symbolic links followed), for containment checks.
  Future<String> resolveRealPath(String path);

  Future<void> createDirectory(String path);

  /// Creates an empty file; fails if anything already exists at [path].
  Future<void> createExclusive(String path);

  /// Writes all of [bytes] to an existing file, flushing and closing it.
  Future<void> writeAll(String path, Uint8List bytes);

  Future<Uint8List> readAll(String path);

  /// Moves [from] to [to]. The caller checks that [to] is free first.
  Future<void> rename(String from, String to);

  Future<void> delete(String path);
}

/// The real adapter over `dart:io`.
final class IoExportFileSystem implements ExportFileSystem {
  @override
  Future<FileSystemEntityType> typeOf(String path) =>
      FileSystemEntity.type(path, followLinks: false);

  @override
  Future<String> resolveRealPath(String path) async {
    final type = await FileSystemEntity.type(path);
    return type == FileSystemEntityType.directory
        ? Directory(path).resolveSymbolicLinks()
        : File(path).resolveSymbolicLinks();
  }

  @override
  Future<void> createDirectory(String path) =>
      Directory(path).create(recursive: false);

  @override
  Future<void> createExclusive(String path) async {
    await File(path).create(exclusive: true);
  }

  @override
  Future<void> writeAll(String path, Uint8List bytes) async {
    final handle = await File(path).open(mode: FileMode.write);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  @override
  Future<Uint8List> readAll(String path) => File(path).readAsBytes();

  @override
  Future<void> rename(String from, String to) async {
    await File(from).rename(to);
  }

  @override
  Future<void> delete(String path) => File(path).delete();
}
