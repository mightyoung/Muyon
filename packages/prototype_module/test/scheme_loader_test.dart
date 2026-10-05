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
}
