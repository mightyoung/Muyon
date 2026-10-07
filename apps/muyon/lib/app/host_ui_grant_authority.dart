/// An unforgeable, short-lived capability for an already-confirmed host UI
/// interaction. The private constructor belongs to this host UI library.
/// Models, documents, rules and SOUL are data, never callers of this issuer;
/// assistant code must not import it. No tool or module API exposes the issuer.
/// AUTH-1a does not wire it to a UI or an assistant: AUTH-1b owns that wiring.
final class HostUiGrantToken {
  HostUiGrantToken._();
  bool _active = true;

  void checkActive() {
    if (!_active) throw StateError('Host UI grant interaction has ended');
  }
}

/// Only the host UI's confirmed-interaction handler may call this function.
/// The grants barrel exposes the token type, never this issuer. A token cannot
/// be constructed from input data, extended, or retained for later creation.
Future<T> withConfirmedHostUiGrant<T>(
  Future<T> Function(HostUiGrantToken token) create,
) async {
  final token = HostUiGrantToken._();
  try {
    return await create(token);
  } finally {
    token._active = false;
  }
}
