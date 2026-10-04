import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:cryptography/dart.dart';

/// Long-term device identity: a P-256 key and a self-signed certificate.
///
/// The private key is handed to the caller for platform secure storage. This
/// type never writes it to disk. Trust is the certificate fingerprint the
/// user compared out of band, not the device name and not the discovery packet.
class DeviceIdentity {
  DeviceIdentity._({
    required this.certificatePem,
    required this.privateKeyPem,
    required ECPrivateKey privateKey,
  }) : _privateKey = privateKey,
       fingerprint = fingerprintOfPem(certificatePem);

  final String certificatePem;
  final String privateKeyPem;
  final String fingerprint;
  final ECPrivateKey _privateKey;

  String get shortCode => shortCodeFor(fingerprint);

  /// Full fingerprint for a QR payload. The short code is only a comparison aid.
  String get qrPayload => 'muyon-pair:1:$fingerprint';

  static DeviceIdentity generate() {
    final pair = CryptoUtils.generateEcKeyPair();
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem(
      const {'CN': 'muyon-device'},
      privateKey,
      publicKey,
    );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      825,
    );
    final identity = DeviceIdentity._(
      certificatePem: certificate,
      privateKeyPem: CryptoUtils.encodeEcPrivateKeyToPem(privateKey),
      privateKey: privateKey,
    );
    identity._checkKeyMatchesCertificate();
    return identity;
  }

  static DeviceIdentity restore({
    required String certificatePem,
    required String privateKeyPem,
  }) {
    final identity = DeviceIdentity._(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      privateKey: CryptoUtils.ecPrivateKeyFromPem(privateKeyPem),
    );
    identity._checkKeyMatchesCertificate();
    return identity;
  }

  Map<String, String> toJson() => {
    'certificatePem': certificatePem,
    'privateKeyPem': privateKeyPem,
  };

  void _checkKeyMatchesCertificate() {
    final marked = utf8.encode('muyon-identity-v1');
    if (!verify(
      publicKeyFromCertificate(certificatePem),
      marked,
      sign(marked),
    )) {
      throw StateError(
        'device identity private key does not match certificate',
      );
    }
  }

  String sign(List<int> data) => CryptoUtils.ecSignatureToBase64(
    CryptoUtils.ecSign(
      _privateKey,
      Uint8List.fromList(data),
      algorithmName: 'SHA-256/ECDSA',
    ),
  );

  static bool verify(ECPublicKey publicKey, List<int> data, String signature) {
    try {
      return CryptoUtils.ecVerifyBase64(
        publicKey,
        Uint8List.fromList(data),
        signature,
        algorithm: 'SHA-256/ECDSA',
      );
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  static String fingerprintOfPem(String certificatePem) =>
      sha256Hex(CryptoUtils.getBytesFromPEMString(certificatePem));

  static String fingerprintOfDer(List<int> der) => sha256Hex(der);

  static ECPublicKey publicKeyFromCertificate(String certificatePem) {
    final hex = X509Utils.x509CertificateFromPem(certificatePem)
        .tbsCertificate
        ?.subjectPublicKeyInfo
        .bytes;
    if (hex == null || hex.isEmpty) {
      throw const FormatException('certificate has no public key');
    }
    return CryptoUtils.ecPublicKeyFromDerBytes(_decodeHex(hex));
  }

  /// Eight-byte visual comparison code. It is not a secret.
  static String shortCodeFor(String fingerprint) {
    final hex = fingerprint.toLowerCase();
    if (hex.length < 16) {
      throw ArgumentError.value(fingerprint, 'fingerprint', 'too short');
    }
    final groups = <String>[];
    for (var i = 0; i < 16; i += 4) {
      groups.add(hex.substring(i, i + 4));
    }
    return groups.join('-');
  }

  /// Accepts the short code, the bare fingerprint, or the QR payload.
  static bool codeMatches(String fingerprint, String confirmed) {
    final value = confirmed.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final payload = value.startsWith('muyon-pair:1:')
        ? value.substring('muyon-pair:1:'.length)
        : value;
    final compact = payload.replaceAll('-', '').replaceAll(':', '');
    return compact == fingerprint.toLowerCase() ||
        compact == shortCodeFor(fingerprint).replaceAll('-', '');
  }
}

/// Bytes the sender signs. A different body, length, nonce or sender fails.
List<int> pushBinding({
  required String fingerprint,
  required String nonce,
  required String messageId,
  required int length,
  required String bodyHash,
}) => utf8.encode(
  'muyon-push-v1\n$fingerprint\n$nonce\n$messageId\n$length\n$bodyHash',
);

String randomToken() {
  final bytes = Uint8List(16);
  final random = Random.secure();
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return base64Url.encode(bytes);
}

String sha256Hex(List<int> bytes) {
  final sink = const DartSha256().newHashSink();
  sink.add(bytes);
  sink.close();
  return _hex(sink.hashSync().bytes);
}

class Sha256Sink {
  final _sink = const DartSha256().newHashSink();
  void add(List<int> chunk) => _sink.add(chunk);
  String close() {
    _sink.close();
    return _hex(_sink.hashSync().bytes);
  }
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _decodeHex(String hex) {
  if (hex.length.isOdd) throw const FormatException('odd hex');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Persistence for the private key and the paired-certificate set.
/// The host implementation must use platform secure storage.
abstract class LanSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryLanSecretStore implements LanSecretStore {
  final _values = <String, String>{};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
