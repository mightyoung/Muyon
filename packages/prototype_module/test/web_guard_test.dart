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

  test('pages inside the version root load', () {
    expect(
      guard.allowsNavigation('file:///data/prototypes/p1/v1/index.html'),
      isTrue,
    );
    expect(
      guard.allowsNavigation('file:///data/prototypes/p1/v1/assets/app.js'),
      isTrue,
    );
    expect(guard.allowsNavigation('about:blank'), isTrue);
  });

  test('other versions, siblings and outside paths are blocked', () {
    for (final url in [
      'file:///data/prototypes/p1/v2/index.html',
      'file:///data/prototypes/p1/v10/index.html',
      'file:///data/prototypes/p1/v1evil/index.html',
      'file:///etc/passwd',
      'https://example.com/',
      'http://example.com/',
    ]) {
      expect(guard.allowsNavigation(url), isFalse, reason: url);
    }
  });

  test('dot-dot segments are refused even when they resolve inside', () {
    for (final url in [
      'file:///data/prototypes/p1/v1/../v1/index.html',
      'file:///data/prototypes/p1/v1/a/../index.html',
      'file:///data/prototypes/p1/v1/../../../../etc/passwd',
      'file:///data/prototypes/p1/v1/%2e%2e/%2E%2E/etc/passwd',
      'file:///data/prototypes/p1/v1/%2E./x',
    ]) {
      expect(guard.allowsNavigation(url), isFalse, reason: url);
    }
  });

  test('javascript, data, blob, ftp, chrome and credentials are blocked', () {
    for (final url in [
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      'data:text/html,<script>1</script>',
      'blob:file:///data/prototypes/p1/v1/x',
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
