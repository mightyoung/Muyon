import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:muyon_module_api/muyon_module_api.dart';

import '../services/models/credential_redaction.dart';
import '../services/models/model_gateway.dart' show SecretStore;
import 'tool_registry.dart';
import 'outbound_tool_ledger.dart';

/// One external MCP server reached over Streamable HTTP.
class McpServerConfig {
  McpServerConfig({
    required this.id,
    required this.endpoint,
    this.credentialRef,
  }) {
    final loopback = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
    if (!RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(id) ||
        !endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty ||
        !(endpoint.scheme == 'https' ||
            (endpoint.scheme == 'http' && loopback))) {
      throw ArgumentError(
        'MCP server needs a simple id and an https '
        '(or loopback http) endpoint',
      );
    }
  }
  final String id;
  final Uri endpoint;

  /// Secret store reference for a bearer token; the token is never stored here.
  final String? credentialRef;
}

/// Query parameter names that carry a credential.
const _credentialParams = {
  'api_key', 'apikey', 'api-key', 'key', 'token', 'access_token', 'auth', //
  'authorization', 'secret', 'client_secret', 'password', 'pass', 'sig',
  'signature', 'passwd', 'x-api-key', 'access_key', 'accesskey', 'private_key',
  'jwt',
};

/// A name that ends in `_key` or `-key`, or a camelCase `...Key` (`apiKey`).
/// A plain `endsWith('key')` would also take `monkey` and `hockey`.
final _camelKey = RegExp(r'[a-z0-9]Key$');

/// Whether a query parameter called [name] is treated as a credential.
bool isCredentialParam(String name) {
  final lower = name.toLowerCase();
  return _credentialParams.contains(lower) ||
      RegExp(r'[_-]key$').hasMatch(lower) ||
      _camelKey.hasMatch(name) ||
      ['token', 'secret', 'password', 'apikey'].any(lower.contains);
}

List<MapEntry<String, String>> _queryPairs(Uri endpoint) => [
  for (final part in endpoint.query.split('&'))
    if (part.isNotEmpty)
      MapEntry(
        part.contains('=') ? part.substring(0, part.indexOf('=')) : part,
        part.contains('=') ? part.substring(part.indexOf('=') + 1) : '',
      ),
];

String _decoded(String raw) {
  try {
    return Uri.decodeQueryComponent(raw);
  } catch (_) {
    return raw;
  }
}

/// Names of the credential parameters in [endpoint]'s query, in order.
List<String> credentialParamNames(Uri endpoint) => [
  for (final pair in _queryPairs(endpoint))
    if (isCredentialParam(_decoded(pair.key)) && pair.value.isNotEmpty)
      _decoded(pair.key),
];

/// [endpoint] as text with the values of credential parameters replaced by
/// [mask]. Everything else is kept as written.
String maskedEndpoint(Uri endpoint, {String mask = '••••'}) {
  if (!endpoint.hasQuery) return endpoint.toString();
  final query = [
    for (final part in endpoint.query.split('&'))
      if (part.contains('=') &&
          isCredentialParam(_decoded(part.substring(0, part.indexOf('=')))) &&
          part.length > part.indexOf('=') + 1)
        '${part.substring(0, part.indexOf('='))}=$mask'
      else
        part,
  ].join('&');
  final text = endpoint.toString();
  return '${text.substring(0, text.indexOf('?'))}?$query'
      '${endpoint.hasFragment ? '#${endpoint.fragment}' : ''}';
}

/// [text] without the credential parameter values of [endpoint]: the URL
/// itself (as dart:io quotes it in `uri = ...`) is rewritten in masked form,
/// then any value of [minRedactedSecretLength]+ characters is replaced
/// wherever it still appears.
String redactEndpoint(String text, Uri endpoint) {
  var out = text.replaceAll(
    endpoint.toString(),
    maskedEndpoint(endpoint, mask: '<redacted>'),
  );
  for (final pair in _queryPairs(endpoint)) {
    if (!isCredentialParam(_decoded(pair.key))) continue;
    for (final value in {pair.value, _decoded(pair.value)}) {
      out = maskSecret(out, value);
    }
  }
  return out;
}

class McpConnection {
  McpConnection(this.config, this.registered, this.skipped);
  final McpServerConfig config;
  final List<String> registered;

  /// Remote tool name → why it was not registered (e.g. unsupported schema).
  final Map<String, String> skipped;
}

/// Adapts MCP tools into the host [ToolRegistry]. The protocol stays at this
/// edge: each remote tool becomes an ordinary `network`-effect tool, so it
/// gets parameter validation, a per-call host approval bound to the server
/// as destination, a persistent receipt, and effect-aware cancel/failure
/// wording like every other tool. Internal module contracts do not change.
abstract final class McpAdapter {
  static const protocolVersion = '2025-06-18';
  static const _maxPages = 20;
  static const _maxDescription = 500;

  static Future<McpConnection> connect(
    ToolRegistry registry,
    McpServerConfig config, {
    required SecretStore secrets,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _McpClient(
      config,
      secrets,
      timeout,
      OutboundToolLedger(registry.database),
    );
    await client.initialize();
    final registered = <String>[];
    final skipped = <String, String>{};
    String? cursor;
    for (var page = 0; page < _maxPages; page++) {
      final result = await client.rpc('tools/list', {'cursor': ?cursor});
      for (final raw in result['tools'] as List? ?? const []) {
        final tool = Map<String, Object?>.from(raw as Map);
        final name = tool['name'];
        if (name is! String ||
            !RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(name)) {
          skipped['$name'] = 'Unsupported tool name';
          continue;
        }
        final toolId = 'mcp.${config.id}.$name';
        final description = maskSecret(
          '${tool['description'] ?? ''}',
          client.token,
        );
        try {
          registry.register(
            providerId: 'mcp:${config.id}',
            descriptor: ToolDescriptor(
              toolId: toolId,
              moduleId: 'mcp',
              effect: ToolEffect.network,
              parameterSchema: Map<String, Object?>.from(
                (tool['inputSchema'] as Map?) ?? const {'type': 'object'},
              ),
              supportsCancel: true,
              description: description.length > _maxDescription
                  ? description.substring(0, _maxDescription)
                  : description,
            ),
            // Remote tools receive only their parameters, never local objects.
            supportedScopes: const {AssistantScopeKind.global},
            dataModuleIds: const {},
            handler: (context) => _call(client, name, context),
          );
          registered.add(toolId);
        } catch (error) {
          skipped[name] = '$error';
        }
      }
      cursor = result['nextCursor'] as String?;
      if (cursor == null) break;
    }
    return McpConnection(config, registered, skipped);
  }

  /// [value] with [secret] masked in every string, keys included. Walks the
  /// decoded structure: a token with `"` or `\` is escaped once serialized, so
  /// replacing in the JSON text would miss it.
  static Object? _maskTree(Object? value, String? secret) => switch (value) {
    String() => maskSecret(value, secret),
    Map() => {
      for (final entry in value.entries)
        maskSecret('${entry.key}', secret): _maskTree(entry.value, secret),
    },
    List() => [for (final item in value) _maskTree(item, secret)],
    _ => value,
  };

  static Future<ToolCallResult> _call(
    _McpClient client,
    String name,
    ToolCallContext context,
  ) async {
    final destination = context.request.destination;
    if (destination != client.config.endpoint.origin) {
      return ToolCallResult(
        status: ToolCallStatus.failed,
        summary: 'Approved destination $destination is not this MCP server',
      );
    }
    context.checkBeforeEffect();
    final result = await client.rpc('tools/call', {
      'name': name,
      'arguments': context.request.parameters,
    }, cancellation: context.cancellation);
    final text = [
      for (final item in result['content'] as List? ?? const [])
        if (item is Map && item['type'] == 'text') '${item['text']}',
    ].join('\n');
    // A server that echoes the token must not get it into receipts or the UI.
    final masked = maskSecret(text, client.token);
    final summary = masked.length > 2000
        ? '${masked.substring(0, 2000)}…'
        : masked;
    return ToolCallResult(
      status: result['isError'] == true
          ? ToolCallStatus.failed
          : ToolCallStatus.succeeded,
      summary: summary.isEmpty ? '(no text content)' : summary,
      data: {
        'text': summary,
        if (result['structuredContent'] is Map)
          'structured': _maskTree(result['structuredContent'], client.token),
      },
    );
  }
}

class _McpClient {
  _McpClient(this.config, this.secrets, this.timeout, this.ledger);
  final OutboundToolLedger ledger;
  final McpServerConfig config;
  final SecretStore secrets;
  final Duration timeout;
  static const _maxBytes = 1024 * 1024;
  String? _session;
  var _nextId = 1;

  /// Token used for this server's requests, kept to redact echoes of it.
  String? token;

  /// Errors leave the client without the token: a malformed header quotes it,
  /// and a server may echo it in an error or a response body.
  Future<T> _redacting<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error, stack) {
      final safe = redactCredentials(
        redactEndpoint('$error', config.endpoint),
        secret: token,
      );
      if (safe != '$error') Error.throwWithStackTrace(StateError(safe), stack);
      rethrow;
    }
  }

  Future<void> initialize() async {
    await rpc('initialize', {
      'protocolVersion': McpAdapter.protocolVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'muyon', 'version': '0.1.0'},
    });
    await _redacting(
      () => _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
  }

  Future<Map<String, Object?>> rpc(
    String method,
    Map<String, Object?> params, {
    ToolCancellationToken? cancellation,
  }) => _redacting(() => _rpc(method, params, cancellation: cancellation));

  Future<Map<String, Object?>> _rpc(
    String method,
    Map<String, Object?> params, {
    ToolCancellationToken? cancellation,
  }) async {
    final id = _nextId++;
    final reply = await _post({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }, cancellation: cancellation);
    if (reply == null || reply['id'] != id) {
      throw const FormatException('MCP reply missing or mismatched');
    }
    final error = reply['error'];
    if (error is Map) {
      throw StateError('MCP error ${error['code']}: ${error['message']}');
    }
    return Map<String, Object?>.from(reply['result'] as Map? ?? const {});
  }

  Future<Map<String, Object?>?> _post(
    Map<String, Object?> message, {
    ToolCancellationToken? cancellation,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    unawaited(
      cancellation?.whenCancelled.then((_) => client.close(force: true)),
    );
    try {
      return await (() async {
        // Read and check the token before connecting: a token that cannot be
        // sent in a header is refused without any request.
        String? bearer;
        if (config.credentialRef != null) {
          bearer = await secrets.read(config.credentialRef!);
          if (bearer == null || bearer.isEmpty) {
            throw StateError('credential_unavailable');
          }
          if (!isSendableCredential(bearer)) {
            throw StateError('mcp_token_invalid');
          }
          token = bearer;
        }
        final payload = utf8.encode(jsonEncode(message));
        return ledger.run(
          toolId: 'mcp.${config.id}.${message['method']}',
          channel: 'mcp',
          destination: config.endpoint,
          payload: payload,
          secret: token,
          isCancelled: () => cancellation?.isCancelled ?? false,
          failedResult: (reply) =>
              message['id'] != null &&
              (reply == null ||
                  reply['id'] != message['id'] ||
                  reply['error'] != null ||
                  (reply['result'] is Map &&
                      (reply['result'] as Map)['isError'] == true)),
          operation: (countSent) => (() async {
            cancellation?.throwIfCancelled();
            final request = await client.postUrl(config.endpoint);
            request.followRedirects = false;
            request.headers
              ..contentType = ContentType.json
              ..set(
                HttpHeaders.acceptHeader,
                'application/json, text/event-stream',
              )
              ..set('MCP-Protocol-Version', McpAdapter.protocolVersion);
            if (_session != null) {
              request.headers.set('Mcp-Session-Id', _session!);
            }
            if (bearer != null) {
              request.headers.set(
                HttpHeaders.authorizationHeader,
                'Bearer $bearer',
              );
            }
            request.add(payload);
            countSent(payload.length);
            final response = await request.close();
            _session = response.headers.value('mcp-session-id') ?? _session;
            if (response.statusCode == 202) {
              await response.drain<void>();
              return null;
            }
            if (response.statusCode != 200) {
              await response.drain<void>();
              throw HttpException('mcp_http_${response.statusCode}');
            }
            final bytes = <int>[];
            await for (final chunk in response) {
              if (bytes.length + chunk.length > _maxBytes) {
                throw StateError('mcp_response_too_large');
              }
              bytes.addAll(chunk);
            }
            final body = utf8.decode(bytes);
            final type = response.headers.contentType?.mimeType;
            return type == 'text/event-stream'
                ? _fromEvents(body, message['id'])
                : Map<String, Object?>.from(_decode(body) as Map);
          })().timeout(timeout),
        );
      })();
    } finally {
      client.close(force: true);
    }
  }

  /// JSON of a response body. A parse failure quotes part of the body, which a
  /// server may have filled with the token, so the error is fixed text.
  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const FormatException('mcp_response_not_json');
    }
  }

  /// First SSE `data:` JSON-RPC message answering [id].
  static Map<String, Object?>? _fromEvents(String body, Object? id) {
    for (final event in body.split(RegExp(r'\r?\n\r?\n'))) {
      final data = [
        for (final line in event.split(RegExp(r'\r?\n')))
          if (line.startsWith('data:')) line.substring(5).trimLeft(),
      ].join('\n');
      if (data.isEmpty) continue;
      final decoded = _decode(data);
      if (decoded is Map && decoded['id'] == id) {
        return Map<String, Object?>.from(decoded);
      }
    }
    return null;
  }
}
