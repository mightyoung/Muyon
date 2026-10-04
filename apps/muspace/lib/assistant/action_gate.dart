import 'package:muspace_module_api/muspace_module_api.dart';

class ActionGate {
  const ActionGate();
  void require(
    PermissionDecision decision,
    Invocation invocation,
    ToolDescriptor tool,
  ) {
    if (!decision.authorizes(invocation, tool, now: DateTime.now().toUtc())) {
      throw StateError('permission_mismatch');
    }
  }
}
