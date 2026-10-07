import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';

import 'scheme_loader.dart';
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

  /// A sub-resource is allowed only if it is a `muyon-proto://` URL that maps
  /// inside the allowed root. Remote `https`, `data:`, `blob:`, `about:`,
  /// `file:`, `..` paths and other local files are all refused.
  bool allowsResource(String rawUrl) {
    if (!rawUrl.toLowerCase().startsWith('$prototypeScheme:')) return false;
    return _guard.allowsNavigation(rawUrl);
  }

  /// No network at all: `connect-src 'none'` stops `fetch`, XHR, WebSocket and
  /// beacons; frames, objects and forms are off; media and fonts load only from
  /// the prototype scheme, which the loader serves from the version root only.
  String contentSecurityPolicy() => [
    "default-src 'none'",
    'script-src $prototypeScheme:',
    "style-src $prototypeScheme: 'unsafe-inline'",
    'img-src $prototypeScheme:',
    'font-src $prototypeScheme:',
    'media-src $prototypeScheme:',
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

  /// Apple content-blocker rules: block everything, then exempt the prototype
  /// scheme. The scheme loader maps only paths inside the version root, so the
  /// directory restriction lives there. Order matters (`ignore-previous-rules`
  /// undoes earlier blocks).
  List<({String urlFilter, bool block})> contentBlockerRules() => [
    (urlFilter: '.*', block: true),
    (urlFilter: '^$prototypeScheme://$prototypeHost/', block: false),
  ];
}
