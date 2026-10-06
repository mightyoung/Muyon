import 'package:muyon_module_api/muyon_module_api.dart';

import 'scheme_loader.dart';

/// Why a navigation or bridge call was refused; shown in logs and tests.
enum GuardVerdict { allowed, blockedNavigation, blockedBridge }

/// Decides what a prototype page may navigate to and say to the host.
///
/// Navigation is limited to prototype-scheme URLs that [PrototypeSchemeLoader]
/// maps strictly inside the version root (dot segments, encoded separators,
/// bad encodings, credentials and ports are all refused there) plus
/// `about:blank`, which a WebView starts from.
class PrototypeWebGuard {
  PrototypeWebGuard(this.spec);

  final RestrictedWebViewSpec spec;

  late final _loader = PrototypeSchemeLoader(spec);

  /// Only `about:blank` and prototype-scheme URLs that map inside the version
  /// root. `file:` and `https:` top-level navigation is refused outright: the
  /// page itself is loaded through the scheme, so nothing legitimate needs it.
  bool allowsNavigation(String rawUrl) {
    if (rawUrl == 'about:blank') return true;
    if (!rawUrl.toLowerCase().startsWith('$prototypeScheme:')) return false;
    return _loader.toFileUrl(rawUrl) != null;
  }

  /// Page → host messages. Only registered channels pass; the payload is
  /// handed on for the normal tool/permission path and never executed here.
  bool allowsBridge(String channel) => spec.allowsBridge(channel);

  GuardVerdict checkNavigation(String rawUrl) => allowsNavigation(rawUrl)
      ? GuardVerdict.allowed
      : GuardVerdict.blockedNavigation;

  GuardVerdict checkBridge(String channel) =>
      allowsBridge(channel) ? GuardVerdict.allowed : GuardVerdict.blockedBridge;
}
