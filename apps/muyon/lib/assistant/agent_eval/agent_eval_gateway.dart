part of 'agent_eval.dart';

// ---------------------------------------------------------------- gateway

/// A model request or a summary request: the person confirms it as a request
/// to the model, there is no tool call on it.
bool confirmsAsModelRequest(String stage) =>
    stage == 'model' || stage == 'compaction';

class GatewayCall {
  const GatewayCall({
    required this.ms,
    required this.ok,
    this.promptTokens,
    this.completionTokens,
    this.firstEventMs,
  });
  final double ms;
  final bool ok;
  final int? promptTokens, completionTokens;

  /// Streamed responses only: time to the first event (the first token, or
  /// the first piece of a tool call). null for a non-streamed response.
  final double? firstEventMs;
}

int? _count(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : null;

/// The product gateway with a stopwatch and the usage field kept. Only
/// timing and token counts are recorded, never request or response bodies.
/// A non-streaming profile goes through [request]; a streaming or native one
/// through [chatStream], which is recorded too, with the time to its first
/// event. The first successful [calls] entry is the first response.
class RecordingGateway extends OpenAiModelGateway {
  RecordingGateway(super.secrets, {super.timeout, super.ledger});
  final calls = <GatewayCall>[];

  @override
  Future<Map<String, dynamic>> request({
    required ModelProfile profile,
    required Map<String, Object?> payload,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    String caller = 'model',
  }) async {
    final watch = Stopwatch()..start();
    try {
      final decoded = await super.request(
        profile: profile,
        payload: payload,
        cancellation: cancellation,
        beforeSend: beforeSend,
        caller: caller,
      );
      final usage = decoded['usage'];
      calls.add(
        GatewayCall(
          ms: watch.elapsedMicroseconds / 1000,
          ok: true,
          promptTokens: usage is Map ? _count(usage['prompt_tokens']) : null,
          completionTokens: usage is Map
              ? _count(usage['completion_tokens'])
              : null,
        ),
      );
      return decoded;
    } catch (_) {
      calls.add(GatewayCall(ms: watch.elapsedMicroseconds / 1000, ok: false));
      rethrow;
    }
  }

  @override
  Stream<ModelEvent> chatStream({
    required ModelProvider provider,
    required ModelRequest request,
    ModelCancellation? cancellation,
    Future<void> Function()? beforeSend,
    Duration? maxDuration,
  }) async* {
    final watch = Stopwatch()..start();
    double? first;
    int? prompt, completion;
    var done = false, failed = false, recorded = false;
    void record() {
      if (recorded) return;
      recorded = true;
      calls.add(
        GatewayCall(
          ms: watch.elapsedMicroseconds / 1000,
          ok: done && !failed,
          promptTokens: prompt,
          completionTokens: completion,
          firstEventMs: first,
        ),
      );
    }

    try {
      await for (final event in super.chatStream(
        provider: provider,
        request: request,
        cancellation: cancellation,
        beforeSend: beforeSend,
        maxDuration: maxDuration,
      )) {
        first ??= watch.elapsedMicroseconds / 1000;
        switch (event) {
          case Usage():
            prompt = event.promptTokens;
            completion = event.completionTokens;
          case Done():
            done = true;
          case ModelError():
            failed = true;
          default:
            break;
        }
        yield event;
      }
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      record();
    }
  }
}
