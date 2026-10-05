import 'dart:io';
import 'dart:typed_data';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

/// Prototypes are served from their version directory through this custom
/// scheme instead of `file://`: WebViews refuse `type="module"` scripts (every
/// Vite build) from `file://` because the origin is opaque.
const prototypeScheme = 'muyon-proto';
const prototypeHost = 'page';

final _dotSegment = RegExp(
  r'(^|[/\\])(\.|%2e|%2E){2}([/\\]|$)|%2f|%2F|%5c|%5C|%00',
);

/// Translates between the `file:` root in [RestrictedWebViewSpec] (the single
/// source of what is allowed) and `muyon-proto://page/...` URLs. Every refusal
/// is `null`; nothing outside the root is ever mapped.
class PrototypeSchemeLoader {
  PrototypeSchemeLoader(this.spec) : _root = spec.allowedRoots.first;

  final RestrictedWebViewSpec spec;
  final Uri _root;

  String get _rootPath => p.normalize(_root.toFilePath());

  /// `file:` URL inside the root → scheme URL the WebView loads.
  Uri toSchemeUrl(Uri fileUrl) {
    final rel = p.relative(fileUrl.toFilePath(), from: _rootPath);
    return Uri(
      scheme: prototypeScheme,
      host: prototypeHost,
      pathSegments: p.split(rel),
    );
  }

  Uri get entry => toSchemeUrl(spec.entry);

  /// Scheme URL → `file:` URL, or null if it is not strictly inside the root.
  Uri? toFileUrl(String rawUrl) {
    if (_dotSegment.hasMatch(rawUrl)) return null;
    final Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } on FormatException {
      return null;
    }
    if (uri.scheme != prototypeScheme ||
        uri.host != prototypeHost ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final rel = uri.pathSegments.where((s) => s.isNotEmpty).join('/');
    if (rel.isEmpty) return null;
    final path = p.normalize(p.join(_rootPath, rel));
    if (!p.isWithin(_rootPath, path)) return null;
    final file = Uri.file(path);
    return spec.allowsNavigation(file) ? file : null;
  }

  /// Bytes and content type for [rawUrl]; null for refused or missing files.
  Future<({Uint8List data, String contentType})?> read(String rawUrl) async {
    final file = toFileUrl(rawUrl);
    if (file == null) return null;
    final target = File.fromUri(file);
    if (!await target.exists()) return null;
    return (data: await target.readAsBytes(), contentType: mimeFor(file.path));
  }

  static const _mime = {
    'html': 'text/html',
    'htm': 'text/html',
    'js': 'text/javascript',
    'mjs': 'text/javascript',
    'css': 'text/css',
    'json': 'application/json',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'txt': 'text/plain',
  };

  static String mimeFor(String path) =>
      _mime[p.extension(path).replaceFirst('.', '').toLowerCase()] ??
      'application/octet-stream';
}
