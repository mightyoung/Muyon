import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';

/// Host metadata and compiler output, never a renderer capability before end.
class HostUiStreamProgress {
  const HostUiStreamProgress(
    this.request,
    this.session,
    this.view, {
    this.failureCode,
    this.compilationPhase,
  });
  final UiPlanningRequest request;
  final UiStreamSession session;
  final UiStreamView view;
  final String? failureCode;
  final UiStreamPhase? compilationPhase;

  /// Preserve compiler evidence and the last read-only preview while revoking
  /// the capability independently of the original whole-candidate validation.
  HostUiStreamProgress revoke(String code, {UIPlan? preview}) =>
      HostUiStreamProgress(
        request,
        session,
        UiStreamView(
          candidatePlan: view.candidatePlan,
          previewPlan: session.plan([
            for (final node in (preview ?? view.previewPlan).nodes)
              node.copyWith(events: const {}),
          ]),
          statuses: view.statuses,
          text: view.text,
          diagnostics: view.diagnostics,
          phase: view.complete || view.phase == UiStreamPhase.streaming
              ? UiStreamPhase.incomplete
              : view.phase,
          receivedLines: view.receivedLines,
          badLines: view.badLines,
          diagnosticCount: view.diagnosticCount,
          batchValidation: view.batchValidation,
        ),
        failureCode: code,
        compilationPhase: compilationPhase ?? view.phase,
      );
}

typedef HostUiModelStream = Future<void> Function(
  UiPlanningRequest request,
  String prompt,
  void Function(String) receive,
);

class _StreamFailure extends StateError {
  _StreamFailure(this.code) : super(code);
  final String code;
}

/// Production NDJSON gateway stream. Whole original candidate remains the final
/// validation input; bad lines are not filtered into a successful replacement.
class StreamMotivationUiPlanningProvider implements UiPlanningPort {
  StreamMotivationUiPlanningProvider(this.requestModel, {this.onProgress});
  final HostUiModelStream requestModel;
  final void Function(HostUiStreamProgress)? onProgress;
  final _progress = <UiPlanningRequest, HostUiStreamProgress>{};
  HostUiStreamProgress? progressFor(UiPlanningRequest request) =>
      _progress[request];

  @override
  Future<UiPlanningResult> plan(UiPlanningRequest request) async {
    if (request.catalog.version != 'library-2') {
      throw StateError('Stream production requires library-2');
    }
    final session = UiStreamSession(
      surfaceId: request.currentView.surfaceId,
      revision: request.currentView.revision + 1,
      snapshot: request.snapshot,
      intent: request.intent,
      catalog: request.catalog,
      protocolVersion: streamProtocolV2,
    );
    final compiler = UiStreamCompiler(session: session);
    final pending = StringBuffer();
    var pendingBytes = 0;
    var firstLineIsEndOnly = false;
    // A rejected end deliberately empties the shared compiler's preview. Keep
    // its last pre-end projection separately, never its executable candidate.
    var lastReadOnlyPreview = compiler.current.previewPlan;
    // After end only the line boundary matters. Do not buffer untrusted trailing
    // content or apply a pre-end byte limit to ignored protocol lines.
    bool getEnded() =>
        compiler.current.phase == UiStreamPhase.complete ||
        compiler.current.phase == UiStreamPhase.rejected;
    void publish() {
      final current = compiler.current;
      if (current.phase == UiStreamPhase.streaming) {
        lastReadOnlyPreview = current.previewPlan;
      }
      final progress = HostUiStreamProgress(request, session, current);
      final value = current.phase == UiStreamPhase.rejected
          ? progress.revoke(
              current.badLines > 0 ? 'malformed_stream' : 'invalid_plan',
              preview: lastReadOnlyPreview,
            )
          : progress;
      _progress[request] = value;
      onProgress?.call(value);
    }

    void line(String value) {
      if (compiler.current.receivedLines == 0) {
        firstLineIsEndOnly =
            parseUiStreamLine(
                  value,
                  protocolVersion: streamProtocolV2,
                ).operation
                is UiStreamEnd;
      }
      final view = compiler.addLine(value);
      // Await normal transport completion before classifying the end-only
      // decision; do not publish empty-plan validation as a host refusal.
      if (!(firstLineIsEndOnly && view.receivedLines == 1)) publish();
      if (view.phase == UiStreamPhase.limitExceeded) {
        throw _StreamFailure('limit_exceeded');
      }
    }

    try {
      publish();
      await requestModel(
        request,
        jsonEncode({
          'instructions':
              'Return raw aiui-stream/2 NDJSON only, one operation per line. '
              'Use the supplied library-2 schemas and trusted snapshot bindings. '
              'Do not return batch JSON, a markdown fence or an assistant answer envelope. '
              'The host freezes surface/revision/snapshot/intent. Root id is root. '
              'If no content card is useful, return only {"op":"end"} and no other operation. '
              'Otherwise end with {"op":"end"}. Actions are unavailable until full end validation.',
          'protocol': streamProtocolV2,
          'request': request.toJson(),
        }),
        (chunk) {
          for (final unit in chunk.runes) {
            if (unit == 10) {
              final value = pending.toString();
              line(
                value.endsWith('\r')
                    ? value.substring(0, value.length - 1)
                    : value,
              );
              pending.clear();
              pendingBytes = 0;
            } else if (getEnded()) {
              pendingBytes = 1;
            } else {
              pending.writeCharCode(unit);
              pendingBytes += unit <= 0x7f
                  ? 1
                  : unit <= 0x7ff
                  ? 2
                  : unit <= 0xffff
                  ? 3
                  : 4;
              if (pendingBytes > UiStreamLimits.v1.lineBytes) {
                line(pending.toString());
                throw _StreamFailure('limit_exceeded');
              }
            }
          }
        },
      );
      request.requireCurrentModelReferences();
      if (pendingBytes > 0) line(pending.toString());
      // Provider-level no-card decision only; the compiler still rejects an
      // empty UIPlan and cannot grant a final capability. Transport must finish.
      if (firstLineIsEndOnly &&
          compiler.current.receivedLines == 1 &&
          compiler.current.badLines == 0) {
        _progress.remove(request);
        return UiPlanningResult(
          decision: UiDisplayDecision.textOnly,
          reasonCode: 'model_no_card',
        );
      }
      if (!compiler.current.complete || compiler.current.finalPlan == null) {
        compiler.interrupt();
        publish();
        final view = compiler.current;
        throw _StreamFailure(
          view.phase == UiStreamPhase.limitExceeded
              ? 'limit_exceeded'
              : view.phase == UiStreamPhase.incomplete
              ? 'incomplete'
              : view.badLines > 0
              ? 'malformed_stream'
              : 'invalid_plan',
        );
      }
      return UiPlanningResult(
        decision: UiDisplayDecision.supplement,
        reasonCode: 'validated_stream_2',
        plan: compiler.current.finalPlan!.plan,
      );
    } catch (error) {
      compiler.interrupt();
      final value = HostUiStreamProgress(request, session, compiler.current)
          .revoke(
            error is _StreamFailure
                ? error.code
                : error is StateError && error.message == 'model_unavailable'
                ? 'model_unavailable'
                : error is StateError &&
                      error.message == 'planning_model_cancelled'
                ? 'cancelled'
                : 'transport_error',
            preview: compiler.current.phase == UiStreamPhase.rejected
                ? lastReadOnlyPreview
                : null,
          );
      _progress[request] = value;
      onProgress?.call(value);
      rethrow;
    }
  }
}
