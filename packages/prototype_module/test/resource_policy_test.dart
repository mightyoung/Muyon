import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:prototype_module/src/resource_policy.dart';

void main() {
  final root = Uri.parse('file:///data/prototypes/p1/v1/');
  final policy = PrototypeResourcePolicy(
    RestrictedWebViewSpec(
      entry: Uri.parse('file:///data/prototypes/p1/v1/index.html'),
      allowedRoots: {root},
      bridgeChannels: {'muyon.feedback'},
    ),
  );

  test('only prototype-scheme URLs inside the version root are resources', () {
    for (final ok in [
      'muyon-proto://page/assets/app.js',
      'muyon-proto://page/legacy/data.js',
      'muyon-proto://page/index.html',
    ]) {
      expect(policy.allowsResource(ok), isTrue, reason: ok);
    }
    for (final bad in [
      'https://example.com/x.js',
      'http://example.com/x.js',
      'data:image/png;base64,AAAA',
      'blob:muyon-proto://page/x',
      'about:blank',
      'file:///data/prototypes/p1/v1/assets/app.js',
      'file:///etc/passwd',
      'muyon-proto://other/app.js',
      'muyon-proto://page/../v2/app.js',
      'muyon-proto://page/%2e%2e/secret',
      'muyon-proto://page/',
      'muyon-proto://page',
      'javascript:alert(1)',
      'wss://example.com/socket',
      'ftp://example.com/',
      '',
    ]) {
      expect(policy.allowsResource(bad), isFalse, reason: bad);
    }
  });

  test('CSP forbids network, frames, forms and remote origins', () {
    final csp = policy.contentSecurityPolicy();
    expect(csp, contains("default-src 'none'"));
    expect(csp, contains("connect-src 'none'"));
    expect(csp, contains("frame-src 'none'"));
    expect(csp, contains("object-src 'none'"));
    expect(csp, contains("form-action 'none'"));
    expect(csp, contains("base-uri 'none'"));
    expect(csp, contains('script-src muyon-proto:'));
    expect(csp, isNot(contains('file:')));
    expect(csp, isNot(contains('https')));
    expect(csp, isNot(contains('http:')));
    expect(csp, isNot(contains('data:')));
    expect(csp, isNot(contains('blob:')));
    expect(csp, isNot(contains("'unsafe-eval'")));
    expect(csp, isNot(contains("script-src muyon-proto: 'unsafe-inline'")));
  });

  test('user script injects the policy as the first head child, quoted', () {
    final js = policy.cspUserScriptSource();
    expect(js, contains('Content-Security-Policy'));
    expect(js, contains('insertBefore'));
    expect(js, contains('"${policy.contentSecurityPolicy()}"'));
    // The policy contains single quotes only; it must stay a valid JS string.
    expect(js.split('\n').where((l) => l.contains('meta.content')).length, 1);
  });

  test(
    'content blocker blocks all, then exempts the prototype scheme only',
    () {
      final rules = policy.contentBlockerRules();
      expect(rules.first, (urlFilter: '.*', block: true));
      expect(rules, hasLength(2));
      expect(rules.last.block, isFalse);
      final exempt = RegExp(rules.last.urlFilter);
      expect(exempt.hasMatch('muyon-proto://page/a.js'), isTrue);
      expect(exempt.hasMatch('muyon-proto://other/a.js'), isFalse);
      expect(exempt.hasMatch('file:///data/prototypes/p1/v1/a.js'), isFalse);
      expect(exempt.hasMatch('https://muyon-proto://page/'), isFalse);
    },
  );
}
