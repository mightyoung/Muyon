/// Access boundary for a business page embedded in a restricted WebView.
///
/// The host WebView must route every navigation through [allowsNavigation]
/// and every page-to-host message through [allowsBridge]; anything else is
/// blocked. Bridge payloads still go through the normal tool/permission path.
class RestrictedWebViewSpec {
  RestrictedWebViewSpec({
    required this.entry,
    required Set<Uri> allowedRoots,
    Set<String> bridgeChannels = const {},
  }) : allowedRoots = Set.unmodifiable(allowedRoots),
       bridgeChannels = Set.unmodifiable(bridgeChannels) {
    if (!allowsNavigation(entry)) {
      throw ArgumentError.value(entry, 'entry', 'Entry outside allowed roots');
    }
  }

  static const _schemes = {'https', 'file'};

  final Uri entry;
  final Set<Uri> allowedRoots;
  final Set<String> bridgeChannels;

  bool allowsNavigation(Uri uri) {
    if (!_schemes.contains(uri.scheme)) return false;
    final target = uri.normalizePath();
    return allowedRoots.any((root) {
      if (root.scheme != target.scheme ||
          root.host != target.host ||
          root.port != target.port) {
        return false;
      }
      final base = root.path.endsWith('/') ? root.path : '${root.path}/';
      return target.path == root.path || target.path.startsWith(base);
    });
  }

  bool allowsBridge(String channel) => bridgeChannels.contains(channel);
}
