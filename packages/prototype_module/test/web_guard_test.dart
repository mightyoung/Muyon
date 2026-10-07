import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:prototype_module/src/web_guard.dart';

void main() {
  final root = Uri.parse('file:///data/prototypes/p1/v1');
  final guard = PrototypeWebGuard(
    RestrictedWebViewSpec(
      entry: Uri.parse('file:///data/prototypes/p1/v1/index.html'),
      allowedRoots: {root},
      bridgeChannels: {'muyon.feedback'},
    ),
  );

  test('prototype-scheme pages inside the version root load', () {
    expect(guard.allowsNavigation('muyon-proto://page/index.html'), isTrue);
    expect(guard.allowsNavigation('muyon-proto://page/assets/app.js'), isTrue);
    expect(guard.allowsNavigation('about:blank'), isTrue);
  });

  test('file: and remote navigation is refused, even inside the root', () {
    for (final url in [
      'file:///data/prototypes/p1/v1/index.html',
      'file:///data/prototypes/p1/v1/assets/app.js',
      'file:///data/prototypes/p1/v2/index.html',
      'file:///data/prototypes/p1/v10/index.html',
      'file:///etc/passwd',
      'https://example.com/',
      'http://example.com/',
    ]) {
      expect(guard.allowsNavigation(url), isFalse, reason: url);
    }
  });

  test('other hosts, empty paths and dot-dot segments are refused', () {
    for (final url in [
      'muyon-proto://other/index.html',
      'muyon-proto://page/',
      'muyon-proto://page/../v2/index.html',
      'muyon-proto://page/a/../index.html',
      'muyon-proto://page/%2e%2e/%2E%2E/etc/passwd',
      'muyon-proto://page/%2E./x',
      'muyon-proto://page/%c0%ae/x',
      'muyon-proto://user@page/index.html',
      'muyon-proto://page:8080/index.html',
    ]) {
      expect(guard.allowsNavigation(url), isFalse, reason: url);
    }
  });

  test('javascript, data, blob, ftp, chrome and junk are blocked', () {
    for (final url in [
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      'data:text/html,<script>1</script>',
      'blob:muyon-proto://page/x',
      'ftp://data/prototypes/p1/v1/x',
      'chrome://settings',
      'file://user:pw@/data/prototypes/p1/v1/index.html',
      'not a url at all %',
      '',
    ]) {
      expect(guard.allowsNavigation(url), isFalse, reason: url);
    }
  });

  test('only registered bridge channels pass', () {
    expect(guard.allowsBridge('muyon.feedback'), isTrue);
    expect(guard.allowsBridge('muyon.readFile'), isFalse);
    expect(guard.allowsBridge(''), isFalse);
    expect(guard.checkBridge('muyon.feedback'), GuardVerdict.allowed);
    expect(guard.checkBridge('other'), GuardVerdict.blockedBridge);
    expect(
      guard.checkNavigation('file:///etc/passwd'),
      GuardVerdict.blockedNavigation,
    );
  });
}
