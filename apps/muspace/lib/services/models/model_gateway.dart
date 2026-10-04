import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ModelLocation { local, ownDevice, remote }

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
  Map<String, Object?> toJson() => {
    'id': id,
    'endpoint': endpoint.toString(),
    'location': location.name,
    'modelId': modelId,
    'endpointIdentity': endpointIdentity,
    'credentialRef': credentialRef,
    'cloudProxy': cloudProxy,
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
        final request = await client.postUrl(profile.endpoint);
        if (beforeSend != null) await beforeSend();
        token.check();
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (credential != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $credential',
          );
        }
        request.write(
          jsonEncode({
            'model': profile.modelId,
            'messages': messages,
            'stream': false,
          }),
        );
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
        final content =
            (decoded['choices'] as List).first['message']['content'];
        if (content is! String || content.trim().isEmpty) {
          throw const FormatException('Empty model response');
        }
        return content;
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
