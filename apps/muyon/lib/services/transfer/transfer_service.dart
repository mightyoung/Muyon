import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/lan.dart';
import 'package:uuid/uuid.dart';

import 'chat_log.dart';
import '../../platform/outbound_tool_ledger.dart';
import '../../platform/tool_registry.dart' show ToolPlatformException;
import '../../platform/grants/host_effect_intent.dart';
import '../../platform/grants/host_tool_authorization.dart';
import '../../platform/grants/host_transfer_ledger.dart';
import 'task_coordinator.dart';

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
  TransferService(
    this.database,
    this.rootPath, {
    ManagedDatabase? outboundDatabase,
  }) : outboundLedger = OutboundToolLedger(outboundDatabase ?? database);
  final OutboundToolLedger outboundLedger;
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

  /// Task envelopes are routed here and are not import receipts.
  Future<void> Function(Map<String, Object?> envelope)? onTaskEnvelope;

  /// Production leaves this on. Tests can stop the delivery acknowledgement
  /// so a successful push stays `sent` instead of becoming `delivered`.
  bool acknowledgeChatDelivery = true;

  /// `sent` may be retried only after this age. There is no automatic retry.
  Duration chatSentRetryAfter = const Duration(minutes: 2);

  final _chatEvents = StreamController<void>.broadcast();
  Stream<void> get chatChanges => _chatEvents.stream;

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
      if (TaskCoordinator.decodeFile(entity.path) != null) continue;
      if (ChatLog.decodeFile(entity.path) != null) continue;
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

  List<LanPeer> pairedOnline() {
    final node = _node;
    if (node == null) return const [];
    return [
      for (final peer in node.peers)
        if (node.isPaired(peer.fingerprint)) peer,
    ];
  }

  /// Pushes a task envelope to every paired device currently visible.
  /// This does not authorize execution on either side.
  Future<void> sendTaskEnvelope(Map<String, Object?> envelope) async {
    final node = _node;
    if (node == null) throw StateError('Device communication is disabled');
    final targets = pairedOnline();
    if (targets.isEmpty) throw StateError('对方不在线，没有中继');
    final file = File(p.join(rootPath, 'tasks', const Uuid().v4()));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(envelope), flush: true);
    try {
      for (final peer in targets) {
        await node.push(peer, file.path);
      }
    } finally {
      await _removeIfPresent(file);
    }
  }

  Future<void> deliverPendingTaskEnvelopes() async {
    final inbox = Directory(p.join(rootPath, 'inbox'));
    if (!await inbox.exists()) return;
    await for (final entity in inbox.list(followLinks: false)) {
      if (entity is! File) continue;
      final decoded = TaskCoordinator.decodeFile(entity.path);
      if (decoded == null) continue;
      await onTaskEnvelope?.call(decoded);
      await _removeIfPresent(entity);
    }
  }

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
    final task = TaskCoordinator.decodeFile(push.path);
    if (task != null) {
      final handler = onTaskEnvelope;
      if (handler != null) {
        _items = _items.then((_) async {
          await handler(task);
          final file = File(push.path);
          await _removeIfPresent(file);
        });
      }
      return;
    }
    final chat = ChatLog.decodeFile(push.path);
    if (chat != null) {
      _items = _items.then((_) => _receiveChat(push, chat));
      return;
    }
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
    final noted = await database.write((db) {
      final existing = db.select(
        'SELECT item_id FROM transfer_items WHERE path=? OR attachment_sha256=?',
        [push.path, digest],
      );
      final itemId = existing.isEmpty
          ? const Uuid().v4()
          : existing.single['item_id'] as String;
      if (existing.isEmpty) {
        db.execute('INSERT INTO transfer_items VALUES(?,?,?,?,?,?,?,?,?,?,?)', [
          itemId,
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
      }
      return _recordPackageMessage(
        db,
        peerFingerprint: push.senderFingerprint,
        bytes: bytes,
        itemId: itemId,
      );
    });
    if (noted) {
      _emitChat();
      onPendingReceived?.call();
    }
  }

  /// Package text becomes a chat row. The transfer item's import flag is not
  /// changed here. A manifest without a sender clock uses the local receive time.
  bool _recordPackageMessage(
    Database db, {
    required String peerFingerprint,
    required List<int> bytes,
    required String itemId,
  }) {
    Map? manifest;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) manifest = decoded;
    } on FormatException {
      return false;
    }
    if (manifest == null || manifest['format'] != 'muyon-transfer-v1') {
      return false;
    }
    final body = manifest['message'];
    final packageId = manifest['packageId'];
    if (body is! String ||
        body.isEmpty ||
        body.length > ChatLog.maxBody ||
        packageId is! String ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(packageId)) {
      return false;
    }
    final now = DateTime.now().toUtc();
    return ChatLog.insertInbound(
      db,
      peerFingerprint: peerFingerprint,
      messageId: packageId,
      body: body,
      createdAt: now,
      receivedAt: now,
      packageItemId: itemId,
    );
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

  /// True when [bytes] are a `muyon-research` document, or a zip whose
  /// `manifest.json` says so. The bytes stay opaque; nothing is imported.
  static bool isResearchPackage(List<int> bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      return _zipManifestType(bytes) == 'muyon-research';
    }
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
      outboundLedger: outboundLedger,
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

  HostEffectIntent? prepareSendIntent(
    ToolCallRequest request, {
    required Map<String, String> allowedMembers,
    Iterable<ObjectRef> sourceObjects = const [],
  }) {
    final node = _node;
    final peer = node?.peers
        .where((value) => value.id == request.parameters['peerId'])
        .firstOrNull;
    if (node == null ||
        peer == null ||
        !node.isPaired(peer.fingerprint) ||
        peer.fingerprint.isEmpty) {
      throw const ToolPlatformException(
        'peer_unavailable',
        'Verified paired TLS peer required',
      );
    }
    final endpoint = Uri(
      scheme: 'https',
      host: peer.address,
      port: peer.port,
      path: '/push',
    );
    if (request.destination != endpoint.toString()) {
      throw const ToolPlatformException(
        'destination_mismatch',
        'Exact paired TLS destination required',
      );
    }
    final path = request.parameters['path'];
    final expectedDigest = request.parameters['sourceDigest'];
    if (path is! String ||
        expectedDigest is! String ||
        allowedMembers.isEmpty ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const ToolPlatformException(
        'source_invalid',
        'Managed approved package required',
      );
    }
    final outbox = Directory(p.join(rootPath, 'outbox'));
    final file = File(path);
    if (!outbox.existsSync() ||
        !p.isWithin(
          outbox.resolveSymbolicLinksSync(),
          file.resolveSymbolicLinksSync(),
        )) {
      throw const ToolPlatformException(
        'source_invalid',
        'Managed outbox package required',
      );
    }
    // A complete bounded producer. Larger bodies stay on explicit manual paths.
    if (file.lengthSync() > 8 * 1024 * 1024) return null;
    final bytes = file.readAsBytesSync();
    if (bytes.length > 8 * 1024 * 1024 ||
        sha256.convert(bytes).toString() != expectedDigest) {
      throw const ToolPlatformException(
        'source_changed',
        'Package bytes differ from approved source',
      );
    }
    final manifest = jsonDecode(utf8.decode(bytes));
    if (manifest is! Map || manifest['message'] != null) {
      throw const ToolPlatformException(
        'source_invalid',
        'Selected source package required',
      );
    }
    final members = _decodePackage(bytes);
    if (members.entries.any(
      (entry) =>
          allowedMembers[entry.key] != sha256.convert(entry.value).toString(),
    )) {
      throw const ToolPlatformException(
        'scope_mismatch',
        'Package includes sources outside host scope',
      );
    }
    return HostEffectIntent.transport(
      toolId: request.toolId,
      invocationId: request.invocationId,
      endpoint: endpoint,
      endpointIdentity: jsonEncode(['paired-tls', peer.id, peer.fingerprint]),
      content: bytes,
      sourceObjects: sourceObjects,
    );
  }

  Future<void> send(
    LanPeer peer,
    String verifiedPackagePath, {
    String? expectedDigest,
    Map<String, String>? allowedMembers,
    void Function()? checkBeforeEffect,
    HostAuthorizationLink? authorization,
    void Function(int sent, int total)? onProgress,
  }) async {
    final node = _node;
    if (node == null) throw StateError('Device communication is disabled');
    // Always validate the actual TLS pin, even without a caller callback.
    void guard() {
      checkBeforeEffect?.call();
      authorization?.checkEndpointIdentity(
        jsonEncode(['paired-tls', peer.id, peer.fingerprint]),
      );
      if (!node.isPaired(peer.fingerprint)) throw StateError('未配对或已撤销');
      if (!node.peers.any(
        (candidate) =>
            candidate.id == peer.id &&
            candidate.address == peer.address &&
            candidate.port == peer.port &&
            candidate.fingerprint == peer.fingerprint,
      )) {
        throw StateError('对方不在线，或已验证设备目的地发生变化');
      }
    }

    guard();
    final frozen = await freezeForSend(
      verifiedPackagePath,
      expectedDigest: expectedDigest,
      allowedMembers: allowedMembers,
      checkBeforeEffect: guard,
    );
    try {
      guard();
      final payload = authorization == null
          ? null
          : List<int>.unmodifiable(await File(frozen).readAsBytes());
      if (authorization != null) {
        authorization.check(
          outboundLedger.database,
          authorization.toolId,
          Uri(
            scheme: 'https',
            host: peer.address,
            port: peer.port,
            path: '/push',
          ),
          sha256.convert(payload!).toString(),
        );
      }
      await node.push(
        peer,
        frozen,
        onProgress: onProgress,
        checkBeforeEffect: guard,
        payload: payload,
        outboundLedger: authorization == null
            ? null
            : HostTransferLedger(outboundLedger, authorization),
      );
    } finally {
      await File(frozen).delete();
    }
  }

  Future<ChatMessage> sendText(LanPeer peer, String body) async {
    _requireText(body);
    final node = _requireSendable(peer);
    final messageId = const Uuid().v4();
    final created = DateTime.now().toUtc();
    await database.write((db) {
      ChatLog.insertOutbound(
        db,
        peerFingerprint: peer.fingerprint,
        messageId: messageId,
        body: body,
        createdAt: created,
      );
    });
    _emitChat();
    await _pushText(
      node,
      peer,
      messageId: messageId,
      body: body,
      createdAt: created,
      peerFingerprint: peer.fingerprint,
    );
    return _message(peer.fingerprint, messageId);
  }

  List<ChatThread> threads() {
    final node = _node;
    final grouped = <String, List<ChatMessage>>{};
    for (final message in _allMessages()) {
      grouped.putIfAbsent(message.peerFingerprint, () => []).add(message);
    }
    return [
      for (final entry in grouped.entries)
        ChatThread(
          peerFingerprint: entry.key,
          peerName: _peerByFingerprint(entry.key)?.name,
          last: entry.value.last,
          unread: entry.value
              .where(
                (message) =>
                    message.direction == 'in' && message.readAt == null,
              )
              .length,
          online:
              node != null &&
              _peerByFingerprint(entry.key) != null &&
              node.isPaired(entry.key),
          paired: node?.isPaired(entry.key) ?? false,
        ),
    ];
  }

  List<ChatMessage> messages(String peerFingerprint) => [
    for (final message in _allMessages())
      if (message.peerFingerprint == peerFingerprint) message,
  ];

  /// Local read time only. Nothing is sent to the peer.
  Future<void> markChatRead(String peerFingerprint) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = await database.write((db) {
      db.execute(
        "UPDATE chat_messages SET read_at=? WHERE peer_fingerprint=? AND direction='in' AND read_at IS NULL",
        [now, peerFingerprint],
      );
      return db.updatedRows;
    });
    if (changed > 0) _emitChat();
  }

  Future<void> acceptChat(String peerFingerprint, String messageId) =>
      _setAcceptance(peerFingerprint, messageId, 'accepted');

  Future<void> rejectChat(String peerFingerprint, String messageId) =>
      _setAcceptance(peerFingerprint, messageId, 'rejected');

  /// Explicit resend of a `failed` row, or of `sent` older than
  /// [chatSentRetryAfter]. The same message id is used, so the receiver keeps
  /// one row. The peer fingerprint selects which row, so two peers can share
  /// a message id. This never runs from a timer.
  Future<ChatMessage> retryText(
    String peerFingerprint,
    String messageId,
  ) async {
    final message = _single(
      peerFingerprint,
      messageId,
      direction: 'out',
      missing: '消息不存在',
    );
    if (message.sendState == 'delivered') {
      throw StateError('对方已确认保存，不能重发');
    }
    if (message.sendState == 'sent') {
      final sentAt = message.sentAt;
      if (sentAt == null ||
          DateTime.now().toUtc().difference(sentAt.toUtc()) <
              chatSentRetryAfter) {
        throw StateError('发出结果未知，尚未到可重发时间');
      }
    } else if (message.sendState != 'failed' && message.sendState != 'queued') {
      throw StateError('这条文字不能重发');
    }
    final peer = _peerByFingerprint(message.peerFingerprint);
    if (peer == null) throw StateError('对方不在线，没有中继');
    final node = _requireSendable(peer);
    await _pushText(
      node,
      peer,
      messageId: message.id,
      body: message.body,
      createdAt: message.createdAt,
      peerFingerprint: message.peerFingerprint,
    );
    return _message(message.peerFingerprint, message.id);
  }

  /// Removes the local row for this peer and message id. The peer is not told.
  Future<void> deleteChat(String peerFingerprint, String messageId) async {
    _single(peerFingerprint, messageId, direction: null, missing: '消息不存在');
    await database.write((db) {
      db.execute(
        'DELETE FROM chat_messages WHERE peer_fingerprint=? AND message_id=?',
        [peerFingerprint, messageId],
      );
    });
    _emitChat();
  }

  /// Removes every local row for this peer. The peer is not told.
  Future<void> deleteChatThread(String peerFingerprint) async {
    await database.write((db) {
      db.execute('DELETE FROM chat_messages WHERE peer_fingerprint=?', [
        peerFingerprint,
      ]);
    });
    _emitChat();
  }

  Future<void> close() => _serialize(() async {
    final node = _node;
    _node = null;
    await node?.stop();
    if (!_chatEvents.isClosed) await _chatEvents.close();
  });

  void _requireText(String body) {
    if (body.isEmpty) throw ArgumentError('文字不能为空');
    if (body.length > ChatLog.maxBody) throw ArgumentError('文字超过 16000 字');
  }

  LanNode _requireSendable(LanPeer peer) {
    final node = _node;
    if (node == null) throw StateError('Device communication is disabled');
    if (!node.isPaired(peer.fingerprint)) throw StateError('未配对或已撤销');
    final online = node.peers.any(
      (candidate) =>
          candidate.id == peer.id && candidate.address == peer.address,
    );
    if (!online) throw StateError('对方不在线，没有中继');
    return node;
  }

  LanPeer? _peerByFingerprint(String fingerprint) {
    final node = _node;
    if (node == null) return null;
    for (final peer in node.peers) {
      if (peer.fingerprint == fingerprint) return peer;
    }
    return null;
  }

  List<ChatMessage> _allMessages() => ChatLog.list(database.raw);

  ChatMessage _message(String peerFingerprint, String messageId) =>
      messages(peerFingerprint)
          .firstWhere((message) => message.id == messageId);

  ChatMessage _single(
    String peerFingerprint,
    String messageId, {
    required String? direction,
    required String missing,
  }) {
    final matches = [
      for (final message in _allMessages())
        if (message.peerFingerprint == peerFingerprint &&
            message.id == messageId &&
            (direction == null || message.direction == direction))
          message,
    ];
    if (matches.length != 1) throw StateError(missing);
    return matches.single;
  }

  Future<void> _setAcceptance(
    String peerFingerprint,
    String messageId,
    String acceptance,
  ) async {
    final message = _single(
      peerFingerprint,
      messageId,
      direction: 'in',
      missing: '消息不存在',
    );
    if (message.acceptance == acceptance) return;
    await database.write((db) {
      db.execute(
        'UPDATE chat_messages SET acceptance=? WHERE peer_fingerprint=? AND message_id=? AND direction=?',
        [acceptance, peerFingerprint, messageId, 'in'],
      );
    });
    _emitChat();
  }

  Future<void> _pushText(
    LanNode node,
    LanPeer peer, {
    required String messageId,
    required String body,
    required DateTime createdAt,
    required String peerFingerprint,
  }) async {
    final file = File(p.join(rootPath, 'chat-out', const Uuid().v4()));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'muyon': ChatLog.marker,
        'type': 'text',
        'messageId': messageId,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
      }),
      flush: true,
    );
    try {
      await node.push(peer, file.path);
      final sentAt = DateTime.now().toUtc().toIso8601String();
      await database.write((db) {
        db.execute(
          "UPDATE chat_messages SET send_state='sent', sent_at=?, error=NULL WHERE peer_fingerprint=? AND message_id=? AND direction='out' AND send_state!='delivered'",
          [sentAt, peerFingerprint, messageId],
        );
      });
      _emitChat();
    } catch (error) {
      await database.write((db) {
        db.execute(
          "UPDATE chat_messages SET send_state='failed', error=? WHERE peer_fingerprint=? AND message_id=? AND direction='out' AND send_state!='delivered'",
          ['$error', peerFingerprint, messageId],
        );
      });
      _emitChat();
      rethrow;
    } finally {
      await _removeIfPresent(file);
    }
  }

  Future<void> _receiveChat(LanPush push, Map<String, Object?> envelope) async {
    final file = File(push.path);
    try {
      if (push.senderFingerprint.isEmpty) return;
      if (envelope['type'] == 'delivered') {
        final changed = await database.write((db) {
          db.execute(
            "UPDATE chat_messages SET send_state='delivered', error=NULL WHERE peer_fingerprint=? AND message_id=? AND direction='out'",
            [push.senderFingerprint, envelope['messageId']],
          );
          return db.updatedRows;
        });
        if (changed > 0) _emitChat();
        return;
      }
      final created = DateTime.tryParse(envelope['createdAt'] as String);
      final now = DateTime.now().toUtc();
      final inserted = await database.write(
        (db) => ChatLog.insertInbound(
          db,
          peerFingerprint: push.senderFingerprint,
          messageId: envelope['messageId'] as String,
          body: envelope['body'] as String,
          createdAt: created?.toUtc() ?? now,
          receivedAt: now,
        ),
      );
      if (inserted) {
        _emitChat();
        onPendingReceived?.call();
      }
      if (!acknowledgeChatDelivery) return;
      final peer = _peerByFingerprint(push.senderFingerprint);
      final node = _node;
      if (peer == null || node == null || !node.isPaired(peer.fingerprint)) {
        return;
      }
      final ack = File(p.join(rootPath, 'chat-out', const Uuid().v4()));
      await ack.parent.create(recursive: true);
      await ack.writeAsString(
        jsonEncode({
          'muyon': ChatLog.marker,
          'type': 'delivered',
          'messageId': envelope['messageId'],
        }),
        flush: true,
      );
      try {
        await node.push(peer, ack.path);
      } catch (_) {
        // The inbound row is already durable. The sender stays at `sent`.
      } finally {
        await _removeIfPresent(ack);
      }
    } finally {
      await _removeIfPresent(file);
    }
  }

  /// The receiving side also clears pushed files, and a delete can race with
  /// that or with shutdown. A file that is already gone is the goal, not an
  /// error: an exception here would also stall every later receipt queued
  /// behind it in [_items].
  static Future<void> _removeIfPresent(FileSystemEntity entity) async {
    try {
      await entity.delete();
    } on PathNotFoundException {
      // already removed
    }
  }

  void _emitChat() {
    if (!_chatEvents.isClosed) _chatEvents.add(null);
  }
}

const _maxZipEntries = 4096;
const _maxManifestBytes = 8 * 1024 * 1024;

/// `packageType` from a single `manifest.json`, or null when the zip is not a
/// readable research archive. Only store and raw-deflate are read, and only
/// that one entry. An oversized or inconsistent manifest is not a package.
String? _zipManifestType(List<int> bytes) {
  final eocd = _eocdOffset(bytes);
  if (eocd == null) return null;
  if (_u16(bytes, eocd + 4) != 0 || _u16(bytes, eocd + 6) != 0) return null;
  final entries = _u16(bytes, eocd + 8);
  final total = _u16(bytes, eocd + 10);
  final cdSize = _u32(bytes, eocd + 12);
  final cdOffset = _u32(bytes, eocd + 16);
  if (entries != total ||
      entries > _maxZipEntries ||
      entries == 0xffff ||
      cdSize == 0xffffffff ||
      cdOffset == 0xffffffff ||
      cdOffset > bytes.length ||
      cdSize > bytes.length - cdOffset) {
    return null;
  }
  var cursor = cdOffset;
  final end = cdOffset + cdSize;
  String? packageType;
  var sawManifest = false;
  for (var i = 0; i < entries; i++) {
    if (cursor + 46 > end || _u32(bytes, cursor) != 0x02014b50) return null;
    final flags = _u16(bytes, cursor + 8);
    final method = _u16(bytes, cursor + 10);
    final crc = _u32(bytes, cursor + 16);
    final compSize = _u32(bytes, cursor + 20);
    final uncompSize = _u32(bytes, cursor + 24);
    final nameLen = _u16(bytes, cursor + 28);
    final extraLen = _u16(bytes, cursor + 30);
    final commentLen = _u16(bytes, cursor + 32);
    final localOffset = _u32(bytes, cursor + 42);
    final nameStart = cursor + 46;
    final next = nameStart + nameLen + extraLen + commentLen;
    if (next > end) return null;
    final name = _zipName(bytes.sublist(nameStart, nameStart + nameLen), flags);
    cursor = next;
    if (name != 'manifest.json') continue;
    if (sawManifest ||
        (flags & 1) != 0 ||
        (method != 0 && method != 8) ||
        compSize > _maxManifestBytes ||
        uncompSize > _maxManifestBytes) {
      return null;
    }
    sawManifest = true;
    final plain = _manifestBytes(
      bytes,
      localOffset: localOffset,
      method: method,
      crc: crc,
      compSize: compSize,
      uncompSize: uncompSize,
      name: utf8.encode('manifest.json'),
    );
    if (plain == null) return null;
    try {
      final value = jsonDecode(utf8.decode(plain));
      final type = value is Map ? value['packageType'] : null;
      packageType = type is String ? type : null;
    } on FormatException {
      return null;
    }
  }
  if (!sawManifest || cursor != end) return null;
  return packageType;
}

int? _eocdOffset(List<int> bytes) {
  if (bytes.length < 22) return null;
  final earliest = bytes.length > 22 + 65535 ? bytes.length - 22 - 65535 : 0;
  for (var i = bytes.length - 22; i >= earliest; i--) {
    if (_u32(bytes, i) != 0x06054b50) continue;
    if (i + 22 + _u16(bytes, i + 20) == bytes.length) return i;
  }
  return null;
}

String? _zipName(List<int> name, int flags) {
  try {
    return (flags & 0x800) != 0 ? utf8.decode(name) : latin1.decode(name);
  } on FormatException {
    return null;
  }
}

List<int>? _manifestBytes(
  List<int> bytes, {
  required int localOffset,
  required int method,
  required int crc,
  required int compSize,
  required int uncompSize,
  required List<int> name,
}) {
  if (localOffset < 0 || localOffset + 30 > bytes.length) return null;
  if (_u32(bytes, localOffset) != 0x04034b50) return null;
  final localFlags = _u16(bytes, localOffset + 6);
  if (_u16(bytes, localOffset + 8) != method || (localFlags & 1) != 0) {
    return null;
  }
  final nameLen = _u16(bytes, localOffset + 26);
  final extraLen = _u16(bytes, localOffset + 28);
  final nameStart = localOffset + 30;
  final dataStart = nameStart + nameLen + extraLen;
  if (nameLen != name.length || dataStart > bytes.length) return null;
  for (var i = 0; i < nameLen; i++) {
    if (bytes[nameStart + i] != name[i]) return null;
  }
  final described = (localFlags & 8) == 0;
  if (described &&
      (_u32(bytes, localOffset + 14) != crc ||
          _u32(bytes, localOffset + 18) != compSize ||
          _u32(bytes, localOffset + 22) != uncompSize)) {
    return null;
  }
  if (dataStart + compSize > bytes.length) return null;
  final compressed = bytes.sublist(dataStart, dataStart + compSize);
  List<int> plain;
  try {
    plain = method == 8
        ? ZLibDecoder(raw: true).convert(compressed)
        : compressed;
  } on Exception {
    return null;
  }
  if (plain.length != uncompSize || _crc32(plain) != crc) return null;
  return plain;
}

int _u16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      final mask = -(crc & 1);
      crc = (crc >> 1) ^ (0xedb88320 & mask);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
