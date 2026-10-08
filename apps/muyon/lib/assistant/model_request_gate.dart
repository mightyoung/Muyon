/// Where a model request is allowed to proceed (ADR-0005 §7.1). The agent
/// asks the gate before every request; whatever the gate answers, the request
/// still goes through `beforeSend` and `ledger.begin`. Only host code calls
/// it: neither the loop nor a provider has any way to grant or widen
/// permission.
library;

import '../services/models/model_gateway.dart';
import '../platform/grants/host_authorization_policy.dart';

final class ModelRequestFacts {
  const ModelRequestFacts({
    required this.location,
    required this.endpoint,
    required this.endpointIdentity,
    required this.scopeDigest,
    required this.requestDigest,
    required this.dataCategories,
    required this.step,
  });

  /// From the profile the person set, never from the model or the endpoint
  /// text.
  final ModelLocation location;
  final String endpoint, endpointIdentity;
  final String scopeDigest, requestDigest;
  final Set<String> dataCategories;
  final int step;
}

sealed class GateDecision {
  const GateDecision();
}

/// Show the confirmation card and wait for the person.
final class GateConfirm extends GateDecision {
  const GateConfirm({this.policyRevision});
  final String? policyRevision;
}

/// Reserved for AUTH-1; K-2a treats it as not allowed.
///
/// Proceed without a card; the ledger and the receipt record [grantId].
final class GateAllowed extends GateDecision {
  const GateAllowed(this.grantId);
  final String grantId;
}

final class GateDenied extends GateDecision {
  const GateDenied(this.reason);
  final String reason;
}

abstract interface class ModelRequestGate {
  Future<GateDecision> decide(ModelRequestFacts facts);
}

/// Today's behaviour: every model request waits for the person's
/// confirmation.
class AlwaysConfirmGate implements ModelRequestGate {
  const AlwaysConfirmGate();
  @override
  Future<GateDecision> decide(ModelRequestFacts facts) async =>
      const GateConfirm();
}

/// Rechecks the actual host policy for an already-confirmed request.
abstract interface class ModelPolicyGuard {
  void checkPolicy(String? revision);
}

/// Category fencing only. Automatic mode/grant issuance remains a separate
/// C permission service; this gate still asks the person for allowed requests.
final class HostPolicyModelGate implements ModelRequestGate, ModelPolicyGuard {
  HostPolicyModelGate(this.policy);
  final HostAuthorizationPolicy policy;
  @override
  Future<GateDecision> decide(ModelRequestFacts facts) async {
    final current = policy.current;
    return current.allows(AssistantAuthorizationCategory.model)
        ? GateConfirm(policyRevision: current.revision)
        : const GateDenied('该操作类别已关闭，未提出');
  }

  @override
  void checkPolicy(String? revision) {
    final current = policy.current;
    if (!current.allows(AssistantAuthorizationCategory.model) ||
        current.revision != revision) {
      throw StateError('model_policy_changed');
    }
  }
}
