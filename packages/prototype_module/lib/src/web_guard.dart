import 'package:muyon_module_api/muyon_module_api.dart';

import 'scheme_loader.dart';

/// Why a navigation or bridge call was refused; shown in logs and tests.
enum GuardVerdict { allowed, blockedNavigation, blockedBridge }

/// Decides what a prototype page may load and say to the host.
///
/// It tightens [RestrictedWebViewSpec]: any `..` or encoded dot segment in the
/// raw URL, embedded credentials, and every scheme other than `file`/`https`
/// are refused before the spec's allowed-root check runs. `about:blank` is the
/// only non-file page a WebView needs to start from and is allowed.
class PrototypeWebGuard {
  PrototypeWebGuard(this.spec);

  final RestrictedWebViewSpec spec;

  static final _dotSegment = RegExp(r'(^|[/\\])(\.|%2e|%2E){2}([/\\]|$)');

  late final _loader = PrototypeSchemeLoader(spec);

  bool allowsNavigation(String rawUrl) {
    if (rawUrl == 'about:blank') return true;
    if (rawUrl.toLowerCase().startsWith('$prototypeScheme:')) {
      return _loader.toFileUrl(rawUrl) != null;
    }
    if (_dotSegment.hasMatch(rawUrl)) return false;
    final Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } on FormatException {
      return false;
    }
    if (uri.userInfo.isNotEmpty) return false;
    return spec.allowsNavigation(uri);
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
