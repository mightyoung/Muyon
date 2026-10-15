import 'package:muyon_module_api/muyon_module_api.dart';

import '../platform/tool_registry.dart';
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
}
