/// Where a model request is allowed to proceed (ADR-0005 §7.1). The agent
/// asks the gate before every request; whatever the gate answers, the request
/// still goes through `beforeSend` and `ledger.begin`. Only host code calls
/// it: neither the loop nor a provider has any way to grant or widen
/// permission.
library;

import '../services/models/model_gateway.dart';

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
  const GateConfirm();
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
