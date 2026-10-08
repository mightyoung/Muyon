import 'package:supplier_core/lan.dart';

import '../outbound_tool_ledger.dart';
import 'host_tool_authorization.dart';

/// Per-push adapter: other discovery/probe/reply traffic keeps its own ledger.
final class HostTransferLedger implements LanOutboundLedger {
  HostTransferLedger(this.ledger, this.authorization);
  final OutboundToolLedger ledger;
  final HostAuthorizationLink authorization;
  @override
  Future<T> send<T>({
    required String toolId,
    required Uri destination,
    required String payloadDigest,
    required Future<T> Function(void Function(int)) operation,
  }) => ledger.runDigest(
    toolId: authorization.toolId,
    channel: 'transfer',
    destination: destination,
    payloadDigest: payloadDigest,
    authorization: authorization,
    errorCode: 'transfer_request_failed',
    operation: operation,
  );
}
