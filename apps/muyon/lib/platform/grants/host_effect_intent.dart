import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

/// Only host transport adapters construct this value; it has no JSON decoder.
final class HostEffectIntent {
  HostEffectIntent.transport({
    required this.toolId,
    required this.invocationId,
    required this.endpoint,
    required this.endpointIdentity,
    required List<int> content,
    Iterable<ObjectRef> sourceObjects = const [],
  }) : content = List.unmodifiable(content),
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
  final String toolId, invocationId, endpointIdentity;
  final Uri endpoint;
  final List<int> content;
  final List<ObjectRef> sourceObjects;
  String get destinationDigest =>
      _hash(utf8.encode(jsonEncode([endpoint.toString(), endpointIdentity])));
  String get payloadDigest => _hash(content);
  String get digest => _hash(
    utf8.encode(
      jsonEncode([
        toolId,
        invocationId,
        destinationDigest,
        payloadDigest,
        sourceObjects.map((ref) => ref.toJson()).toList(),
      ]),
    ),
  );
  String get displayDestination => Uri(
    scheme: endpoint.scheme,
    host: endpoint.host,
    port: endpoint.hasPort ? endpoint.port : null,
    path: endpoint.path,
  ).toString();
  static String _hash(List<int> bytes) => sha256.convert(bytes).toString();
}
