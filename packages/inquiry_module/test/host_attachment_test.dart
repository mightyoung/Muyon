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

class HostModelSettings implements InquiryModelSettingsBridge {
  @override
  String baseUrl = 'https://host.example/v1';
  @override
  String model = 'shared-model';
  bool configured = true;
  @override
  Future<bool> hasCredential() async => configured;
  @override
  Future<void> save({
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    this.baseUrl = baseUrl;
    this.model = model;
    if (apiKey != null) configured = apiKey.isNotEmpty;
  }
}

void main() {
  test('shared model settings and factory override legacy config with task cancellation', () async {
    final directory = Directory.systemTemp.createTempSync('inquiry-model-host');
    final db = sqlite3.openInMemory(), jobsDb = sqlite3.openInMemory();
    createSchema(db);
    AiJobStore.initializeSchema(jobsDb);
    final jobs = AiJobStore.attach(jobsDb);
    final settings = HostModelSettings();
    final secrets = HostSecrets();
    AiCancellation? receivedCancellation;
    final runtime = InquiryRuntime.attach(
      store: Store.attach(
        db,
        device: 'host',
        backgroundExecutor: <T>(action) async => await action(),
      ),
      dataDirectory: directory,
      aiJobs: jobs,
      secrets: secrets,
      initialSettings: {
        'ai_base_url': 'https://legacy.example',
        'ai_model': 'legacy',
      },
      sharedModelSettings: settings,
      sharedLlmFactory: ({cancellation}) async {
        receivedCancellation = cancellation;
        return LlmClient(
          LlmConfig(
            apiKey: '',
            baseUrl: settings.baseUrl,
            model: settings.model,
          ),
          transport: (body) async => {
            'choices': [
              {
                'message': {'content': 'shared result'},
              },
            ],
          },
        );
      },
    );
    addTearDown(() async {
      await runtime.close();
      jobs.close();
      db.close();
      jobsDb.close();
      directory.deleteSync(recursive: true);
    });
    expect(runtime.state.aiBaseUrl, settings.baseUrl);
    expect(runtime.state.aiModel, 'shared-model');
    await runtime.state.saveAi(
      baseUrl: 'https://updated.example/v1',
      model: 'new-shared',
      apiKey: 'private',
    );
    expect(settings.model, 'new-shared');
    expect(runtime.state.aiModel, 'new-shared');
    expect(secrets.values, isEmpty);
    expect(File('${directory.path}/settings.json').existsSync(), isFalse);
    expect(await runtime.state.hasAiKey(), isTrue);
    final token = AiCancellation();
    final result = await runtime.state.runAiTask(
      AiTask.clauseReading,
      {},
      (client) => client.complete([
        {'role': 'user', 'content': 'test'},
      ]),
      cancellation: token,
    );
    expect(result['content'], 'shared result');
    expect(identical(receivedCancellation, token), isTrue);
    expect(runtime.state.aiTasks.single.status, 'ready');
  });
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
