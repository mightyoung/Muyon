import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:muspace_module_api/muspace_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/supplier_core.dart';

import '../platform/storage_manager.dart';
import '../services/models/secret_store.dart';

/// The host adapts Folio's existing transaction owner; it does not rewrite its
/// cross-project supplier/project relationships into research scopes.
class InquiryPlugin {
  InquiryPlugin._(this.runtime, this.jobs);
  final InquiryRuntime runtime;
  final AiJobStore jobs;
  static final schema = ModuleSchema(
    version: 1,
    definitionDigest: _digest('inquiry-host-v1:domain12'),
    migrations: [
      ModuleMigration(
        version: 1,
        id: 'inquiry-host-v1',
        definitionDigest: _digest('inquiry-host-v1:domain12'),
        migrate: (db) {
          registerFunctions(db);
          createSchema(db);
          ensureSearchIndex(db);
        },
      ),
    ],
  );
  static final jobsSchema = ModuleSchema(
    version: 1,
    definitionDigest: _digest('inquiry-jobs-host-v1'),
    migrations: [
      ModuleMigration(
        version: 1,
        id: 'inquiry-jobs-v1',
        definitionDigest: _digest('inquiry-jobs-host-v1'),
        migrate: AiJobStore.initializeSchema,
      ),
    ],
  );
  static String _digest(String declaration) => sha256
      .convert(
        utf8.encode('b35eccbe9ddf458a6538fa107baa9b456972a4f8:$declaration'),
      )
      .toString();

  static Future<InquiryPlugin> open(
    StorageManager storage, {
    required String deviceId,
  }) async {
    final database = await storage.open('inquiry', schema);
    final jobsDatabase = await storage.open('inquiry_jobs', jobsSchema);
    // Recovery is an open-time operation, also for an already migrated job DB.
    await jobsDatabase.write(AiJobStore.initializeSchema);
    final jobs = AiJobStore.attach(jobsDatabase.raw);
    final store = Store.attach(
      database.raw,
      device: deviceId,
      backgroundExecutor: <T>(action) =>
          database.exclusiveAsync((_) => action()),
    );
    final root = Directory(
      p.join(storage.rootPath, 'modules', 'inquiry', 'files'),
    );
    root.createSync(recursive: true);
    final settingsFile = File(p.join(root.path, 'settings.json'));
    final settings = settingsFile.existsSync()
        ? Map<String, Object?>.from(
            jsonDecode(settingsFile.readAsStringSync()) as Map,
          )
        : <String, Object?>{};
    final runtime = InquiryRuntime.attach(
      store: store,
      dataDirectory: root,
      aiJobs: jobs,
      secrets: const _InquirySecrets(),
      initialSettings: settings,
    );
    return InquiryPlugin._(runtime, jobs);
  }

  Future<void> close() async {
    await runtime.close();
    jobs.close();
  }
}

class _InquirySecrets implements InquirySecretStore {
  const _InquirySecrets();
  static const storage = MethodChannelSecretStore();
  String _reference(String key) =>
      'inquiry-${sha256.convert(utf8.encode(key))}';
  @override
  Future<String?> read({required String key}) => storage.read(_reference(key));
  @override
  Future<void> write({required String key, required String value}) =>
      storage.write(_reference(key), value);
  @override
  Future<void> delete({required String key}) => storage.remove(_reference(key));
}
