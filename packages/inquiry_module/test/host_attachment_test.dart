import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supplier_core/supplier_core.dart';

class HostSecrets implements InquirySecretStore {
  final values = <String, String>{};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

void main() {
  test(
    'host attachment does not create private databases or auto-start LAN',
    () async {
      final directory = Directory.systemTemp.createTempSync('inquiry-host');
      final db = sqlite3.openInMemory();
      final jobsDb = sqlite3.openInMemory();
      addTearDown(() {
        db.close();
        jobsDb.close();
        directory.deleteSync(recursive: true);
      });
      createSchema(db);
      AiJobStore.initializeSchema(jobsDb);
      Future<T> execute<T>(FutureOr<T> Function() action) async =>
          await action();
      final store = Store.attach(
        db,
        device: 'host',
        backgroundExecutor: execute,
      );
      final jobs = AiJobStore.attach(jobsDb);
      final secrets = HostSecrets();
      final runtime = InquiryRuntime.attach(
        store: store,
        dataDirectory: directory,
        aiJobs: jobs,
        secrets: secrets,
        initialSettings: {'lan_visible': '1'},
      );
      expect(runtime.state.lan, isNull);
      expect(runtime.state.lanVisible, isFalse);
      expect(runtime.state.aiTasks, isEmpty);
      await runtime.state.saveExchangePassphrase('secret-value');
      expect(await runtime.state.exchangePassphrase(), 'secret-value');
      expect(
        directory.listSync().whereType<File>().map(
          (f) => f.uri.pathSegments.last,
        ),
        ['settings.json'],
      );
      expect(
        File('${directory.path}/settings.json').readAsStringSync(),
        isNot(contains('secret-value')),
      );
      final started = Completer<void>();
      final finish = Completer<void>();
      final writing = runtime.state.writeInBackground((store) async {
        started.complete();
        await finish.future;
        store.db.execute("INSERT INTO meta VALUES('drained','yes')");
      });
      await started.future;
      var closed = false;
      final closing = runtime.close().then((_) => closed = true);
      final blocked = await runtime.state.writeInBackground((store) {
        fail('Closing runtime accepted a new write');
      });
      expect(blocked, isNotNull);
      expect(
        runtime.state.write(
          (_) => fail('Closing runtime accepted a sync write'),
        ),
        isNotNull,
      );
      expect(closed, isFalse);
      finish.complete();
      await writing;
      await closing;
      expect(
        db.select("SELECT value FROM meta WHERE key='drained'").single['value'],
        'yes',
      );
      expect(db.select('PRAGMA quick_check').single.values.single, 'ok');
      expect(jobs.jobs, isEmpty);
      jobs.close();
    },
  );
}
