import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/lan.dart';
import 'package:uuid/uuid.dart';

class TransferReceipt {
  const TransferReceipt(this.id, this.digest, this.paths, this.receivedAt);
  final String id, digest;
  final List<String> paths;
  final DateTime receivedAt;
}

/// Explicit package exchange, also used over the existing supplier LAN stack.
/// LAN is opt-in and plaintext; no listener starts during host construction.
class TransferService {
  TransferService(this.database, this.rootPath);
  final ManagedDatabase database;
  final String rootPath;
  LanNode? _node;
  Future<void> _lifecycle = Future<void>.value();
  Future<void> _serialize(Future<void> Function() action) {
    final result = _lifecycle.then((_) => action());
    _lifecycle = result.catchError((Object _) {});
    return result;
  }

  final List<String> pendingReceivedPaths = [];
  void Function()? onPendingReceived;

  /// Restores only bounded, regular inbox files. Receipt acceptance is separate
  /// from business import, and already accepted bytes are never offered again.
  Future<void> initialize() => _serialize(() async {
    final inbox = Directory(p.join(rootPath, 'inbox'));
    if (await FileSystemEntity.type(inbox.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final accepted = receipts().map((receipt) => receipt.digest).toSet();
    final pending = <String>[];
    var inspected = 0;
    var candidates = 0;
    await for (final entity in inbox.list(followLinks: false)) {
      if (++inspected > 1000 || candidates >= maxFiles) break;
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      candidates++;
      try {
        final file = File(entity.path);
        final size = await file.length();
        if (size == 0 || size > maxBytes * 2) continue;
        var read = 0;
        Stream<List<int>> bounded() async* {
          await for (final chunk in file.openRead(0, maxBytes * 2 + 1)) {
            read += chunk.length;
            if (read > maxBytes * 2) {
              throw const FormatException('Inbox file exceeds limit');
            }
            yield chunk;
          }
        }

        final digest = (await sha256.bind(bounded()).first).toString();
        if (!accepted.contains(digest)) pending.add(file.path);
      } on FileSystemException {
        // A removed/incomplete file is retried on the next initialization.
      } on FormatException {
        // Oversized files stay outside the pending list.
      }
    }
    pendingReceivedPaths
      ..clear()
      ..addAll(pending);
    if (pending.isNotEmpty) onPendingReceived?.call();
  });
  static const maxBytes = 64 * 1024 * 1024,
      maxFileBytes = 20 * 1024 * 1024,
      maxFiles = 100;
  bool get listening => _node != null;
  List<LanPeer> get peers => _node?.peers ?? [];
  List<TransferReceipt> receipts() => [
    for (final row in database.raw.select(
      'SELECT * FROM transfer_receipts ORDER BY received_at DESC',
    ))
      TransferReceipt(
        row['receipt_id'] as String,
        row['digest'] as String,
        (jsonDecode(row['payload'] as String) as List).cast<String>(),
        DateTime.parse(row['received_at'] as String),
      ),
  ];

  String _safe(String name) {
    if (name.isEmpty ||
        name.length > 240 ||
        name.contains('\\') ||
        name.contains('\u0000') ||
        p.posix.isAbsolute(name) ||
        RegExp(r'^[A-Za-z]:').hasMatch(name) ||
        name.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw const FormatException('Unsafe package path');
    }
    return name;
  }

  Future<String> exportFiles(
    List<String> paths, {
    String? message,
    void Function()? checkBeforeEffect,
  }) async {
    checkBeforeEffect?.call();
    if (paths.length > maxFiles ||
        (paths.isEmpty && (message == null || message.isEmpty))) {
      throw ArgumentError('No files/message or too many files');
    }
    final members = <Map<String, Object?>>[];
    var total = 0;
    final names = <String>{};
    for (final path in paths) {
      checkBeforeEffect?.call();
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('Only regular files');
      }
      final name = _safe(p.basename(path));
      if (!names.add(name)) throw const FormatException('Duplicate file names');
      final file = File(path);
      if (await file.length() > maxFileBytes) {
        throw const FormatException('File too large');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxFileBytes) {
        throw const FormatException('File too large');
      }
      total += bytes.length;
      if (total > maxBytes) throw const FormatException('Package too large');
      members.add({
        'name': name,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'data': base64Encode(bytes),
      });
    }
    if (message != null && message.length > 16000) {
      throw const FormatException('Message too large');
    }
    final manifest = {
      'format': 'muyon-transfer-v1',
      'packageId': const Uuid().v4(),
      'message': message,
      'files': members,
    };
    final out = File(
      p.join(rootPath, 'outbox', '${manifest['packageId']}.muyon'),
    );
    checkBeforeEffect?.call();
    await out.parent.create(recursive: true);
    checkBeforeEffect?.call();
    await out.writeAsString(jsonEncode(manifest), flush: true);
    return out.path;
  }

  Future<TransferReceipt> importPackage(
    String path, {
    void Function()? checkCancelled,
    String? expectedDigest,
  }) async {
    checkCancelled?.call();
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > maxBytes * 2) {
      throw const FormatException('Package too large or missing');
    }
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    if (bytes.length > maxBytes * 2 ||
        (expectedDigest != null && expectedDigest != digest)) {
      throw const FormatException('Package differs from approved bytes');
    }
    TransferReceipt? existing() {
      final rows = database.raw.select(
        'SELECT * FROM transfer_receipts WHERE digest=?',
        [digest],
      );
      if (rows.isEmpty) return null;
      final r = rows.single;
      return TransferReceipt(
        r['receipt_id'] as String,
        digest,
        (jsonDecode(r['payload'] as String) as List).cast<String>(),
        DateTime.parse(r['received_at'] as String),
      );
    }

    final previous = existing();
    if (previous != null) return previous;
    final files = _decodePackage(bytes);
    checkCancelled?.call();
    final id = const Uuid().v4();
    final directory = Directory(p.join(rootPath, 'received', id));
    await directory.create(recursive: true);
    try {
      final paths = <String>[];
      for (final entry in files.entries) {
        checkCancelled?.call();
        final target = File(p.join(directory.path, entry.key));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value, flush: true);
        paths.add(target.path);
      }
      final result = await database.write((db) {
        checkCancelled?.call();
        final prior = existing();
        if (prior != null) return prior;
        final now = DateTime.now().toUtc();
        db.execute('INSERT INTO transfer_receipts VALUES(?,?,?,?)', [
          digest,
          id,
          jsonEncode(paths),
          now.toIso8601String(),
        ]);
        return TransferReceipt(id, digest, List.unmodifiable(paths), now);
      });
      if (result.id != id) await directory.delete(recursive: true);
      return result;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Map<String, List<int>> _decodePackage(List<int> bytes) {
    final manifest = jsonDecode(utf8.decode(bytes));
    if (manifest is! Map ||
        manifest['format'] != 'muyon-transfer-v1' ||
        manifest['files'] is! List ||
        (manifest['files'] as List).length > maxFiles ||
        (manifest['message'] != null &&
            (manifest['message'] is! String ||
                (manifest['message'] as String).length > 16000))) {
      throw const FormatException('Invalid package manifest');
    }
    if (manifest.keys.any(
          (k) => !{'format', 'packageId', 'message', 'files'}.contains(k),
        ) ||
        manifest['packageId'] is! String ||
        !RegExp(r'^[0-9a-fA-F-]{36}$')
            .hasMatch(manifest['packageId'] as String)) {
      throw const FormatException('Unexpected manifest metadata');
    }
    final files = <String, List<int>>{};
    var total = 0;
    for (final item in manifest['files'] as List) {
      if (item is! Map ||
          item['name'] is! String ||
          item['size'] is! int ||
          item['data'] is! String ||
          item['sha256'] is! String) {
        throw const FormatException('Invalid file manifest');
      }
      if (item.keys.any(
        (k) => !{'name', 'size', 'sha256', 'data'}.contains(k),
      )) {
        throw const FormatException('Unexpected file metadata');
      }
      final name = _safe(item['name'] as String), size = item['size'] as int;
      if (size < 0 ||
          size > maxFileBytes ||
          (item['data'] as String).length > maxFileBytes * 2 ||
          files.containsKey(name)) {
        throw const FormatException('File size or duplicate name');
      }
      total += size;
      if (total > maxBytes) {
        throw const FormatException('Expanded package too large');
      }
      final decoded = base64Decode(item['data'] as String);
      if (decoded.length != size ||
          sha256.convert(decoded).toString() != item['sha256']) {
        throw const FormatException('File checksum mismatch');
      }
      files[name] = decoded;
    }
    if (manifest['message'] is String &&
        (manifest['message'] as String).isNotEmpty) {
      if (files.containsKey('message.txt')) {
        throw const FormatException('Reserved message path');
      }
      files['message.txt'] = utf8.encode(manifest['message'] as String);
    }
    return files;
  }

  Future<void> start({
    required String deviceId,
    required String deviceName,
    int? discoveryPort,
    int? httpPort,
  }) => _serialize(() async {
    if (_node != null) return;
    _node = await LanNode.start(
      id: deviceId,
      name: deviceName,
      inbox: Directory(p.join(rootPath, 'inbox')),
      onPush: (push) {
        if (pendingReceivedPaths.length < maxFiles &&
            !pendingReceivedPaths.contains(push.path)) {
          pendingReceivedPaths.add(push.path);
          onPendingReceived?.call();
        }
      },
      discoveryPort: discoveryPort ?? lanDiscoveryPort,
      httpPort: httpPort ?? lanHttpPort,
    );
  });
  Future<String> freezeForSend(
    String path, {
    String? expectedDigest,
    Map<String, String>? allowedMembers,
    void Function()? checkBeforeEffect,
  }) async {
    checkBeforeEffect?.call();
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.length() > maxBytes * 2) {
      throw const FormatException('Invalid outgoing package');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes * 2 ||
        (expectedDigest != null &&
            sha256.convert(bytes).toString() != expectedDigest)) {
      throw const FormatException(
        'Outgoing package differs from approved bytes',
      );
    }
    final members = _decodePackage(bytes);
    if (allowedMembers != null &&
        members.entries.any(
          (entry) =>
              allowedMembers[entry.key] !=
              sha256.convert(entry.value).toString(),
        )) {
      throw StateError('Outgoing bytes are outside approved source scope');
    }
    checkBeforeEffect?.call();
    final frozen = File(p.join(rootPath, 'sending', const Uuid().v4()));
    await frozen.parent.create(recursive: true);
    checkBeforeEffect?.call();
    await frozen.writeAsBytes(bytes, flush: true);
    return frozen.path;
  }

  Future<void> send(
    LanPeer peer,
    String verifiedPackagePath, {
    String? expectedDigest,
    Map<String, String>? allowedMembers,
    void Function()? checkBeforeEffect,
    void Function(int sent, int total)? onProgress,
  }) async {
    final node = _node;
    if (node == null) throw StateError('Device communication is disabled');
    final frozen = await freezeForSend(
      verifiedPackagePath,
      expectedDigest: expectedDigest,
      allowedMembers: allowedMembers,
      checkBeforeEffect: checkBeforeEffect,
    );
    try {
      checkBeforeEffect?.call();
      await node.push(peer, frozen, onProgress: onProgress);
    } finally {
      await File(frozen).delete();
    }
  }

  Future<void> close() => _serialize(() async {
    final node = _node;
    _node = null;
    await node?.stop();
  });
}
