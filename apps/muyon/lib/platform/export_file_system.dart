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

/// Availability of a platform-native secure export adapter.
enum ExportAdapterAvailability { available, unavailable }

/// Linux native adapter (O_TMPFILE + pinned directory fds + linkat).
///
/// Kept [ExportAdapterAvailability.unavailable]: PR #56 hold — directory
/// identity revalidation and the final [linkat] remain separate syscalls, so
/// `research/exports` containment is not proven. Callers must not treat an
/// unknown / unproven write path as a pass.
abstract final class ExportNativeLinux {
  static const availability = ExportAdapterAvailability.unavailable;

  static const unavailableReason =
      'linux_native_export_unavailable: research/exports containment '
      'unproven (identity check and linkat are separate syscalls)';

  /// Always refuses. Never returns an adapter that would write without a
  /// proven directory scope.
  static ExportFileSystem open() =>
      throw UnsupportedError(unavailableReason);
}

/// Path-based adapter over `dart:io`. Suitable for injectable tests against a
/// real filesystem in an approved environment; it is **not** the Linux native
/// secure adapter ([ExportNativeLinux]).
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
