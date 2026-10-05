import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_module/src/core/lan_transfer.dart';
import 'package:research_module/src/core/store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temp, standalone, hosted;
  late WorkbenchStore store;
  late Database database;
  late String alias;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('research-boundary-');
    standalone = Directory('${temp.path}/standalone')..createSync();
    hosted = Directory('${temp.path}/hosted')..createSync();
    Directory('${hosted.path}/child').createSync();
    store = WorkbenchStore.open(standalone.path);
    database = sqlite3.openInMemory();
    WorkbenchStore.attach(rootPath: hosted.path, database: database);
    alias = '${standalone.path}/alias';
    Link(alias).createSync('${hosted.path}/child');
  });
  tearDown(() {
    store.close();
    database.close();
    temp.deleteSync(recursive: true);
  });

  test(
    'sender refuses symlink parent traversal before copying or listening',
    () async {
      final source = File('${standalone.path}/source.zip')
        ..writeAsBytesSync([1]);
      LanShareSession? session;
      Object? error;
      try {
        session = await LanShareSession.start(
          file: source,
          stagingDirectory: Directory('$alias/../outbox'),
          bindAddress: InternetAddress.loopbackIPv4,
        );
      } catch (e) {
        error = e;
      }
      if (session != null) await session.stop();
      expect(error, isA<StateError>());
      expect(Directory('${hosted.path}/outbox').existsSync(), false);
    },
  );

  test(
    'receiver refuses symlink parent traversal before a network request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.headers.set('x-file-name', 'received.zip');
        request.response.add([1]);
        await request.response.close();
      });
      await expectLater(
        LanTransferReceiver.receive(
          url: Uri.parse('http://127.0.0.1:${server.port}'),
          code: 'code',
          destination: Directory('$alias/../inbox'),
        ),
        throwsStateError,
      );
      expect(requests, 0);
      expect(Directory('${hosted.path}/inbox').existsSync(), false);
    },
  );

  test(
    'store opener refuses symlink parent traversal before creating a database',
    () {
      WorkbenchStore? opened;
      Object? error;
      try {
        opened = WorkbenchStore.open('$alias/../new-root');
      } catch (e) {
        error = e;
      }
      opened?.close();
      expect(error, isA<StateError>());
      expect(Directory('${hosted.path}/new-root').existsSync(), false);
    },
  );
  test('active sender blocks overlapping host attachment until fully stopped', () async {
    final source = File('${standalone.path}/source.zip')..writeAsBytesSync([1]);
    final session = await LanShareSession.start(
      file: source,
      stagingDirectory: Directory('${standalone.path}/outbox'),
      bindAddress: InternetAddress.loopbackIPv4,
    );
    addTearDown(session.stop);
    for (final root in [
      standalone.path,
      '${standalone.path}/outbox',
      '${standalone.path}/outbox/new',
    ]) {
      expect(
        () => WorkbenchStore.attach(rootPath: root, database: database),
        throwsStateError,
      );
    }
    // Failed attachment must not register a host root or invalidate the sender.
    expect(session.isActive, true);
    final unrelated = Directory('${temp.path}/unrelated');
    WorkbenchStore.attach(rootPath: unrelated.path, database: database);
    await session.stop();
    WorkbenchStore.attach(rootPath: standalone.path, database: database);
    expect(() => WorkbenchStore.open(standalone.path), throwsStateError);
  });

  test(
    'active receiver blocks attachment and releases its lease after completion',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestArrived = Completer<HttpRequest>();
      server.listen(requestArrived.complete);
      final transfer = LanTransferReceiver.receive(
        url: Uri.parse('http://127.0.0.1:${server.port}'),
        code: 'code',
        destination: Directory('${standalone.path}/inbox'),
      );
      final request = await requestArrived.future;
      Object? error;
      try {
        WorkbenchStore.attach(rootPath: standalone.path, database: database);
      } catch (e) {
        error = e;
      }
      request.response.headers.set('x-file-name', 'received.zip');
      request.response.add([1, 2]);
      await request.response.close();
      final file = await transfer;
      expect(error, isA<StateError>());
      expect(file.readAsBytesSync(), [1, 2]);
      WorkbenchStore.attach(rootPath: standalone.path, database: database);
    },
  );

  test('failed starts release transfer leases', () async {
    await expectLater(
      LanShareSession.start(
        file: File('${standalone.path}/missing'),
        stagingDirectory: Directory('${standalone.path}/outbox'),
        bindAddress: InternetAddress.loopbackIPv4,
      ),
      throwsFormatException,
    );
    await expectLater(
      LanTransferReceiver.receive(
        url: Uri.parse('http://127.0.0.1:1'),
        code: '',
        destination: Directory('${standalone.path}/inbox'),
      ),
      throwsFormatException,
    );
    WorkbenchStore.attach(rootPath: standalone.path, database: database);
  });

  test(
    'host aliases and unknown roots deny before filesystem or network effects',
    () async {
      final directAlias = '${standalone.path}/host-link';
      Link(directAlias).createSync(hosted.path);
      final source = File('${standalone.path}/source.zip')
        ..writeAsBytesSync([1]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.response.close();
      });
      for (final root in [
        hosted.path,
        directAlias,
        '$directAlias/missing/child',
        '${temp.path}/unknown',
      ]) {
        final outbox = Directory('$root/outbox');
        final inbox = Directory('$root/inbox');
        await expectLater(
          LanShareSession.start(
            file: source,
            stagingDirectory: outbox,
            bindAddress: InternetAddress.loopbackIPv4,
          ),
          throwsStateError,
        );
        await expectLater(
          LanTransferReceiver.receive(
            url: Uri.parse('http://127.0.0.1:${server.port}'),
            code: 'code',
            destination: inbox,
          ),
          throwsStateError,
        );
        expect(outbox.existsSync(), false);
        expect(inbox.existsSync(), false);
      }
      expect(requests, 0);
      for (final root in [
        hosted.path,
        '${hosted.path}/new',
        temp.path,
        directAlias,
        '$directAlias/missing',
      ]) {
        expect(() => WorkbenchStore.open(root), throwsStateError);
        expect(File('$root/workbench.sqlite').existsSync(), false);
      }
    },
  );

  test('hosted sources are denied even with standalone staging', () async {
    File('${hosted.path}/secret.zip').writeAsBytesSync([9]);
    final directAlias = '${standalone.path}/host-link';
    Link(directAlias).createSync(hosted.path);
    for (final source in [
      '${hosted.path}/secret.zip',
      '$directAlias/secret.zip',
      '$alias/../secret.zip',
    ]) {
      await expectLater(
        LanShareSession.start(
          file: File(source),
          stagingDirectory: Directory('${standalone.path}/outbox'),
          bindAddress: InternetAddress.loopbackIPv4,
        ),
        throwsStateError,
      );
    }
    expect(Directory('${standalone.path}/outbox').existsSync(), false);
  });

  for (final relation in ['same', 'host-child', 'host-parent']) {
    test('host ownership wins $relation and stays after close', () async {
      final base = Directory('${temp.path}/overlap')..createSync();
      final localRoot = relation == 'host-parent'
          ? '${base.path}/child'
          : base.path;
      final hostRoot = relation == 'host-child'
          ? '${base.path}/child'
          : base.path;
      final local = WorkbenchStore.open(localRoot);
      final attached = WorkbenchStore.attach(
        rootPath: hostRoot,
        database: database,
      );
      attached.close();
      local.close();
      expect(() => WorkbenchStore.open(localRoot), throwsStateError);
      await expectLater(
        LanTransferReceiver.receive(
          url: Uri.parse('http://127.0.0.1:1'),
          code: 'code',
          destination: Directory('$hostRoot/inbox'),
        ),
        throwsStateError,
      );
      if (relation == 'host-child') {
        final source = File('$localRoot/source.zip')..writeAsBytesSync([1]);
        final sibling = await LanShareSession.start(
          file: source,
          stagingDirectory: Directory('$localRoot/sibling-outbox'),
          bindAddress: InternetAddress.loopbackIPv4,
        );
        await sibling.stop();
      }
      // Unrelated standalone root retains its permission in the same isolate.
      final source = File('${standalone.path}/source.zip')
        ..writeAsBytesSync([1]);
      final session = await LanShareSession.start(
        file: source,
        stagingDirectory: Directory('${standalone.path}/outbox'),
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await session.stop();
    });
  }

  test('validated sender paths survive retargeting the original symlink', () async {
    final link = Link('${temp.path}/standalone-link')
      ..createSync(standalone.path);
    File('${standalone.path}/source.zip').writeAsBytesSync([1]);
    File('${hosted.path}/source.zip').writeAsBytesSync([9]);
    final starting = LanShareSession.start(
      file: File('${link.path}/source.zip'),
      stagingDirectory: Directory('${link.path}/outbox'),
      bindAddress: InternetAddress.loopbackIPv4,
    );
    // Acquisition happens synchronously, before the first asynchronous effect.
    expect(
      () =>
          WorkbenchStore.attach(rootPath: standalone.path, database: database),
      throwsStateError,
    );
    link.deleteSync();
    link.createSync(hosted.path);
    final session = await starting;
    addTearDown(session.stop);
    final file = await LanTransferReceiver.receive(
      url: Uri.parse('http://127.0.0.1:${session.port}'),
      code: session.code,
      destination: Directory('${standalone.path}/inbox'),
    );
    expect(file.readAsBytesSync(), [1]);
    expect(Directory('${hosted.path}/outbox').existsSync(), false);
    await session.stop();
  });

  test('validated receiver destination survives symlink retargeting while awaiting response', () async {
    final link = Link('${temp.path}/standalone-link')
      ..createSync(standalone.path);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestArrived = Completer<HttpRequest>();
    server.listen(requestArrived.complete);
    final transfer = LanTransferReceiver.receive(
      url: Uri.parse('http://127.0.0.1:${server.port}'),
      code: 'code',
      destination: Directory('${link.path}/inbox'),
    );
    final request = await requestArrived.future;
    link.deleteSync();
    link.createSync(hosted.path);
    request.response.add([1]);
    await request.response.close();
    final file = await transfer;
    expect(file.readAsBytesSync(), [1]);
    expect(
      file.parent.path,
      Directory('${standalone.path}/inbox').resolveSymbolicLinksSync(),
    );
    expect(Directory('${hosted.path}/inbox').existsSync(), false);
  });

  test(
    'failed network receive releases its lease for subsequent host activation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      });
      await expectLater(
        LanTransferReceiver.receive(
          url: Uri.parse('http://127.0.0.1:${server.port}'),
          code: 'wrong',
          destination: Directory('${standalone.path}/inbox'),
        ),
        throwsFormatException,
      );
      WorkbenchStore.attach(rootPath: standalone.path, database: database);
      expect(Directory('${standalone.path}/inbox').existsSync(), false);
    },
  );
}
