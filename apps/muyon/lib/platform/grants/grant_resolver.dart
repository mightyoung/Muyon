import 'grant.dart';
import 'grant_store.dart';

/// Resolution never consumes or mints permission. The future host wiring must
/// call recordUse with the same authoritative request before signing approval.
final class GrantResolver {
  GrantResolver(this.store);
  final GrantStore store;

  AssistantGrant? resolve(GrantRequest request) => store.findMatching(request);
}
