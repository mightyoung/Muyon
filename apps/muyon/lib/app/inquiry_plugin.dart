import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:inquiry_module/inquiry_module.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:supplier_core/supplier_core.dart';

import '../platform/storage_manager.dart';
import '../services/models/secret_store.dart';
import '../services/models/model_gateway.dart';
import '../services/models/profile_repository.dart';

class InquiryModelApprovalPreview {
  InquiryModelApprovalPreview({
    required this.profile,
    required Map<String, Object?> body,
  }) : body = freezeJsonMap(body),
       bodyDigest = sha256.convert(utf8.encode(jsonEncode(body))).toString();
  final ModelProfile profile;
  Uri get endpoint => profile.endpoint;
  final Map<String, Object?> body;
  final String bodyDigest;
}

typedef InquiryModelApproval = Future<bool> Function(
  InquiryModelApprovalPreview preview,
);

/// The host adapts Folio's existing transaction owner; it does not rewrite its
/// cross-project supplier/project relationships into research scopes.
class InquiryPlugin {
  InquiryPlugin._(this.runtime, this.jobs);
  final InquiryRuntime runtime;
  final AiJobStore jobs;
  static final schema = ModuleSchema(
    version: 2,
    definitionDigest: _digest('inquiry-host-v2:domain12:change-log'),
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
      ModuleMigration(
        version: 2,
        id: 'inquiry-host-v2-change-log',
        definitionDigest: _digest('inquiry-host-v2:domain12:change-log'),
        migrate: (db) {
          ModuleChangeLog.createTable(db);
          // SQL triggers cover raw exchange/merge writes as well as Store.save.
          // Their records commit or roll back with the domain row, without
          // invoking reentrant SQL from a SQLite user-defined function.
          for (final type in const [
            'supplier',
            'inquiry',
            'quotation',
            'project',
            'project_item',
          ]) {
            String scope(String row) => type == 'project'
                ? '$row.id'
                : "json_extract($row.data, '\$.project_id')";
            String summary(String row) =>
                "coalesce(json_extract($row.data, '\$.name'), "
                "json_extract($row.data, '\$.title'), "
                "json_extract($row.data, '\$.subject'), "
                "json_extract($row.data, '\$.code'), $row.id)";
            String record(String row, String op) =>
                'INSERT INTO ${ModuleChangeLog.table}'
                '(object_type,object_id,native_project_id,revision_ref,'
                'op,summary,recorded_at) VALUES('
                "'$type',$row.id,${scope(row)},CAST($row.version AS TEXT),"
                "$op,${summary(row)},strftime('%Y-%m-%dT%H:%M:%fZ','now'));";
            final upsert = record(
              'new',
              "CASE WHEN new.deleted=1 THEN 'delete' ELSE 'upsert' END",
            );
            db.execute(
              'CREATE TRIGGER muyon_${type}_ai AFTER INSERT ON $type '
              'BEGIN $upsert END',
            );
            // Remove the old scoped projection when an object changes project.
            db.execute(
              'CREATE TRIGGER muyon_${type}_au AFTER UPDATE ON $type '
              'BEGIN INSERT INTO ${ModuleChangeLog.table}'
              '(object_type,object_id,native_project_id,revision_ref,'
              'op,summary,recorded_at) '
              "SELECT '$type',old.id,${scope('old')},"
              "CAST(old.version AS TEXT),'delete',${summary('old')},"
              "strftime('%Y-%m-%dT%H:%M:%fZ','now') "
              "WHERE ${scope('old')} IS NOT ${scope('new')}; $upsert END",
            );
            db.execute(
              'CREATE TRIGGER muyon_${type}_ad AFTER DELETE ON $type '
              "BEGIN ${record('old', "'delete'")} END",
            );
            // Existing rows must become discoverable when upgrading from v1.
            db.execute(
              'INSERT INTO ${ModuleChangeLog.table}'
              '(object_type,object_id,native_project_id,revision_ref,'
              'op,summary,recorded_at) '
              "SELECT '$type',$type.id,${scope(type)},"
              "CAST($type.version AS TEXT),"
              "CASE WHEN deleted=1 THEN 'delete' ELSE 'upsert' END,"
              "${summary(type)},strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM $type",
            );
          }
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
    required ProfileRepository modelProfiles,
    required OpenAiModelGateway modelGateway,
    InquiryModelApproval? approveModelRequest,
    MethodChannelSecretStore modelSecrets = const MethodChannelSecretStore(),
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
    final models = InquiryHostModels(
      profiles: modelProfiles,
      gateway: modelGateway,
      secrets: modelSecrets,
      approve: approveModelRequest,
    );
    final runtime = InquiryRuntime.attach(
      store: store,
      dataDirectory: root,
      aiJobs: jobs,
      secrets: const _InquirySecrets(),
      initialSettings: settings,
      sharedModelSettings: models,
      sharedLlmFactory: models.createClient,
    );
    return InquiryPlugin._(runtime, jobs);
  }

  Future<void> close() async {
    await runtime.close();
    jobs.close();
  }
}

/// Adapts source business logic to the one host model/credential authority.
class InquiryHostModels implements InquiryModelSettingsBridge {
  InquiryHostModels({
    required this.profiles,
    required this.gateway,
    this.secrets = const MethodChannelSecretStore(),
    this.approve,
  });
  final ProfileRepository profiles;
  final OpenAiModelGateway gateway;
  final MethodChannelSecretStore secrets;
  final InquiryModelApproval? approve;

  ModelProfile? get active {
    final id = profiles.workspaces.setting('activeModelProfileId');
    return profiles
        .all()
        .where(
          (profile) => profile.id == id && profile.purpose == ModelPurpose.chat,
        )
        .firstOrNull;
  }

  String _base(ModelProfile profile) {
    final endpoint = profile.endpoint.toString();
    const suffix = '/chat/completions';
    return endpoint.endsWith(suffix)
        ? endpoint.substring(0, endpoint.length - suffix.length)
        : endpoint;
  }

  @override
  String get baseUrl => active == null ? '' : _base(active!);
  @override
  String get model => active?.modelId ?? '';
  @override
  Future<bool> hasCredential() async {
    final profile = active;
    if (profile == null) return false;
    if (profile.credentialRef == null) {
      return profile.location == ModelLocation.local;
    }
    return (await gateway.secrets.read(profile.credentialRef!))?.isNotEmpty ??
        false;
  }

  @override
  Future<void> save({
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    final prior = active;
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final endpoint = prior != null && base == _base(prior)
        ? prior.endpoint
        : Uri.parse(
            base.endsWith('/chat/completions')
                ? base
                : '$base/chat/completions',
          );
    final local = ['localhost', '127.0.0.1', '::1'].contains(endpoint.host);
    final location = local
        ? ModelLocation.local
        : prior?.endpoint.host == endpoint.host &&
              prior?.location == ModelLocation.ownDevice
        ? ModelLocation.ownDevice
        : ModelLocation.remote;
    final id = prior?.id ?? 'inquiry-${DateTime.now().microsecondsSinceEpoch}';
    final reference = prior?.credentialRef ?? 'model-$id';
    final profile = ModelProfile(
      id: id,
      endpoint: endpoint,
      location: location,
      modelId: model.trim(),
      endpointIdentity: endpoint.toString(),
      credentialRef:
          local &&
              prior?.credentialRef == null &&
              (apiKey == null || apiKey.isEmpty)
          ? null
          : reference,
      cloudProxy: prior?.cloudProxy ?? false,
    );
    if (apiKey != null) {
      if (apiKey.isEmpty) {
        await secrets.remove(reference);
      } else {
        await secrets.write(reference, apiKey);
      }
    }
    await profiles.save(profile);
    await profiles.workspaces.setSetting('activeModelProfileId', id);
  }

  Future<LlmClient?> createClient({AiCancellation? cancellation}) async {
    final profile = active;
    if (profile == null) return null;
    final sourceToken = cancellation ?? AiCancellation();
    return LlmClient(
      LlmConfig(
        apiKey: '',
        baseUrl: profile.endpoint.toString(),
        model: profile.modelId,
      ),
      transport: (body) async {
        sourceToken.check();
        final preview = InquiryModelApprovalPreview(
          profile: profile,
          body: body,
        );
        final token = ModelCancellation();
        final remove = sourceToken.onCancel(token.cancel);
        try {
          return await gateway.request(
            profile: profile,
            payload: preview.body,
            cancellation: token,
            beforeSend: () async {
              sourceToken.check();
              if (approve == null || !await approve!(preview)) {
                throw LlmException('本次模型请求未获宿主确认');
              }
              sourceToken.check();
              // A profile switch during a dialog invalidates its frozen request.
              if (active == null ||
                  jsonEncode(active!.toJson()) !=
                      jsonEncode(profile.toJson())) {
                throw LlmException('模型配置已变更，请重新发起请求');
              }
            },
          );
        } finally {
          remove();
        }
      },
    );
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
