import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';

import 'web_guard.dart';

/// What a prototype page may *load*, as opposed to where it may navigate.
///
/// `shouldOverrideUrlLoading` only sees top-level navigations. Images, scripts,
/// styles, `fetch`/XHR and frames are limited by up to three layers, all fed
/// by the same [RestrictedWebViewSpec]:
///
/// 1. a Content-Security-Policy injected at document start (every platform),
/// 2. request interception where the platform has it (Android, Windows),
/// 3. an Apple content-blocker rule list (iOS/macOS).
///
/// Which layer is actually enforced on which platform is documented in
/// docs/implementation/prototype-resource-policy.md and is "unverified" on
/// real devices.
class PrototypeResourcePolicy {
  PrototypeResourcePolicy(this.spec) : _guard = PrototypeWebGuard(spec);

  final RestrictedWebViewSpec spec;
  final PrototypeWebGuard _guard;

  /// A sub-resource is allowed only if it is a `file:` URL inside an allowed
  /// root. Remote `https`, `data:`, `blob:`, `about:`, `..` paths and other
  /// local files are all refused.
  bool allowsResource(String rawUrl) {
    if (!rawUrl.toLowerCase().startsWith('file:')) return false;
    return _guard.allowsNavigation(rawUrl);
  }

  /// No network at all: `connect-src 'none'` stops `fetch`, XHR, WebSocket and
  /// beacons; frames, objects and forms are off; media and fonts load only from
  /// local files. `file:` is the narrowest scheme source CSP can express for
  /// local files, so the root-level restriction comes from layers 2 and 3.
  String contentSecurityPolicy() => [
    "default-src 'none'",
    'script-src file:',
    "style-src file: 'unsafe-inline'",
    'img-src file:',
    'font-src file:',
    'media-src file:',
    "connect-src 'none'",
    "frame-src 'none'",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
  ].join('; ');

  /// Runs at document start in every frame and adds the policy as a `<meta>`
  /// element before the page's own resources are parsed.
  String cspUserScriptSource() {
    final policy = jsonEncode(contentSecurityPolicy());
    return '''
(function () {
  try {
    var meta = document.createElement('meta');
    meta.httpEquiv = 'Content-Security-Policy';
    meta.content = $policy;
    var parent = document.head || document.documentElement;
    parent.insertBefore(meta, parent.firstChild);
  } catch (e) {}
})();''';
  }

  /// Apple content-blocker rules: block everything, then exempt the allowed
  /// roots. Order matters (`ignore-previous-rules` undoes earlier blocks).
  List<({String urlFilter, bool block})> contentBlockerRules() => [
    (urlFilter: '.*', block: true),
    for (final root in spec.allowedRoots)
      (urlFilter: '^${_escape(_dirPrefix(root))}', block: false),
  ];

  static String _dirPrefix(Uri root) {
    final text = root.normalizePath().toString();
    return text.endsWith('/') ? text : '$text/';
  }

  static String _escape(String text) =>
      text.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');
}
