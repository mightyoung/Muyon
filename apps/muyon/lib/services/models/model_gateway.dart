import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ModelLocation { local, ownDevice, remote }

enum ModelPurpose { chat, embedding }

abstract interface class SecretStore {
  Future<String?> read(String reference);
}

/// Fail closed until a platform keychain adapter is supplied by the host.
class UnavailableSecretStore implements SecretStore {
  @override
  Future<String?> read(String reference) async => null;
}

class ModelProfile {
  ModelProfile({
    required this.id,
    required this.endpoint,
    required this.location,
    required this.modelId,
    required this.endpointIdentity,
    this.credentialRef,
    this.cloudProxy = false,
    this.purpose = ModelPurpose.chat,
  }) {
    if (!endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        endpoint.query.isNotEmpty ||
        !['http', 'https'].contains(endpoint.scheme) ||
        modelId.trim().isEmpty ||
        id.isEmpty ||
        endpointIdentity.isEmpty) {
      throw ArgumentError('Invalid model profile');
    }
    if (location == ModelLocation.remote && endpoint.scheme != 'https') {
      throw ArgumentError('Remote endpoints require HTTPS');
    }
    if (location == ModelLocation.local &&
        !['localhost', '127.0.0.1', '::1'].contains(endpoint.host)) {
      throw ArgumentError('Local endpoints must be loopback');
    }
    if (location != ModelLocation.local && credentialRef == null) {
      throw ArgumentError('Authenticated endpoint required');
    }
  }
  final String id;
  final Uri endpoint;
  final ModelLocation location;
  final String modelId;
  final String endpointIdentity;
  final String? credentialRef;
  final bool cloudProxy;
  final ModelPurpose purpose;
  Map<String, Object?> toJson() => {
    'id': id,
    'endpoint': endpoint.toString(),
    'location': location.name,
    'modelId': modelId,
    'endpointIdentity': endpointIdentity,
    'credentialRef': credentialRef,
    'cloudProxy': cloudProxy,
    'purpose': purpose.name,
  };
}

class ModelCancellation {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw StateError('cancelled');
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  void add(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void remove(void Function() listener) => _listeners.remove(listener);
}

class OpenAiModelGateway {
  OpenAiModelGateway(
    this.secrets, {
    this.timeout = const Duration(seconds: 45),
    this.maxResponseBytes = 2 * 1024 * 1024,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final SecretStore secrets;
  final Duration timeout;
  final int maxResponseBytes;
  final HttpClient Function() _clientFactory;

  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
  }) async {
    if (profile.purpose != ModelPurpose.chat) {
      throw StateError('Model profile is not configured for chat');
    }
    final decoded = await request(
      profile: profile,
      payload: {
        'model': profile.modelId,
        'messages': messages,
        'stream': false,
      },
      cancellation: cancellation,
      beforeSend: beforeSend,
    );
    final content = (decoded['choices'] as List).first['message']['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Empty model response');
    }
    return content;
  }

  /// Endpoint is explicit in the profile; no URL rewriting or provider fallback.
  Future<List<List<double>>> embed({
    required ModelProfile profile,
    required List<String> texts,
    ModelCancellation? cancellation,
    required Future<void> Function() beforeSend,
  }) async {
    if (profile.purpose != ModelPurpose.embedding) {
      throw StateError('Model profile is not configured for embeddings');
    }
    if (texts.isEmpty ||
        texts.length > 128 ||
        texts.fold<int>(0, (n, s) => n + s.length) > 256000) {
      throw ArgumentError('Embedding input exceeds bounds');
    }
    final decoded = await request(
      profile: profile,
      payload: {
        'model': profile.modelId,
        'input': texts,
        'encoding_format': 'float',
      },
      cancellation: cancellation,
      beforeSend: beforeSend,
    );
    final data = decoded['data'];
    if (data is! List || data.length != texts.length) {
      throw const FormatException('Invalid embedding response count');
    }
    final result = List<List<double>?>.filled(texts.length, null);
    int? dimension;
    for (final item in data) {
      if (item is! Map || item['index'] is! int || item['embedding'] is! List) {
        throw const FormatException('Invalid embedding response');
      }
      final index = item['index'] as int;
      final values = (item['embedding'] as List).map((n) {
        if (n is! num || !n.isFinite) {
          throw const FormatException('Non-finite embedding');
        }
        return n.toDouble();
      }).toList();
      if (index < 0 ||
          index >= result.length ||
          result[index] != null ||
          values.isEmpty ||
          values.length > 65536 ||
          (dimension != null && dimension != values.length)) {
        throw const FormatException('Invalid embedding dimensions/index');
      }
      dimension = values.length;
      result[index] = values;
    }
    return result.cast<List<double>>();
  }

  Future<Map<String, dynamic>> request({
    required ModelProfile profile,
    required Map<String, Object?> payload,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
  }) async {
    final frozenPayload = jsonEncode(payload);
    if (utf8.encode(frozenPayload).length > 2 * 1024 * 1024) {
      throw ArgumentError('Model payload too large');
    }
    final token = cancellation ?? ModelCancellation();
    token.check();
    final client = _clientFactory();
    void abort() => client.close(force: true);
    token.add(abort);
    try {
      return await (() async {
        final credential = profile.credentialRef == null
            ? null
            : await secrets.read(profile.credentialRef!);
        token.check();
        if (profile.credentialRef != null &&
            (credential == null || credential.isEmpty)) {
          throw StateError('credential_unavailable');
        }
        if (beforeSend != null) await beforeSend();
        token.check();
        final request = await client.postUrl(profile.endpoint);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (credential != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $credential',
          );
        }
        request.write(frozenPayload);
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('model_http_${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          token.check();
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw StateError('model_response_too_large');
          }
          bytes.addAll(chunk);
        }
        token.check();
        final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        return decoded;
      })().timeout(timeout);
    } on TimeoutException {
      token.cancel();
      rethrow;
    } finally {
      token.remove(abort);
      abort();
    }
  }
}
