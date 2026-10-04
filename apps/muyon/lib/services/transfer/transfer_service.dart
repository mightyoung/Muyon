import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/lan.dart';
import 'package:uuid/uuid.dart';

/// Private key and paired certificates. Plain files are not a substitute.
class FlutterLanSecretStore implements LanSecretStore {
  const FlutterLanSecretStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: 'muyon-lan-$key');
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: 'muyon-lan-$key', value: value);
}

class TransferReceipt {
  const TransferReceipt(this.id, this.digest, this.paths, this.receivedAt);
  final String id, digest;
  final List<String> paths;
  final DateTime receivedAt;
}

/// Five states that must not be collapsed into one another.
class TransferItem {
  const TransferItem({
    required this.id,
    required this.peerFingerprint,
    required this.path,
    required this.delivered,
    required this.attachmentState,
    required this.attachmentLength,
    required this.attachmentSha256,
    required this.imported,
    required this.readAt,
    required this.acceptance,
  });
  final String id, peerFingerprint, attachmentState, acceptance;
  final String? path, attachmentSha256, readAt;
  final bool delivered, imported;
  final int? attachmentLength;

  /// A transferred package never grants permission to execute it.
  bool get grantsExecution => false;
}

/// Explicit package exchange over the paired TLS LAN stack.
/// Listening is opt-in. No listener starts during host construction.
/// Delivery, durable receipt, import, read and human acceptance stay separate.
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

  /// Called once when a person accepts a verified package. Not called on receipt.
  void Function(TransferItem item)? onAccepted;
  Future<void> _items = Future<void>.value();
  Future<void> get itemsSettled => _items;

  /// Restores only bounded, regular inbox files. Receipt acceptance is separate
  /// from business import, and already accepted bytes are never offered again.
  Future<void> initialize() => _serialize(() async {
    final inbox = Directory(p.join(rootPath, 'inbox'));
    if (await FileSystemEntity.type(inbox.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final accepted = receipts().map((receipt) => receipt.digest).toSet();
    final acceptedItems = {
      for (final row in database.raw.select(
        "SELECT attachment_sha256 FROM transfer_items WHERE acceptance='accepted' AND attachment_sha256 IS NOT NULL",
      ))
        row['attachment_sha256'] as String,
    };
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
        if (!accepted.contains(digest) && !acceptedItems.contains(digest)) {
          pending.add(file.path);
        }
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

  void _notePush(LanPush push) {
    if (push.senderFingerprint.isEmpty) return;
    if (pendingReceivedPaths.length < maxFiles &&
        !pendingReceivedPaths.contains(push.path)) {
      pendingReceivedPaths.add(push.path);
      onPendingReceived?.call();
    }
    _items = _items.then((_) => _insertReceived(push));
  }

  Future<void> _insertReceived(LanPush push) async {
    final file = File(push.path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    await database.write((db) {
      final existing = db.select(
        'SELECT item_id FROM transfer_items WHERE path=? OR attachment_sha256=?',
        [push.path, digest],
      );
      if (existing.isNotEmpty) return;
      db.execute('INSERT INTO transfer_items VALUES(?,?,?,?,?,?,?,?,?,?,?)', [
        const Uuid().v4(),
        push.senderFingerprint,
        push.path,
        1,
        'durable',
        bytes.length,
        digest,
        0,
        null,
        'pending',
        DateTime.now().toUtc().toIso8601String(),
      ]);
    });
  }

  List<TransferItem> items() => [
    for (final row in database.raw.select(
      'SELECT * FROM transfer_items ORDER BY created_at',
    ))
      TransferItem(
        id: row['item_id'] as String,
        peerFingerprint: row['peer_fingerprint'] as String,
        path: row['path'] as String?,
        delivered: row['delivered'] == 1,
        attachmentState: row['attachment_state'] as String,
        attachmentLength: row['attachment_length'] as int?,
        attachmentSha256: row['attachment_sha256'] as String?,
        imported: row['imported'] == 1,
        readAt: row['read_at'] as String?,
        acceptance: row['acceptance'] as String,
      ),
  ];

  Future<void> markRead(String itemId) => database.write((db) {
    db.execute(
      'UPDATE transfer_items SET read_at=? WHERE item_id=? AND read_at IS NULL',
      [DateTime.now().toUtc().toIso8601String(), itemId],
    );
  });

  /// Human acceptance. Idempotent: the import hand-off runs at most once.
  /// Acceptance does not set [TransferItem.imported].
  Future<void> acceptItem(String itemId) async {
    final item = await database.write((db) {
      final rows = db.select('SELECT * FROM transfer_items WHERE item_id=?', [
        itemId,
      ]);
      if (rows.isEmpty || rows.single['acceptance'] != 'pending') return null;
      db.execute(
        "UPDATE transfer_items SET acceptance='accepted' WHERE item_id=?",
        [itemId],
      );
      final row = rows.single;
      return TransferItem(
        id: row['item_id'] as String,
        peerFingerprint: row['peer_fingerprint'] as String,
        path: row['path'] as String?,
        delivered: row['delivered'] == 1,
        attachmentState: row['attachment_state'] as String,
        attachmentLength: row['attachment_length'] as int?,
        attachmentSha256: row['attachment_sha256'] as String?,
        imported: row['imported'] == 1,
        readAt: row['read_at'] as String?,
        acceptance: 'accepted',
      );
    });
    if (item == null) return;
    onAccepted?.call(item);
  }

  /// Records business import after human acceptance. Receipt alone cannot call this.
  Future<void> markImported(String itemId) => database.write((db) {
    final rows = db.select(
      'SELECT acceptance FROM transfer_items WHERE item_id=?',
      [itemId],
    );
    if (rows.isEmpty || rows.single['acceptance'] != 'accepted') {
      throw StateError('已核验收妥，尚未人工接纳，不能导入');
    }
    db.execute(
      'UPDATE transfer_items SET imported=1 WHERE item_id=? AND imported=0',
      [itemId],
    );
  });

  /// True when [bytes] are a `muyon-research` package. The bytes stay opaque here.
  static bool isResearchPackage(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      return value is Map && value['packageType'] == 'muyon-research';
    } on FormatException {
      return false;
    }
  }

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
    final tracked = database.raw.select(
      'SELECT acceptance FROM transfer_items WHERE path=? OR attachment_sha256=?',
      [path, digest],
    );
    if (tracked.isNotEmpty && tracked.first['acceptance'] != 'accepted') {
      throw StateError('已核验收妥，尚未人工接纳，不能导入');
    }
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
        db.execute(
          'UPDATE transfer_items SET imported=1 WHERE path=? OR attachment_sha256=?',
          [path, digest],
        );
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

  int? get httpPort => _node?.httpPort;
  String? get localShortCode => _node?.identity.shortCode;
  String? get localQrPayload => _node?.identity.qrPayload;
  bool isPaired(LanPeer peer) => _node?.isPaired(peer.fingerprint) ?? false;

  Future<LanPeer> probe(String host, {int port = lanHttpPort}) {
    final node = _node;
    if (node == null) throw StateError('Device communication is disabled');
    return node.probe(host, port: port);
  }

  void confirmPeer({
    required String fingerprint,
    required String confirmedCode,
    required String certificatePem,
  }) {
    final node = _node;
    if (node == null) throw StateError('Device communication is disabled');
    node.confirmPeer(
      fingerprint: fingerprint,
      confirmedCode: confirmedCode,
      certificatePem: certificatePem,
    );
  }

  void revoke(String fingerprint) => _node?.revoke(fingerprint);

  Future<void> start({
    required String deviceId,
    required String deviceName,
    int? discoveryPort,
    int? httpPort,
    LanSecretStore? secrets,
  }) => _serialize(() async {
    if (_node != null) return;
    _node = await LanNode.start(
      id: deviceId,
      name: deviceName,
      inbox: Directory(p.join(rootPath, 'inbox')),
      onPush: _notePush,
      discoveryPort: discoveryPort ?? lanDiscoveryPort,
      httpPort: httpPort ?? lanHttpPort,
      secrets: secrets ?? const FlutterLanSecretStore(),
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
    if (isResearchPackage(bytes)) {
      if (allowedMembers != null) {
        throw const FormatException('Research package has no transfer members');
      }
    } else {
      final members = _decodePackage(bytes);
      if (allowedMembers != null &&
          members.entries.any(
            (entry) =>
                allowedMembers[entry.key] !=
                sha256.convert(entry.value).toString(),
          )) {
        throw StateError('Outgoing bytes are outside approved source scope');
      }
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
    if (!node.isPaired(peer.fingerprint)) {
      throw StateError('未配对或已撤销');
    }
    final online = node.peers.any(
      (candidate) =>
          candidate.id == peer.id && candidate.address == peer.address,
    );
    if (!online) throw StateError('对方不在线，没有中继');
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
