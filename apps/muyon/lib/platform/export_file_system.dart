import 'dart:io';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

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

  /// Atomically commits the owned inode without replacing any entry at [to].
  Future<void> rename(String from, String to);

  Future<void> delete(String path);
}

/// The real adapter over `dart:io`.
final class IoExportFileSystem
    implements ExportFileSystem, ExportFileSystemScopeFactory {
  @override
  Future<ExportFileSystemScope> openScope(String researchDirectory) async =>
      _native.openScope(researchDirectory);
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
    throw const FileSystemException('Commit requires an owned export scope');
  }

  @override
  Future<void> delete(String path) => File(path).delete();
}

/// A scope holds directory identity for the whole operation, including cleanup.
abstract interface class ExportFileSystemScopeFactory {
  Future<ExportFileSystemScope> openScope(String researchDirectory);
}

abstract interface class ExportFileSystemScope implements ExportFileSystem {
  void close();
}

/// Linux guarantees used here: openat(O_NOFOLLOW) pins each directory;
/// O_TMPFILE gives us an unnamed inode; linkat follows our /proc fd reference
/// and creates the final directory entry atomically, refusing an existing name.
/// No user-controlled temporary pathname is opened, renamed or deleted.
final class _LinuxExportScope implements ExportFileSystemScope {
  _LinuxExportScope(this.root, this.rootFd, this.directoryFd);

  final String root;
  final int rootFd;
  final int directoryFd;
  final _temps = <String, int>{};
  String get exports => p.join(root, 'exports');

  String _name(String path) {
    if (p.dirname(path) != exports) {
      throw FileSystemException('Path outside pinned export directory', path);
    }
    return p.basename(path);
  }

  String _anchored(String path) => '/proc/self/fd/$directoryFd/${_name(path)}';

  @override
  Future<FileSystemEntityType> typeOf(String path) async {
    if (path == root || path == exports) return FileSystemEntityType.directory;
    if (_temps.containsKey(path)) return FileSystemEntityType.file;
    return FileSystemEntity.type(_anchored(path), followLinks: false);
  }

  @override
  Future<String> resolveRealPath(String path) async {
    if (path != root && path != exports) _name(path);
    return path;
  }

  @override
  Future<void> createDirectory(String path) async {
    throw FileSystemException('Scope directory already exists', path);
  }

  @override
  Future<void> createExclusive(String path) async {
    _name(path);
    if (_temps.containsKey(path) ||
        await typeOf(path) != FileSystemEntityType.notFound) {
      throw FileSystemException('Temporary name occupied', path);
    }
    final fd = _native.openAt(directoryFd, '.', 0x410000 | 0x80000 | 2, 0x180);
    if (fd < 0) {
      throw FileSystemException('Anonymous temporary file unsupported', path);
    }
    _temps[path] = fd;
  }

  int _owned(String path) =>
      _temps[path] ??
      (throw FileSystemException('No owned temporary inode', path));

  @override
  Future<void> writeAll(String path, Uint8List bytes) async {
    final fd = _owned(path);
    _native.withBytes(bytes, (buffer) {
      var offset = 0;
      while (offset < bytes.length) {
        final count = _native.write(fd, buffer + offset, bytes.length - offset);
        if (count <= 0) throw FileSystemException('Write failed', path);
        offset += count;
      }
    });
    if (_native.sync(fd) != 0) throw FileSystemException('Flush failed', path);
  }

  @override
  Future<Uint8List> readAll(String path) async {
    final fd = _owned(path);
    final builder = BytesBuilder(copy: false);
    _native.withBytes(Uint8List(65536), (buffer) {
      var offset = 0;
      while (true) {
        final count = _native.readAt(fd, buffer, 65536, offset);
        if (count < 0) throw FileSystemException('Read failed', path);
        if (count == 0) break;
        builder.add(Uint8List.fromList(buffer.asTypedList(count)));
        offset += count;
      }
    });
    return builder.takeBytes();
  }

  @override
  Future<void> rename(String from, String to) async {
    final fd = _owned(from);
    final name = _name(to);
    if (_native.link(-100, '/proc/self/fd/$fd', directoryFd, name, 0x400) !=
        0) {
      throw FileSystemException('Atomic no-replace commit failed', to);
    }
    _temps.remove(from);
    _native.closeFd(fd);
  }

  @override
  Future<void> delete(String path) async {
    final fd = _owned(path);
    // Linux releases the descriptor even on an interrupted close. Never retry
    // a descriptor number that may have been reused by another operation.
    _temps.remove(path);
    if (_native.closeFd(fd) != 0) {
      throw FileSystemException('Temporary inode close failed', path);
    }
  }

  @override
  void close() {
    for (final fd in _temps.values) {
      _native.closeFd(fd);
    }
    _temps.clear();
    _native.closeFd(directoryFd);
    _native.closeFd(rootFd);
  }
}

final _native = _LinuxCalls();

/// Fixed-signature libc bindings, with allocations owned only for each call.
final class _LinuxCalls {
  late final _lib = DynamicLibrary.open('libc.so.6');
  late final _malloc = _lib
      .lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)
      >('malloc');
  late final _free = _lib
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  late final _openAt = _lib
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Int32, Uint32),
        int Function(int, Pointer<Uint8>, int, int)
      >('openat');
  late final _mkdirAt = _lib
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Uint32),
        int Function(int, Pointer<Uint8>, int)
      >('mkdirat');
  late final closeFd = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  late final sync = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');
  late final write = _lib
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  late final readAt = _lib
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
        int Function(int, Pointer<Uint8>, int, int)
      >('pread');
  late final _linkAt = _lib
      .lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Int32),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int)
      >('linkat');

  T withBytes<T>(Uint8List bytes, T Function(Pointer<Uint8>) action) {
    final ptr = _malloc(bytes.isEmpty ? 1 : bytes.length);
    if (ptr == nullptr) throw const FileSystemException('Allocation failed');
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return action(ptr);
    } finally {
      _free(ptr);
    }
  }

  T _string<T>(String value, T Function(Pointer<Uint8>) action) {
    if (value.contains('\u0000')) {
      throw const FileSystemException('Invalid path');
    }
    return withBytes(Uint8List.fromList([...utf8.encode(value), 0]), action);
  }

  int openAt(int fd, String path, int flags, int mode) =>
      _string(path, (ptr) => _openAt(fd, ptr, flags, mode));
  int mkdirAt(int fd, String path) =>
      _string(path, (ptr) => _mkdirAt(fd, ptr, 0x1c0));
  int link(int fromFd, String from, int toFd, String to, int flags) => _string(
    from,
    (a) => _string(to, (b) => _linkAt(fromFd, a, toFd, b, flags)),
  );

  ExportFileSystemScope openScope(String path) {
    if (!Platform.isLinux ||
        (Abi.current() != Abi.linuxX64 && Abi.current() != Abi.linuxArm64)) {
      throw const FileSystemException(
        'Secure export IO unsupported on this platform',
      );
    }
    final root = p.normalize(p.absolute(path));
    var fd = openAt(-100, '/', 0x10000 | 0x20000 | 0x80000, 0);
    if (fd < 0) throw FileSystemException('Cannot open filesystem root', root);
    try {
      for (final part in p.split(root).skip(1)) {
        final next = openAt(fd, part, 0x10000 | 0x20000 | 0x80000, 0);
        if (next < 0) {
          throw FileSystemException('Unsafe research directory', root);
        }
        closeFd(fd);
        fd = next;
      }
      // Existing entries are validated by O_DIRECTORY | O_NOFOLLOW below.
      mkdirAt(fd, 'exports');
      final exportsFd = openAt(fd, 'exports', 0x10000 | 0x20000 | 0x80000, 0);
      if (exportsFd < 0) {
        throw FileSystemException('Unsafe export directory', root);
      }
      return _LinuxExportScope(root, fd, exportsFd);
    } on Object {
      closeFd(fd);
      rethrow;
    }
  }
}
