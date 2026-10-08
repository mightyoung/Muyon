import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../platform/outbound_ledger.dart';
import '../../platform/grants/host_authorization_policy.dart';
import '../../platform/grants/host_model_authorization.dart';
import 'credential_redaction.dart';
import 'model_provider.dart';

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

/// OpenAI-compatible providers document a base URL ("https://api.deepseek.com"
/// or ".../v1"); the request goes to its chat or embeddings path. A base URL
/// is completed here so the stored profile, the consent preview and the
/// request all show the same full URL. Any other path is used as given.
Uri completeModelEndpoint(Uri endpoint, ModelPurpose purpose) {
  final path = endpoint.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isNotEmpty && !RegExp(r'^/v\d+$').hasMatch(path)) return endpoint;
  final tail = purpose == ModelPurpose.chat ? 'chat/completions' : 'embeddings';
  return endpoint.replace(path: '$path/$tail');
}

class ModelProfile {
  ModelProfile({
    required this.id,
    required Uri endpoint,
    required this.location,
    required this.modelId,
    required this.endpointIdentity,
    this.credentialRef,
    this.cloudProxy = false,
    this.purpose = ModelPurpose.chat,
    this.capabilities = ModelCapabilities.compat,
    this.detectedCapabilities,
  }) : endpoint = completeModelEndpoint(endpoint, purpose) {
    if (!this.endpoint.hasAuthority ||
        this.endpoint.userInfo.isNotEmpty ||
        this.endpoint.fragment.isNotEmpty ||
        this.endpoint.query.isNotEmpty ||
        !['http', 'https'].contains(this.endpoint.scheme) ||
        modelId.trim().isEmpty ||
        id.isEmpty ||
        endpointIdentity.isEmpty) {
      throw ArgumentError('Invalid model profile');
    }
    if (location == ModelLocation.remote && this.endpoint.scheme != 'https') {
      throw ArgumentError('Remote endpoints require HTTPS');
    }
    if (location == ModelLocation.local &&
        !['localhost', '127.0.0.1', '::1'].contains(this.endpoint.host)) {
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

  /// Declared by the person (or a preset); code-constructed profiles are
  /// compatibility mode, non-streaming.
  final ModelCapabilities capabilities;

  /// The last "测试连接" result (ADR-0005 §4.5). Never read when a task starts
  /// and never part of [toJson]: only [toStoredJson] carries it.
  final DetectedCapabilities? detectedCapabilities;

  ModelProfile copyWith({
    ModelCapabilities? capabilities,
    DetectedCapabilities? detectedCapabilities,
  }) => ModelProfile(
    id: id,
    endpoint: endpoint,
    location: location,
    modelId: modelId,
    endpointIdentity: endpointIdentity,
    credentialRef: credentialRef,
    cloudProxy: cloudProxy,
    purpose: purpose,
    capabilities: capabilities ?? this.capabilities,
    detectedCapabilities: detectedCapabilities ?? this.detectedCapabilities,
  );

  /// What the profile repository saves: [toJson] plus the detection result.
  /// Kept apart so the task payload, digests and previews are unchanged.
  Map<String, Object?> toStoredJson() => {
    ...toJson(),
    if (detectedCapabilities != null)
      'detectedCapabilities': detectedCapabilities!.toJson(),
  };

  /// [toJson] without the capability block: the shape digests had before
  /// capabilities existed, so they do not change with the upgrade.
  Map<String, Object?> toJsonWithoutCapabilities() =>
      toJson()..remove('capabilities');

  Map<String, Object?> toJson() => {
    'id': id,
    'endpoint': endpoint.toString(),
    'location': location.name,
    'modelId': modelId,
    'endpointIdentity': endpointIdentity,
    'credentialRef': credentialRef,
    'cloudProxy': cloudProxy,
    'purpose': purpose.name,
    'capabilities': capabilities.toJson(),
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
    this.connectTimeout = const Duration(seconds: 15),
    this.idleTimeout = const Duration(seconds: 60),
    this.streamLimit = const Duration(minutes: 5),
    HttpClient Function()? clientFactory,
    this.ledger,
    this.authorizationPolicy,
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final SecretStore secrets;

  /// [text] with the credential of [profile] masked, for content an endpoint
  /// wrote that is about to be stored (it may echo the key).
  Future<String> mask(ModelProfile profile, String text) async {
    final ref = profile.credentialRef;
    if (ref == null) return text;
    return maskSecret(text, await secrets.read(ref));
  }

  /// Records every request before it is sent; when set, a failed record
  /// means the request is not sent.
  final OutboundLedger? ledger;
  final HostAuthorizationPolicy? authorizationPolicy;
  final Duration timeout;

  /// Streaming requests (ADR-0005 §6.1): connecting, silence between two
  /// chunks, and the absolute length of one request. They replace [timeout],
  /// which still covers the non-streaming [chat] / [request] / [embed].
  final Duration connectTimeout, idleTimeout, streamLimit;
  final int maxResponseBytes;
  final HttpClient Function() _clientFactory;

  Future<String> chat({
    required ModelProfile profile,
    required List<Map<String, String>> messages,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'chat',
  }) async {
    if (profile.purpose != ModelPurpose.chat) {
      throw StateError('Model profile is not configured for chat');
    }
    Future<Map<String, dynamic>> send(bool withFormat) => request(
      profile: profile,
      payload: {
        'model': profile.modelId,
        'messages': messages,
        'stream': false,
        if (withFormat) 'response_format': const {'type': 'json_object'},
      },
      cancellation: cancellation,
      beforeSend: beforeSend,
      caller: caller,
    );
    final key = '${profile.endpoint}|${profile.modelId}';
    final withFormat =
        _jsonObjectCallers.contains(caller) && !_noJsonObject.contains(key);
    Map<String, dynamic> decoded;
    try {
      decoded = await send(withFormat);
    } on HttpException catch (error) {
      // An endpoint that rejects response_format (400/422) must keep working:
      // send the same confirmed content once more without it. Both requests
      // are in the ledger. Only a resend that succeeds proves the parameter
      // was the problem; a 400 for another reason (e.g. context too long)
      // must not mark the endpoint as lacking JSON mode.
      final rejected =
          error.message == 'model_http_400' ||
          error.message == 'model_http_422';
      if (!withFormat || !rejected) rethrow;
      decoded = await send(false);
      _noJsonObject.add(key);
    }
    final content = (decoded['choices'] as List).first['message']['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Empty model response');
    }
    return content;
  }

  /// Callers whose protocol is one JSON object per reply. They ask for JSON
  /// output so a model does not answer in prose or in its native tool-call
  /// markup (P0-3d); other callers keep their plain requests.
  static const _jsonObjectCallers = {'assistant'};

  /// Endpoint+model pairs that rejected `response_format: json_object`.
  final _noJsonObject = <String>{};

  /// Endpoint is explicit in the profile; no URL rewriting or provider fallback.
  Future<List<List<double>>> embed({
    required ModelProfile profile,
    required List<String> texts,
    ModelCancellation? cancellation,
    required Future<void> Function() beforeSend,
    String caller = 'embedding',
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
      caller: caller,
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
    String caller = 'model',
  }) async {
    final frozenPayload = jsonEncode(payload);
    final items = payload['messages'] ?? payload['input'];
    if (utf8.encode(frozenPayload).length > 2 * 1024 * 1024) {
      throw ArgumentError('Model payload too large');
    }
    final token = cancellation ?? ModelCancellation();
    token.check();
    final channel = _GatewayChannel(this, profile, token, streamed: false);
    try {
      return await (() async {
        await channel.open(
          payload: frozenPayload,
          itemCount: items is List ? items.length : 1,
          caller: caller,
          beforeSend: beforeSend,
        );
        final bytes = <int>[];
        await for (final chunk in channel.body) {
          bytes.addAll(chunk);
        }
        token.check();
        // The parser quotes (and truncates) the body in its message, so an
        // endpoint echoing the key could leak part of it past maskSecret.
        // Fail with a fixed reason instead of the source text.
        final Object? parsed;
        try {
          parsed = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          throw const FormatException('model_response_not_json');
        }
        if (parsed is! Map<String, dynamic>) {
          throw const FormatException('model_response_not_object');
        }
        final decoded = parsed;
        await channel.finish(const OutboundOutcome(OutboundStatus.succeeded));
        return decoded;
      })().timeout(timeout);
    } on TimeoutException {
      token.cancel();
      await channel.finish(
        OutboundOutcome(OutboundStatus.timeout, error: channel.stoppedNote),
      );
      rethrow;
    } catch (error, stack) {
      await channel.fail(error, stack);
    } finally {
      channel.dispose();
    }
  }

  /// One model request as events (ADR-0005 §4.4, §5). Same order as
  /// [request]: credential, `beforeSend`, `ledger.begin`, send. A failed
  /// `begin` sends nothing. One ledger row spans the whole stream and is
  /// finished once: `succeeded` after [Done], `failed` for an HTTP error,
  /// a provider error event or a body that ends without a finish reason
  /// (`stream_truncated`, with `bytes_received`), `timeout` for a silent
  /// connection or a stream past its limit, `cancelled` when the caller
  /// cancels or stops listening. Pre-send failures and non-200 answers are
  /// thrown (an [HttpException] `model_http_<code>`, redacted like
  /// [request]), as is a connection that drops mid-stream; a provider error
  /// event or a body that ends without a finish reason is a [ModelError].
  /// There is no fallback to another protocol, model or endpoint.
  ///
  /// [maxDuration] caps one request below [streamLimit] (the host passes what
  /// is left of its active-time budget).
  Stream<ModelEvent> chatStream({
    required ModelProvider provider,
    required ModelRequest request,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    Duration? maxDuration,
  }) async* {
    if (request.profile.purpose != ModelPurpose.chat) {
      throw StateError('Model profile is not configured for chat');
    }
    final key = '${request.profile.endpoint}|${request.profile.modelId}';
    var attempt =
        request.jsonObject &&
            (_noJsonObject.contains(key) ||
                HostModelPermission.current?.prefersWithoutJsonObject == true)
        ? request.withoutJsonObject()
        : request;
    final first = attempt;
    while (true) {
      try {
        // Not `yield*`: that forwards an error to the listener instead of
        // throwing it here, where the resend rule below must see it.
        await for (final event in _streamOnce(
          provider,
          attempt,
          cancellation,
          beforeSend,
          maxDuration,
        )) {
          yield event;
        }
        if (!identical(attempt, first)) _noJsonObject.add(key);
        return;
      } on HttpException catch (error) {
        // Same rule as [chat], for non-streaming requests only: an endpoint
        // that rejects response_format (400/422) gets the confirmed content
        // once more without it; both requests are in the ledger. A streamed
        // request is never resent: a 400/422 could just as well be about
        // `stream`, so the caller fails with a fixed reason instead.
        final rejected =
            error.message == 'model_http_400' ||
            error.message == 'model_http_422';
        if (attempt.profile.capabilities.streaming ||
            !attempt.jsonObject ||
            !rejected) {
          rethrow;
        }
        HostModelPermission.current?.allowCompatibilityRetry();
        attempt = attempt.withoutJsonObject();
      }
    }
  }

  Stream<ModelEvent> _streamOnce(
    ModelProvider provider,
    ModelRequest request,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    Duration? maxDuration,
  ) async* {
    final frozenPayload = jsonEncode(provider.encode(request));
    if (utf8.encode(frozenPayload).length > 2 * 1024 * 1024) {
      throw ArgumentError('Model payload too large');
    }
    final token = cancellation ?? ModelCancellation();
    token.check();
    final channel = _GatewayChannel(
      this,
      request.profile,
      token,
      streamed: request.profile.capabilities.streaming,
    );
    var limitHit = false;
    var finished = false;
    Timer? limit;
    int? promptTokens, completionTokens;
    final cap = maxDuration != null && maxDuration < streamLimit
        ? maxDuration
        : streamLimit;
    try {
      // The cap runs from the start, so a server that accepts the connection
      // and never answers cannot hold the request past it either.
      limit = Timer(cap, () {
        limitHit = true;
        token.cancel();
      });
      final streamed = request.profile.capabilities.streaming;
      final base = streamed ? idleTimeout : timeout;
      await channel.open(
        payload: frozenPayload,
        itemCount: request.messages.length,
        caller: request.caller,
        beforeSend: beforeSend,
        requestDigest: request.requestDigest,
        headerTimeout: base < cap ? base : cap,
      );
      ModelError? failure;
      var done = false;
      await for (final event in provider.decode(request, channel.body)) {
        if (event is Usage) {
          promptTokens = event.promptTokens;
          completionTokens = event.completionTokens;
        }
        yield event;
        if (event is Done) done = true;
        if (event is ModelError) failure = event;
        if (done || failure != null) break;
      }
      token.check();
      if (limitHit) throw TimeoutException('model_stream_limit');
      if (!done && failure == null) {
        failure = ModelError(
          'stream_truncated',
          partialOutput: channel.bytesReceived > 0,
        );
        yield failure;
      }
      finished = true;
      await channel.finish(
        failure == null
            ? OutboundOutcome(
                OutboundStatus.succeeded,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
              )
            : OutboundOutcome(
                OutboundStatus.failed,
                error: failure.code,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
              ),
      );
    } on TimeoutException {
      finished = true;
      token.cancel();
      await channel.finish(
        OutboundOutcome(OutboundStatus.timeout, error: channel.stoppedNote),
      );
      rethrow;
    } catch (error, stack) {
      if (limitHit) {
        finished = true;
        await channel.finish(
          OutboundOutcome(OutboundStatus.timeout, error: channel.stoppedNote),
        );
        throw TimeoutException('model_stream_limit');
      }
      finished = true;
      // Stopping the client makes the body fail with a connection error:
      // that is the caller's cancellation, not a new failure.
      await channel.fail(
        token.isCancelled && error is! StateError
            ? StateError('cancelled')
            : error,
        stack,
      );
    } finally {
      limit?.cancel();
      if (!finished) {
        // The listener went away (or the generator was closed) mid-stream.
        await channel.finish(
          OutboundOutcome(OutboundStatus.cancelled, error: channel.stoppedNote),
        );
      }
      channel.dispose();
    }
  }

  Future<void> _finish(
    String? id,
    OutboundOutcome outcome,
    int? httpStatus, {
    int? firstByteMs,
    int? bytesReceived,
  }) async {
    if (id == null) return;
    try {
      await ledger!.finish(
        id,
        outcome.status.name,
        httpStatus: httpStatus,
        error: outcome.error,
        promptTokens: outcome.promptTokens,
        completionTokens: outcome.completionTokens,
        firstByteMs: firstByteMs,
        bytesReceived: bytesReceived,
      );
    } catch (_) {
      // Left as 'sending'; recoverInterrupted() marks it on next start. The
      // request's own result/error is what the caller must see.
    }
  }
}

/// The gateway's one outbound path (ADR-0005 §4.4): credential, `beforeSend`,
/// ledger row, send, status check, then the body with its limits.
class _GatewayChannel implements OutboundChannel {
  _GatewayChannel(
    this._gateway,
    this.profile,
    this.token, {
    required this.streamed,
  }) : _client = _gateway._clientFactory() {
    if (streamed) _client.connectionTimeout = _gateway.connectTimeout;
    token.add(abort);
    _stopPolicyWatch = _gateway.authorizationPolicy?.onChange(token.cancel);
    _stopGrantWatch = _permission?.watch(token);
  }
  final OpenAiModelGateway _gateway;
  final ModelProfile profile;
  final ModelCancellation token;

  /// Streaming requests also record first byte, size and an idle limit.
  final bool streamed;
  final HttpClient _client;
  HttpClientResponse? _response;
  String? _recordId;
  String? _usedCredential;
  bool _sent = false;
  String? _policyRevision;
  String? _permissionPayload;
  final _permission = HostModelPermission.current;
  void Function()? _stopPolicyWatch, _stopGrantWatch;
  void _checkPolicy() {
    final permission = _permission;
    if (permission != null && _permissionPayload != null) {
      final ledger = _gateway.ledger;
      if (ledger == null) throw StateError('model_permission_ledger_required');
      permission.check(
        database: ledger.database,
        profile: profile,
        payload: _permissionPayload!,
      );
    }
    final policy = _gateway.authorizationPolicy;
    if (policy == null) return;
    final current = policy.current;
    _policyRevision ??= current.revision;
    if (!current.allows(AssistantAuthorizationCategory.model) ||
        current.revision != _policyRevision) {
      throw StateError('model_policy_changed');
    }
  }

  int? _httpStatus;
  int _bytes = 0;
  int? _firstByteMs;
  final _sinceBegin = Stopwatch();

  void abort() => _client.close(force: true);

  void dispose() {
    _stopPolicyWatch?.call();
    _stopGrantWatch?.call();
    token.remove(abort);
    abort();
  }

  @override
  int get bytesReceived => _bytes;

  String get stoppedNote => _sent
      ? 'Stopped after the request was sent; the endpoint may have processed it'
      : 'Stopped before the request was sent';

  Future<String?> _readCredential(String reference) async {
    token.check();
    final stopped = Completer<String?>();
    void cancelled() {
      if (!stopped.isCompleted) stopped.completeError(StateError('cancelled'));
    }

    token.add(cancelled);
    try {
      return await Future.any([
        _gateway.secrets.read(reference),
        stopped.future,
      ]);
    } finally {
      token.remove(cancelled);
    }
  }

  Future<void> open({
    required String payload,
    required int itemCount,
    required String caller,
    Future<void> Function()? beforeSend,
    String? requestDigest,
    Duration? headerTimeout,
  }) async {
    _permissionPayload = payload;
    await _permission?.prepareAttempt(payload);
    token.check();
    _checkPolicy();
    final credential = profile.credentialRef == null
        ? null
        : await _readCredential(profile.credentialRef!);
    token.check();
    if (profile.credentialRef != null &&
        (credential == null || credential.isEmpty)) {
      throw StateError('credential_unavailable');
    }
    // Checked before approval and before the ledger row: a key dart:io
    // cannot put in a header would otherwise fail with the whole header,
    // key included, in the exception text.
    if (credential != null && !isSendableCredential(credential)) {
      throw StateError('credential_invalid');
    }
    _usedCredential = credential;
    if (beforeSend != null) await beforeSend();
    token.check();
    _checkPolicy();
    _recordId = await _gateway.ledger?.begin(
      caller: caller,
      profile: profile,
      payload: payload,
      itemCount: itemCount,
      requestDigest: requestDigest,
      streamed: streamed ? true : null,
    );
    _sinceBegin.start();
    token.check();
    _checkPolicy();
    final request = await _client.postUrl(profile.endpoint);
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (credential != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $credential',
      );
    }
    token.check();
    _checkPolicy();
    request.write(payload);
    _sent = true;
    final response = headerTimeout == null
        ? await request.close()
        : await request.close().timeout(
            headerTimeout,
            onTimeout: () => throw TimeoutException('model_header_timeout'),
          );
    _httpStatus = response.statusCode;
    if (response.statusCode != 200) {
      throw HttpException('model_http_${response.statusCode}');
    }
    _response = response;
  }

  @override
  Stream<List<int>> get body async* {
    Stream<List<int>> source = _response!;
    if (streamed) {
      source = source.timeout(
        _gateway.idleTimeout,
        onTimeout: (sink) {
          sink.addError(TimeoutException('model_stream_idle'));
          sink.close();
        },
      );
    }
    var total = 0;
    await for (final chunk in source) {
      token.check();
      _checkPolicy();
      if (total + chunk.length > _gateway.maxResponseBytes) {
        throw StateError('model_response_too_large');
      }
      total += chunk.length;
      if (streamed) {
        _bytes = total;
        _firstByteMs ??= _sinceBegin.elapsedMilliseconds;
      }
      yield chunk;
    }
  }

  @override
  Future<void> finish(OutboundOutcome outcome) => _gateway._finish(
    _recordId,
    outcome,
    _httpStatus,
    firstByteMs: streamed ? _firstByteMs : null,
    bytesReceived: streamed ? _bytes : null,
  );

  /// Ends the row for an error and throws it. Callers store and show error
  /// text (tasks, notifications, receipts); an error that quotes the key, or
  /// a header carrying it, leaves the gateway already redacted.
  Future<Never> fail(Object error, StackTrace stack) async {
    final safe = redactCredentials(error, secret: _usedCredential);
    await finish(
      OutboundOutcome(
        token.isCancelled ? OutboundStatus.cancelled : OutboundStatus.failed,
        error: token.isCancelled ? stoppedNote : safe,
      ),
    );
    if (safe != '$error') Error.throwWithStackTrace(StateError(safe), stack);
    Error.throwWithStackTrace(error, stack);
  }
}
