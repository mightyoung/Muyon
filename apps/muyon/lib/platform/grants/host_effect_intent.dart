import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// Only host effect adapters construct this value; it has no JSON decoder.
final class HostEffectIntent {
  HostEffectIntent.transport({
    required this.toolId,
    required this.invocationId,
    required Uri endpoint,
    required String endpointIdentity,
    required List<int> content,
    Iterable<ObjectRef> sourceObjects = const [],
  }) : _endpoint = endpoint,
       _endpointIdentity = endpointIdentity,
       content = List.unmodifiable(content),
       sourceObjects = List.unmodifiable(sourceObjects) {
    final loopback = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
    if (toolId.isEmpty ||
        invocationId.isEmpty ||
        endpointIdentity.trim().isEmpty ||
        !endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        !(endpoint.scheme == 'https' ||
            (endpoint.scheme == 'http' && loopback)) ||
        this.content.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Trusted transport identity and body bytes required');
    }
  }

  /// Exact host validated local operation; no invented transport endpoint.
  HostEffectIntent.localWrite({
    required this.toolId,
    required this.invocationId,
    required List<int> content,
    required Iterable<ObjectRef> sourceObjects,
  }) : _endpoint = null,
       _endpointIdentity = null,
       content = List.unmodifiable(content),
       sourceObjects = List.unmodifiable(sourceObjects) {
    if (toolId.isEmpty ||
        invocationId.isEmpty ||
        this.sourceObjects.isEmpty ||
        this.content.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError(
        'Actual local operation and resolved targets required',
      );
    }
  }
  final String toolId, invocationId;
  final Uri? _endpoint;
  final String? _endpointIdentity;
  bool get isTransport => _endpoint != null;
  Uri? get reviewEndpoint => _endpoint;
  Uri get endpoint =>
      _endpoint ?? (throw StateError('Local write has no endpoint'));
  String get endpointIdentity =>
      _endpointIdentity ??
      (throw StateError('Local write has no transport identity'));
  final List<int> content;
  final List<ObjectRef> sourceObjects;
  String? get destinationDigest => !isTransport
      ? null
      : _hash(utf8.encode(jsonEncode([endpoint.toString(), endpointIdentity])));
  String get payloadDigest => _hash(content);
  String get digest => _hash(
    utf8.encode(
      jsonEncode([
        isTransport ? 'transport' : 'local_write',
        toolId,
        invocationId,
        destinationDigest,
        payloadDigest,
        sourceObjects.map((ref) => ref.toJson()).toList(),
      ]),
    ),
  );
  String? get displayDestination => !isTransport
      ? null
      : Uri(
          scheme: endpoint.scheme,
          host: endpoint.host,
          port: endpoint.hasPort ? endpoint.port : null,
          path: endpoint.path,
        ).toString();
  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
}
