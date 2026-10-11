import 'dart:convert';

import 'package:muyon_module_api/ui_contract.dart';

/// Host metadata and compiler output, never a renderer capability before end.
class HostUiStreamProgress {
  const HostUiStreamProgress(this.request, this.session, this.view);
  final UiPlanningRequest request;
  final UiStreamSession session;
  final UiStreamView view;
}

typedef HostUiModelStream = Future<void> Function(
  UiPlanningRequest request, String prompt, void Function(String) receive);

/// Production NDJSON gateway stream. Whole original candidate remains the final
/// validation input; bad lines are not filtered into a successful replacement.
class StreamMotivationUiPlanningProvider implements UiPlanningPort {
  StreamMotivationUiPlanningProvider(this.requestModel, {this.onProgress});
  final HostUiModelStream requestModel;
  final void Function(HostUiStreamProgress)? onProgress;
  final _progress = <UiPlanningRequest, HostUiStreamProgress>{};
  HostUiStreamProgress? progressFor(UiPlanningRequest request) => _progress[request];

  @override
  Future<UiPlanningResult> plan(UiPlanningRequest request) async {
    if (request.catalog.version != 'library-2') {
      throw StateError('Stream production requires library-2');
    }
    final session = UiStreamSession(surfaceId: request.currentView.surfaceId,
      revision: request.currentView.revision + 1, snapshot: request.snapshot,
      intent: request.intent, catalog: request.catalog, protocolVersion: streamProtocolV2);
    final compiler = UiStreamCompiler(session: session);
    final pending = StringBuffer();
    var pendingBytes = 0, ended = false;
    void publish() {
      final value = HostUiStreamProgress(request, session, compiler.current);
      _progress[request] = value;
      onProgress?.call(value);
    }
    void line(String value) {
      if (ended) throw StateError('Content after stream end');
      final view = compiler.addLine(value);
      ended = view.phase != UiStreamPhase.streaming;
      publish();
      if (view.phase == UiStreamPhase.limitExceeded) throw StateError('Stream limit');
    }
    try {
      publish();
      await requestModel(request, jsonEncode({
        'instructions': 'Return raw aiui-stream/2 NDJSON only, one operation per line. '
          'Use the supplied library-2 schemas and trusted snapshot bindings. '
          'Do not return batch JSON, a markdown fence or an assistant answer envelope. '
          'The host freezes surface/revision/snapshot/intent. Root id is root. '
          'End with {"op":"end"}. Actions are unavailable until full end validation.',
        'protocol': streamProtocolV2, 'request': request.toJson(),
      }), (chunk) {
        // Bound each unterminated line while tokens arrive, not after assembly.
        for (final unit in chunk.runes) {
          if (unit == 10) {
            final value = pending.toString();
            line(value.endsWith('\r') ? value.substring(0, value.length - 1) : value);
            pending.clear(); pendingBytes = 0;
          } else {
            pending.writeCharCode(unit);
            pendingBytes += unit <= 0x7f ? 1 : unit <= 0x7ff ? 2 : unit <= 0xffff ? 3 : 4;
            if (pendingBytes > UiStreamLimits.v1.lineBytes) {
              throw StateError('Stream line limit');
            }
          }
        }
      });
      if (pending.isNotEmpty) line(pending.toString());
      if (!compiler.current.complete || compiler.current.finalPlan == null) {
        compiler.interrupt(); publish();
        throw StateError('Incomplete or rejected UI stream');
      }
      return UiPlanningResult(decision: UiDisplayDecision.supplement, reasonCode: 'validated_stream_2',
        plan: compiler.current.finalPlan!.plan);
    } catch (_) {
      compiler.interrupt();
      // Even a valid end followed by a transport/protocol failure must not
      // remain observable as a completed production request.
      _progress.remove(request);
      rethrow;
    }
  }
}
