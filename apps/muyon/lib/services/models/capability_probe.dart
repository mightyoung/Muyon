/// 测试连接 (ADR-0005 §4.5): a fixed probe request, sent only when the person
/// clicks "测试连接", that shows which of tools / streaming / usage (and, if
/// asked, JSON mode and parallel calls) an endpoint supports.
///
/// Every probe request takes the one outbound path: [ModelRequestGate], then
/// the gateway's channel and a ledger row with `caller = capability_probe`.
/// The payload is a constant with no user data; `probe_echo` is a made-up
/// tool that is registered nowhere and whose calls are never executed (the
/// reply is only looked at to see its shape). What is observed is returned as
/// [DetectedCapabilities]; nothing here changes a profile's capabilities.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../assistant/model_request_gate.dart';
import 'model_gateway.dart';
import 'model_presets.dart';
import 'model_provider.dart';
import 'openai_compat_provider.dart';

/// Ledger `caller` of every probe request.
const probeCaller = 'capability_probe';

/// The only tool a probe offers. It is not in any `ToolRegistry`.
const probeToolName = 'probe_echo';

/// What the confirmation card says (ADR-0005 §4.5).
const probeConfirmNotice = '将向该端点发送凭据与固定探测内容';

const probeSystemSentence =
    'You are a connectivity probe. Follow the instruction exactly.';
const probeUserSentence = '请调用工具 probe_echo，参数 {"value":"ok"}';
const probeExtendedUserSentence =
    '请同时调用两次工具 probe_echo，参数分别为 {"value":"a"} 和 {"value":"b"}，'
    '并以 JSON 对象回复。';

const _probeTool = ModelToolSpec(
  name: probeToolName,
  description: 'Echo a value back. Used only to test the connection.',
  parameters: {
    'type': 'object',
    'properties': {
      'value': {'type': 'string'},
    },
    'required': ['value'],
  },
);

ModelRequest _probeRequest(
  ModelProfile profile,
  bool extended,
  String? digest,
) => ModelRequest(
  // Streaming on: the probe asks for `stream: true` and `include_usage`.
  profile: profile.copyWith(
    capabilities: const ModelCapabilities(streaming: true),
  ),
  messages: [
    const ModelMessage(role: 'system', content: probeSystemSentence),
    ModelMessage(
      role: 'user',
      content: extended ? probeExtendedUserSentence : probeUserSentence,
    ),
  ],
  tools: const [_probeTool],
  jsonObject: extended,
  caller: probeCaller,
  requestDigest: digest,
);

/// The two fixed probe requests for [profile]. P1 asks for one tool call; P2
/// (JSON mode and parallel calls) asks for two and a JSON object reply.
ModelRequest probeRequest(ModelProfile profile, {bool extended = false}) =>
    _probeRequest(profile, extended, probeContentDigest(extended: extended));

/// Digest of the constant probe content: the wire payload without the model
/// name (messages, tool, stream options and, for P2, the response format).
/// It holds no endpoint, model or credential, so it is the same for every
/// profile, and a ledger row's `request_digest` can be compared with it.
String probeContentDigest({bool extended = false}) {
  final wire = const OpenAiCompatProvider().encode(
    _probeRequest(
      ModelProfile(
        id: 'probe',
        endpoint: Uri.parse('http://127.0.0.1/v1'),
        location: ModelLocation.local,
        modelId: 'probe',
        endpointIdentity: 'probe',
      ),
      extended,
      null,
    ),
  )..remove('model');
  return sha256.convert(utf8.encode(jsonEncode(wire))).toString();
}

/// What the person is shown before each probe request is sent.
final class ProbeConfirmation {
  const ProbeConfirmation({
    required this.index,
    required this.total,
    required this.extended,
    required this.profile,
    required this.payload,
    required this.digest,
  });

  /// 1-based number of this request and how many were asked for.
  final int index, total;
  final bool extended;
  final ModelProfile profile;

  /// The wire payload (fixed content, no user data).
  final Map<String, Object?> payload;
  final String digest;
  String get notice => probeConfirmNotice;
}

final class ProbeOutcome {
  const ProbeOutcome({this.detected, this.stoppedBy});

  /// null when no request was sent.
  final DetectedCapabilities? detected;

  /// `declined` (the person said no), `denied` (the gate refused) or
  /// `cancelled`; null when the probe ran to its end.
  final String? stoppedBy;
}

class CapabilityProbe {
  CapabilityProbe({
    required this.gateway,
    required this.gate,
    this.provider = const OpenAiCompatProvider(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final OpenAiModelGateway gateway;
  final ModelRequestGate gate;
  final ModelProvider provider;
  final DateTime Function() _clock;

  /// Sends the probe(s) for [profile], each one only after the gate and
  /// [confirm] (the person) agree. At most two requests; the second only when
  /// [extended] is set and the first got an answer.
  Future<ProbeOutcome> run(
    ModelProfile profile, {
    bool extended = false,
    required Future<bool> Function(ProbeConfirmation) confirm,
    ModelCancellation? cancellation,
  }) async {
    if (profile.purpose != ModelPurpose.chat) {
      throw ArgumentError('Only chat models can be tested');
    }
    final before = _ledgerIds(profile);
    final total = extended ? 2 : 1;
    final first = await _send(
      profile,
      extended: false,
      index: 1,
      total: total,
      confirm: confirm,
      cancellation: cancellation,
    );
    if (first.stoppedBy != null) {
      return ProbeOutcome(stoppedBy: first.stoppedBy);
    }
    var nativeTools = ProbeVerdict.undetermined;
    var streaming = ProbeVerdict.undetermined;
    var usage = ProbeVerdict.undetermined;
    final one = first.observed!;
    if (one.rejected) {
      // A 400/422 to the tools request is the endpoint saying no to tools;
      // it cannot tell whether `stream` was also a problem.
      nativeTools = ProbeVerdict.no;
    } else if (one.done) {
      streaming = ProbeVerdict.yes;
      nativeTools = one.calls >= 1
          ? ProbeVerdict.yes
          : ProbeVerdict.unconfirmed;
      usage = one.usage ? ProbeVerdict.yes : ProbeVerdict.no;
    }
    var jsonObject = ProbeVerdict.notTested;
    var parallel = ProbeVerdict.notTested;
    if (extended) {
      if (!one.done) {
        jsonObject = parallel = ProbeVerdict.undetermined;
      } else {
        final second = await _send(
          profile,
          extended: true,
          index: 2,
          total: total,
          confirm: confirm,
          cancellation: cancellation,
        );
        if (second.stoppedBy != null) {
          // Stopped between the two: keep what the first one showed.
          jsonObject = parallel = ProbeVerdict.notTested;
        } else {
          final two = second.observed!;
          jsonObject = parallel = ProbeVerdict.undetermined;
          if (two.rejected) {
            jsonObject = ProbeVerdict.no;
          } else if (two.done) {
            jsonObject = ProbeVerdict.yes;
            parallel = two.calls >= 2
                ? ProbeVerdict.yes
                : ProbeVerdict.unconfirmed;
          }
        }
      }
    }
    final preset = presetFor(profile.modelId);
    final ids = _ledgerIds(profile).difference(before);
    return ProbeOutcome(
      detected: DetectedCapabilities(
        nativeTools: nativeTools,
        streaming: streaming,
        reportsUsage: usage,
        jsonObject: jsonObject,
        parallelToolCalls: parallel,
        contextTokens: preset?.contextTokens,
        maxOutputTokens: preset?.maxOutputTokens,
        presetNativeTools: preset?.nativeTools,
        detectedAt: _clock().toUtc(),
        payloadDigest: probeContentDigest(extended: extended),
        ledgerIds: ids.toList()..sort(),
      ),
    );
  }

  Set<String> _ledgerIds(ModelProfile profile) => {
    for (final row in gateway.ledger?.recent(limit: 200) ?? const [])
      if (row['caller'] == probeCaller && row['profile_id'] == profile.id)
        row['id'] as String,
  };

  Future<_Sent> _send(
    ModelProfile profile, {
    required bool extended,
    required int index,
    required int total,
    required Future<bool> Function(ProbeConfirmation) confirm,
    ModelCancellation? cancellation,
  }) async {
    final request = probeRequest(profile, extended: extended);
    final digest = request.requestDigest!;
    // No task, no scope, no data categories: the gate sees a probe for what
    // it is, and decides as for any other model request.
    final decision = await gate.decide(
      ModelRequestFacts(
        location: profile.location,
        endpoint: profile.endpoint.toString(),
        endpointIdentity: profile.endpointIdentity,
        scopeDigest: sha256.convert(utf8.encode('{}')).toString(),
        requestDigest: digest,
        dataCategories: const {},
        step: 0,
      ),
    );
    switch (decision) {
      case GateDenied():
        return const _Sent.stopped('denied');
      case GateConfirm():
        if (!await confirm(
          ProbeConfirmation(
            index: index,
            total: total,
            extended: extended,
            profile: profile,
            payload: provider.encode(request),
            digest: digest,
          ),
        )) {
          return const _Sent.stopped('declined');
        }
      case GateAllowed():
        // Authorised by a grant: no card, but still the ledger below.
        break;
    }
    final token = cancellation ?? ModelCancellation();
    var done = false, usage = false, rejected = false, errored = false;
    var calls = 0;
    try {
      await for (final event in gateway.chatStream(
        provider: provider,
        request: request,
        cancellation: token,
      )) {
        switch (event) {
          case ToolCallComplete():
            // Looked at, never executed: probe_echo is registered nowhere.
            if (event.valid && event.name == probeToolName) calls++;
          case Usage():
            usage =
                usage ||
                event.promptTokens != null ||
                event.completionTokens != null;
          case Done():
            done = true;
          case TextDelta() || ToolCallDelta():
            break;
          case ModelError():
            // Let the stream end so the ledger row is finished as failed.
            errored = true;
        }
      }
    } on HttpException catch (error) {
      rejected =
          error.message == 'model_http_400' ||
          error.message == 'model_http_422';
      done = false;
    } on StateError catch (error) {
      if (error.message == 'cancelled') {
        return const _Sent.stopped('cancelled');
      }
      done = false;
    } on Object {
      // Timeout, refused connection, dropped stream, 401/403/5xx: no result.
      done = false;
    }
    return _Sent.observed(_Observed(done && !errored, usage, rejected, calls));
  }
}

final class _Observed {
  const _Observed(this.done, this.usage, this.rejected, this.calls);
  final bool done, usage, rejected;
  final int calls;
}

final class _Sent {
  const _Sent.stopped(String this.stoppedBy) : observed = null;
  const _Sent.observed(_Observed this.observed) : stoppedBy = null;
  final String? stoppedBy;
  final _Observed? observed;
}
