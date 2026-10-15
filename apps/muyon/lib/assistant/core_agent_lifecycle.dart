import 'package:muyon_module_api/muyon_module_api.dart';

import '../platform/tool_registry.dart';
import '../platform/foundation_repository.dart';
import '../services/models/model_gateway.dart';
import 'core_agent_protocol.dart';

/// Cancellation before admission prevents dispatch. After admission the host
/// drains the real read receipt; a model cancellation cannot rewrite it.
final class CoreAgentLifecycle {
  final modelCancellation = ModelCancellation();
  bool stopped = false;
  bool closing = false;
  bool admitted = false;
  Future<ToolCallResult>? pending;

  void stop({required bool close}) {
    if (stopped) return;
    stopped = true;
    closing = close;
    modelCancellation.cancel();
  }

  Future<ToolCallResult> invoke(
    ToolRegistry registry,
    ToolCallRequest request,
  ) {
    if (stopped || admitted) {
      throw const CoreAgentFailure('tool_denied');
    }
    admitted = true;
    return pending = registry.invoke(request);
  }

  ({PersonalTaskState state, String? code}) failure(
    String code, {
    required bool hasProjection,
    bool hostClosing = false,
  }) {
    final missingTransportResult = const {
      'host_protocol',
      'host_budget',
      'callback_mismatch',
      'host_eof',
      'callback_timeout',
      'core_backend_unavailable',
      'tool_outcome_unknown',
    }.contains(code);
    if (admitted && !hasProjection && missingTransportResult) {
      return (
        state: PersonalTaskState.interrupted,
        code: 'tool_outcome_unknown',
      );
    }
    if (admitted && code == 'projection_rejected') {
      return (state: PersonalTaskState.failed, code: code);
    }
    if (stopped || hostClosing) {
      return closing || hostClosing
          ? (state: PersonalTaskState.interrupted, code: 'host_closed')
          : (state: PersonalTaskState.cancelled, code: null);
    }
    if (code == 'host_eof') {
      return (state: PersonalTaskState.interrupted, code: code);
    }
    return (
      state: PersonalTaskState.failed,
      code:
          code == 'model_confirmation_required' ||
              code == 'tool_confirmation_required'
          ? 'core_confirmation_required'
          : code,
    );
  }
}
