import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/file_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

/// [FileGateway.freeze] snapshots an import into host staging without keeping
/// the external path, and refuses anything that is not a regular file or
/// directory (including symbolic links).
void main() {
  late Directory tmp;
  late FileGateway gateway;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file-gateway-');
    gateway = FileGateway(p.join(tmp.path, 'root'));
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('copies a single file into staging under its basename', () async {
    final source = File(p.join(tmp.path, 'note.txt'))
      ..writeAsStringSync('hello');

    final frozen = await gateway.freeze(
      SelectedInput(path: source.path, displayName: '采购说明'),
    );

    expect(frozen.displayName, '采购说明');
    expect(frozen.path, startsWith(p.join(gateway.rootPath, 'staging')));
    expect(File(frozen.path).readAsStringSync(), 'hello');
    // The snapshot no longer points at the mutable external path.
    expect(frozen.path, isNot(source.path));
    source.writeAsStringSync('changed');
    expect(File(frozen.path).readAsStringSync(), 'hello');
  });

  test('copies a directory tree and rejects symbolic links', () async {
    final source = Directory(p.join(tmp.path, 'project'))..createSync();
    File(p.join(source.path, 'a.txt')).writeAsStringSync('a');
    Directory(p.join(source.path, 'sub')).createSync();
    File(p.join(source.path, 'sub', 'b.txt')).writeAsStringSync('b');

    final frozen = await gateway.freeze(
      SelectedInput(path: source.path, displayName: 'project'),
    );
    expect(File(p.join(frozen.path, 'a.txt')).readAsStringSync(), 'a');
    expect(
      File(p.join(frozen.path, 'sub', 'b.txt')).readAsStringSync(),
      'b',
    );

    Link(p.join(source.path, 'link')).createSync(p.join(source.path, 'a.txt'));
    await expectLater(
      gateway.freeze(SelectedInput(path: source.path, displayName: 'project')),
      throwsStateError,
    );
  });

  test('rejects paths that are neither a regular file nor directory', () async {
    await expectLater(
      gateway.freeze(
        SelectedInput(path: p.join(tmp.path, 'missing'), displayName: 'x'),
      ),
      throwsArgumentError,
    );
  });
}
