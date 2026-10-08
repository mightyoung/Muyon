import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_identity.dart';

export 'lan_identity.dart';

/// UDP port devices announce themselves on, and the HTTP port pushes go to
/// (typed by hand when broadcasts don't get through).
const lanDiscoveryPort = 47810, lanHttpPort = 47811;

/// Largest push accepted.
const maxPushBytes = 300 * 1024 * 1024;

/// Signed push time must fall inside this window. Older signatures are
/// refused even if the process that first saw them has exited.
const pushAcceptWindow = Duration(minutes: 5);

/// Listener and client contexts. Dart exposes a minimum version but no
/// portable maximum, so a TLS 1.2-only handshake cannot be staged here.
SecurityContext lanTlsContext() =>
    SecurityContext(withTrustedRoots: false)
      ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;

/// A device is listed while its announcements keep arriving.
const _announceEvery = Duration(seconds: 3),
    _forgetAfter = Duration(seconds: 10);

/// Resource budgets; file format and transport remain unchanged.
class LanLimits {
  const LanLimits({
    this.maxPeers = 256,
    this.maxUploads = 4,
    this.maxUploadsPerAddress = 2,
    this.maxReservedBytes = 600 * 1024 * 1024,
    this.peerLifetime = _forgetAfter,
    this.uploadIdle = const Duration(seconds: 30),
    this.transferTimeout = const Duration(minutes: 15),
    this.probeTimeout = const Duration(seconds: 10),
  }) : assert(maxPeers > 0),
       assert(maxUploads > 0),
       assert(maxUploadsPerAddress > 0),
       assert(maxReservedBytes > 0);

  final int maxPeers, maxUploads, maxUploadsPerAddress, maxReservedBytes;
  final Duration peerLifetime, uploadIdle, transferTimeout, probeTimeout;
}

class LanPeer {
  LanPeer(
    this.id,
    this.name,
    this.address,
    this.port,
    this.seen, {
    this.announcedFingerprint = '',
    this.fingerprint = '',
    this.certificatePem = '',
  });
  final String id, name, address;
  final int port;
  final DateTime seen;

  /// Fingerprint carried by discovery. Discovery is not trust.
  final String announcedFingerprint;

  /// Fingerprint of the certificate actually presented on the TLS connection.
  /// Empty until [LanNode.probe]. Never implied by [announcedFingerprint].
  final String fingerprint;
  final String certificatePem;
}

/// A file another device pushed, saved under the inbox until the user
/// accepts or declines it.
class LanPush {
  LanPush(
    this.fromId,
    this.fromName,
    this.address,
    this.path,
    this.at, {
    this.senderFingerprint = '',
  });
  final String fromId, fromName, address, path;
  final DateTime at;

  /// Paired fingerprint that signed the payload. Empty is not a sender.
  final String senderFingerprint;
}

class LanException implements Exception {
  LanException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// This device on the local network: announces itself over UDP broadcast,
/// answers announcements so devices that miss broadcasts (Android) still
/// learn about us, and receives pushes over TLS. Discovery carries a
/// fingerprint and no trust. Payloads are accepted only from a paired,
/// unrevoked peer. Nothing is imported here: pushes wait in [inbox].
/// Optional for standalone supplier clients; the host always supplies its
/// durable ledger. Each operation awaits pending before touching a socket.
abstract interface class LanOutboundLedger {
  Future<T> send<T>({
    required String toolId,
    required Uri destination,
    required String payloadDigest,
    required Future<T> Function(void Function(int)) operation,
  });
}

class LanNode {
  LanNode._(
    this.id,
    this.name,
    this.inbox,
    this.identity,
    this._http,
    this._udp,
    this._discoveryPort,
    this._onPush,
    this._onPeers,
    this._limits,
    this._secrets,
    Map<String, String> paired,
    Set<String> revoked,
  ) : _paired = paired,
      _revoked = revoked;

  static Future<LanNode> start({
    required String id,
    required String name,
    required Directory inbox,
    required void Function(LanPush push) onPush,
    void Function()? onPeers,
    int discoveryPort = lanDiscoveryPort,
    int httpPort = lanHttpPort,
    LanLimits limits = const LanLimits(),
    LanSecretStore? secrets,
    DeviceIdentity? identity,
    LanOutboundLedger? outboundLedger,
  }) async {
    inbox.createSync(recursive: true);
    final resolved = identity ?? await _loadIdentity(secrets);
    final trust = await _loadTrust(secrets);
    HttpServer http;
    try {
      http = await _bind(resolved, httpPort);
    } on SocketException {
      // Port taken (a second copy of the app): discovery still finds us.
      http = await _bind(resolved, 0);
    }
    final RawDatagramSocket udp;
    try {
      udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
    } catch (_) {
      await http.close(force: true);
      rethrow;
    }
    udp.broadcastEnabled = true;
    final node = LanNode._(
      id,
      name,
      inbox,
      resolved,
      http,
      udp,
      discoveryPort,
      onPush,
      onPeers,
      limits,
      secrets,
      trust.$1,
      trust.$2,
    );
    node._ledger = outboundLedger;
    http.listen((request) {
      final pending = node._serve(request);
      node._requests.add(pending);
      unawaited(pending.whenComplete(() => node._requests.remove(pending)));
    }, onError: (Object _) {});
    udp.listen(
      (e) {
        if (e == RawSocketEvent.read) node._receive();
      },
      // Failed sends surface here (an adapter without broadcast, network
      // down); discovery just tries again on the next tick.
      onError: (Object _) {},
    );
    node._timer = Timer.periodic(_announceEvery, (_) {
      unawaited(node._tick().catchError((Object _) {}));
    });
    try {
      await node._tick();
    } catch (_) {
      await node.stop();
      rethrow;
    }
    node._loadSeenPushes();
    return node;
  }

  LanOutboundLedger? _ledger;
  final _audits = <Future<dynamic>>{};
  Future<T> _audit<T>(
    Uri destination,
    String digest,
    Future<T> Function(void Function(int)) operation, {
    String? toolId,
    LanOutboundLedger? ledgerOverride,
  }) async {
    Future<T> bounded(void Function(int) count) => operation(count).timeout(
      destination.path == '/push'
          ? _limits.transferTimeout
          : _limits.probeTimeout,
    );
    final chosenLedger = ledgerOverride ?? _ledger;
    final result = chosenLedger == null
        ? bounded((_) {})
        : chosenLedger.send(
            toolId:
                toolId ??
                (destination.scheme == 'udp'
                    ? 'transfer.listen'
                    : destination.path == '/push'
                    ? 'transfer.send'
                    : 'transfer.probe'),
            destination: destination,
            payloadDigest: digest,
            operation: bounded,
          );
    _audits.add(result);
    try {
      return await result;
    } finally {
      _audits.remove(result);
    }
  }

  static String _digest(List<int> bytes) {
    final sink = Sha256Sink()..add(bytes);
    return sink.close();
  }

  Future<void> _sendHello(
    InternetAddress address,
    int port, {
    bool reply = false,
  }) {
    final payload = _hello(reply: reply);
    return _audit(
      Uri(scheme: 'udp', host: address.address, port: port, path: '/discovery'),
      _digest(payload),
      (count) async {
        if (_stopped) throw LanException('局域网已关闭');
        final sent = _udp.send(payload, address, port);
        count(sent);
        if (sent != payload.length)
          throw LanException('Discovery send incomplete');
      },
    );
  }

  final String id, name;
  final Directory inbox;
  final DeviceIdentity identity;
  final HttpServer _http;
  final RawDatagramSocket _udp;
  final int _discoveryPort;
  final void Function(LanPush) _onPush;
  final void Function()? _onPeers;
  final LanLimits _limits;
  final LanSecretStore? _secrets;
  final Map<String, String> _paired;
  final Set<String> _revoked;
  final _usedNonces = <String>[];
  final _usedNonceSet = <String>{};
  final _seenMessages = <String>[];
  final _seenMessageSet = <String>{};
  final _pushAuth = <HttpRequest, _PushAuth>{};
  final _peers = <String, LanPeer>{};
  final _requests = <Future<void>>{};
  final _outbound = <HttpClient, Completer<void>>{};
  final _uploads = <StreamIterator<List<int>>>{};
  final _uploadsByAddress = <String, int>{};
  int _reservedBytes = 0;
  bool _stopped = false;
  Timer? _peerNotification;
  Future<void>? _stopping;
  late final Timer _timer;

  int get httpPort => _http.port;
  int get discoveryPort => _udp.port;

  bool isPaired(String fingerprint) =>
      fingerprint.isNotEmpty &&
      _paired.containsKey(fingerprint) &&
      !_revoked.contains(fingerprint);

  /// Records an out-of-band confirmation. [confirmedCode] is the short code,
  /// the fingerprint, or the QR payload read from the other device's screen.
  void confirmPeer({
    required String fingerprint,
    required String confirmedCode,
    required String certificatePem,
  }) {
    if (_revoked.contains(fingerprint)) {
      throw LanException('该设备已撤销');
    }
    if (DeviceIdentity.fingerprintOfPem(certificatePem) != fingerprint ||
        !DeviceIdentity.codeMatches(fingerprint, confirmedCode)) {
      throw LanException('核对码与证书不一致');
    }
    _paired[fingerprint] = certificatePem;
    unawaited(_persistTrust());
  }

  void revoke(String fingerprint) {
    _paired.remove(fingerprint);
    _revoked.add(fingerprint);
    unawaited(_persistTrust());
  }

  static Future<HttpServer> _bind(DeviceIdentity identity, int port) {
    final context = lanTlsContext()
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    return HttpServer.bindSecure(InternetAddress.anyIPv4, port, context);
  }

  static Future<DeviceIdentity> _loadIdentity(LanSecretStore? secrets) async {
    final raw = await secrets?.read('lan-identity');
    if (raw != null) {
      final json = jsonDecode(raw);
      if (json is Map) {
        return DeviceIdentity.restore(
          certificatePem: json['certificatePem'] as String,
          privateKeyPem: json['privateKeyPem'] as String,
        );
      }
    }
    final created = DeviceIdentity.generate();
    if (secrets != null) {
      await secrets.write('lan-identity', jsonEncode(created.toJson()));
    }
    return created;
  }

  static Future<(Map<String, String>, Set<String>)> _loadTrust(
    LanSecretStore? secrets,
  ) async {
    final raw = await secrets?.read('lan-trust');
    if (raw == null) return (<String, String>{}, <String>{});
    final json = jsonDecode(raw);
    if (json is! Map) return (<String, String>{}, <String>{});
    final paired = <String, String>{};
    final stored = json['paired'];
    if (stored is Map) {
      stored.forEach((key, value) {
        if (key is String && value is String) paired[key] = value;
      });
    }
    final revoked = <String>{};
    final denied = json['revoked'];
    if (denied is List) {
      for (final item in denied) {
        if (item is String) revoked.add(item);
      }
    }
    paired.removeWhere((fingerprint, _) => revoked.contains(fingerprint));
    return (paired, revoked);
  }

  Future<void> _persistTrust() async {
    final secrets = _secrets;
    if (secrets == null) return;
    await secrets.write(
      'lan-trust',
      jsonEncode({'paired': _paired, 'revoked': _revoked.toList()}),
    );
  }

  /// Devices heard from recently, by name.
  List<LanPeer> get peers {
    _expirePeers();
    return _peers.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    _stopped = true;
    _timer.cancel();
    _peerNotification?.cancel();
    _udp.close();
    final outgoing = Map<HttpClient, Completer<void>>.of(_outbound);
    for (final client in outgoing.keys) {
      client.close(force: true);
    }
    await Future.wait(_uploads.toList().map((u) => u.cancel()));
    await _http.close(force: true);
    await Future.wait(_requests.toList());
    await Future.wait(outgoing.values.map((done) => done.future));
    await Future.wait(
      _audits.toList().map(
        (work) => work.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
  }

  void _expirePeers() {
    final cutoff = DateTime.now().subtract(_limits.peerLifetime);
    _peers.removeWhere((_, peer) => !peer.seen.isAfter(cutoff));
  }

  void _notifyPeers() {
    if (_stopped || _peerNotification != null) return;
    _peerNotification = Timer(const Duration(milliseconds: 100), () {
      _peerNotification = null;
      if (!_stopped) _onPeers?.call();
    });
  }

  // --- Discovery -----------------------------------------------------------

  List<int> _hello({bool reply = false}) => utf8.encode(
    jsonEncode({
      'siq': 1,
      'id': id,
      'name': name,
      'port': httpPort,
      // Public fingerprint only. Hearing it does not make this device trusted.
      'fp': identity.fingerprint,
      if (reply) 'reply': true,
    }),
  );

  /// Announces this device to one address (tests, or a known device).
  Future<void> helloTo(InternetAddress address, int port) =>
      _sendHello(address, port);

  var _listed = 0;

  Future<void> _tick() async {
    for (final target
        in _discoveryPort == 0
            ? const <InternetAddress>[]
            : await _broadcastTargets()) {
      try {
        if (_stopped) return;
        await _sendHello(target, _discoveryPort);
      } on SocketException {
        // An interface without broadcast; the others still work.
      }
    }
    // Tell the UI when a device dropped off.
    if (peers.length != _listed) {
      _listed = peers.length;
      _notifyPeers();
    }
  }

  /// The limited broadcast plus each interface's /24 broadcast: Windows
  /// sends 255.255.255.255 out of one adapter only, and Dart doesn't expose
  /// netmasks.
  // ponytail: assumes /24 office networks; add a netmask lookup if a site
  // uses larger subnets and devices go unseen.
  static Future<Set<InternetAddress>> _broadcastTargets() async {
    final targets = {InternetAddress('255.255.255.255')};
    try {
      for (final i in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      )) {
        for (final a in i.addresses) {
          final b = a.rawAddress;
          targets.add(InternetAddress('${b[0]}.${b[1]}.${b[2]}.255'));
        }
      }
    } on SocketException {
      // No interface list: the limited broadcast alone.
    }
    return targets;
  }

  void _receive() {
    // Leave remaining datagrams for the next socket event so UI work can run.
    for (var count = 0; count < 32 && !_stopped; count++) {
      final d = _udp.receive();
      if (d == null) break;
      if (d.data.length > 4096) continue;
      final Map<String, Object?> m;
      try {
        final decoded = jsonDecode(utf8.decode(d.data));
        if (decoded is! Map<String, Object?>) continue;
        m = decoded;
      } on FormatException {
        continue;
      }
      if (!_validIdentity(m) ||
          m['port'] is! int ||
          (m['port']! as int) < 1 ||
          (m['port']! as int) > 65535 ||
          m['id'] == id) {
        continue;
      }
      _expirePeers();
      final isNew = !_peers.containsKey(m['id']);
      if (isNew && _peers.length >= _limits.maxPeers) continue;
      final announced = m['fp'] is String ? m['fp']! as String : '';
      final previous = _peers[m['id']];
      // A repeated announcement must not erase a fingerprint verified by probe.
      // A changed announcement drops that verification; the trust store stays.
      final stillVerified =
          previous != null &&
          previous.fingerprint.isNotEmpty &&
          previous.fingerprint == announced &&
          isPaired(previous.fingerprint);
      _peers[m['id']! as String] = LanPeer(
        m['id']! as String,
        m['name']! as String,
        d.address.address,
        m['port']! as int,
        DateTime.now(),
        announcedFingerprint: announced,
        fingerprint: stillVerified ? previous.fingerprint : '',
        certificatePem: stillVerified ? previous.certificatePem : '',
      );
      if (isNew && m['reply'] != true) {
        try {
          unawaited(
            _sendHello(
              d.address,
              d.port,
              reply: true,
            ).catchError((Object _) {}),
          );
        } on SocketException {
          // Discovery retries later.
        }
      }
      if (isNew) _notifyPeers();
    }
  }

  static bool _validIdentity(Map<String, Object?> m) =>
      m['siq'] == 1 &&
      m['id'] is String &&
      (m['id']! as String).isNotEmpty &&
      utf8.encode(m['id']! as String).length <= 128 &&
      m['name'] is String &&
      utf8.encode(m['name']! as String).length <= 256;

  // --- Transfer ------------------------------------------------------------

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    final destination = Uri(
      scheme: 'https',
      host: req.connectionInfo!.remoteAddress.address,
      port: req.connectionInfo!.remotePort,
      path: req.uri.path,
    );
    var replyAccounted = false;
    try {
      if (req.method == 'GET' && req.uri.path == '/hello') {
        res.headers.contentType = ContentType.json;
        final payload = utf8.encode(
          jsonEncode({
            'siq': 1,
            'id': id,
            'name': name,
            'fingerprint': identity.fingerprint,
            'certificate': identity.certificatePem,
          }),
        );
        replyAccounted = true;
        await _audit(destination, _digest(payload), (count) async {
          res.add(payload);
          count(payload.length);
          await res.close();
        }, toolId: 'transfer.listen');
      } else if (req.method == 'POST' && req.uri.path == '/push') {
        final auth = _authorizePush(req);
        if (auth == null) return;
        _pushAuth[req] = auth;
        try {
          await _acceptPush(req);
        } finally {
          _pushAuth.remove(req);
        }
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      if (req.uri.path == '/hello') {
        try {
          (await res.detachSocket(writeHeaders: false)).destroy();
        } catch (_) {}
        return;
      }
      try {
        res.statusCode = HttpStatus.badRequest;
        res.persistentConnection = false;
      } catch (_) {
        // The socket may already be closed during shutdown.
      }
    } finally {
      try {
        if (replyAccounted) {
          await res.close();
        } else {
          // Empty acknowledgements/refusals still communicate a status. They
          // require pending too, with the empty-body digest and zero bytes.
          await _audit(
            destination,
            _digest(const []),
            (_) => res.close(),
            toolId: 'transfer.listen',
          );
        }
      } catch (_) {
        try {
          (await res.detachSocket(writeHeaders: false)).destroy();
        } catch (_) {}
      }
    }
  }

  File get _seenPushFile => File('${inbox.path}.seen-pushes.json');
  final _persistedMessages = <String, int>{};

  void _loadSeenPushes() {
    final file = _seenPushFile;
    if (!file.existsSync()) return;
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return;
    } on FileSystemException {
      return;
    }
    if (decoded is! Map) return;
    final now = _unixNow();
    for (final entry in decoded.entries) {
      final at = entry.value;
      if (entry.key.isEmpty || at is! int) continue;
      if ((now - at).abs() > pushAcceptWindow.inSeconds) continue;
      _persistedMessages[entry.key] = at;
    }
  }

  void _rememberPersisted(String messageId, int sentAtUnix) {
    final now = _unixNow();
    _persistedMessages.removeWhere(
      (_, at) => (now - at).abs() > pushAcceptWindow.inSeconds,
    );
    _persistedMessages[messageId] = sentAtUnix;
    _seenPushFile.writeAsStringSync(
      jsonEncode(_persistedMessages),
      flush: true,
    );
  }

  _PushAuth? _authorizePush(HttpRequest req) {
    final fingerprint = req.headers.value('x-muyon-fp') ?? '';
    final nonce = req.headers.value('x-muyon-nonce') ?? '';
    final messageId = req.headers.value('x-muyon-msg') ?? '';
    final signature = req.headers.value('x-muyon-sig') ?? '';
    final sentAtUnix = int.tryParse(req.headers.value('x-muyon-ts') ?? '');
    final now = _unixNow();
    if (!isPaired(fingerprint) ||
        nonce.isEmpty ||
        messageId.isEmpty ||
        signature.isEmpty ||
        sentAtUnix == null ||
        (now - sentAtUnix).abs() > pushAcceptWindow.inSeconds) {
      req.response.statusCode = HttpStatus.unauthorized;
      req.response.persistentConnection = false;
      return null;
    }
    if (_usedNonceSet.contains(nonce) ||
        _seenMessageSet.contains(messageId) ||
        _persistedMessages.containsKey(messageId)) {
      req.response.statusCode = HttpStatus.conflict;
      req.response.persistentConnection = false;
      return null;
    }
    _remember(_usedNonces, _usedNonceSet, nonce);
    _remember(_seenMessages, _seenMessageSet, messageId);
    return _PushAuth(fingerprint, nonce, messageId, sentAtUnix, signature);
  }

  void _remember(List<String> order, Set<String> seen, String value) {
    seen.add(value);
    order.add(value);
    if (order.length <= 4096) return;
    seen.remove(order.removeAt(0));
  }

  Future<void> _acceptPush(HttpRequest req) async {
    final auth = _pushAuth[req];
    final length = req.contentLength;
    if (length <= 0 || length > maxPushBytes) {
      req.response.statusCode = HttpStatus.requestEntityTooLarge;
      req.response.persistentConnection = false;
      return;
    }
    final address = req.connectionInfo!.remoteAddress.address;
    final active = _uploadsByAddress[address] ?? 0;
    if (_stopped ||
        _uploads.length >= _limits.maxUploads ||
        active >= _limits.maxUploadsPerAddress ||
        _reservedBytes + length > _limits.maxReservedBytes) {
      req.response.statusCode = HttpStatus.serviceUnavailable;
      req.response.persistentConnection = false;
      return;
    }
    final fromId = req.headers.value('x-siq-id') ?? '';
    final fromName = Uri.decodeComponent(req.headers.value('x-siq-name') ?? '');
    final at = DateTime.now();
    if (utf8.encode(fromId).length > 128 ||
        utf8.encode(fromName).length > 256) {
      throw const FormatException('sender identity too long');
    }
    final input = StreamIterator(req.timeout(_limits.uploadIdle));
    _uploads.add(input);
    _uploadsByAddress[address] = active + 1;
    _reservedBytes += length;
    var timedOut = false;
    final hasher = Sha256Sink();
    final deadline = Timer(_limits.transferTimeout, () {
      timedOut = true;
      unawaited(input.cancel());
    });
    Directory? staging;
    RandomAccessFile? sink;
    var retained = false;
    var received = 0;
    try {
      staging = await inbox.createTemp('push-');
      final file = File('${staging.path}/data.siq');
      sink = await file.open(mode: FileMode.write);
      while (await input.moveNext()) {
        final chunk = input.current;
        received += chunk.length;
        if (received > length) throw const FormatException('too long');
        hasher.add(chunk);
        await sink.writeFrom(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (timedOut || _stopped) throw const FormatException('transfer stopped');
      if (received != length) throw const FormatException('cut short');
      if (auth == null) throw const FormatException('missing sender proof');
      final bodyHash = hasher.close();
      final certificate = _paired[auth.fingerprint];
      final proofOk =
          certificate != null &&
          DeviceIdentity.verify(
            DeviceIdentity.publicKeyFromCertificate(certificate),
            pushBinding(
              fingerprint: auth.fingerprint,
              nonce: auth.nonce,
              messageId: auth.messageId,
              sentAtUnix: auth.sentAtUnix,
              length: length,
              bodyHash: bodyHash,
            ),
            auth.signature,
          );
      if (!proofOk) throw const FormatException('sender proof rejected');
      _rememberPersisted(auth.messageId, auth.sentAtUnix);
      // Move out of the unique staging directory: callers delete only the file.
      final finalFile = await file.rename('${staging.path}.siq');
      try {
        if (timedOut || _stopped)
          throw const FormatException('transfer stopped');
        _onPush(
          LanPush(
            fromId,
            fromName.isEmpty ? address : fromName,
            address,
            finalFile.path,
            at,
            senderFingerprint: auth.fingerprint,
          ),
        );
        retained = true;
      } finally {
        if (!retained && await finalFile.exists()) await finalFile.delete();
      }
    } finally {
      deadline.cancel();
      try {
        try {
          await input.cancel();
        } finally {
          try {
            await sink?.close();
          } finally {
            if (staging != null && await staging.exists()) {
              await staging.delete(recursive: true);
            }
          }
        }
      } finally {
        _uploads.remove(input);
        _reservedBytes -= length;
        final remaining = (_uploadsByAddress[address] ?? 1) - 1;
        if (remaining == 0) {
          _uploadsByAddress.remove(address);
        } else {
          _uploadsByAddress[address] = remaining;
        }
      }
    }
  }

  HttpClient _client({
    required bool acceptPresented,
    required bool Function(String fingerprint) pinned,
  }) {
    final client = HttpClient(context: lanTlsContext())
      ..connectionTimeout = const Duration(seconds: 5)
      ..badCertificateCallback = (certificate, host, port) {
        final fingerprint = DeviceIdentity.fingerprintOfDer(certificate.der);
        if (acceptPresented) {
          pinned(fingerprint);
          return true;
        }
        return pinned(fingerprint);
      };
    return client;
  }

  static Future<List<int>> _responseBytes(
    HttpClientResponse response, [
    int limit = 8192,
  ]) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > limit) {
        throw const FormatException('response too large');
      }
      bytes.addAll(chunk);
    }
    return bytes;
  }

  /// Looks up a device by address when discovery can't see it.
  ///
  /// The presented certificate is observed so the user can compare its
  /// fingerprint. This does not pair the peer and must not carry a payload.
  Future<LanPeer> probe(String host, {int port = lanHttpPort}) async {
    var presented = '';
    final client = _outboundClient(
      acceptPresented: true,
      pinned: (fingerprint) {
        presented = fingerprint;
        return true;
      },
    );
    try {
      final m = await (() async {
        final destination = Uri(
          scheme: 'https',
          host: host,
          port: port,
          path: '/hello',
        );
        return _audit(destination, _digest(const []), (_) async {
          if (_stopped) throw LanException('局域网已关闭');
          final req = await client.getUrl(destination);
          req.followRedirects = false;
          final res = await req.close();
          if (res.statusCode != HttpStatus.ok) throw const FormatException();
          final decoded = jsonDecode(
            utf8.decode(await _responseBytes(res, 8192)),
          );
          if (decoded is! Map<String, Object?> || !_validIdentity(decoded)) {
            throw const FormatException();
          }
          return decoded;
        });
      })();
      final certificate = m['certificate'];
      if (presented.isEmpty ||
          certificate is! String ||
          DeviceIdentity.fingerprintOfPem(certificate) != presented) {
        throw const FormatException();
      }
      final peer = LanPeer(
        m['id']! as String,
        m['name']! as String,
        host,
        port,
        DateTime.now(),
        announcedFingerprint: presented,
        fingerprint: presented,
        certificatePem: certificate,
      );
      _expirePeers();
      if (_stopped) throw LanException('局域网已关闭');
      if (!_peers.containsKey(peer.id) && _peers.length >= _limits.maxPeers) {
        throw LanException('附近设备过多，请稍后再试');
      }
      _peers[peer.id] = peer;
      _notifyPeers();
      return peer;
    } on FormatException {
      throw LanException('$host 上运行的不是询价台账');
    } on IOException {
      throw LanException('连不上 $host：确认对方已打开"局域网可见"，且在同一网络');
    } on TimeoutException {
      throw LanException('连接 $host 超时');
    } finally {
      _finishOutbound(client);
    }
  }

  /// Sends [file] to [to]; completes once the device has stored it.
  /// Progress counts bytes handed to the HTTP stream. Reaching `total` still
  /// requires a successful receiver response before this future completes.
  Future<void> push(
    LanPeer to,
    String file, {
    void Function(int sent, int total)? onProgress,
    void Function()? checkBeforeEffect,
    List<int>? payload,
    LanOutboundLedger? outboundLedger,
    String? messageId,
    String? nonce,
    int? sentAtUnix,
  }) async {
    checkBeforeEffect?.call();
    final frozenPayload = payload == null
        ? null
        : List<int>.unmodifiable(payload);
    final fingerprint = to.fingerprint;
    if (!isPaired(fingerprint)) {
      throw LanException('未配对或已撤销，拒绝发送');
    }
    final client = _outboundClient(
      acceptPresented: false,
      pinned: (presented) => presented == fingerprint,
    );
    try {
      await (() async {
        final length = frozenPayload?.length ?? File(file).lengthSync();
        final hasher = Sha256Sink();
        if (frozenPayload == null) {
          await for (final chunk in File(file).openRead()) {
            hasher.add(chunk);
          }
        } else {
          hasher.add(frozenPayload);
        }
        final bodyHash = hasher.close();
        final chosenNonce = nonce ?? randomToken();
        final chosenMessage = messageId ?? randomToken();
        final chosenSentAt = sentAtUnix ?? _unixNow();
        final destination = Uri(
          scheme: 'https',
          host: to.address,
          port: to.port,
          path: '/push',
        );
        await _audit(destination, bodyHash, (count) async {
          if (_stopped) throw LanException('局域网已关闭');
          checkBeforeEffect?.call();
          final req = await client.postUrl(destination);
          checkBeforeEffect?.call();
          req.followRedirects = false;
          req.headers
            ..contentType = ContentType.binary
            ..contentLength = length
            ..set('x-siq-id', id)
            ..set('x-siq-name', Uri.encodeComponent(name))
            ..set('x-muyon-fp', identity.fingerprint)
            ..set('x-muyon-nonce', chosenNonce)
            ..set('x-muyon-msg', chosenMessage)
            ..set('x-muyon-ts', '$chosenSentAt')
            ..set(
              'x-muyon-sig',
              identity.sign(
                pushBinding(
                  fingerprint: identity.fingerprint,
                  nonce: chosenNonce,
                  messageId: chosenMessage,
                  sentAtUnix: chosenSentAt,
                  length: length,
                  bodyHash: bodyHash,
                ),
              ),
            );
          var sent = 0;
          onProgress?.call(sent, length);
          checkBeforeEffect?.call();
          await req.addStream(
            (frozenPayload == null
                    ? File(file).openRead()
                    : Stream<List<int>>.value(frozenPayload))
                .map((chunk) {
                  checkBeforeEffect?.call();
                  final nextSent = sent + chunk.length;
                  onProgress?.call(nextSent, length);
                  // The callback may synchronously withdraw authority. This
                  // chunk has not been handed to HttpClient yet.
                  checkBeforeEffect?.call();
                  sent = nextSent;
                  count(chunk.length);
                  return chunk;
                }),
          );
          final res = await req.close();
          await _responseBytes(res);
          if (res.statusCode != HttpStatus.ok) {
            throw LanException(
              res.statusCode == HttpStatus.requestEntityTooLarge
                  ? '内容太大，对方拒收（上限 ${maxPushBytes ~/ 1048576} MB）'
                  : '对方没有收下（HTTP ${res.statusCode}）',
            );
          }
        }, ledgerOverride: outboundLedger);
      })();
    } on IOException {
      throw LanException('发送给 ${to.name} 失败：对方可能已关闭"局域网可见"或离开网络');
    } on TimeoutException {
      throw LanException('发送给 ${to.name} 超时');
    } on FormatException {
      throw LanException('来自 ${to.name} 的响应无效');
    } finally {
      _finishOutbound(client);
    }
  }

  HttpClient _outboundClient({
    required bool acceptPresented,
    required bool Function(String fingerprint) pinned,
  }) {
    if (_stopped) throw LanException('局域网已关闭');
    final client = _client(acceptPresented: acceptPresented, pinned: pinned);
    _outbound[client] = Completer<void>();
    return client;
  }

  void _finishOutbound(HttpClient client) {
    client.close(force: true);
    _outbound.remove(client)?.complete();
  }
}

class _PushAuth {
  const _PushAuth(
    this.fingerprint,
    this.nonce,
    this.messageId,
    this.sentAtUnix,
    this.signature,
  );
  final String fingerprint, nonce, messageId, signature;
  final int sentAtUnix;
}

int _unixNow() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
