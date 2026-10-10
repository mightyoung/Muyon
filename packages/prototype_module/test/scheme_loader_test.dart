import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:prototype_module/src/scheme_loader.dart';

void main() {
  late Directory tmp;
  late PrototypeSchemeLoader loader;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scheme-loader');
    final v1 = Directory(p.join(tmp.path, 'p1', 'v1'))
      ..createSync(recursive: true);
    Directory(p.join(v1.path, 'assets')).createSync();
    File(p.join(v1.path, 'index.html')).writeAsStringSync('<p>hi</p>');
    File(p.join(v1.path, 'assets', 'app.js')).writeAsStringSync('1');
    File(p.join(v1.path, 'my file.css')).writeAsStringSync('b{}');
    Directory(p.join(tmp.path, 'p1', 'v2')).createSync();
    File(p.join(tmp.path, 'p1', 'v2', 'secret.txt')).writeAsStringSync('s');
    File(p.join(tmp.path, 'p1', 'v10.txt')).writeAsStringSync('s');
    final root = Uri.directory(v1.path);
    loader = PrototypeSchemeLoader(
      RestrictedWebViewSpec(
        entry: root.resolve('index.html'),
        allowedRoots: {root},
      ),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('entry maps to the scheme URL', () {
    expect(loader.entry.toString(), 'muyon-proto://page/index.html');
  });

  test('files inside the root are served with a content type', () async {
    final html = await loader.read('muyon-proto://page/index.html');
    expect(String.fromCharCodes(html!.data), '<p>hi</p>');
    expect(html.contentType, 'text/html');
    final js = await loader.read('muyon-proto://page/assets/app.js');
    expect(js!.contentType, 'text/javascript');
    final css = await loader.read('muyon-proto://page/my%20file.css');
    expect(css!.contentType, 'text/css');
  });

  test('everything else is refused', () async {
    for (final bad in [
      'muyon-proto://page/../v2/secret.txt',
      'muyon-proto://page/%2e%2e/v2/secret.txt',
      'muyon-proto://page/%2E%2E/v2/secret.txt',
      'muyon-proto://page/assets/..%2f..%2fv2/secret.txt',
      'muyon-proto://page/assets/%2e%2e%5c..%5cv2/secret.txt',
      'muyon-proto://page/..\\v2\\secret.txt',
      'muyon-proto://page//etc/passwd',
      'muyon-proto://page/${p.join(tmp.path, 'p1', 'v2', 'secret.txt')}',
      'muyon-proto://page/',
      'muyon-proto://page',
      'muyon-proto://page/missing.js',
      'muyon-proto://page/assets',
      'muyon-proto://other/index.html',
      'muyon-proto://user@page/index.html',
      'muyon-proto://page:8080/index.html',
      'muyon-proto://page/index.html%00.png',
      'https://page/index.html',
      'file://${p.join(tmp.path, 'p1', 'v1', 'index.html')}',
      '',
    ]) {
      expect(await loader.read(bad), isNull, reason: bad);
    }
  });
  test('invalid percent-encoding is a refusal, never an exception', () async {
    for (final bad in [
      'muyon-proto://page/%c0%ae/index.html',
      'muyon-proto://page/%ff',
      'muyon-proto://page/assets/%e0%80%af/app.js',
    ]) {
      expect(() => loader.toFileUrl(bad), returnsNormally, reason: bad);
      expect(loader.toFileUrl(bad), isNull, reason: bad);
      expect(await loader.read(bad), isNull, reason: bad);
    }
    // Malformed escapes that still decode stay literal names inside the root.
    for (final odd in ['muyon-proto://page/%', 'muyon-proto://page/%zz']) {
      expect(() => loader.toFileUrl(odd), returnsNormally, reason: odd);
      expect(await loader.read(odd), isNull, reason: odd);
    }
  });

  test('sibling directories with a similar name stay out of reach', () async {
    final v10 = Directory(p.join(tmp.path, 'p1', 'v10'))..createSync();
    File(p.join(v10.path, 'a.txt')).writeAsStringSync('x');
    final evil = Directory(p.join(tmp.path, 'p1', 'v1-evil'))..createSync();
    File(p.join(evil.path, 'a.txt')).writeAsStringSync('x');
    for (final bad in [
      'muyon-proto://page/../v10/a.txt',
      'muyon-proto://page/../v1-evil/a.txt',
      'muyon-proto://page/v10/a.txt',
      'muyon-proto://page/v1-evil/a.txt',
    ]) {
      expect(await loader.read(bad), isNull, reason: bad);
    }
  });

  test('an absolute path never maps outside the root', () async {
    final outside = p.join(tmp.path, 'p1', 'v2', 'secret.txt');
    expect(File(outside).existsSync(), isTrue);
    final root = p.join(tmp.path, 'p1', 'v1');
    for (final url in [
      'muyon-proto://page/$outside',
      'muyon-proto://page//$outside',
    ]) {
      final file = loader.toFileUrl(url);
      expect(
        file == null || p.isWithin(root, file.toFilePath()),
        isTrue,
        reason: url,
      );
      expect(await loader.read(url), isNull, reason: url);
    }
  });

  group('symbolic links cannot lead out of the root', () {
    String v1() => p.join(tmp.path, 'p1', 'v1');
    String v2() => p.join(tmp.path, 'p1', 'v2');

    test('a file link to a file outside', () async {
      Link(p.join(v1(), 'leak.txt')).createSync(p.join(v2(), 'secret.txt'));
      expect(await loader.read('muyon-proto://page/leak.txt'), isNull);
    });

    test('a directory link to a directory outside', () async {
      Link(p.join(v1(), 'dir')).createSync(v2());
      expect(await loader.read('muyon-proto://page/dir/secret.txt'), isNull);
    });

    test('a relative link that climbs out', () async {
      Link(p.join(v1(), 'rel.txt')).createSync('../v2/secret.txt');
      expect(await loader.read('muyon-proto://page/rel.txt'), isNull);
    });

    test('a link to a sibling whose name starts with the root name', () async {
      final v10 = Directory(p.join(tmp.path, 'p1', 'v10'))..createSync();
      File(p.join(v10.path, 'a.txt')).writeAsStringSync('x');
      Link(p.join(v1(), 'v10link')).createSync(v10.path);
      expect(await loader.read('muyon-proto://page/v10link/a.txt'), isNull);
    });

    test('a link that stays inside the root still works', () async {
      Link(p.join(v1(), 'alias.js'))
          .createSync(p.join(v1(), 'assets', 'app.js'));
      final js = await loader.read('muyon-proto://page/alias.js');
      expect(String.fromCharCodes(js!.data), '1');
    });
  });
}
